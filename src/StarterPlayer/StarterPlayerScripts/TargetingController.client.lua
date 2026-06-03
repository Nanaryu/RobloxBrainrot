-- StarterPlayer/StarterPlayerScripts/TargetingController.client.lua
-- Hold Q to enter chain-target mode.
--   ROAMING : small orb on a chain follows the mouse.
--   SNAPPED : chain hides, rotating arc-segment ring appears flat on the
--             ground under the enemy.  Release Q -> RequestAttack fires.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestAttack = Remotes:WaitForChild("RequestAttack")

-- ── Tunables ──────────────────────────────────────────────────────────────────
local TARGETING_KEY   = Enum.KeyCode.Q

-- Orb / chain (roaming)
local SNAP_RADIUS     = 12      -- studs: how close orb must be to snap
local CHAIN_MAX_LEN   = 35      -- studs: max chain reach
local ORB_RADIUS      = 0.45
local CHAIN_SEGMENTS  = 12
local CHAIN_THICKNESS = 0.07
local ORB_COLOR       = Color3.fromRGB(80, 200, 255)
local CHAIN_COLOR     = Color3.fromRGB(120, 210, 255)
local ORB_LERP        = 0.20

-- Ring (snapped)
-- Arc bars are Block parts: X = arc chord length, Y = bar height (vertical),
-- Z = bar width (tangential thickness visible from above).
local RING_RADIUS     = 2.4     -- studs from enemy centre to arc midpoint
local RING_HEIGHT     = 0.22    -- studs -- vertical size of each bar
local RING_WIDTH      = 0.22    -- studs -- width of each bar (tangential)
local RING_Y_OFFSET   = 0.40    -- studs above the tile surface (keeps ring visible)
local ARC_COUNT       = 4
local ARC_GAP_DEG     = 24      -- gap between arcs in degrees
local RING_COLOR      = Color3.fromRGB(255, 80,  80)
local RING_GLOW_COLOR = Color3.fromRGB(255, 160, 60)
local SPIN_OUTER      =  90     -- deg/s clockwise
local SPIN_INNER      = -55     -- deg/s counter-clockwise
local SNAP_LERP       = 0.32

-- ── State ─────────────────────────────────────────────────────────────────────
local player   = Players.LocalPlayer
local camera   = workspace.CurrentCamera
local mouse    = player:GetMouse()

local active         = false
local isSnapped      = false
local wasSnapped     = false
local snappedEnemy   = nil
local snappedEnemyId = nil
local orbWorldPos    = Vector3.zero
local orbVisualPos   = Vector3.zero
local ringAngle      = 0
local ringAngleInner = 0

-- ── Visual handles ────────────────────────────────────────────────────────────
local vFolder      = nil
local orbPart      = nil
local orbGlow      = nil
local orbShell     = nil
local chainSegs    = {}
local outerArcs    = {}
local innerArcs    = {}
local ringAnchor   = nil
local ringLight    = nil
local popLabel     = nil
local popBB        = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function getHRP()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function isAlive()
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function findNearestEnemy(worldPos)
	local map    = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Enemies")
	if not folder then return nil, nil end
	local best, bestId, bestDist = nil, nil, SNAP_RADIUS
	for _, model in ipairs(folder:GetChildren()) do
		if not model:IsA("Model") then continue end
		if model:GetAttribute("State") == "dead" then continue end
		local id = model:GetAttribute("EnemyId")
		if not id then continue end
		local d = (model:GetPivot().Position - worldPos).Magnitude
		if d < bestDist then bestDist=d; best=model; bestId=id end
	end
	return best, bestId
end

