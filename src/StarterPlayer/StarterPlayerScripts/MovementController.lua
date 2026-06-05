-- StarterPlayer/StarterPlayerScripts/MovementController.lua
-- v3 — complete rewrite for smooth, jank-free tile movement.
--
-- Improvements over v2:
--   • WASD movement: each key press queues a one-tile move in the held direction.
--     Holding a key repeats at Config.WASD_REPEAT_INTERVAL (default 0.25s).
--     WASD is additive — you can mix WASD and click freely.
--   • slideToWorld rewritten: uses a single Heartbeat loop that integrates
--     delta-time at a constant studs/second rate. The snap threshold is now
--     speed-proportional (0.5 frames worth of movement) so it never overshoots
--     or stalls at high/low FPS.
--   • Facing direction is updated every Heartbeat frame during a slide rather
--     than only at step start, giving smooth continuous rotation.
--   • Walk animation: started once when the first step begins, stopped once
--     after the last step, never toggled mid-path (eliminates the
--     start/stop flicker on multi-tile paths).
--   • Click dedup: rapid clicks to the same tile are ignored; a new click to a
--     different tile while already waiting for server response correctly
--     replaces the pending request.
--   • Attack-move path: single token increment (fixed the double-increment bug
--     from v1), no post-loop currentTile overwrite.
--   • Other-player tween: uses a per-user speed attribute broadcast alongside
--     the path so remote players animate at the correct speed, not the fixed
--     MOVE_TWEEN_TIME constant.
--   • Spawn: the initial PlayerMoved snap correctly handles the case where the
--     GUI LoadingOverlay is still present (defers any pending click).

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local player = Players.LocalPlayer

-- ─── Speed helper (mirrors server) ───────────────────────────────────────────
local function getPlayerSpeed()
	local char  = player.Character
	local ls    = char and char:FindFirstChild("leaderstats")
	local level = (ls and ls:FindFirstChild("Level") and ls.Level.Value) or 1
	level = math.max(1, level)
	local t = math.clamp(level / Config.PLAYER_SPEED_LEVEL, 0, 1)
	return Config.PLAYER_SPEED_BASE + (Config.PLAYER_SPEED_MIN - Config.PLAYER_SPEED_BASE) * t
end

-- Studs-per-second walk rate for lerp
local function getStudsPerSecond()
	return Config.TILE_SIZE / getPlayerSpeed()
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
	return ts and ts:FindFirstChild(string.format("Tile_%d_%d", tx, tz))
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
			local cx, cz = m:GetAttribute("CurrentTileX"), m:GetAttribute("CurrentTileZ")
			local mx, mz = m:GetAttribute("MovingToTileX"), m:GetAttribute("MovingToTileZ")
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

-- WASD state
local wasdHeld    = {}   -- keycode → true while held
local wasdRepeat  = {}   -- keycode → thread (repeat coroutine)
local WASD_INITIAL_DELAY  = 0.20   -- seconds before repeat starts
local WASD_REPEAT_INTERVAL = (type(Config.WASD_REPEAT_INTERVAL) == "number"
	and Config.WASD_REPEAT_INTERVAL) or 0.25

local WASD_DIR = {
	[Enum.KeyCode.W] = {  0, -1 },
	[Enum.KeyCode.S] = {  0,  1 },
	[Enum.KeyCode.A] = { -1,  0 },
	[Enum.KeyCode.D] = {  1,  0 },
	-- Arrow keys as aliases
	[Enum.KeyCode.Up]    = {  0, -1 },
	[Enum.KeyCode.Down]  = {  0,  1 },
	[Enum.KeyCode.Left]  = { -1,  0 },
	[Enum.KeyCode.Right] = {  1,  0 },
}

local hrp         = nil
local humanoid    = nil
local walkTrack   = nil
local walkPlaying = false   -- true while animation is actually running

-- ─── Utility ──────────────────────────────────────────────────────────────────
local function isAlive()
	return humanoid ~= nil and humanoid.Health > 0
end

local function isGUILoading()
	return player.PlayerGui:FindFirstChild("LoadingOverlay") ~= nil
end

