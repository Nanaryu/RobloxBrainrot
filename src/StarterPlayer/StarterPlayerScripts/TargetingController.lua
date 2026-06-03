-- StarterPlayer/StarterPlayerScripts/TargetingController.client.lua
-- Hold-to-target enemy selection system.
-- Hold [E] → circle-on-chain follows mouse → auto-snaps to closest enemy → release to attack.
-- Fully client-side visuals; server interaction via RequestAttack remote only.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestAttack = Remotes:WaitForChild("RequestAttack")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

-- ─── Tuning ───────────────────────────────────────────────────────────────────
local KEYBIND         = Enum.KeyCode.E
local CHAIN_BEADS     = 8
local BEAD_SIZE       = 0.12
local SNAP_RANGE_PX   = 60       -- screen-space px: mouse→enemy to trigger snap
local SNAP_WORLD_DIST = 14       -- world studs: reticle→enemy to allow attack
local LERP_SPEED      = 0.22     -- reticle follow smoothing (lower = snappier)
local CHAIN_LERP      = 0.14

-- ─── State ────────────────────────────────────────────────────────────────────
local active     = false
local snapped    = false
local target     = nil   -- Model
local targetId   = nil   -- string

local reticleX   = 0
local reticleY   = 0

local cRender, cHeart
local inputConn

-- ─── ScreenGui layer ──────────────────────────────────────────────────────────
local gui                 = Instance.new("ScreenGui")
gui.Name                  = "TargetingGui"
gui.ResetOnSpawn          = false
gui.DisplayOrder          = 50
gui.IgnoreGuiInset        = true
gui.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
gui.Enabled               = false
gui.Parent                = player.PlayerGui

-- ─── Reticle ring ─────────────────────────────────────────────────────────────
local ring                = Instance.new("Frame")
ring.Name                 = "Ring"
ring.AnchorPoint          = Vector2.new(0.5, 0.5)
ring.Size                 = UDim2.new(0, 120, 0, 120)
ring.BackgroundTransparency = 1
ring.BorderSizePixel      = 0
ring.Visible              = false
ring.Parent               = gui

local ringCorner          = Instance.new("UICorner")
ringCorner.CornerRadius   = UDim.new(1, 0)
ringCorner.Parent         = ring

local ringStroke          = Instance.new("UIStroke")
ringStroke.Color          = Color3.fromRGB(0, 220, 255)
ringStroke.Thickness      = 2.5
ringStroke.Transparency   = 0.15
ringStroke.Parent         = ring

local ringFill            = Instance.new("Frame")
ringFill.Name             = "Fill"
ringFill.Size             = UDim2.new(1, 0, 1, 0)
ringFill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
ringFill.BackgroundTransparency = 0.92
ringFill.BorderSizePixel  = 0
ringFill.Parent           = ring
local ringFillCorner      = Instance.new("UICorner")
ringFillCorner.CornerRadius = UDim.new(1, 0)
ringFillCorner.Parent     = ringFill

-- Center crosshair dot
local dot                 = Instance.new("Frame")
dot.Name                  = "Dot"
dot.AnchorPoint           = Vector2.new(0.5, 0.5)
dot.Size                  = UDim2.new(0, 6, 0, 6)
dot.BackgroundColor3      = Color3.fromRGB(0, 255, 255)
dot.BackgroundTransparency = 0.15
dot.BorderSizePixel       = 0
dot.Visible               = false
dot.Parent                = gui
local dotCorner           = Instance.new("UICorner")
dotCorner.CornerRadius    = UDim.new(1, 0)
dotCorner.Parent          = dot

-- Glow ring (pulsing backdrop)
local glow                = Instance.new("Frame")
glow.Name                 = "Glow"
glow.AnchorPoint          = Vector2.new(0.5, 0.5)
glow.Size                 = UDim2.new(0, 150, 0, 150)
glow.BackgroundTransparency = 0.82
glow.BackgroundColor3     = Color3.fromRGB(0, 140, 255)
glow.BorderSizePixel      = 0
glow.Visible              = false
glow.Parent               = gui
local glowCorner          = Instance.new("UICorner")
glowCorner.CornerRadius   = UDim.new(1, 0)
glowCorner.Parent         = glow