-- ── Build visuals ─────────────────────────────────────────────────────────────
local function buildVisuals()
	if vFolder then vFolder:Destroy() end
	vFolder        = Instance.new("Folder")
	vFolder.Name   = "TargetingFX"
	vFolder.Parent = workspace

	-- Orb
	orbPart            = Instance.new("Part")
	orbPart.Shape      = Enum.PartType.Ball
	orbPart.Size       = Vector3.new(ORB_RADIUS*2, ORB_RADIUS*2, ORB_RADIUS*2)
	orbPart.Anchored   = true
	orbPart.CanCollide = false; orbPart.CanQuery = false; orbPart.CastShadow = false
	orbPart.Color      = ORB_COLOR; orbPart.Material = Enum.Material.Neon
	orbPart.CFrame     = CFrame.new(orbVisualPos)
	orbPart.Parent     = vFolder

	orbGlow            = Instance.new("PointLight")
	orbGlow.Brightness = 5; orbGlow.Range = 12; orbGlow.Color = ORB_COLOR
	orbGlow.Parent     = orbPart

	orbShell              = Instance.new("Part")
	orbShell.Shape        = Enum.PartType.Ball
	orbShell.Size         = Vector3.new(ORB_RADIUS*4, ORB_RADIUS*4, ORB_RADIUS*4)
	orbShell.Anchored     = true
	orbShell.CanCollide   = false; orbShell.CanQuery = false; orbShell.CastShadow = false
	orbShell.Color        = ORB_COLOR; orbShell.Material = Enum.Material.Neon
	orbShell.Transparency = 0.74
	orbShell.CFrame       = CFrame.new(orbVisualPos)
	orbShell.Parent       = vFolder

	-- Chain
	chainSegs = {}
	for i = 1, CHAIN_SEGMENTS do
		local s           = Instance.new("Part")
		s.Shape           = Enum.PartType.Cylinder
		s.Size            = Vector3.new(0.001, CHAIN_THICKNESS, CHAIN_THICKNESS)
		s.Anchored        = true
		s.CanCollide      = false; s.CanQuery = false; s.CastShadow = false
		s.Color           = CHAIN_COLOR; s.Material = Enum.Material.Neon
		s.Transparency    = 0.5
		s.Parent          = vFolder
		chainSegs[i]      = s
	end

	-- Arc ring parts  (Block, NOT Cylinder -- easier size axes)
	-- Size.X = arc chord length (set per-frame), Size.Y = vertical height, Size.Z = bar width
	outerArcs = {}
	for i = 1, ARC_COUNT do
		local a           = Instance.new("Part")
		a.Size            = Vector3.new(0.001, RING_HEIGHT, RING_WIDTH)
		a.Anchored        = true
		a.CanCollide      = false; a.CanQuery = false; a.CastShadow = false
		a.Color           = RING_COLOR; a.Material = Enum.Material.Neon
		a.Transparency    = 1
		a.Parent          = vFolder
		outerArcs[i]      = a
	end
	innerArcs = {}
	for i = 1, ARC_COUNT do
		local a           = Instance.new("Part")
		a.Size            = Vector3.new(0.001, RING_HEIGHT, RING_WIDTH * 0.6)
		a.Anchored        = true
		a.CanCollide      = false; a.CanQuery = false; a.CastShadow = false
		a.Color           = RING_GLOW_COLOR; a.Material = Enum.Material.Neon
		a.Transparency    = 1
		a.Parent          = vFolder
		innerArcs[i]      = a
	end

	-- Ring glow light anchor
	ringAnchor            = Instance.new("Part")
	ringAnchor.Size       = Vector3.new(0.1,0.1,0.1)
	ringAnchor.Anchored   = true
	ringAnchor.CanCollide = false; ringAnchor.CanQuery = false
	ringAnchor.Transparency = 1
	ringAnchor.Parent     = vFolder
	ringLight             = Instance.new("PointLight")
	ringLight.Brightness  = 0; ringLight.Range = 14; ringLight.Color = RING_COLOR
	ringLight.Parent      = ringAnchor

	-- Pop billboard (attached to orbPart for position)
	popBB               = Instance.new("BillboardGui")
	popBB.Size          = UDim2.new(0,90,0,30)
	popBB.StudsOffset   = Vector3.new(0,2.5,0)
	popBB.AlwaysOnTop   = true
	popBB.ResetOnSpawn  = false
	popBB.Adornee       = orbPart
	popBB.Parent        = vFolder
	popLabel                       = Instance.new("TextLabel")
	popLabel.Size                  = UDim2.new(1,0,1,0)
	popLabel.BackgroundTransparency= 1
	popLabel.Font                  = Enum.Font.GothamBold
	popLabel.TextSize              = 18
	popLabel.TextColor3            = RING_COLOR
	popLabel.TextStrokeTransparency= 0.2
	popLabel.TextStrokeColor3      = Color3.new(0,0,0)
	popLabel.Text                  = ""
	popLabel.TextTransparency      = 1
	popLabel.Parent                = popBB
