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

-- ─── Per-character refs (reset on respawn) ────────────────────────────────────
local hrp      = nil
local humanoid = nil

local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:WaitForChild("Humanoid")

	humanoid.WalkSpeed     = 0
	humanoid.JumpPower     = 0
	humanoid.AutoRotate    = false
	humanoid.PlatformStand = true

	-- Reset movement state for the new life
	isMoving  = false
	moveQueue = {}
	if activeTween then activeTween:Cancel() activeTween = nil end
	-- spawned stays false until server fires PlayerMoved for this character
	spawned   = false
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
local function stepToTile(tx, tz)
	if not hrp then return end
	isMoving = true

	local fromX, fromZ = currentTileX, currentTileZ
	currentTileX, currentTileZ = tx, tz

	local dx = tx - fromX
	local dz = tz - fromZ
	local targetPos = tileToWorld(tx, tz)

	-- CFrame.lookAt(eye, target) is unambiguous: +Z of model faces target.
	-- We want the model to face the direction of travel, so lookAt = pos + dir.
	local targetCF
	if dx ~= 0 or dz ~= 0 then
		-- lookAt points the model's LOOK direction (front face) toward the target.
		targetCF = CFrame.lookAt(targetPos, targetPos + Vector3.new(dx, 0, dz))
	else
		targetCF = CFrame.new(targetPos)
	end

	if activeTween then activeTween:Cancel() end
	activeTween = TweenService:Create(hrp, MOVE_TWEEN, { CFrame = targetCF })
	activeTween:Play()
	activeTween.Completed:Wait()
	activeTween = nil
	isMoving = false

	if #moveQueue > 0 then
		local next = table.remove(moveQueue, 1)
		stepToTile(next[1], next[2])
	end
end

-- ─── Request move ─────────────────────────────────────────────────────────────
local function requestMove(tx, tz)
	if not spawned or not hrp then return end
	tx = math.clamp(math.floor(tx), 1, Config.GRID_WIDTH)
	tz = math.clamp(math.floor(tz), 1, Config.GRID_HEIGHT)
	if tx == currentTileX and tz == currentTileZ then return end

	moveQueue = {}
	local px, pz = currentTileX, currentTileZ
	while px ~= tx or pz ~= tz do
		if px ~= tx then px = px + (tx > px and 1 or -1)
		else              pz = pz + (tz > pz and 1 or -1) end
		table.insert(moveQueue, { px, pz })
	end

	RequestMove:FireServer(tx, tz)

	if not isMoving and #moveQueue > 0 then
		local next = table.remove(moveQueue, 1)
		task.spawn(stepToTile, next[1], next[2])
	end
end

-- ─── PlayerMoved: own spawn snap + other players ──────────────────────────────
PlayerMoved.OnClientEvent:Connect(function(userId, tx, tz)
	if userId ~= player.UserId then
		-- Other players
		local other = Players:GetPlayerByUserId(userId)
		if not other or not other.Character then return end
		local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
		if not otherHRP then return end

		local prevX = otherHRP:GetAttribute("LastTileX")
		local prevZ = otherHRP:GetAttribute("LastTileZ")
		local pos   = tileToWorld(tx, tz)
		local cf
		if prevX and prevZ and (tx ~= prevX or tz ~= prevZ) then
			cf = CFrame.lookAt(pos, pos + Vector3.new(tx - prevX, 0, tz - prevZ))
		else
			cf = CFrame.new(pos)
		end
		otherHRP:SetAttribute("LastTileX", tx)
		otherHRP:SetAttribute("LastTileZ", tz)
		TweenService:Create(otherHRP, MOVE_TWEEN, { CFrame = cf }):Play()
		return
	end

	-- Own spawn: server placed us, snap into position
	if not spawned then
		spawned = true
		currentTileX, currentTileZ = tx, tz
		if hrp then
			hrp.CFrame = CFrame.new(tileToWorld(tx, tz))
		end
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
	if tx and tz then requestMove(tonumber(tx), tonumber(tz)) end
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
local M = {}
function M.GetCurrentTile() return currentTileX, currentTileZ end
function M.IsMoving() return isMoving end
return M