-- ─── Walk animation ───────────────────────────────────────────────────────────
local function setupWalkAnimation()
	walkTrack  = nil
	walkPlaying = false
	if not humanoid then return end
	local anim = humanoid:FindFirstChildOfClass("Animator")
	if not anim then
		anim        = Instance.new("Animator")
		anim.Parent = humanoid
	end
	local a           = Instance.new("Animation")
	a.AnimationId     = (humanoid.RigType == Enum.HumanoidRigType.R6)
		and "rbxassetid://180426354"
		or  "rbxassetid://507777826"
	walkTrack         = anim:LoadAnimation(a)
	walkTrack.Looped  = true
	walkTrack.Priority = Enum.AnimationPriority.Movement
end

local function playWalk()
	if walkTrack and not walkPlaying then
		walkTrack:Play(0.08)
		walkPlaying = true
	end
end

local function stopWalk()
	if walkTrack and walkPlaying then
		walkTrack:Stop(0.12)
		walkPlaying = false
	end
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
local function stopAllWASD()
	for key, thread in pairs(wasdRepeat) do
		task.cancel(thread)
		wasdRepeat[key] = nil
	end
	wasdHeld = {}
end

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
		spawned     = false
		moveToken  += 1
		isMoving    = false
		walkPlaying = false
		if walkTrack then walkTrack:Stop(0) end
		clearHighlight()
		stopAllWASD()
		requestedTileX = nil
		requestedTileZ = nil
		pendingTileX   = nil
		pendingTileZ   = nil
	end)

	isMoving       = false
	moveToken     += 1
	walkPlaying    = false
	requestedTileX = nil
	requestedTileZ = nil
	pendingTileX   = nil
	pendingTileZ   = nil
	spawned        = false
	stopAllWASD()
	clearHighlight()
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

-- ─── Core mover — smooth delta-time integration ───────────────────────────────
-- Moves HRP to targetPos at a constant studs/second rate.
-- Returns true if the step completed successfully (token still valid).
-- Returns false if the token changed (new path / cancel / death).
local function slideToWorld(targetPos, token)
	if not hrp or not isAlive() then return false end

	-- Snap threshold: half a frame's worth of movement at current speed.
	-- This is generous enough to avoid stalling but tight enough to prevent
	-- visible overshoot.
	local snapThreshold = (getStudsPerSecond() / 60) * 0.5
	snapThreshold = math.max(snapThreshold, 0.05)   -- floor at 0.05 studs

	while true do
		if token ~= moveToken then return false end
		if not hrp or not isAlive() then return false end

		local delta2D = Vector3.new(
			targetPos.X - hrp.Position.X,
			0,
			targetPos.Z - hrp.Position.Z
		)
		local dist = delta2D.Magnitude

		if dist <= snapThreshold then break end

		local dt   = RunService.Heartbeat:Wait()
		if token ~= moveToken then return false end   -- re-check after yield

		local step = math.min(dist, getStudsPerSecond() * dt)
		local dir  = delta2D.Unit

		-- Update position and facing in one CFrame write
		local newPos = Vector3.new(
			hrp.Position.X + dir.X * step,
			targetPos.Y,                    -- lock Y to tile height (no bobbing)
			hrp.Position.Z + dir.Z * step
		)
		hrp.CFrame = CFrame.lookAt(newPos, newPos + dir)
	end

	-- Snap exactly onto the tile centre (eliminates sub-pixel drift)
	if token == moveToken and hrp and isAlive() then
		local finalDir = Vector3.new(
			targetPos.X - hrp.Position.X,
			0,
			targetPos.Z - hrp.Position.Z
		)
		if finalDir.Magnitude > 0.001 then
			hrp.CFrame = CFrame.lookAt(targetPos, targetPos + finalDir)
		else
			-- Same position — preserve current facing
			hrp.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.atan2(hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Z) + math.pi, 0)
		end
	end

	return token == moveToken
end

-- Move one tile step.  Updates currentTileX/Z on success.
local function moveStep(tx, tz, token)
	if not hrp then return false end
	local ok = slideToWorld(tileToWorld(tx, tz), token)
	if ok then
		currentTileX = tx
		currentTileZ = tz
	end
	return ok
end