end

local function destroyVisuals()
	if vFolder then
		vFolder:Destroy()
		vFolder=nil; orbPart=nil; orbGlow=nil; orbShell=nil
		chainSegs={}; outerArcs={}; innerArcs={}
		ringAnchor=nil; ringLight=nil; popBB=nil; popLabel=nil
	end
end

-- ── Visibility helpers ────────────────────────────────────────────────────────
local function setRingVisible(v)
	for _,a in ipairs(outerArcs) do a.Transparency = v and 0.05 or 1 end
	for _,a in ipairs(innerArcs) do a.Transparency = v and 0.50 or 1 end
end

local function setOrbVisible(v)
	if orbPart  then orbPart.Transparency  = v and 0    or 1 end
	if orbShell then orbShell.Transparency = v and 0.74 or 1 end
	if orbGlow  then orbGlow.Brightness    = v and 5    or 0 end
end

local function setChainVisible(v)
	for _,s in ipairs(chainSegs) do s.Transparency = v and 0.5 or 1 end
end

-- ── Pop transitions ───────────────────────────────────────────────────────────
local function triggerSnap()
	setOrbVisible(false)
	setChainVisible(false)
	setRingVisible(true)

	-- Scale-bounce the arcs in
	for _,a in ipairs(outerArcs) do
		a.Size = Vector3.new(a.Size.X, RING_HEIGHT * 2.5, RING_WIDTH * 2.5)
		TweenService:Create(a, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = Vector3.new(a.Size.X, RING_HEIGHT, RING_WIDTH) }):Play()
	end
	for _,a in ipairs(innerArcs) do
		a.Size = Vector3.new(a.Size.X, RING_HEIGHT*2, RING_WIDTH*0.6*2)
		TweenService:Create(a, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = Vector3.new(a.Size.X, RING_HEIGHT, RING_WIDTH*0.6) }):Play()
	end

	if ringLight then
		ringLight.Brightness = 10
		TweenService:Create(ringLight, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 4 }):Play()
	end

	if popLabel then
		popLabel.Text = "LOCKED ON"
		popLabel.TextColor3 = RING_COLOR
		popLabel.TextTransparency = 0
		TweenService:Create(popLabel, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1 }):Play()
	end
end

local function triggerUnsnap()
	setRingVisible(false)
	if ringLight then ringLight.Brightness = 0 end
	setOrbVisible(true)
	setChainVisible(true)

	if orbPart then
		orbPart.Size = Vector3.new(ORB_RADIUS*3.5, ORB_RADIUS*3.5, ORB_RADIUS*3.5)
		TweenService:Create(orbPart, TweenInfo.new(0.20, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ Size = Vector3.new(ORB_RADIUS*2, ORB_RADIUS*2, ORB_RADIUS*2) }):Play()
	end

	if popLabel then
		popLabel.Text = "o"
		popLabel.TextColor3 = ORB_COLOR
		popLabel.TextTransparency = 0
		TweenService:Create(popLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1 }):Play()
	end
end

