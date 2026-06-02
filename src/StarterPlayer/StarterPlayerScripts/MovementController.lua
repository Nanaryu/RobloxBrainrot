-- StarterPlayer/StarterPlayerScripts/MovementController.lua
-- Click-to-move, cardinal only. No diagonal movement.
-- Multi-tile paths use server A* and animate step-by-step.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local player = Players.LocalPlayer

local MOVE_SPEED = Config.TILE_SIZE / Config.MOVE_TWEEN_TIME
local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)

-- Returns current player speed (tween time per tile) based on level
local function getPlayerSpeed()
	local char = player.Character
	local ls = char and char:FindFirstChild("leaderstats")
	local level = ls and ls:FindFirstChild("Level") and ls.Level.Value or 1
	local t = math.clamp(level / Config.PLAYER_SPEED_LEVEL, 0, 1)
	return Config.PLAYER_SPEED_BASE + (Config.PLAYER_SPEED_MIN - Config.PLAYER_SPEED_BASE) * t
end

-- ─── Tile helpers ─────────────────────────────────────────────────────────────
local function tileToWorld(tx, tz)
	return Vector3.new(
		(tx - 0.5) * Config.TILE_SIZE,
		Config.TILE_HEIGHT + 3.0,
		(tz - 0.5) * Config.TILE_SIZE
	)
end

local function getTilePart(tx, tz)
	local map = workspace:FindFirstChild("Map")
	local tg  = map and map:FindFirstChild("TileGrid")
	local ts  = tg  and tg:FindFirstChild("Tiles")
	return ts and ts:FindFirstChild(("Tile_%d_%d"):format(tx, tz))
end

local function isTileWalkable(tx, tz)
	local t = getTilePart(tx, tz)
	return t ~= nil and t:GetAttribute("Walkable") ~= false
end

local function isEnemyOnTile(tx, tz)
	local map     = workspace:FindFirstChild("Map")
	local enemies = map and map:FindFirstChild("Enemies")
	if not enemies then return false end
	for _, m in ipairs(enemies:GetChildren()) do
		if m:GetAttribute("State") ~= "dead" then
			local cx = m:GetAttribute("CurrentTileX")
			local cz = m:GetAttribute("CurrentTileZ")
			local mx = m:GetAttribute("MovingToTileX")
			local mz = m:GetAttribute("MovingToTileZ")
			if (cx == tx and cz == tz) or (mx == tx and mz == tz) then
				return true
			end
		end
	end
	return false
end

-- ─── State ────────────────────────────────────────────────────────────────────
local currentTileX          = 1
local currentTileZ          = 1
local isMoving              = false
local moveToken             = 0
local moveRequestId         = 0
local acceptedMoveRequestId = 0
local requestedTileX        = nil
local requestedTileZ        = nil
local destinationHighlight  = nil

-- `spawned` tracks whether the server has confirmed our initial tile placement.
-- It is only used inside PlayerMoved to distinguish a spawn snap from a path update.
-- It does NOT block requestMove — clicks before spawn are queued and replayed.
local spawned = false

-- If the player clicks before the server has confirmed spawn, we store their
-- intended destination here and re-issue it the moment we receive the spawn snap.
local pendingTileX = nil
local pendingTileZ = nil

local hrp         = nil
local humanoid    = nil
local walkTrack   = nil
local activeTween = nil

local function isAlive()
	return humanoid ~= nil and humanoid.Health > 0
end

-- ─── Walk animation ───────────────────────────────────────────────────────────
local function setupWalkAnimation()
	walkTrack = nil
	if not humanoid then return end
	local anim = humanoid:FindFirstChildOfClass("Animator")
	if not anim then anim = Instance.new("Animator") anim.Parent = humanoid end
	local a        = Instance.new("Animation")
	a.AnimationId  = humanoid.RigType == Enum.HumanoidRigType.R6
		and "rbxassetid://180426354" or "rbxassetid://507777826"
	walkTrack          = anim:LoadAnimation(a)
	walkTrack.Looped   = true
	walkTrack.Priority = Enum.AnimationPriority.Movement
end

local function playWalk()
	if walkTrack and not walkTrack.IsPlaying then walkTrack:Play(0.08) end
end
local function stopWalk()
	if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.12) end
end

-- ─── Destination highlight ────────────────────────────────────────────────────
local function clearHighlight()
	if destinationHighlight then
		destinationHighlight:Destroy()
		destinationHighlight = nil
	end
end

local function setHighlight(tx, tz)
	clearHighlight()
	local tile = getTilePart(tx, tz)
	if not tile then return end
	local h               = Instance.new("Highlight")
	h.Adornee             = tile
	h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor           = Color3.fromRGB(80, 210, 255)
	h.FillTransparency    = 0.68
	h.OutlineColor        = Color3.fromRGB(170, 245, 255)
	h.OutlineTransparency = 0
	h.Parent              = tile
	destinationHighlight  = h