-- ─── Chain beads (circles connected to player) ────────────────────────────────
local beadFrames = {}
for i = 1, CHAIN_BEADS do
	local b               = Instance.new("Frame")
	b.Name                = "Bead" .. i
	b.AnchorPoint         = Vector2.new(0.5, 0.5)
	b.Size                = UDim2.new(0, BEAD_SIZE * 80, 0, BEAD_SIZE * 80)
	b.BackgroundColor3    = Color3.fromRGB(0, 200, 240)
	b.BackgroundTransparency = 0.25
	b.BorderSizePixel     = 0
	b.Visible             = false
	b.Parent              = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	beadFrames[i] = b
end

-- ─── Chain beam (thick line from player → reticle) ────────────────────────────
local chainPart           = Instance.new("Part")
chainPart.Name            = "ChainBeam"
chainPart.Anchored        = true
chainPart.CanCollide      = false
chainPart.CanQuery        = false
chainPart.CanTouch        = false
chainPart.Transparency    = 1
chainPart.Size            = Vector3.new(0.2, 0.2, 0.2)
chainPart.CFrame          = CFrame.new(0, 0, 0)
chainPart.Parent          = workspace.CurrentCamera

local att0                = Instance.new("Attachment")
att0.Parent               = chainPart
local att1                = Instance.new("Attachment")
att1.Parent               = chainPart

local chainBeam           = Instance.new("Beam")
chainBeam.Attachment0     = att0
chainBeam.Attachment1     = att1
chainBeam.Color           = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 240, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 80, 200)),
})
chainBeam.Transparency    = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(1, 0.75),
})
chainBeam.Width0          = 0.06
chainBeam.Width1          = 0.03
chainBeam.FaceCamera      = true
chainBeam.LightEmission   = 0.6
chainBeam.LightInfluence  = 0.2
chainBeam.Enabled         = false
chainBeam.Parent          = chainPart

-- ─── Target highlight ─────────────────────────────────────────────────────────
local highlight               = Instance.new("Highlight")
highlight.Name                = "TargetHL"
highlight.FillColor           = Color3.fromRGB(0, 200, 255)
highlight.FillTransparency    = 0.7
highlight.OutlineColor        = Color3.fromRGB(0, 255, 200)
highlight.OutlineTransparency = 0.15
highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Adornee             = nil
highlight.Parent              = player.PlayerGui

-- ─── Snap burst particles ─────────────────────────────────────────────────────
local snapParticles             = Instance.new("Part")
snapParticles.Name              = "SnapBurst"
snapParticles.Anchored          = true
snapParticles.CanCollide        = false
snapParticles.CanQuery         = false
snapParticles.CanTouch         = false
snapParticles.Transparency     = 1
snapParticles.Size             = Vector3.new(0.2, 0.2, 0.2)
snapParticles.Parent           = workspace.CurrentCamera

local snapEmitter              = Instance.new("ParticleEmitter")
snapEmitter.Color              = ColorSequence.new(Color3.fromRGB(0, 255, 220))
snapEmitter.Size               = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(1, 0),
})
snapEmitter.Transparency       = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.4, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})
snapEmitter.Lifetime           = NumberRange.new(0.25, 0.45)
snapEmitter.Speed              = NumberRange.new(18, 35)
snapEmitter.SpreadAngle        = Vector2.new(360, 360)
snapEmitter.RotSpeed           = NumberRange.new(-180, 180)
snapEmitter.Rotation           = NumberRange.new(0, 360)
snapEmitter.Rate               = 0
snapEmitter.LightEmission      = 1
snapEmitter.LightInfluence     = 0
snapEmitter.Parent             = snapParticles

