-- ServerScriptService/Services/CombatService.lua
-- Server-driven auto-attack with Rucoy-style damage formula.
-- Click-to-attack: walk to enemy if not adjacent, then auto-attack.
--
-- Damage formula (from Rucoy):
--   min_raw = (ATK_Level × BASE_ATK) / 20
--   max_raw = (ATK_Level × BASE_ATK) / 10
--   accuracy = clamp((max_raw - enemy_DEF) / (max_raw - min_raw), 0, 1)
--   if accuracy == 0 → deal 0 (hard progression gate)
--   else roll random(min_raw, max_raw) - enemy_DEF

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage.Modules.Config)
local Pathfinder = require(ReplicatedStorage.Modules.Pathfinder)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult  = Remotes:WaitForChild("AttackResult")
local RequestAttack = Remotes:WaitForChild("RequestAttack")
local StopAttack    = Remotes:WaitForChild("StopAttack")
local PlayerMoved   = Remotes:WaitForChild("PlayerMoved")
local DamageNumber  = Remotes:WaitForChild("DamageNumber")

-- ─── Lazy service references ──────────────────────────────────────────────────
local EnemyService
local MovementService
local SkillService
local TileGrid

local function getEnemyService()
	if not EnemyService then EnemyService = require(script.Parent.EnemyService) end
	return EnemyService
end
local function getMovementService()
	if not MovementService then MovementService = require(script.Parent.MovementService) end
	return MovementService
end
local function getSkillService()
	if not SkillService then SkillService = require(script.Parent.SkillService) end
	return SkillService
end
local function getTileGrid()
	if not TileGrid then TileGrid = require(script.Parent.TileGridService) end
	return TileGrid
end

-- ─── Per-player state ─────────────────────────────────────────────────────────
local loopActive: { [number]: boolean } = {}
local attackTarget: { [number]: string } = {} -- userId → enemyId

-- ─── Forward declarations (circular runtime deps) ────────────────────────────
local startChase  -- defined later, referenced by doAttackTick

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function manhattan(ax, az, bx, bz): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

local function getEnemyAtTile(ptx: number, ptz: number): Model?
	local es = getEnemyService()
	return es.GetEnemyAtTile(ptx, ptz)
end

function stopLoop(player: Player)
	loopActive[player.UserId] = false
end

-- ─── Damage formula (Rucoy-style) ────────────────────────────────────────────
local function calculateDamage(player: Player, enemyDEF: number): number
	local ss = getSkillService()
	local atkLevel = ss.GetAttackLevel(player)
	local baseATK  = Config.BASE_ATK

	local min_raw = (atkLevel * baseATK) / 20
	local max_raw = (atkLevel * baseATK) / 10

	local range = max_raw - min_raw
	if range <= 0 or max_raw <= enemyDEF then
		return 0
	end

	local accuracy = math.clamp((max_raw - enemyDEF) / range, 0, 1)
	if math.random() > accuracy then
		return 0
	end

	local rolled = math.random(math.floor(min_raw), math.ceil(max_raw))
	return math.max(0, rolled - enemyDEF)
end

-- ─── Single attack tick for one player ───────────────────────────────────────
local function doAttackTick(player: Player)
	if not isPlayerAlive(player) then return end

	local ms = getMovementService()
	local ss = getSkillService()
	local es = getEnemyService()

	local targetId = attackTarget[player.UserId]
	if not targetId then return end

	local targetModel = es.GetEnemy(targetId)
	if not targetModel or targetModel:GetAttribute("State") == "dead" then
		attackTarget[player.UserId] = nil
		stopLoop(player)
		return
	end

	local ptx, ptz = ms.GetPlayerTile(player)
	if not ptx then return end

	local etx = targetModel:GetAttribute("CurrentTileX")
	local etz = targetModel:GetAttribute("CurrentTileZ")
	if not etx or not etz then return end

	local dist = manhattan(ptx, ptz, etx, etz)

	-- Out of range — re-chase enemy dynamically
	if dist > Config.AUTO_ATTACK_RANGE then
		stopLoop(player)
		task.defer(function()
			startChase(player, targetModel)
		end)
		return
	end

	-- In range — attack
	local enemyDEF = targetModel:GetAttribute("Defense") or 0
	local damage = calculateDamage(player, enemyDEF)

	local enemyId = targetModel:GetAttribute("EnemyId")
	if enemyId then
		es.DamageEnemy(enemyId, damage, player)
		ss.GrantAttackXP(player, 1)
		AttackResult:FireClient(player, damage > 0, damage, enemyId)
		if damage > 0 then
			DamageNumber:FireAllClients(player.UserId, damage, enemyId)
		end
	end
end

