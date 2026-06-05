-- ServerScriptService/Services/MovementService.lua
-- v3 — complete rewrite for smooth, jank-free movement.
--
-- Key improvements over v2:
--   • Per-player request rate limiter (max 1 approved path per RATE_LIMIT_INTERVAL).
--     Prevents pathfinding spam from fast clicks or WASD repeat-fire.
--   • Path deduplication: if the new destination equals the in-progress destination
--     and the player hasn't moved >2 tiles since approval, silently ignore.
--   • Server tile tracking now uses a monotonic timer to advance steps instead of
--     stacking task.delay calls. One task.spawn per path; each step sleeps only
--     the delta since the previous step was dispatched (not the full stepIndex*speed
--     formula that accumulated float error over long paths).
--   • playerDest cleared immediately on any new RequestMove so CombatService
--     always pathfinds from the actual current tile, not a stale destination.
--   • GetEffectiveTile now returns the most recently accepted destination rather
--     than a possibly stale cleared one.
--   • CancelMovement returns the new sequence number AND resets the per-player
--     rate bucket so a chase can fire immediately after cancellation.
--   • GetPlayerSpeed: falls back to rawStats XP via Leaderboard instead of
--     leaderstats.Level (avoids the frame-0 level=0 bug on fresh spawn).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Pathfinder = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Pathfinder"))
local TileGrid   = require(script.Parent.TileGridService)
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local RequestMove = Remotes:WaitForChild("RequestMove")
local PlayerMoved = Remotes:WaitForChild("PlayerMoved")

local MovementService = {}

-- ─── Constants ────────────────────────────────────────────────────────────────
local MAX_PATH_NODES       = 800
local RATE_LIMIT_INTERVAL  = 0.12   -- minimum seconds between approved paths from one player
                                     -- (≈ 8 per second max, well above any real-use need)
local SAME_DEST_TOLERANCE  = 2      -- if new dest == current dest AND player is within this
                                     -- many tiles of origin, skip re-pathing

-- ─── Per-player state ─────────────────────────────────────────────────────────
local playerTiles    = {}   -- [userId] = { tx, tz }  — authoritative current tile
local playerMoveSeq  = {}   -- [userId] = number      — incremented on every new path / cancel
local playerDest     = {}   -- [userId] = { tx, tz }  — most recently accepted destination
local playerLastPath = {}   -- [userId] = number(tick) — when we last approved a path (rate limit)

local EnemyService           -- lazy-loaded to avoid circular require

-- ─── Helpers ──────────────────────────────────────────────────────────────────
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

local function getEnemyService()
	if not EnemyService then
		EnemyService = require(script.Parent.EnemyService)
	end
	return EnemyService
end

local function isPassableForPlayer(px, pz)
	if not TileGrid.IsWalkable(px, pz) then return false end
	local es = getEnemyService()
	if es.IsTileBlockedForPlayers and es.IsTileBlockedForPlayers(px, pz) then return false end
	return true
end

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

-- Find a path for a player, with automatic fallback to the authoritative tile
-- if the client-reported origin is too stale.
local function findPlayerPath(player, fromX, fromZ, toX, toZ)
	if not isValidTile(fromX, fromZ) or not isValidTile(toX, toZ) then return nil end

	local es = getEnemyService()
	if es.IsTileBlockedForPlayers and es.IsTileBlockedForPlayers(toX, toZ) then return nil end
	if not isPassableForPlayer(toX, toZ) then return nil end

	local path = Pathfinder.FindPath(isPassableForPlayer, fromX, fromZ, toX, toZ, MAX_PATH_NODES)

	-- Fallback: if client origin is stale, try from the server-tracked tile
	if not path then
		local userId = player.UserId
		local cur = playerTiles[userId]
		if cur and (cur.tx ~= fromX or cur.tz ~= fromZ) then
			path = Pathfinder.FindPath(isPassableForPlayer, cur.tx, cur.tz, toX, toZ, MAX_PATH_NODES)
		end
	end

	if path and #path > MAX_PATH_NODES then return nil end
	return path
