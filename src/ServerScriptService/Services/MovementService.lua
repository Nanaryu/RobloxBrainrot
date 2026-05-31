-- ServerScriptService/Services/MovementService.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local TileGrid    = require(script.Parent.TileGridService)
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local playerTiles = {}   -- [userId] = { tx, tz }
local EnemyService

-- ─── Validation ───────────────────────────────────────────────────────────────
local MAX_JUMP = 24

local function isPlayerTileOccupied(tx, tz, exceptPlayer)
	for userId, tile in pairs(playerTiles) do
		if tile.tx == tx and tile.tz == tz then
			if not exceptPlayer or userId ~= exceptPlayer.UserId then
				return true
			end
		end
	end
	return false
end

local function isValid(player, tx, tz)
	if type(tx) ~= "number" or type(tz) ~= "number" then return false end
	tx, tz = math.floor(tx), math.floor(tz)
	if tx < 1 or tz < 1 or tx > Config.GRID_WIDTH or tz > Config.GRID_HEIGHT then return false end
	if not TileGrid.IsWalkable(tx, tz) then return false end
	if isPlayerTileOccupied(tx, tz, player) then return false end
	if not EnemyService then EnemyService = require(script.Parent.EnemyService) end
	if EnemyService.IsTileOccupied(tx, tz) then return false end
	local cur = playerTiles[player.UserId]
	if cur then
		if math.abs(tx - cur.tx) + math.abs(tz - cur.tz) > MAX_JUMP then return false end
	end
	return true
end

-- ─── Move handler ─────────────────────────────────────────────────────────────
RequestMove.OnServerEvent:Connect(function(player, tx, tz)
	tx, tz = math.floor(tx or 0), math.floor(tz or 0)
	if not isValid(player, tx, tz) then return end

	playerTiles[player.UserId] = { tx = tx, tz = tz }

	-- DO NOT touch hrp.CFrame here — the client owns visual position.
	-- Only broadcast so other clients can lerp.
	-- We fire to ALL clients (including sender) so their "other player" lerp works.
	-- The sender ignores its own userId in the PlayerMoved handler for normal moves.
	PlayerMoved:FireAllClients(player.UserId, tx, tz)
end)

-- ─── Spawn ────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait for TileGrid to exist (it generates on server start)
		local map = workspace:WaitForChild("Map", 30)
		map:WaitForChild("TileGrid", 30)

		-- Use the official spawn tile defined in TileGridService
		local spawnTx, spawnTz = TileGrid.GetSpawnTile()
		playerTiles[player.UserId] = { tx = spawnTx, tz = spawnTz }

		-- Hard-place the server-side HRP so hitboxes are correct from frame 1
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if hrp then
			local wp = TileGrid.TileToWorld(spawnTx, spawnTz)
			-- +3 Y so character stands on top of tile, matching client tileToWorld
			hrp.CFrame = CFrame.new(wp.X, wp.Y + 3, wp.Z)
		end

		-- Tell THIS client where they spawned (triggers their initial snap)
		-- Small wait ensures client scripts have loaded
		task.wait(0.2)
		PlayerMoved:FireClient(player, player.UserId, spawnTx, spawnTz)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerTiles[player.UserId] = nil
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
local MovementService = {}

function MovementService.GetPlayerTile(player)
	local t = playerTiles[player.UserId]
	if t then return t.tx, t.tz end
	return nil, nil
end

function MovementService.IsPlayerTileOccupied(tx, tz, exceptPlayer)
	return isPlayerTileOccupied(tx, tz, exceptPlayer)
end

print("[MovementService] Ready.")
return MovementService