-- ─── Unsnap ring particles ────────────────────────────────────────────────────
local unsnapParticles           = Instance.new("Part")
unsnapParticles.Name            = "UnsnapBurst"
unsnapParticles.Anchored        = true
unsnapParticles.CanCollide      = false
unsnapParticles.CanQuery       = false
unsnapParticles.CanTouch       = false
unsnapParticles.Transparency   = 1
unsnapParticles.Size           = Vector3.new(0.2, 0.2, 0.2)
unsnapParticles.Parent         = workspace.CurrentCamera

local unsnapEmitter            = Instance.new("ParticleEmitter")
unsnapEmitter.Color            = ColorSequence.new(Color3.fromRGB(255, 100, 60))
unsnapEmitter.Size             = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 0),
})
unsnapEmitter.Transparency     = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})
unsnapEmitter.Lifetime         = NumberRange.new(0.2, 0.4)
unsnapEmitter.Speed            = NumberRange.new(14, 28)
unsnapEmitter.SpreadAngle      = Vector2.new(360, 360)
unsnapEmitter.RotSpeed         = NumberRange.new(-120, 120)
unsnapEmitter.Rotation         = NumberRange.new(0, 360)
unsnapEmitter.Rate             = 0
unsnapEmitter.LightEmission    = 1
unsnapEmitter.LightInfluence   = 0
unsnapEmitter.Parent           = unsnapParticles

-- ─── Utility (must be before arc indicator) ───────────────────────────────────
local function worldToScreen(wp: Vector3): (number, number, boolean)
	local cam = workspace.CurrentCamera
	local sp, onScreen = cam:WorldToViewportPoint(wp)
	return sp.X, sp.Y, onScreen
end

local function isEnemyAlive(model: Model): boolean
	if not model or not model.Parent then return false end
	local state = model:GetAttribute("State")
	if state == "dead" or not state then return false end
	local hp = model:GetAttribute("CurrentHP")
	return hp ~= nil and hp > 0
end

-- ─── Arc indicator (selected enemy rotating ring) ─────────────────────────────
local ARC_SEGS   = 6
local ARC_RADIUS = 42
local ARC_SEG_W  = 22
local ARC_SEG_H  = 4
local ARC_SPEED  = 100 -- deg/s

local arcScreenGui              = Instance.new("ScreenGui")
arcScreenGui.Name               = "ArcIndicatorGui"
arcScreenGui.ResetOnSpawn       = false
arcScreenGui.DisplayOrder       = 51
arcScreenGui.IgnoreGuiInset     = true
arcScreenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
arcScreenGui.Enabled            = false
arcScreenGui.Parent             = player.PlayerGui

local arcFrame                  = Instance.new("Frame")
arcFrame.Name                   = "ArcRing"
arcFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
arcFrame.Size                   = UDim2.new(0, ARC_RADIUS * 2 + ARC_SEG_W, 0, ARC_RADIUS * 2 + ARC_SEG_H)
arcFrame.BackgroundTransparency = 1
arcFrame.BorderSizePixel        = 0
arcFrame.Parent                 = arcScreenGui

local arcSegs = {}
for i = 1, ARC_SEGS do
	local ang = (i - 1) / ARC_SEGS * 360
	local rad = math.rad(ang)
	local s   = Instance.new("Frame")
	s.Name    = "S" .. i
	s.AnchorPoint         = Vector2.new(0.5, 0.5)
	s.Size                = UDim2.new(0, ARC_SEG_W, 0, ARC_SEG_H)
	s.Position            = UDim2.new(0.5, math.cos(rad) * ARC_RADIUS, 0.5, math.sin(rad) * ARC_RADIUS)
	s.Rotation            = ang
	s.BackgroundColor3    = Color3.fromRGB(0, 220, 255)
	s.BackgroundTransparency = 0.05
	s.BorderSizePixel     = 0
	s.Parent              = arcFrame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = s
	arcSegs[i] = s
end

