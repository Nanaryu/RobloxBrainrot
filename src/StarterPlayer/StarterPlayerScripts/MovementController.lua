-- StarterPlayer/StarterPlayerScripts/MovementController.lua
-- Handles WASD + click-to-move. Re-initialises on every respawn.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local player = Players.LocalPlayer

local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)

-- ─── Tile helpers (pure, no character refs) ───────────────────────────────────
local function tileToWorld(tx, tz)
	return Vector3.new(
		(tx - 0.5) * Config.TILE_SIZE,
		Config.TILE_HEIGHT + 3.0,
		(tz - 0.5) * Config.TILE_SIZE
	)
end

-- ─── Shared state (persists across respawns) ──────────────────────────────────
local currentTileX = 1
local currentTileZ = 1
local isMoving     = false
local moveQueue    = {}
local activeTween  = nil
local spawned      = false
local requestedTileX = nil
local requestedTileZ = nil
local destinationHighlight = nil
local moveToken = 0

-- ─── Per-character refs (reset on respawn) ────────────────────────────────────
local hrp      = nil
local humanoid = nil
local walkTrack = nil

local function worldToTile(pos)
	local tx = math.floor(pos.X / Config.TILE_SIZE) + 1
	local tz = math.floor(pos.Z / Config.TILE_SIZE) + 1
	tx = math.clamp(tx, 1, Config.GRID_WIDTH)
	tz = math.clamp(tz, 1, Config.GRID_HEIGHT)
	return tx, tz
end

local function getTilePart(tx, tz)
	local map = workspace:FindFirstChild("Map")
	local tileGrid = map and map:FindFirstChild("TileGrid")
	local tiles = tileGrid and tileGrid:FindFirstChild("Tiles")
	return tiles and tiles:FindFirstChild(string.format("Tile_%d_%d", tx, tz))
end

local function isEnemyTileOccupied(tx, tz)
	local map = workspace:FindFirstChild("Map")
	local enemies = map and map:FindFirstChild("Enemies")
	if not enemies then return false end

	for _, model in ipairs(enemies:GetChildren()) do
		if model:GetAttribute("State") ~= "dead" then
			local currentX = model:GetAttribute("CurrentTileX")
			local currentZ = model:GetAttribute("CurrentTileZ")
			local movingX = model:GetAttribute("MovingToTileX")
			local movingZ = model:GetAttribute("MovingToTileZ")
			if (currentX == tx and currentZ == tz) or (movingX == tx and movingZ == tz) then
				return true
			end
		end
	end
	return false
end

local function clearDestinationHighlight()
	if destinationHighlight then
		destinationHighlight:Destroy()
		destinationHighlight = nil
	end
end

local function setupWalkAnimation()
	walkTrack = nil
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		animation.AnimationId = "rbxassetid://180426354"
	else
		animation.AnimationId = "rbxassetid://507777826"
	end

	walkTrack = animator:LoadAnimation(animation)
	walkTrack.Looped = true
	walkTrack.Priority = Enum.AnimationPriority.Movement
end

local function playWalkAnimation()
	if walkTrack and not walkTrack.IsPlaying then
		walkTrack:Play(0.08)
	end
end

local function stopWalkAnimation()
	if walkTrack and walkTrack.IsPlaying then
		walkTrack:Stop(0.12)
	end
end

local function setDestinationHighlight(tx, tz)
	clearDestinationHighlight()
	local tile = getTilePart(tx, tz)
	if not tile then return end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = tile
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(80, 210, 255)
	highlight.FillTransparency = 0.68
	highlight.OutlineColor = Color3.fromRGB(170, 245, 255)
	highlight.OutlineTransparency = 0
	highlight.Parent = tile
	destinationHighlight = highlight
end

local function cancelActiveMove()
	moveToken += 1
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	stopWalkAnimation()
	isMoving = false
	if hrp then
		currentTileX, currentTileZ = worldToTile(hrp.Position)
	end
end

local function fireMoveRequest(tx, tz)
	requestedTileX = tx
	requestedTileZ = tz
	RequestMove:FireServer(tx, tz, currentTileX, currentTileZ)
	task.delay(0.6, function()
		if requestedTileX == tx and requestedTileZ == tz then
			requestedTileX = nil
			requestedTileZ = nil
			clearDestinationHighlight()
		end
	end)
end

local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")

	humanoid.WalkSpeed     = 0
	humanoid.JumpPower     = 0
	humanoid.AutoRotate    = false
	humanoid.PlatformStand = false
	hrp.Anchored = true
	setupWalkAnimation()

	-- Reset movement state for the new life
	isMoving  = false
	moveQueue = {}
	moveToken += 1
	clearDestinationHighlight()
	if activeTween then activeTween:Cancel() activeTween = nil end
	stopWalkAnimation()
	-- spawned stays false until server fires PlayerMoved for this character
	spawned   = false
	requestedTileX = nil
	requestedTileZ = nil
end

-- Initialise for current character, then reconnect on every future respawn
local function onCharacterAdded(character)
	setupCharacter(character)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	setupCharacter(player.Character)
end

