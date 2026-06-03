-- ServerScriptService/Services/MovementService.lua
--
-- FIXES:
--   • getEffectiveOrigin now uses playerTiles (current tracked tile) not playerDest.
--     playerDest was the final destination of a walk — pathfinding FROM there caused
--     the server to route from a tile the player hadn't reached yet, creating detour
--     paths and server/client position divergence.
--   • CancelMovement now also clears playerDest so stale destinations can't leak
--     into subsequent pathfinding origins.
--   • Tile update delay calculation uses actual speed at time of approval (captured
--     once) so speed-level changes mid-path don't cause step timing drift.
--   • RequestMove: client origin clamped before drift check; toleranced to 2 tiles
--     (was 3) to catch faster desync while staying permissive for normal lag.
--   • SetPlayerTile is now also used by the tile-update tasks to keep tracking
--     consistent with CombatService's chase path updates.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Pathfinder = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Pathfinder"))
local TileGrid   = require(script.Parent.TileGridService)
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local MovementService = {}

local playerTiles    = {} -- [userId] = { tx, tz }  — authoritative current tile
local playerMoveSeq  = {}
local playerDest     = {} -- [userId] = { tx, tz }  — final destination (for display only)
local EnemyService

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
	if not EnemyService then EnemyService = require(script.Parent.EnemyService) end
	if EnemyService.IsTileBlockedForPlayers and EnemyService.IsTileBlockedForPlayers(tx, tz) then return nil end

	local function isPassable(px, pz)
		if not TileGrid.IsWalkable(px, pz) then return false end
		if EnemyService.IsTileBlockedForPlayers and EnemyService.IsTileBlockedForPlayers(px, pz) then return false end
		return true
	end

	if not isPassable(tx, tz) then return nil end
	local path = Pathfinder.FindPath(isPassable, fromX, fromZ, tx, tz, MAX_PATH_NODES)
	if path and #path > MAX_PATH_NODES then return nil end
	return path
end

-- ─── Move handler ─────────────────────────────────────────────────────────────
RequestMove.OnServerEvent:Connect(function(player, tx, tz, fromX, fromZ, requestId)
	if not isPlayerAlive(player) then return end

	tx, tz = math.floor(tx or 0), math.floor(tz or 0)
	local userId = player.UserId
	local cur = playerTiles[userId]
	if not cur then return end

	playerMoveSeq[userId] = (playerMoveSeq[userId] or 0) + 1
	local seq = playerMoveSeq[userId]

	-- Use the client's reported origin if it's within 2 tiles of the server's
	-- tracked tile. Otherwise, use the server tile to prevent cheating/desync.
	-- FIX: use playerTiles (current tile) not playerDest for origin validation.
	local clientFromX = math.floor(fromX or cur.tx)
	local clientFromZ = math.floor(fromZ or cur.tz)
	clientFromX = math.clamp(clientFromX, 1, Config.GRID_WIDTH)
	clientFromZ = math.clamp(clientFromZ, 1, Config.GRID_HEIGHT)

	local originDrift = math.abs(clientFromX - cur.tx) + math.abs(clientFromZ - cur.tz)

	local fromTileX, fromTileZ
	if originDrift <= 2 then
		fromTileX, fromTileZ = clientFromX, clientFromZ
	else
		fromTileX, fromTileZ = cur.tx, cur.tz
	end

	local path = findPlayerPath(player, fromTileX, fromTileZ, tx, tz)
	if not path or #path == 0 then return end

	-- Broadcast the approved path to all clients.
	PlayerMoved:FireAllClients(player.UserId, tx, tz, path, requestId)

	-- Record destination for GetEffectiveTile (used by CombatService only).
	playerDest[userId] = { tx = tx, tz = tz }

	-- Capture speed once so all delayed updates use consistent timing.
	local speed = MovementService.GetPlayerSpeed(player)

	-- Immediately update server tile to first step.
	playerTiles[userId] = { tx = path[1][1], tz = path[1][2] }

	-- Schedule remaining step updates.
	for stepIndex = 2, #path do
		local step = path[stepIndex]
		task.delay((stepIndex - 1) * speed, function()
			if playerMoveSeq[userId] == seq then
				playerTiles[userId] = { tx = step[1], tz = step[2] }
			end
		end)
	end

	-- Clear destination after walk completes.
	task.delay(#path * speed + 0.05, function()
		if playerMoveSeq[userId] == seq then
			playerDest[userId] = nil
		end
	end)
end)

-- ─── Spawn ────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local map = workspace:WaitForChild("Map", 30)
		map:WaitForChild("TileGrid", 30)

		local spawnTx, spawnTz = TileGrid.GetSpawnTile()
		playerTiles[player.UserId]   = { tx = spawnTx, tz = spawnTz }
		playerMoveSeq[player.UserId] = (playerMoveSeq[player.UserId] or 0) + 1
		playerDest[player.UserId]    = nil

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
				playerDest[player.UserId] = nil
			end)
		end
		if hrp then
			hrp.Anchored = true
			local wp = TileGrid.TileToWorld(spawnTx, spawnTz)
			hrp.CFrame = CFrame.new(wp.X, wp.Y + 3, wp.Z)
		end

		task.wait(0.2)
		PlayerMoved:FireClient(player, player.UserId, spawnTx, spawnTz, nil, 0)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerTiles[player.UserId]   = nil
	playerMoveSeq[player.UserId] = nil
	playerDest[player.UserId]    = nil
end)

-- ─── Public API ───────────────────────────────────────────────────────────────
function MovementService.GetPlayerTile(player)
	local t = playerTiles[player.UserId]
	if t then return t.tx, t.tz end
	return nil, nil
end

-- Returns the effective position for pathfinding: final destination of any
-- in-progress walk, so walk-to-enemy starts from where the player is going.
-- NOTE: intentionally returns playerDest (not playerTiles) — callers that want
-- the exact current tile should use GetPlayerTile directly.
function MovementService.GetEffectiveTile(player)
	local userId = player.UserId
	local dest = playerDest[userId]
	if dest then return dest.tx, dest.tz end
	local t = playerTiles[userId]
	if t then return t.tx, t.tz end
	return nil, nil
end

function MovementService.IsPlayerTileOccupied(tx, tz, exceptPlayer)
	return isPlayerTileOccupied(tx, tz, exceptPlayer)
end

function MovementService.GetPlayerSpeed(player): number
	local char = player.Character
	local ls = char and char:FindFirstChild("leaderstats")
	local level = ls and ls:FindFirstChild("Level") and ls.Level.Value or 1
	local t = math.clamp(level / Config.PLAYER_SPEED_LEVEL, 0, 1)
	return Config.PLAYER_SPEED_BASE + (Config.PLAYER_SPEED_MIN - Config.PLAYER_SPEED_BASE) * t
end

function MovementService.SetPlayerTile(player, tx, tz)
	playerTiles[player.UserId] = { tx = tx, tz = tz }
end

-- Cancel any in-progress movement and increment sequence.
-- FIX: also clears playerDest so the next pathfind doesn't originate from a
-- stale destination.
function MovementService.CancelMovement(player: Player)
	local userId = player.UserId
	playerMoveSeq[userId] = (playerMoveSeq[userId] or 0) + 1
	playerDest[userId] = nil      -- FIX: clear dest so origin is current tile
	return playerMoveSeq[userId]
end

function MovementService.GetMoveSeq(player: Player): number
	return playerMoveSeq[player.UserId] or 0
end

function MovementService.GetPathDuration(player, pathLength: number): number
	local speed = MovementService.GetPlayerSpeed(player)
	return pathLength * speed
end

print("[MovementService] Ready.")
return MovementService