local arcGlow                  = Instance.new("Frame")
arcGlow.Name                   = "Glow"
arcGlow.AnchorPoint            = Vector2.new(0.5, 0.5)
arcGlow.Size                   = UDim2.new(0, ARC_RADIUS * 2 + 20, 0, ARC_RADIUS * 2 + 20)
arcGlow.BackgroundColor3       = Color3.fromRGB(0, 180, 255)
arcGlow.BackgroundTransparency = 0.85
arcGlow.BorderSizePixel        = 0
arcGlow.Parent                 = arcFrame
local arcGlowC                 = Instance.new("UICorner")
arcGlowC.CornerRadius          = UDim.new(1, 0)
arcGlowC.Parent                = arcGlow

local arcVisible  = false
local arcAngle    = 0
local arcWorldPos = nil
local arcColor    = Color3.fromRGB(0, 220, 255)
local cArcRender  = nil

local function updateArc(dt: number)
	if not arcVisible or not arcWorldPos then return end
	arcAngle = arcAngle + dt * ARC_SPEED
	arcFrame.Rotation = arcAngle

	local sx, sy, onScreen = worldToScreen(arcWorldPos)
	if onScreen then
		arcFrame.Position = UDim2.new(0, sx, 0, sy)
		arcFrame.Visible  = true
	else
		arcFrame.Visible = false
	end
end

local function showArcRender()
	if cArcRender then return end
	cArcRender = RunService.RenderStepped:Connect(updateArc)
end

local function hideArcRender()
	if cArcRender then
		cArcRender:Disconnect()
		cArcRender = nil
	end
end

-- ─── Sounds ───────────────────────────────────────────────────────────────────
local function playSound(id: string, volume: number)
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume  = volume or 0.4
	s.Parent  = workspace.CurrentCamera
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end

-- ─── Utility ──────────────────────────────────────────────────────────────────
local function destroyInstance(obj: Instance?)
	if obj and obj.Parent then obj:Destroy() end
end

local function closestEnemyToMouse(): (Model?, number)
	local best, bestDist = nil, math.huge
	local map     = workspace:FindFirstChild("Map")
	local enemies = map and map:FindFirstChild("Enemies")
	if not enemies then return nil, math.huge end

	for _, m in ipairs(enemies:GetChildren()) do
		if isEnemyAlive(m) then
			local pp = m.PrimaryPart and m.PrimaryPart.Position
				or m:GetPivot().Position
			local sx, sy, onScreen = worldToScreen(pp)
			if onScreen then
				local d = (Vector2.new(sx, sy) - Vector2.new(mouse.X, mouse.Y)).Magnitude
				if d < bestDist then
					bestDist = d
					best     = m
				end
			end
		end
	end
	return best, bestDist
end

local function worldDist(a, b): number
	local pa = a.PrimaryPart and a.PrimaryPart.Position or a:GetPivot().Position
	local pb = b.PrimaryPart and b.PrimaryPart.Position or b:GetPivot().Position
	return (pa - pb).Magnitude
end

-- ─── Visual: show / hide ──────────────────────────────────────────────────────
local function show()
	gui.Enabled       = true
	ring.Visible      = true
	dot.Visible       = true
	glow.Visible      = true
	chainBeam.Enabled = true
	for _, b in ipairs(beadFrames) do b.Visible = true end
end

local function hide()
	gui.Enabled       = false
	ring.Visible      = false
	dot.Visible       = false
	glow.Visible      = false
	chainBeam.Enabled = false
	for _, b in ipairs(beadFrames) do b.Visible = false end
end

-- ─── Visual: position + animate ───────────────────────────────────────────────
local pulseT = 0