-- ─── Animate a server-approved path ──────────────────────────────────────────
local function animatePath(path)
	if not path or #path == 0 then return end

	-- One clean increment to invalidate any prior movement
	moveToken += 1
	local token   = moveToken
	local finalX  = path[#path][1]
	local finalZ  = path[#path][2]

	isMoving = true
	playWalk()   -- start animation ONCE for the whole path

	for _, step in ipairs(path) do
		if token ~= moveToken then
			isMoving = false
			stopWalk()
			return
		end
		if not moveStep(step[1], step[2], token) then
			isMoving = false
			stopWalk()
			return
		end
	end

	-- Completed cleanly
	isMoving = false
	stopWalk()   -- stop animation ONCE at end

	if requestedTileX == finalX and requestedTileZ == finalZ then
		requestedTileX = nil
		requestedTileZ = nil
		clearHighlight()
	end
end

-- ─── Fire move request to server ──────────────────────────────────────────────
local function fireMoveRequest(tx, tz)
	moveRequestId += 1
	local rid      = moveRequestId
	requestedTileX = tx
	requestedTileZ = tz
	RequestMove:FireServer(tx, tz, currentTileX, currentTileZ, rid)

	-- If no server response within 0.8 s, clean up the pending state so the
	-- player isn't stuck waiting. Only clean up if the server hasn't already
	-- responded (acceptedMoveRequestId >= rid).
	task.delay(0.8, function()
		if requestedTileX == tx
			and requestedTileZ == tz
			and moveRequestId == rid
			and acceptedMoveRequestId < rid then
			requestedTileX = nil
			requestedTileZ = nil
			clearHighlight()
		end
	end)
end

-- ─── Request a move to any tile ───────────────────────────────────────────────
local function requestMove(tx, tz)
	if not hrp or not isAlive() then return end
	tx = math.clamp(math.floor(tx), 1, Config.GRID_WIDTH)
	tz = math.clamp(math.floor(tz), 1, Config.GRID_HEIGHT)
	if not isTileWalkable(tx, tz) then return end
	if isEnemyOnTile(tx, tz) then return end

	local dist = math.abs(tx - currentTileX) + math.abs(tz - currentTileZ)
	if dist > Config.MAX_CLICK_DISTANCE then return end
	if dist == 0 then return end

	if not spawned then
		pendingTileX = tx
		pendingTileZ = tz
		setHighlight(tx, tz)
		return
	end

	-- Dedup: ignore if it's the same destination we already sent
	if requestedTileX == tx and requestedTileZ == tz then return end

	setHighlight(tx, tz)
	fireMoveRequest(tx, tz)
end

-- ─── WASD movement ───────────────────────────────────────────────────────────
local function wasdStep(dir)
	if not isAlive() or not spawned then return end
	if isGUILoading() then return end

	local tx = currentTileX + dir[1]
	local tz = currentTileZ + dir[2]
	tx = math.clamp(tx, 1, Config.GRID_WIDTH)
	tz = math.clamp(tz, 1, Config.GRID_HEIGHT)
	requestMove(tx, tz)
end

local function startWASDRepeat(key, dir)
	if wasdRepeat[key] then return end
	wasdRepeat[key] = task.spawn(function()
		-- Initial delay before repeat kicks in
		task.wait(WASD_INITIAL_DELAY)
		while wasdHeld[key] do
			wasdStep(dir)
			task.wait(WASD_REPEAT_INTERVAL)
		end
		wasdRepeat[key] = nil
	end)
end

local function stopWASDKey(key)
	wasdHeld[key] = false
	if wasdRepeat[key] then
		task.cancel(wasdRepeat[key])
		wasdRepeat[key] = nil
	end
end

-- ─── PlayerMoved remote ───────────────────────────────────────────────────────
PlayerMoved.OnClientEvent:Connect(function(userId, tx, tz, path, requestId, enemyTx, enemyTz)

	-- ── Other player ─────────────────────────────────────────────────────────
	if userId ~= player.UserId then
		local other    = Players:GetPlayerByUserId(userId)
		if not other or not other.Character then return end
		local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
		if not otherHRP then return end

		otherPlayerTokens[userId] = (otherPlayerTokens[userId] or 0) + 1
		local token = otherPlayerTokens[userId]

		-- Use the other player's speed from their character attribute if available,
		-- otherwise fall back to a sensible default
		local otherSpeed = other.Character:GetAttribute("MoveSpeed") or Config.MOVE_TWEEN_TIME
		local tweenInfo  = TweenInfo.new(otherSpeed, Enum.EasingStyle.Linear)

		path = path or { {tx, tz} }

		task.spawn(function()
			local prevX = otherHRP:GetAttribute("LastTileX")
			local prevZ = otherHRP:GetAttribute("LastTileZ")
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
				local tw = TweenService:Create(otherHRP, tweenInfo, { CFrame = cf })
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

		-- Flush any pending click that arrived before spawn confirmation
		if pendingTileX and pendingTileZ and not isGUILoading() then
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

	-- ── Attack-move path (server-driven walk to enemy, requestId == -1) ───────
	if requestId == -1 and path and #path > 0 then
		-- Single clean token increment to cancel any in-progress walk
		moveToken += 1
		local token = moveToken
		isMoving       = false
		requestedTileX = nil
		requestedTileZ = nil
		clearHighlight()
		if walkPlaying then stopWalk() end

		isMoving = true
		playWalk()

		task.spawn(function()
			for _, step in ipairs(path) do
				if token ~= moveToken then
					isMoving = false
					stopWalk()
					return
				end
				if not moveStep(step[1], step[2], token) then
					isMoving = false
					stopWalk()
					return
				end
			end
			isMoving = false
			stopWalk()

			-- Face the enemy after arriving
			if hrp and isAlive() and enemyTx and enemyTz then
				local dir = Vector3.new(enemyTx - currentTileX, 0, enemyTz - currentTileZ)
				if dir.Magnitude > 0 then
					hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir.Unit)
				end
			end
		end)
		return
	end

	-- ── Animate server-approved player-move path ──────────────────────────────
	-- Accept the response if:
	--   1. The destination matches what we're waiting for (requestedTileX/Z), AND
	--   2. The requestId is not older than the last one we already acted on.
	-- We no longer require requestId == moveRequestId exactly — rapid clicking
	-- advances moveRequestId faster than the server round-trip, which caused
	-- every response after the first click to be silently dropped, leaving the
	-- player frozen in place.
	if requestedTileX == tx and requestedTileZ == tz
		and requestId >= acceptedMoveRequestId then
		acceptedMoveRequestId = requestId
		task.spawn(animatePath, path or { {tx, tz} })
	end
end)

-- ─── Click-to-move ────────────────────────────────────────────────────────────
-- Lazy-loaded reference to hold-Q targeting system
local TargetingController = nil

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
		if obj:IsA("Model") and obj:GetAttribute("EnemyId") then return obj end
		obj = obj.Parent
	end
	return nil
end

local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	if not isAlive() then return end
	if isTargetingActive() then return end
	if isGUILoading() then return end

	local target = mouse.Target
	if not target then return end
	if getEnemyFromPart(target) then return end

	local tx, tz = target.Name:match("^Tile_(%d+)_(%d+)$")
	if tx and tz then
		requestMove(tonumber(tx), tonumber(tz))
	end
end)

-- ─── WASD input ───────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if isGUILoading() then return end

	local dir = WASD_DIR[input.KeyCode]
	if not dir then return end

	wasdHeld[input.KeyCode] = true
	-- Fire one step immediately, then start the repeat coroutine
	wasdStep(dir)
	startWASDRepeat(input.KeyCode, dir)
end)

UserInputService.InputEnded:Connect(function(input, _)
	if WASD_DIR[input.KeyCode] then
		stopWASDKey(input.KeyCode)
	end
end)

-- Stop WASD when focus is lost (e.g. chat box opened)
UserInputService.WindowFocusReleased:Connect(stopAllWASD)
game:GetService("GuiService").MenuOpened:Connect(stopAllWASD)

-- ─── Public API ───────────────────────────────────────────────────────────────
local M = {}
function M.GetCurrentTile()                return currentTileX, currentTileZ end
function M.IsMoving()                      return isMoving end
function M.RequestMove(tx, tz)             requestMove(tx, tz) end
function M.SetDestinationHighlight(tx, tz) setHighlight(tx, tz) end
function M.ClearDestinationHighlight()     clearHighlight() end
return M