-- ─── Per-player attack loop ───────────────────────────────────────────────────
local lastAttack: { [number]: number } = {}

local function startLoop(player: Player)
	local userId = player.UserId
	if loopActive[userId] then return end
	loopActive[userId] = true

	task.spawn(function()
		while loopActive[userId] do
			local now  = tick()
			local last = lastAttack[userId] or 0
			local wait = Config.AUTO_ATTACK_INTERVAL - (now - last)
			if wait > 0 then task.wait(wait) end
			if not loopActive[userId] then break end

			lastAttack[userId] = tick()
			local ok, err = pcall(doAttackTick, player)
			if not ok then
				warn("[CombatService] Attack tick error:", err)
				stopLoop(player)
				break
			end
		end
		loopActive[userId] = false
	end)
end

-- ─── Chase system: dynamically re-path towards moving enemy ──────────────────
-- Replaces static walkToEnemy with a loop that re-paths as the enemy moves.
-- Uses time-based client position estimation to keep paths accurate.

local chaseSeq          = {} -- [userId] → number; increment to cancel active chase
local chaseEnemyTile    = {} -- [userId] → { tx, tz } — enemy tile when we last sent a path
local chaseLastSentTime = {} -- [userId] → tick() — when the last chase path was sent
local chaseLastSentSpeed= {} -- [userId] → seconds per tile at time of send
local chaseLastSentPath = {} -- [userId] → {{tx,tz}, ...} — last path sent to client

local REVAL_INTERVAL = 0.2 -- seconds between chase re-evaluations

local function stopChase(player)
	local userId = player.UserId
	chaseSeq[userId]          = (chaseSeq[userId] or 0) + 1
	chaseEnemyTile[userId]    = nil
	chaseLastSentTime[userId] = nil
	chaseLastSentSpeed[userId]= nil
	chaseLastSentPath[userId] = nil
end