local function updateVisuals(dt: number)
	-- Player screen position
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local px, py, pOn = worldToScreen(hrp.Position)
	if not pOn then return end

	-- Reticle target position
	local tx, ty
	if snapped and target and isEnemyAlive(target) then
		local pp = target.PrimaryPart and target.PrimaryPart.Position
			or target:GetPivot().Position
		local sx, sy, onS = worldToScreen(pp)
		if onS then tx, ty = sx, sy end
	end
	if not tx then tx, ty = mouse.X, mouse.Y end

	-- Lerp reticle
	reticleX += (tx - reticleX) * math.clamp(dt / LERP_SPEED, 0, 1)
	reticleY += (ty - reticleY) * math.clamp(dt / LERP_SPEED, 0, 1)

	-- Pulse when snapped
	pulseT += dt * (snapped and 8 or 3)
	local pulse = snapped and (1 + math.sin(pulseT) * 0.12) or 1

	-- Ring
	local ringSize = snapped and 100 * pulse or 120
	ring.Position = UDim2.new(0, reticleX, 0, reticleY)
	ring.Size     = UDim2.new(0, ringSize, 0, ringSize)

	ringStroke.Color = snapped
		and Color3.fromRGB(255, 220, 50)
		or  Color3.fromRGB(0, 220, 255)
	ringStroke.Thickness = snapped and 3 or 2.5

	ringFill.BackgroundColor3 = snapped
		and Color3.fromRGB(255, 200, 50)
		or  Color3.fromRGB(0, 180, 255)
	ringFill.BackgroundTransparency = snapped and 0.82 or 0.92

	-- Glow
	glow.Position = UDim2.new(0, reticleX, 0, reticleY)
	glow.Size     = UDim2.new(0, ringSize * 1.35, 0, ringSize * 1.35)
	glow.BackgroundColor3 = snapped
		and Color3.fromRGB(255, 180, 40)
		or  Color3.fromRGB(0, 140, 255)
	glow.BackgroundTransparency = snapped and 0.7 or 0.82

	-- Dot
	dot.Position = UDim2.new(0, reticleX, 0, reticleY)

	-- Chain beads
	for i = 1, CHAIN_BEADS do
		local t  = i / (CHAIN_BEADS + 1)
		local bx = px + (reticleX - px) * t
		local by = py + (reticleY - py) * t
		local b  = beadFrames[i]
		local shrink = 1 - t * 0.4
		b.Position = UDim2.new(0, bx, 0, by)
		b.Size     = UDim2.new(0, BEAD_SIZE * 80 * shrink, 0, BEAD_SIZE * 80 * shrink)
		b.BackgroundTransparency = 0.25 + t * 0.45
	end

	-- Chain beam (3D)
	local cam  = workspace.CurrentCamera
	local camCF = cam.CFrame
	local dir  = (hrp.Position - camCF.Position).Unit
	local near = camCF.Position + dir * 0.5
	local far  = camCF.Position + dir * 200
	local ray  = workspace:Raycast(near, far - near, RaycastParams.new())

	local worldReticle
	if ray and ray.Instance then
		worldReticle = ray.Position
	else
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { char }
		local down = workspace:Raycast(
			Vector3.new(mouse.X, 500, mouse.Y),
			Vector3.new(0, -1000, 0),
			rayParams
		)
		worldReticle = down and down.Position
			or (camCF + camCF.LookVector * 40).Position
	end

	att0.WorldCFrame = CFrame.new(hrp.Position + Vector3.new(0, 2.5, 0))
	att1.WorldCFrame = CFrame.new(worldReticle + Vector3.new(0, 1, 0))

	chainBeam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, snapped
			and Color3.fromRGB(255, 220, 50)
			or  Color3.fromRGB(0, 240, 255)),
		ColorSequenceKeypoint.new(1, snapped
			and Color3.fromRGB(255, 160, 30)
			or  Color3.fromRGB(0, 80, 200)),
	})
end

-- ─── Snap / unsnap ────────────────────────────────────────────────────────────
local function doSnap(model: Model)
	if not model or not model.PrimaryPart then return end
	target   = model
	targetId = model:GetAttribute("EnemyId")
	snapped  = true

	-- Selection highlight
	highlight.Adornee = model.PrimaryPart

	-- Burst particles
	snapParticles.CFrame = CFrame.new(model.PrimaryPart.Position)
	snapEmitter:Emit(22)
	task.delay(0.5, function() snapParticles.CFrame = CFrame.new(0, -999, 0) end)

	-- Sound
	playSound(Config.SOUND_HIT_ID ~= "" and Config.SOUND_HIT_ID
		or "rbxassetid://6895079853", 0.35)

	-- Snap tween
	TweenService:Create(ring,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 90, 0, 90) }
	):Play()