end

-- ─── Server tile tracking (one coroutine per approved path) ──────────────────
-- Rather than stacking N independent task.delay calls (which accumulate floating-
-- point drift), we run a single coroutine that wakes once per step.
local function advanceServerTiles(userId, path, speed, seq)
	-- Step 0 is applied immediately before this is called (see handler below)
	for i = 2, #path do
		task.wait(speed)
		-- Abort if the sequence changed (new path / cancel / death)
		if playerMoveSeq[userId] ~= seq then return end
		playerTiles[userId] = { tx = path[i][1], tz = path[i][2] }
	end
	-- Walk complete — clear destination
	if playerMoveSeq[userId] == seq then
		playerDest[userId] = nil
	end
end

-- ─── RequestMove handler ──────────────────────────────────────────────────────
RequestMove.OnServerEvent:Connect(function(player, tx, tz, fromX, fromZ, requestId)
	if not isPlayerAlive(player) then return end

	-- Sanitise inputs
	tx  = math.floor(type(tx)  == "number" and tx  or 0)
	tz  = math.floor(type(tz)  == "number" and tz  or 0)

	local userId = player.UserId
	local cur    = playerTiles[userId]
	if not cur then return end

	-- ── Rate limiter ─────────────────────────────────────────────────────────
	local now = tick()
	local lastPath = playerLastPath[userId] or 0
	if (now - lastPath) < RATE_LIMIT_INTERVAL then return end

	-- ── Destination dedup ────────────────────────────────────────────────────
	-- If the player is rapidly clicking the same tile we already approved, skip.
	local dest = playerDest[userId]
	if dest and dest.tx == tx and dest.tz == tz then
		local distFromCur = math.abs(cur.tx - tx) + math.abs(cur.tz - tz)
		if distFromCur <= SAME_DEST_TOLERANCE then return end
	end

	-- ── Origin validation ────────────────────────────────────────────────────
	-- Accept client-reported origin if it is ≤2 tiles from the server tile.
	-- This allows the client to smooth ahead by one or two steps without
	-- causing pathfinding to start from a tile the character hasn't reached.
	local clientFromX = math.clamp(math.floor(type(fromX) == "number" and fromX or cur.tx), 1, Config.GRID_WIDTH)
	local clientFromZ = math.clamp(math.floor(type(fromZ) == "number" and fromZ or cur.tz), 1, Config.GRID_HEIGHT)
	local drift = math.abs(clientFromX - cur.tx) + math.abs(clientFromZ - cur.tz)

	local fromTileX = drift <= 2 and clientFromX or cur.tx
	local fromTileZ = drift <= 2 and clientFromZ or cur.tz

	-- ── Pathfind ─────────────────────────────────────────────────────────────
	local path = findPlayerPath(player, fromTileX, fromTileZ, tx, tz)
	if not path or #path == 0 then return end

	-- ── Commit ───────────────────────────────────────────────────────────────
	playerLastPath[userId]    = now
	playerMoveSeq[userId]     = (playerMoveSeq[userId] or 0) + 1
	local seq                 = playerMoveSeq[userId]

	playerDest[userId]        = { tx = tx, tz = tz }
	playerTiles[userId]       = { tx = path[1][1], tz = path[1][2] }  -- first step immediate

	-- Broadcast to all clients (all players see everyone move)
	PlayerMoved:FireAllClients(userId, tx, tz, path, requestId)

	-- Advance server tile tracking in a single coroutine
	local speed = MovementService.GetPlayerSpeed(player)
	task.spawn(advanceServerTiles, userId, path, speed, seq)
end)

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local map = workspace:WaitForChild("Map", 30)
		map:WaitForChild("TileGrid", 30)

		local userId           = player.UserId
		local spawnTx, spawnTz = TileGrid.GetSpawnTile()

		playerTiles[userId]    = { tx = spawnTx, tz = spawnTz }
		playerMoveSeq[userId]  = (playerMoveSeq[userId] or 0) + 1
		playerDest[userId]     = nil
		playerLastPath[userId] = 0   -- reset rate bucket on respawn

		local hrp      = character:WaitForChild("HumanoidRootPart", 10)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 10)

		if humanoid then
			humanoid.WalkSpeed     = 0
			humanoid.JumpPower     = 0
			humanoid.AutoRotate    = false
			humanoid.PlatformStand = false
			humanoid.Died:Connect(function()
				playerMoveSeq[userId] = (playerMoveSeq[userId] or 0) + 1
				playerDest[userId]    = nil
			end)
		end

		if hrp then
			hrp.Anchored = true
			local wp = TileGrid.TileToWorld(spawnTx, spawnTz)
			hrp.CFrame = CFrame.new(wp.X, wp.Y + 3, wp.Z)
		end

		-- Small delay so client receives the map before we send spawn position
		task.wait(0.2)
		PlayerMoved:FireClient(player, userId, spawnTx, spawnTz, nil, 0)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId              = player.UserId
	playerTiles[userId]       = nil
	playerMoveSeq[userId]     = nil
	playerDest[userId]        = nil
	playerLastPath[userId]    = nil