-- Estimate the client's current tile using time elapsed since last path was sent.
-- Falls back to server-tracked tile if no path info is available.
local function estimatePlayerTile(player)
	local ms = getMovementService()
	local userId = player.UserId
	local lastTime  = chaseLastSentTime[userId]
	local lastSpeed = chaseLastSentSpeed[userId]
	local lastPath  = chaseLastSentPath[userId]

	if not lastTime or not lastSpeed or not lastPath or #lastPath == 0 then
		return ms.GetPlayerTile(player)
	end

	local elapsed  = tick() - lastTime
	local stepsDone = math.clamp(math.floor(elapsed / lastSpeed), 0, #lastPath)

	if stepsDone == 0 then
		return ms.GetPlayerTile(player)
	end

	return lastPath[stepsDone][1], lastPath[stepsDone][2]
end

local function findAdjacentTile(fromX, fromZ, targetX, targetZ)
	local ms = getMovementService()
	local tg = getTileGrid()
	local es = getEnemyService()

	local candidates = {
		{ targetX + 1, targetZ },
		{ targetX - 1, targetZ },
		{ targetX, targetZ + 1 },
		{ targetX, targetZ - 1 },
	}

	table.sort(candidates, function(a, b)
		local da = math.abs(a[1] - fromX) + math.abs(a[2] - fromZ)
		local db = math.abs(b[1] - fromX) + math.abs(b[2] - fromZ)
		return da < db
	end)

	for _, c in ipairs(candidates) do
		local tx, tz = c[1], c[2]
		if tg.IsWalkable(tx, tz)
			and not es.IsTileBlockedForPlayers(tx, tz) then
			return tx, tz
		end
	end
	return nil, nil
end

startChase = function(player, targetModel)
	local userId  = player.UserId
	local targetId = targetModel:GetAttribute("EnemyId")
	stopChase(player)
	local seq = chaseSeq[userId]

	task.spawn(function()
		while seq == chaseSeq[userId] do
			if not isPlayerAlive(player) then break end
			if attackTarget[userId] ~= targetId then break end

			local ms = getMovementService()
			local es = getEnemyService()

			local enemyModel = es.GetEnemy(targetId)
			if not enemyModel or enemyModel:GetAttribute("State") == "dead" then
				attackTarget[userId] = nil
				break
			end

			local etx = enemyModel:GetAttribute("CurrentTileX")
			local etz = enemyModel:GetAttribute("CurrentTileZ")
			if not etx or not etz then break end

			-- Estimate where the client actually is (not stale server tile)
			local eptx, eptz = estimatePlayerTile(player)
			if not eptx then break end

			-- Already in attack range → stop chasing, start attacking
			if manhattan(eptx, eptz, etx, etz) <= Config.AUTO_ATTACK_RANGE then
				startLoop(player)
				break
			end

			-- No need to re-path if the enemy hasn't moved since our last path
			local last = chaseEnemyTile[userId]
			if last and last.tx == etx and last.tz == etz then
				task.wait(REVAL_INTERVAL)
				continue
			end

			-- Find adjacent walkable tile to the enemy's current position,
			-- sorted by distance to estimated player position
			local adjX, adjZ = findAdjacentTile(eptx, eptz, etx, etz)
			if not adjX then
				task.wait(REVAL_INTERVAL)
				continue
			end

			local function isPassable(px, pz)
				local tg2 = getTileGrid()
				local es2 = getEnemyService()
				if not tg2.IsWalkable(px, pz) then return false end
				if es2.IsTileBlockedForPlayers(px, pz) then return false end
				return true
			end

			-- Pathfind from estimated client position (not stale server tile)
			local path = Pathfinder.FindPath(isPassable, eptx, eptz, adjX, adjZ, 400)

			-- Fallback: try from server-tracked position if estimate failed
			if not path or #path == 0 then
				local sptx, sptz = ms.GetPlayerTile(player)
				if sptx and (sptx ~= eptx or sptz ~= eptz) then
					path = Pathfinder.FindPath(isPassable, sptx, sptz, adjX, adjZ, 400)
				end
			end

			if not path or #path == 0 then
				task.wait(REVAL_INTERVAL)
				continue
			end

			-- Store path info for next position estimation
			chaseEnemyTile[userId]    = { tx = etx, tz = etz }
			chaseLastSentTime[userId] = tick()
			chaseLastSentPath[userId] = path

			-- Cancel old movement tracking, broadcast new path to clients
			local msSeq = ms.CancelMovement(player)
			PlayerMoved:FireAllClients(player.UserId, adjX, adjZ, path, -1)

			-- Record speed AFTER CancelMovement (which might reset dest)
			local speed = ms.GetPlayerSpeed(player)
			chaseLastSentSpeed[userId] = speed

			-- Immediately set server tile to first step (consistent with RequestMove)
			ms.SetPlayerTile(player, path[1][1], path[1][2])

			-- Schedule remaining tile updates
			for i = 2, #path do
				local step = path[i]
				task.delay((i - 1) * speed, function()
					if ms.GetMoveSeq(player) == msSeq and isPlayerAlive(player) then
						ms.SetPlayerTile(player, step[1], step[2])
					end
				end)
			end

			-- Short fixed interval: re-evaluate frequently so we detect
			-- enemy direction changes and in-range quickly
			task.wait(REVAL_INTERVAL)
		end

		chaseEnemyTile[userId]    = nil
		chaseLastSentTime[userId] = nil
		chaseLastSentSpeed[userId]= nil
		chaseLastSentPath[userId] = nil
	end)
end

-- ─── RequestAttack handler ────────────────────────────────────────────────────
RequestAttack.OnServerEvent:Connect(function(player: Player, enemyId: string)
	if not isPlayerAlive(player) then return end

	local es = getEnemyService()
	local ms = getMovementService()
	local model = es.GetEnemy(enemyId)
	if not model or model:GetAttribute("State") == "dead" then return end

	attackTarget[player.UserId] = enemyId

	local ptx, ptz = ms.GetPlayerTile(player)
	local etx = model:GetAttribute("CurrentTileX")
	local etz = model:GetAttribute("CurrentTileZ")
	if ptx and etx and manhattan(ptx, ptz, etx, etz) <= Config.AUTO_ATTACK_RANGE then
		startLoop(player)
	else
		startChase(player, model)
	end
end)

StopAttack.OnServerEvent:Connect(function(player: Player)
	local userId = player.UserId
	attackTarget[userId] = nil
	stopChase(player)
	getMovementService().CancelMovement(player)
	stopLoop(player)
end)

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local userId = player.UserId
		attackTarget[userId] = nil
		stopChase(player)
		getMovementService().CancelMovement(player)
		stopLoop(player)

		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				attackTarget[userId] = nil
				stopChase(player)
				getMovementService().CancelMovement(player)
				stopLoop(player)
			end)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local userId = player.UserId
	attackTarget[userId] = nil
	stopChase(player)
	loopActive[userId] = nil
	lastAttack[userId] = nil
end)

-- ─── Ensure remotes exist ─────────────────────────────────────────────────────
local function ensureRemote(name: string, isFunction: boolean)
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	if not folder:FindFirstChild(name) then
		local r  = Instance.new(isFunction and "RemoteFunction" or "RemoteEvent")
		r.Name   = name
		r.Parent = folder
	end
end
ensureRemote("AttackResult",  false)
ensureRemote("RequestAttack", false)
ensureRemote("StopAttack",    false)
ensureRemote("DamageNumber",  false)

print("[CombatService] Ready — click-to-attack with walk-to-enemy active.")
return {}
