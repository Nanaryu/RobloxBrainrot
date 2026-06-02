-- ServerScriptService/Services/MovementService.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Pathfinder = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Pathfinder"))
local TileGrid   = require(script.Parent.TileGridService)
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local playerTiles   = {}   -- [userId] = { tx, tz }  — tracks current server tile
local playerMoveSeq = {}
local EnemyService

-- Cap path length to prevent a malicious client from triggering A* across the full grid.
local MAX_PATH_NODES = 400

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

local function isPlayerAlive(player)
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function isValidTile(tx, tz)
	if type(tx) ~= "number" or type(tz) ~= "number" then return false end
	tx, tz = math.floor(tx), math.floor(tz)
	if tx < 1 or tz < 1 or tx > Config.GRID_WIDTH or tz > Config.GRID_HEIGHT then return false end
	return TileGrid.IsWalkable(tx, tz)
end

local function findPlayerPath(player, fromX, fromZ, tx, tz)
	if not isValidTile(fromX, fromZ) or not isValidTile(tx, tz) then return nil end
	if isPlayerTileOccupied(tx, tz, player) then return nil end
	if not EnemyService then EnemyService = require(script.Parent.EnemyService) end
	if EnemyService.IsTileBlockedForPlayers and EnemyService.IsTileBlockedForPlayers(tx, tz) then return nil end

	local function isPassable(px, pz)
		if not TileGrid.IsWalkable(px, pz) then return false end
		if isPlayerTileOccupied(px, pz, player) then return false end
		if EnemyService.IsTileBlockedForPlayers and EnemyService.IsTileBlockedForPlayers(px, pz) then return false end
		return true
	end

	if not isPassable(tx, tz) then return nil end
	local path = Pathfinder.FindPath(isPassable, fromX, fromZ, tx, tz, MAX_PATH_NODES)
	-- Reject paths that exceed the cap — client requested something unreasonably far
	if path and #path > MAX_PATH_NODES then return nil end
	return path
end

-- ─── Move handler ─────────────────────────────────────────────────────────────
RequestMove.OnServerEvent:Connect(function(player, tx, tz, fromX, fromZ, requestId)
	if not isPlayerAlive(player) then return end

	tx, tz = math.floor(tx or 0), math.floor(tz or 0)
	local cur = playerTiles[player.UserId]
	if not cur then return end

	playerMoveSeq[player.UserId] = (playerMoveSeq[player.UserId] or 0) + 1
	local seq = playerMoveSeq[player.UserId]

	-- Trust the client's reported origin if it's close to our tracked tile.
	-- This prevents rubber-banding when the client is mid-step.
	fromX = math.floor(fromX or cur.tx)
	fromZ = math.floor(fromZ or cur.tz)
	-- Clamp: don't let the client teleport the origin far away.
	local originDrift = math.abs(fromX - cur.tx) + math.abs(fromZ - cur.tz)
	if originDrift > 3 then
		fromX = cur.tx
		fromZ = cur.tz
	end

	local path = findPlayerPath(player, fromX, fromZ, tx, tz)
	if not path or #path == 0 then return end

	-- Broadcast the approved path to all clients.
	PlayerMoved:FireAllClients(player.UserId, tx, tz, path, requestId)

	-- Update the server's tile record step by step, matching the client's visual pace.
	-- Step 0 (immediate): move to first tile right away so combat range is accurate.
	playerTiles[player.UserId] = { tx = path[1][1], tz = path[1][2] }

	for stepIndex = 2, #path do
		local step = path[stepIndex]
		task.delay((stepIndex - 1) * Config.MOVE_TWEEN_TIME, function()
			if playerMoveSeq[player.UserId] == seq then
				playerTiles[player.UserId] = { tx = step[1], tz = step[2] }
			end
		end)
	end
end)

-- ─── Spawn ────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local map = workspace:WaitForChild("Map", 30)
		map:WaitForChild("TileGrid", 30)

		local spawnTx, spawnTz = TileGrid.GetSpawnTile()
		playerTiles[player.UserId]   = { tx = spawnTx, tz = spawnTz }
		playerMoveSeq[player.UserId] = (playerMoveSeq[player.UserId] or 0) + 1

		local hrp      = character:WaitForChild("HumanoidRootPart", 10)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.WalkSpeed     = 0
			humanoid.JumpPower     = 0
			humanoid.AutoRotate    = false
			humanoid.PlatformStand = false
			humanoid.Died:Connect(function()
				playerMoveSeq[player.UserId] = (playerMoveSeq[player.UserId] or 0) + 1
			end)
		end
		if hrp then
			hrp.Anchored = true
			local wp = TileGrid.TileToWorld(spawnTx, spawnTz)
			hrp.CFrame = CFrame.new(wp.X, wp.Y + 3, wp.Z)
		end

		task.wait(0.2)
		-- FIX: pass nil path and sentinel requestId = 0 so the client can
		-- unambiguously detect this as a spawn snap and not a normal path update,
		-- even if PlayerMoved fires before setupCharacter sets spawned = false.
		PlayerMoved:FireClient(player, player.UserId, spawnTx, spawnTz, nil, 0)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerTiles[player.UserId]   = nil
	playerMoveSeq[player.UserId] = nil
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
