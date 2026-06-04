-- StarterPlayer/StarterPlayerScripts/MovementController.lua
-- Click-to-move, cardinal only. No diagonal movement.
-- Multi-tile paths use server A* and animate step-by-step.
--
-- FIXES:
--   • Attack-move path handler (requestId == -1): previously did `moveToken += 1`
--     twice in a row before starting the new path coroutine. The double-increment
--     meant any previously started coroutine saw TWO increments and any delayed
--     tile-update from MovementService could still fire between the two increments.
--     Now: one increment to cancel (with a token capture), then start the coroutine
--     with that same token — consistent with how animatePath works.
--   • Attack-move path handler: the final `currentTileX = path[#path][1]` assignment
--     after the step loop was redundant (moveStep already updates currentTileX/Z)
--     and could overwrite a partially-completed NEW path if a second attack-move
--     arrived while the loop was still executing. Removed; moveStep is the sole writer.
--   • fireMoveRequest timeout cleanup: the 0.8 s fallback that clears
--     requestedTileX/Z now also compares acceptedMoveRequestId correctly —
--     if the server responded (acceptedMoveRequestId >= rid) we must NOT clear,
--     because we're already animating that path.
--   • slideToWorld: added a guard so the loop cannot yield after moveToken has
--     already been invalidated. Previously a Heartbeat:Wait() could return AFTER
--     a new token was set, causing one extra step to execute.
--   • currentTileX/Z updated in moveStep only on successful completion (already
--     the case), but now also guarded against the HRP being nil (character
--     removal mid-walk).

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local player = Players.LocalPlayer

local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)

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
local otherPlayerTokens     = {}

local spawned      = false
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

-- ─── Core mover ───────────────────────────────────────────────────────────────
local function slideToWorld(targetPos, facingDir, token)
	if not hrp or not isAlive() then return false end

	local moveSpeed = Config.TILE_SIZE / getPlayerSpeed()

	while token == moveToken and isAlive() and hrp do
		-- FIX: capture dt BEFORE re-checking token so a token change between
		-- Heartbeat:Wait() and the while condition doesn't cause one extra step.
		local dt = RunService.Heartbeat:Wait()
		if token ~= moveToken then break end  -- re-check immediately after yield

		local delta = Vector3.new(
			targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
		if delta.Magnitude <= 0.03 then break end

		local step = math.min(delta.Magnitude, moveSpeed * dt)
		local dir  = delta.Unit
		facingDir  = dir
		hrp.CFrame = CFrame.lookAt(
			hrp.Position + dir * step,
			hrp.Position + dir * step + dir)
	end

	if token ~= moveToken or not isAlive() or not hrp then return false end
	if facingDir.Magnitude > 0 then
		hrp.CFrame = CFrame.lookAt(targetPos, targetPos + facingDir)
	else
		hrp.CFrame = CFrame.new(targetPos)
	end
	return true
end

local function moveStep(tx, tz, token)
	if not hrp then return false end
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

	-- FIX: only clean up if the server hasn't responded and this is still the
	-- active request. Checking acceptedMoveRequestId >= rid means "server already
	-- replied" — don't clear in that case.
	task.delay(0.8, function()
		if requestedTileX == tx and requestedTileZ == tz
			and moveRequestId == rid                    -- still the latest request
			and acceptedMoveRequestId < rid then        -- server hasn't responded
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

	local clickDist = math.abs(tx - currentTileX) + math.abs(tz - currentTileZ)
	if clickDist > Config.MAX_CLICK_DISTANCE then return end

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
end

-- ─── PlayerMoved remote ───────────────────────────────────────────────────────
PlayerMoved.OnClientEvent:Connect(function(userId, tx, tz, path, requestId, enemyTx, enemyTz)
	-- ── Other player ─────────────────────────────────────────────────────────
	if userId ~= player.UserId then
		local other = Players:GetPlayerByUserId(userId)
		if not other or not other.Character then return end
		local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
		if not otherHRP then return end

		otherPlayerTokens[userId] = (otherPlayerTokens[userId] or 0) + 1
		local token = otherPlayerTokens[userId]

		local prevX = otherHRP:GetAttribute("LastTileX")
		local prevZ = otherHRP:GetAttribute("LastTileZ")
		path = path or { {tx, tz} }
		task.spawn(function()
			for _, step in ipairs(path) do
				if token ~= otherPlayerTokens[userId] then return end
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

	-- ── Spawn snap ────────────────────────────────────────────────────────────
	if not spawned then
		spawned        = true
		currentTileX   = tx
		currentTileZ   = tz
		requestedTileX = nil
		requestedTileZ = nil
		moveToken     += 1
		clearHighlight()
		if hrp then hrp.CFrame = CFrame.new(tileToWorld(tx, tz)) end

		if pendingTileX and pendingTileZ and not player.PlayerGui:FindFirstChild("LoadingOverlay") then
			local ptx, ptz = pendingTileX, pendingTileZ
			pendingTileX   = nil
			pendingTileZ   = nil
			task.defer(function() requestMove(ptx, ptz) end)
		else
			pendingTileX = nil
			pendingTileZ = nil
		end
		return
	end

	-- ── Attack-move path (server-driven walk-to-enemy, requestId == -1) ───────
	if requestId == -1 and path and #path > 0 then
		-- FIX: one clean token increment to cancel any in-progress movement,
		-- then reuse that same token for the new path coroutine.
		moveToken += 1
		local token = moveToken
		isMoving = false
		requestedTileX = nil
		requestedTileZ = nil
		clearHighlight()
		stopWalk()

		-- Animate the attack-move path under our captured token
		isMoving = true
		playWalk()
		task.spawn(function()
			for _, step in ipairs(path) do
				if token ~= moveToken then
					if token == moveToken then stopWalk() end
					isMoving = false
					return
				end
				if not moveStep(step[1], step[2], token) then
					if token == moveToken then stopWalk() end
					isMoving = false
					return
				end
			end
			-- FIX: don't set currentTileX/Z here — moveStep already did it for
			-- each step. Setting it again here could overwrite a new path's
			-- first-step update if another attack-move arrived during the loop.
			isMoving = false
			stopWalk()

			-- Face the enemy after arriving at the adjacent tile
			if hrp and isAlive() and enemyTx and enemyTz then
				local dir = Vector3.new(
					enemyTx - currentTileX, 0, enemyTz - currentTileZ)
				if dir.Magnitude > 0 then
					hrp.CFrame = CFrame.lookAt(
						hrp.Position, hrp.Position + dir.Unit)
				end
			end
		end)
		return
	end

	-- ── Animate server-approved player-move path ──────────────────────────────
	if requestedTileX == tx and requestedTileZ == tz and requestId == moveRequestId then
		acceptedMoveRequestId = requestId
		task.spawn(animatePath, path or { {tx, tz} })
	end
end)

-- ─── Click-to-move ────────────────────────────────────────────────────────────
local TargetingController

local function isTargetingActive()
	if not TargetingController then
		local ok, mod = pcall(require, script.Parent:WaitForChild("TargetingController"))
		if ok then TargetingController = mod end
	end
	return TargetingController and TargetingController.IsActive()
end

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
	if isTargetingActive() then return end
	if player.PlayerGui:FindFirstChild("LoadingOverlay") then return end

	local target = mouse.Target
	if not target then return end

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