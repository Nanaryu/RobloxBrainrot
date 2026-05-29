-- ServerScriptService/Services/MovementService.lua
-- Receives RequestMove from clients, validates, updates server state,
-- broadcasts PlayerMoved to all clients.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local TileGrid      = require(script.Parent.TileGridService)
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove   = Remotes:WaitForChild("RequestMove")
local PlayerMoved   = Remotes:WaitForChild("PlayerMoved")

-- Server-side record of each player's current tile
local playerTiles: { [number]: { tx: number, tz: number } } = {}

-- ─── Validation ───────────────────────────────────────────────────────────────
local MAX_JUMP = 20   -- sanity: reject moves more than N tiles in one request

local function isValid(player: Player, tx: number, tz: number): boolean
	if type(tx) ~= "number" or type(tz) ~= "number" then return false end
	tx = math.floor(tx)
	tz = math.floor(tz)
	if tx < 1 or tz < 1 or tx > Config.GRID_WIDTH or tz > Config.GRID_HEIGHT then
		return false
	end
	if not TileGrid.IsWalkable(tx, tz) then return false end

	-- Reject teleports
	local current = playerTiles[player.UserId]
	if current then
		local dist = math.abs(tx - current.tx) + math.abs(tz - current.tz)
		if dist > MAX_JUMP then return false end
	end

	return true
end

-- ─── Handler ──────────────────────────────────────────────────────────────────
RequestMove.OnServerEvent:Connect(function(player: Player, tx: number, tz: number)
	tx = math.floor(tx or 0)
	tz = math.floor(tz or 0)

	if not isValid(player, tx, tz) then return end

	-- Update server record
	playerTiles[player.UserId] = { tx = tx, tz = tz }

	-- Move the server-side character so hitboxes stay correct
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local worldPos = TileGrid.TileToWorld(tx, tz)
			hrp.CFrame = CFrame.new(worldPos.X, hrp.Position.Y, worldPos.Z)
		end
	end

	-- Broadcast to all clients so others can lerp
	PlayerMoved:FireAllClients(player.UserId, tx, tz)
end)

-- ─── Cleanup on leave ─────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player: Player)
	playerTiles[player.UserId] = nil
end)

-- ─── Spawn players on a tile ──────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)  -- let character load fully

		-- Default spawn: tile (5, 5) — change to a proper spawn zone later
		local spawnTile = { tx = 5, tz = 5 }
		playerTiles[player.UserId] = spawnTile

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local worldPos = TileGrid.TileToWorld(spawnTile.tx, spawnTile.tz)
			hrp.CFrame = CFrame.new(worldPos.X, worldPos.Y + 3, worldPos.Z)
		end
	end)
end)

print("[MovementService] Ready.")