end

-- ─── Character setup ──────────────────────────────────────────────────────────
local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")

	humanoid.WalkSpeed     = 0
	humanoid.JumpPower     = 0
	humanoid.AutoRotate    = false
	humanoid.PlatformStand = false
	hrp.Anchored           = true
	setupWalkAnimation()

	humanoid.Died:Connect(function()
		spawned    = false
		moveToken += 1
		isMoving   = false
		if activeTween then activeTween:Cancel() activeTween = nil end
		stopWalk()
		clearHighlight()
		requestedTileX = nil
		requestedTileZ = nil
		pendingTileX   = nil
		pendingTileZ   = nil
	end)

	isMoving       = false
	moveToken     += 1
	requestedTileX = nil
	requestedTileZ = nil
	pendingTileX   = nil
	pendingTileZ   = nil
	spawned        = false
	clearHighlight()
	if activeTween then activeTween:Cancel() activeTween = nil end
	stopWalk()
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

-- ─── Core mover: slide HRP to targetPos at constant speed ────────────────────
local function slideToWorld(targetPos, facingDir, token)
	if not hrp or not isAlive() then return false end

	local speed = getPlayerSpeed()
	local moveSpeed = Config.TILE_SIZE / speed

	while token == moveToken and isAlive() and hrp do
		local delta = Vector3.new(
			targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
		if delta.Magnitude <= 0.03 then break end

		local dt   = RunService.Heartbeat:Wait()
		local step = math.min(delta.Magnitude, moveSpeed * dt)
		local dir  = delta.Unit
		facingDir  = dir
		hrp.CFrame = CFrame.lookAt(
			hrp.Position + dir * step,
			hrp.Position + dir * step + dir)
	end

	if token ~= moveToken or not isAlive() then return false end
	if facingDir.Magnitude > 0 then
		hrp.CFrame = CFrame.lookAt(targetPos, targetPos + facingDir)
	else
		hrp.CFrame = CFrame.new(targetPos)
	end
	return true
end

-- Move to a single tile; returns false if interrupted.
local function moveStep(tx, tz, token)
	local target = tileToWorld(tx, tz)
	local facing = Vector3.new(tx - currentTileX, 0, tz - currentTileZ)
	if facing.Magnitude <= 0 then
		facing = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
	end
	local ok = slideToWorld(
		target,
		facing.Magnitude > 0 and facing.Unit or facing,
		token)
	if ok then currentTileX, currentTileZ = tx, tz end
	return ok
end

-- ─── Animate a server-approved path ──────────────────────────────────────────
local function animatePath(path)
	if not path or #path == 0 then return end
	moveToken += 1
	local token = moveToken
	isMoving    = true
	playWalk()

	local finalX = path[#path][1]
	local finalZ = path[#path][2]

	for _, step in ipairs(path) do
		if token ~= moveToken then return end
		if not moveStep(step[1], step[2], token) then
			if token == moveToken then stopWalk() end
			return
		end
	end

	isMoving    = false
	activeTween = nil
	if requestedTileX == finalX and requestedTileZ == finalZ then
		requestedTileX = nil
		requestedTileZ = nil
		clearHighlight()
	end
	stopWalk()
end

-- ─── Fire move request to server ──────────────────────────────────────────────
local function fireMoveRequest(tx, tz)
	moveRequestId += 1
	local rid      = moveRequestId
	requestedTileX = tx
	requestedTileZ = tz
	RequestMove:FireServer(tx, tz, currentTileX, currentTileZ, rid)
	-- If the server doesn't respond within 0.8 s (e.g. blocked tile), clean up.
	task.delay(0.8, function()
		if requestedTileX == tx and requestedTileZ == tz
			and acceptedMoveRequestId < rid then
			requestedTileX = nil
			requestedTileZ = nil
			clearHighlight()
		end
	end)
end

-- ─── Request a move to any walkable tile ──────────────────────────────────────
local function requestMove(tx, tz)
	if not hrp or not isAlive() then return end
	tx = math.clamp(math.floor(tx), 1, Config.GRID_WIDTH)
	tz = math.clamp(math.floor(tz), 1, Config.GRID_HEIGHT)
	if not isTileWalkable(tx, tz) then return end
	if isEnemyOnTile(tx, tz) then return end

	-- Cap click distance to prevent laggy long-range pathfinding
	local clickDist = math.abs(tx - currentTileX) + math.abs(tz - currentTileZ)
	if clickDist > Config.MAX_CLICK_DISTANCE then return end

	-- If the server hasn't confirmed our spawn tile yet, queue the destination
	-- and let the PlayerMoved spawn-snap handler replay it.
	if not spawned then
		pendingTileX = tx
		pendingTileZ = tz
		setHighlight(tx, tz)
		return
	end

	if tx == currentTileX and tz == currentTileZ then return end
	if requestedTileX == tx and requestedTileZ == tz then return end

	setHighlight(tx, tz)
	fireMoveRequest(tx, tz)
	-- animatePath is triggered by the PlayerMoved response from the server.
end

-- ─── PlayerMoved remote ───────────────────────────────────────────────────────
PlayerMoved.OnClientEvent:Connect(function(userId, tx, tz, path, requestId)
	-- ── Other player: tween their character along the path ────────────────────
	if userId ~= player.UserId then
		local other = Players:GetPlayerByUserId(userId)
		if not other or not other.Character then return end
		local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
		if not otherHRP then return end

		local prevX = otherHRP:GetAttribute("LastTileX")
		local prevZ = otherHRP:GetAttribute("LastTileZ")
		path = path or { {tx, tz} }
		task.spawn(function()
			for _, step in ipairs(path) do
				local sx, sz = step[1], step[2]
				local pos    = tileToWorld(sx, sz)
				local cf
				if prevX and prevZ and (sx ~= prevX or sz ~= prevZ) then
					cf = CFrame.lookAt(pos, pos + Vector3.new(sx - prevX, 0, sz - prevZ))
				else
					cf = CFrame.new(pos)
				end
				prevX, prevZ = sx, sz
				otherHRP:SetAttribute("LastTileX", sx)
				otherHRP:SetAttribute("LastTileZ", sz)
				local tw = TweenService:Create(otherHRP, MOVE_TWEEN, { CFrame = cf })
				tw:Play()
				tw.Completed:Wait()
			end
		end)
		return
	end

	if not isAlive() then return end

	-- ── Initial spawn snap ────────────────────────────────────────────────────
	-- The server sends PlayerMoved with no path on first spawn.
	if not spawned then
		spawned        = true
		currentTileX   = tx
		currentTileZ   = tz
		requestedTileX = nil
		requestedTileZ = nil
		moveToken     += 1
		clearHighlight()
		if hrp then hrp.CFrame = CFrame.new(tileToWorld(tx, tz)) end

		-- Replay any click the player made before the snap arrived.
		if pendingTileX and pendingTileZ then
			local ptx, ptz = pendingTileX, pendingTileZ
			pendingTileX   = nil
			pendingTileZ   = nil
			-- Re-enter through requestMove now that spawned = true.
			task.defer(function() requestMove(ptx, ptz) end)
		end
		return
	end

	-- ── Attack-move path (server-driven walk-to-enemy) ─────────────────────────
	if requestId == -1 and path and #path > 0 then
		-- Cancel any current movement
		moveToken += 1
		isMoving = false
		requestedTileX = nil
		requestedTileZ = nil
		clearHighlight()
		stopWalk()

		-- Animate the path directly
		moveToken += 1
		local token = moveToken
		isMoving = true
		playWalk()

		for _, step in ipairs(path) do
			if token ~= moveToken then return end
			if not moveStep(step[1], step[2], token) then
				if token == moveToken then stopWalk() end
				return
			end
		end

		isMoving = false
		currentTileX = path[#path][1]
		currentTileZ = path[#path][2]
		stopWalk()
		return
	end

	-- ── Animate server-approved path ──────────────────────────────────────────
	if requestedTileX == tx and requestedTileZ == tz and requestId == moveRequestId then
		acceptedMoveRequestId = requestId
		task.spawn(animatePath, path or { {tx, tz} })
	end
end)

-- ─── Click-to-move ────────────────────────────────────────────────────────────
local function getEnemyFromPart(part)
	local obj = part
	while obj do
		if obj:IsA("Model") and obj:GetAttribute("EnemyId") then
			return obj
		end
		obj = obj.Parent
	end
	return nil
end

local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	if not isAlive() then return end

	local target = mouse.Target
	if not target then return end

	-- If clicked on an enemy, skip movement (CombatController handles it)
	if getEnemyFromPart(target) then return end

	local tx, tz = target.Name:match("^Tile_(%d+)_(%d+)$")
	if tx and tz then
		requestMove(tonumber(tx), tonumber(tz))
	end
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
local M = {}
function M.GetCurrentTile()                return currentTileX, currentTileZ end
function M.IsMoving()                      return isMoving end
function M.RequestMove(tx, tz)             requestMove(tx, tz) end
function M.SetDestinationHighlight(tx, tz) setHighlight(tx, tz) end
function M.ClearDestinationHighlight()     clearHighlight() end
return M