end

local function doUnsnap()
	if not snapped then return end
	local oldTarget = target

	target   = nil
	targetId = nil
	snapped  = false
	highlight.Adornee = nil

	-- Ring particles
	if oldTarget and oldTarget.PrimaryPart then
		unsnapParticles.CFrame = CFrame.new(oldTarget.PrimaryPart.Position)
		unsnapEmitter:Emit(14)
		task.delay(0.4, function() unsnapParticles.CFrame = CFrame.new(0, -999, 0) end)
	end

	-- Sound
	playSound("rbxassetid://6895079853", 0.2)

	-- Shrink tween
	TweenService:Create(ring,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 120, 0, 120) }
	):Play()
end

-- ─── Per-frame scan ───────────────────────────────────────────────────────────
local function scanForTarget()
	if not active then return end

	local closest, dist = closestEnemyToMouse()

	if snapped then
		-- Lose target: dead, gone, or mouse drifted too far
		if not isEnemyAlive(target)
			or not target.Parent
			or (closest ~= target and dist < SNAP_RANGE_PX) then
			doUnsnap()
		end
	else
		-- Acquire target
		if closest and dist <= SNAP_RANGE_PX then
			doSnap(closest)
		end
	end
end

-- ─── Keybind ──────────────────────────────────────────────────────────────────
local function onInput(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.KeyCode ~= KEYBIND then return end

	if input.UserInputState == Enum.UserInputState.Begin then
		if active then return end
		if not isEnemyAlive(player.Character
			and player.Character:FindFirstChildOfClass("Humanoid")) then
			return
		end

		active = true
		show()
		pulseT = 0

		-- Position reticle at mouse start
		reticleX = mouse.X
		reticleY = mouse.Y

		cRender = RunService.RenderStepped:Connect(updateVisuals)
		cHeart  = RunService.Heartbeat:Connect(scanForTarget)

	elseif input.UserInputState == Enum.UserInputState.End then
		if not active then return end

		-- Attack on release if snapped
		if snapped and target and isEnemyAlive(target) then
			local dist = worldDist(player.Character, target)
			if dist <= SNAP_WORLD_DIST then
				RequestAttack:FireServer(targetId)
				playSound(Config.SOUND_HIT_ID ~= "" and Config.SOUND_HIT_ID
					or "rbxassetid://6895079853", 0.5)
			end
		end

		-- Tear down
		if cRender then cRender:Disconnect() cRender = nil end
		if cHeart  then cHeart:Disconnect()  cHeart  = nil end

		hide()
		target   = nil
		targetId = nil
		snapped  = false
		highlight.Adornee = nil
	end
end

inputConn = UserInputService.InputBegan:Connect(onInput)

-- Reset icon on respawn
player.CharacterAdded:Connect(function()
	mouse.Icon = ""
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
local M = {}
function M.IsActive()  return active end
function M.GetTarget() return target, targetId end

function M.ShowArc(wp: Vector3, color: Color3)
	arcVisible  = true
	arcWorldPos = wp
	arcColor    = color or arcColor
	arcAngle    = 0
	arcScreenGui.Enabled = true
	for _, s in ipairs(arcSegs) do
		s.BackgroundColor3 = arcColor
	end
	arcGlow.BackgroundColor3 = arcColor
	showArcRender()
end

function M.UpdateArcPosition(wp: Vector3)
	arcWorldPos = wp
end

function M.SetArcColor(color: Color3)
	arcColor = color
	for _, s in ipairs(arcSegs) do
		s.BackgroundColor3 = color
	end
	arcGlow.BackgroundColor3 = color
end

function M.HideArc()
	arcVisible    = false
	arcWorldPos   = nil
	arcScreenGui.Enabled = false
	hideArcRender()
end

return M