-- ─── Step one tile ────────────────────────────────────────────────────────────
local function tweenToTile(tx, tz, token)
	if not hrp then return end

	local fromX, fromZ = currentTileX, currentTileZ

	local dx = tx - fromX
	local dz = tz - fromZ
	local targetPos = tileToWorld(tx, tz)

	-- CFrame.lookAt(eye, target) is unambiguous: +Z of model faces target.
	-- We want the model to face the direction of travel, so lookAt = pos + dir.
	local targetCF
	if dx ~= 0 or dz ~= 0 then
		-- lookAt points the model's LOOK direction (front face) toward the target.
		local startPos = hrp.Position
		hrp.CFrame = CFrame.lookAt(startPos, startPos + Vector3.new(dx, 0, dz))
		targetCF = CFrame.lookAt(targetPos, targetPos + Vector3.new(dx, 0, dz))
	else
		targetCF = CFrame.new(targetPos)
	end

	if activeTween then activeTween:Cancel() end
	activeTween = TweenService:Create(hrp, MOVE_TWEEN, { CFrame = targetCF })
	activeTween:Play()
	local playbackState = activeTween.Completed:Wait()
	if token ~= moveToken or playbackState ~= Enum.PlaybackState.Completed then
		if token == moveToken then
			activeTween = nil
			isMoving = false
		end
		return false
	end

	currentTileX, currentTileZ = tx, tz
	activeTween = nil
	return true
end

local function animatePath(path)
	moveToken += 1
	local token = moveToken
	isMoving = true
	playWalkAnimation()

	for _, step in ipairs(path or {}) do
		if token ~= moveToken then
			stopWalkAnimation()
			return
		end
		if not tweenToTile(step[1], step[2], token) then
			stopWalkAnimation()
			return
		end
	end

	isMoving = false
	activeTween = nil
	requestedTileX = nil
	requestedTileZ = nil
	stopWalkAnimation()
	clearDestinationHighlight()
end

-- ─── Request move ─────────────────────────────────────────────────────────────
local function requestMove(tx, tz)
	if not spawned or not hrp then return end
	tx = math.clamp(math.floor(tx), 1, Config.GRID_WIDTH)
	tz = math.clamp(math.floor(tz), 1, Config.GRID_HEIGHT)
	if tx == currentTileX and tz == currentTileZ then return end
	if requestedTileX == tx and requestedTileZ == tz then return end

	cancelActiveMove()
	setDestinationHighlight(tx, tz)
	fireMoveRequest(tx, tz)

end

local function animateOtherPlayer(otherHRP, path, tx, tz)
	local prevX = otherHRP:GetAttribute("LastTileX")
	local prevZ = otherHRP:GetAttribute("LastTileZ")
	path = path or { { tx, tz } }

	task.spawn(function()
		for _, step in ipairs(path) do
			local sx, sz = step[1], step[2]
			local pos = tileToWorld(sx, sz)
			local cf
			if prevX and prevZ and (sx ~= prevX or sz ~= prevZ) then
				cf = CFrame.lookAt(pos, pos + Vector3.new(sx - prevX, 0, sz - prevZ))
			else
				cf = CFrame.new(pos)
			end
			prevX, prevZ = sx, sz
			otherHRP:SetAttribute("LastTileX", sx)
			otherHRP:SetAttribute("LastTileZ", sz)
			local tween = TweenService:Create(otherHRP, MOVE_TWEEN, { CFrame = cf })
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

-- ─── PlayerMoved: own spawn snap + other players ──────────────────────────────
PlayerMoved.OnClientEvent:Connect(function(userId, tx, tz, path)
	if userId ~= player.UserId then
		-- Other players
		local other = Players:GetPlayerByUserId(userId)
		if not other or not other.Character then return end
		local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
		if not otherHRP then return end

		animateOtherPlayer(otherHRP, path, tx, tz)
		return
	end

	-- Own spawn: server placed us, snap into position
	if not spawned then
		spawned = true
		currentTileX, currentTileZ = tx, tz
		requestedTileX = nil
		requestedTileZ = nil
		moveQueue = {}
		moveToken += 1
		clearDestinationHighlight()
		if hrp then
			hrp.CFrame = CFrame.new(tileToWorld(tx, tz))
		end
		return
	end

	if requestedTileX == tx and requestedTileZ == tz then
		task.spawn(animatePath, path or { { tx, tz } })
	end
end)

-- ─── WASD input ───────────────────────────────────────────────────────────────
local KEY_DIRS = {
	[Enum.KeyCode.W]     = {  0, -1 },
	[Enum.KeyCode.S]     = {  0,  1 },
	[Enum.KeyCode.A]     = { -1,  0 },
	[Enum.KeyCode.D]     = {  1,  0 },
	[Enum.KeyCode.Up]    = {  0, -1 },
	[Enum.KeyCode.Down]  = {  0,  1 },
	[Enum.KeyCode.Left]  = { -1,  0 },
	[Enum.KeyCode.Right] = {  1,  0 },
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local dir = KEY_DIRS[input.KeyCode]
	if dir then requestMove(currentTileX + dir[1], currentTileZ + dir[2]) end
end)

-- ─── Click-to-move ────────────────────────────────────────────────────────────
local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then return end
	local tx, tz = target.Name:match("^Tile_(%d+)_(%d+)$")
	if tx and tz then
		tx, tz = tonumber(tx), tonumber(tz)
		if not isEnemyTileOccupied(tx, tz) then
			requestMove(tx, tz)
		end
	end
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
local M = {}
function M.GetCurrentTile() return currentTileX, currentTileZ end
function M.IsMoving() return isMoving end
function M.RequestMove(tx, tz) requestMove(tx, tz) end
function M.SetDestinationHighlight(tx, tz) setDestinationHighlight(tx, tz) end
function M.ClearDestinationHighlight() clearDestinationHighlight() end
return M