-- ── Chain geometry ────────────────────────────────────────────────────────────
local function updateChain(startPos, endPos)
	local delta  = endPos - startPos
	local length = delta.Magnitude
	if length < 0.01 then return end
	local dir    = delta.Unit
	local segLen = length / CHAIN_SEGMENTS
	for i, seg in ipairs(chainSegs) do
		local t      = (i - 0.5) / CHAIN_SEGMENTS
		local pos    = startPos + dir * (length * t)
		local droop  = math.sin(t * math.pi) * math.min(length * 0.045, 0.65)
		pos = pos + Vector3.new(0, -droop, 0)
		seg.Size   = Vector3.new(segLen * 1.05, CHAIN_THICKNESS, CHAIN_THICKNESS)
		seg.CFrame = CFrame.new(pos, pos + dir) * CFrame.Angles(0, math.rad(90), 0)
		local alpha = math.min(t, 1-t) * 2
		seg.Transparency = 0.15 + (1 - alpha) * 0.60
	end
end

-- ── Ring geometry ─────────────────────────────────────────────────────────────
-- centrePos : Vector3 world position of the enemy at ground level
-- The ring floats RING_Y_OFFSET studs above that point.
-- Each arc is a Block part whose:
--   CFrame  = placed at the arc's midpoint, facing tangent direction
--   Size.X  = chord length of the arc segment  (long axis = local X after lookAt)
--   Size.Y  = RING_HEIGHT  (vertical)
--   Size.Z  = RING_WIDTH   (depth, sits along the radius direction)
local function updateRing(centrePos, dt)
	ringAngle      = (ringAngle      + SPIN_OUTER * dt) % 360
	ringAngleInner = (ringAngleInner + SPIN_INNER * dt) % 360

	-- Float the ring above the floor
	local ringY = centrePos.Y + RING_Y_OFFSET

	local function placeArcs(arcs, radius, baseAngleDeg, barWidth)
		local arcDeg  = (360 / ARC_COUNT) - ARC_GAP_DEG
		local stepDeg = 360 / ARC_COUNT
		-- chord length ≈ arc length for small angles, good enough visually
		local arcLen  = math.rad(arcDeg) * radius

		for i, arc in ipairs(arcs) do
			-- Angle at the midpoint of this arc segment
			local midDeg = baseAngleDeg + stepDeg * (i-1) + arcDeg * 0.5
			local midRad = math.rad(midDeg)

			-- World position of arc midpoint (on the ring plane)
			local wx = centrePos.X + math.cos(midRad) * radius
			local wz = centrePos.Z + math.sin(midRad) * radius
			local arcPos = Vector3.new(wx, ringY, wz)

			-- Tangent direction (perpendicular to radius, in XZ plane)
			local tanRad = midRad + math.rad(90)
			local tanDir = Vector3.new(math.cos(tanRad), 0, math.sin(tanRad))

			-- lookAt aligns local +Z toward target; we want local +X along tangent,
			-- so add 90 deg around Y after the lookAt.
			arc.Size   = Vector3.new(arcLen, RING_HEIGHT, barWidth)
			arc.CFrame = CFrame.new(arcPos, arcPos + tanDir)
				* CFrame.Angles(0, math.rad(90), 0)
		end
	end

	placeArcs(outerArcs, RING_RADIUS,        ringAngle,      RING_WIDTH)
	placeArcs(innerArcs, RING_RADIUS * 0.60, ringAngleInner, RING_WIDTH * 0.6)

	if ringAnchor then
		ringAnchor.CFrame = CFrame.new(centrePos.X, ringY, centrePos.Z)
	end
end

-- ── Per-frame loop ────────────────────────────────────────────────────────────
local renderConn = nil