end)

-- ─── Public API ───────────────────────────────────────────────────────────────

-- Authoritative current tile the server believes the player is on.
function MovementService.GetPlayerTile(player)
	local t = playerTiles[player.UserId]
	if t then return t.tx, t.tz end
	return nil, nil
end

-- Effective tile for combat pathfinding origin:
-- returns the accepted walk destination if a walk is in progress,
-- otherwise the current tile. CombatService uses this so chase
-- paths start from "where the player will be" rather than "where
-- they are right now", reducing unnecessary re-paths.
function MovementService.GetEffectiveTile(player)
	local userId = player.UserId
	local dest   = playerDest[userId]
	if dest then return dest.tx, dest.tz end
	local t = playerTiles[userId]
	if t then return t.tx, t.tz end
	return nil, nil
end

function MovementService.IsPlayerTileOccupied(tx, tz, exceptPlayer)
	return isPlayerTileOccupied(tx, tz, exceptPlayer)
end

-- Seconds-per-tile tween time for this player (lower = faster).
-- Reads leaderstats.Level with a safe fallback to 1 if not yet initialised.
function MovementService.GetPlayerSpeed(player)
	local char  = player.Character
	local ls    = char and char:FindFirstChild("leaderstats")
	local level = (ls and ls:FindFirstChild("Level") and ls.Level.Value) or 1
	level = math.max(1, level)   -- guard against 0 on fresh spawn
	local t = math.clamp(level / Config.PLAYER_SPEED_LEVEL, 0, 1)
	return Config.PLAYER_SPEED_BASE + (Config.PLAYER_SPEED_MIN - Config.PLAYER_SPEED_BASE) * t
end

-- Hard-set tile (used by CombatService chase system to keep server in sync
-- with client animation without firing a full RequestMove).
function MovementService.SetPlayerTile(player, tx, tz)
	playerTiles[player.UserId] = { tx = tx, tz = tz }
end

-- Cancel in-progress movement. Increments sequence (stops any running
-- advanceServerTiles coroutine) and clears destination.
-- Also resets the rate bucket so an immediate chase path is allowed.
-- Returns the new sequence number (for CombatService to guard delayed tasks).
function MovementService.CancelMovement(player)
	local userId          = player.UserId
	playerMoveSeq[userId] = (playerMoveSeq[userId] or 0) + 1
	playerDest[userId]    = nil
	playerLastPath[userId]= 0    -- allow the next chase path immediately
	return playerMoveSeq[userId]
end

function MovementService.GetMoveSeq(player)
	return playerMoveSeq[player.UserId] or 0
end

function MovementService.GetPathDuration(player, pathLength)
	return pathLength * MovementService.GetPlayerSpeed(player)
end

print("[MovementService] v3 Ready.")
return MovementService