-- StarterPlayer/StarterPlayerScripts/MovementController.lua
-- Handles WASD + click-to-move on the tile grid.
-- Sends RequestMove to server; listens for PlayerMoved broadcast to lerp characters.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp: BasePart = character:WaitForChild("HumanoidRootPart")
local humanoid: Humanoid = character:WaitForChild("Humanoid")

-- Disable default Roblox movement so we fully control it
humanoid.WalkSpeed = 0
local TWEEN_INFO = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)

-- ─── State ────────────────────────────────────────────────────────────────────
local currentTileX = 1
local currentTileZ = 1
local isMoving = false
local moveQueue: { { number } } = {} -- pending tile steps {tx, tz}

-- ─── Tile ↔ World helpers (mirrors server) ───────────────────────────────────
local function tileToWorld(tx, tz): Vector3
	local x = (tx - 0.5) * Config.TILE_SIZE
	local z = (tz - 0.5) * Config.TILE_SIZE
	return Vector3.new(x, hrp.Position.Y, z) -- keep current Y (standing height)
end

local function worldToTile(pos: Vector3): (number, number)
	local tx = math.floor(pos.X / Config.TILE_SIZE) + 1
	local tz = math.floor(pos.Z / Config.TILE_SIZE) + 1
	return tx, tz
end

-- ─── Snap character to nearest tile on spawn ─────────────────────────────────
do
	local tx, tz = worldToTile(hrp.Position)
	currentTileX, currentTileZ = tx, tz
end

-- ─── Move one tile step ───────────────────────────────────────────────────────
local function stepToTile(tx: number, tz: number)
	isMoving = true
	currentTileX, currentTileZ = tx, tz

	local target = tileToWorld(tx, tz)
	local tween = TweenService:Create(hrp, TWEEN_INFO, { CFrame = CFrame.new(target) })
	tween:Play()
	tween.Completed:Wait()

	isMoving = false

	-- Process next queued step
	if #moveQueue > 0 then
		local next = table.remove(moveQueue, 1)
		stepToTile(next[1], next[2])
	end
end

-- ─── Request a move to (tx, tz) ───────────────────────────────────────────────
local function requestMove(tx: number, tz: number)
	-- Basic bounds check client-side (server will validate too)
	if tx < 1 or tz < 1 then
		return
	end

	-- Replace queue with a single-step toward target
	-- Full A* pathfinding will be added later; for now direct step.
	local dx = tx - currentTileX
	local dz = tz - currentTileZ
	if dx == 0 and dz == 0 then
		return
	end

	-- Step one tile at a time toward destination (simple)
	moveQueue = {}
	local stepX = currentTileX
	local stepZ = currentTileZ

	-- Build path (Manhattan, no diagonal)
	while stepX ~= tx or stepZ ~= tz do
		if stepX ~= tx then
			stepX = stepX + (tx > stepX and 1 or -1)
		elseif stepZ ~= tz then
			stepZ = stepZ + (tz > stepZ and 1 or -1)
		end
		table.insert(moveQueue, { stepX, stepZ })
	end

	-- Fire server with final destination
	RequestMove:FireServer(tx, tz)

	-- Start moving if not already
	if not isMoving and #moveQueue > 0 then
		local next = table.remove(moveQueue, 1)
		stepToTile(next[1], next[2])
	end
end

-- ─── WASD Input ───────────────────────────────────────────────────────────────
local KEY_DIRS = {
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	-- Arrow keys
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local dir = KEY_DIRS[input.KeyCode]
	if dir then
		requestMove(currentTileX + dir[1], currentTileZ + dir[2])
	end
end)

-- ─── Click-to-Move ────────────────────────────────────────────────────────────
local mouse = player:GetMouse()

mouse.Button1Down:Connect(function()
	local target = mouse.Target
	-- Only move if we clicked a tile (named Tile_X_Z)
	if target and target.Name:match("^Tile_%d+_%d+$") then
		-- Extract tile coords from part name
		local tx: number, tz: number = target.Name:match("^Tile_(%d+)_(%d+)$")
		if tx and tz then
			requestMove(tonumber(tx), tonumber(tz))
		end
	end
end)

-- ─── Listen for server-authoritative positions of OTHER players ───────────────
PlayerMoved.OnClientEvent:Connect(function(userId: number, tx: number, tz: number)
	if userId == player.UserId then
		return
	end -- ignore self; we lerp locally

	local otherPlayer = Players:GetPlayerByUserId(userId)
	if not otherPlayer then
		return
	end
	local otherChar = otherPlayer.Character
	if not otherChar then
		return
	end
	local otherHRP = otherChar:FindFirstChild("HumanoidRootPart")
	if not otherHRP then
		return
	end

	local worldPos = tileToWorld(tx, tz)
	TweenService:Create(otherHRP, TWEEN_INFO, { CFrame = CFrame.new(worldPos) }):Play()
end)

-- ─── Expose current tile for other client scripts ─────────────────────────────
local MovementController = {}

function MovementController.GetCurrentTile(): (number, number)
	return currentTileX, currentTileZ
end

function MovementController.IsMoving(): boolean
	return isMoving
end

return MovementController