local function startUpdate()
	if renderConn then return end
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not active then return end

		local hrp = getHRP()
		if not hrp then return end
		local hrpPos = hrp.Position + Vector3.new(0, 0.5, 0)

		-- Project mouse onto horizontal plane at player Y
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local t
		if math.abs(ray.Direction.Y) > 0.0001 then
			t = (hrpPos.Y - ray.Origin.Y) / ray.Direction.Y
		else
			t = 30
		end
		t = math.clamp(t, 0, 200)
		local mousePt = ray.Origin + ray.Direction * t
		local rawOff  = mousePt - hrpPos
		if rawOff.Magnitude > CHAIN_MAX_LEN then
			mousePt = hrpPos + rawOff.Unit * CHAIN_MAX_LEN
		end
		orbWorldPos = mousePt

		-- Snap check
		local nearEnemy, nearId = findNearestEnemy(orbWorldPos)
		local newSnap = nearEnemy ~= nil
		if newSnap ~= wasSnapped then
			if newSnap then triggerSnap() else triggerUnsnap() end
		end
		wasSnapped     = newSnap
		isSnapped      = newSnap
		snappedEnemy   = nearEnemy
		snappedEnemyId = nearId

		if not isSnapped then
			-- Roaming: orb + chain
			local alpha  = 1 - (1 - ORB_LERP) ^ (dt * 60)
			orbVisualPos = orbVisualPos:Lerp(orbWorldPos, alpha)

			if orbPart then
				local pulse = math.sin(tick() * 4.5) * 0.055 + 1
				local s = ORB_RADIUS * 2 * pulse
				orbPart.Size   = Vector3.new(s, s, s)
				orbPart.CFrame = CFrame.new(orbVisualPos)
			end
			if orbShell then
				local ps = math.sin(tick() * 4.5 + 1) * 0.04 + 1
				local ss = ORB_RADIUS * 4 * ps
				orbShell.Size   = Vector3.new(ss, ss, ss)
				orbShell.CFrame = CFrame.new(orbVisualPos)
			end
			updateChain(hrpPos, orbVisualPos)

		else
			-- Snapped: ring under enemy
			if snappedEnemy and snappedEnemy.Parent then
				local enemyPos = snappedEnemy:GetPivot().Position

				-- Ground level = tile top surface, computed from Config
				-- TILE_HEIGHT/2 is the tile's half-height; tile CFrame Y sits at
				-- TILE_HEIGHT/2, so tile top = TILE_HEIGHT.  Add a small offset.
				local tileTopY = Config.TILE_HEIGHT

				-- Use the enemy's X/Z but pin Y to tile top
				local centrePos = Vector3.new(enemyPos.X, tileTopY, enemyPos.Z)

				-- Keep orbPart tracking enemy (billboard anchor for pop text)
				local sa = 1 - (1 - SNAP_LERP) ^ (dt * 60)
				orbVisualPos = orbVisualPos:Lerp(enemyPos, sa)
				if orbPart  then orbPart.CFrame  = CFrame.new(orbVisualPos) end
				if orbShell then orbShell.CFrame = CFrame.new(orbVisualPos) end

				updateRing(centrePos, dt)
			end
		end
	end)
end

local function stopUpdate()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
end

-- ── Activate / deactivate ─────────────────────────────────────────────────────
local function activate()
	if active then return end
	if not isAlive() then return end
	active=true; isSnapped=false; wasSnapped=false
	snappedEnemy=nil; snappedEnemyId=nil
	ringAngle=0; ringAngleInner=0
	local hrp = getHRP()
	orbVisualPos = hrp and hrp.Position or Vector3.zero
	buildVisuals()
	setRingVisible(false)
	setOrbVisible(true)
	setChainVisible(true)
	startUpdate()
end

local function deactivate()
	if not active then return end
	active = false
	stopUpdate()
	if isSnapped and snappedEnemyId then
		RequestAttack:FireServer(snappedEnemyId)
	end
	isSnapped=false; wasSnapped=false; snappedEnemy=nil; snappedEnemyId=nil
	destroyVisuals()
end

-- ── Input ─────────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == TARGETING_KEY then activate() end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if input.KeyCode == TARGETING_KEY then deactivate() end
end)

-- ── Respawn cleanup ───────────────────────────────────────────────────────────
player.CharacterAdded:Connect(function()
	active=false; stopUpdate(); destroyVisuals()
	isSnapped=false; wasSnapped=false; snappedEnemy=nil; snappedEnemyId=nil
end)

-- ── Public API ────────────────────────────────────────────────────────────────
local M = {}
function M.IsActive()          return active          end
function M.GetSnappedEnemyId() return snappedEnemyId  end
return M
