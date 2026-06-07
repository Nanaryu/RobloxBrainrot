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
--
-- FIXES:
--   • Attack loop now uses a per-player token (loopToken) instead of a boolean
--     flag. Previously, if stopLoop() was called while the goroutine was inside
--     task.wait(), startLoop() would immediately return (loopActive still true)
--     and the loop would fail to restart after the wait expired.
--   • Chase loop: "enemy hasn't moved" early-continue now also checks whether
--     the estimated player position has meaningfully changed since the last path
--     was sent — prevents getting stuck just outside attack range.
--   • startChase: path step updates (task.delay tasks) are guarded with both
--     the moveSeq AND the chaseSeq, so stale delayed tasks from a previous
--     chase don't overwrite the player tile after a new chase has started.
--   • doAttackTick: distance check uses GetPlayerTile (authoritative) not the
--     estimated tile, so the server always trusts its own tile record for the
--     final range gate.
--   • RequestAttack: guards against acting on a dead/nil model that arrived
--     in the same frame as a kill.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage.Modules.Config)
local Pathfinder = require(ReplicatedStorage.Modules.Pathfinder)
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult  = Remotes:WaitForChild("AttackResult")
local RequestAttack = Remotes:WaitForChild("RequestAttack")
local StopAttack    = Remotes:WaitForChild("StopAttack")
local PlayerMoved   = Remotes:WaitForChild("PlayerMoved")
local DamageNumber  = Remotes:WaitForChild("DamageNumber")

-- ─── Lazy service references ──────────────────────────────────────────────────
local EnemyService
local MovementService
local SkillService
local LootService
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
local function getLootService()
	if not LootService then LootService = require(script.Parent.LootService) end
	return LootService
end
local function getTileGrid()
	if not TileGrid then TileGrid = require(script.Parent.TileGridService) end
	return TileGrid
end

-- ─── Per-player state ─────────────────────────────────────────────────────────
-- FIX: use integer tokens instead of booleans for both loops so a stop+start
-- in the same frame reliably creates a new independent loop.
local loopToken:  { [number]: number } = {}   -- userId → current loop token
local attackTarget: { [number]: string } = {} -- userId → enemyId

-- ─── Forward declarations ────────────────────────────────────────────────────
local startChase

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Increment token to invalidate the current attack loop (it will exit on its
-- next iteration / after its current wait).
local function stopLoop(player: Player)
	loopToken[player.UserId] = (loopToken[player.UserId] or 0) + 1
end

-- ─── Damage formula (Rucoy-style) ────────────────────────────────────────────
local function calculateDamage(player: Player, enemyDEF: number): number
	local ss = getSkillService()
	local ls = getLootService()
	local atkLevel = ss.GetAttackLevel(player)
	-- Weapon ATK replaces BASE_ATK (absolute Rucoy-style); fallback to fists
	local wepAtk   = ls.GetEquippedWeaponAttack(player)
	if wepAtk <= 0 then wepAtk = Config.BASE_ATK end

	local min_raw = (atkLevel * wepAtk) / 20
	local max_raw = (atkLevel * wepAtk) / 10

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

	-- FIX: use authoritative server tile, not estimated tile, for range check
	local ptx, ptz = ms.GetPlayerTile(player)
	if not ptx then return end

	local etx = targetModel:GetAttribute("CurrentTileX")
	local etz = targetModel:GetAttribute("CurrentTileZ")
	if not etx or not etz then return end

	local dist = Config.manhattan(ptx, ptz, etx, etz)

	-- Out of range — stop attacking and re-chase
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

-- FIX: startLoop now takes a snapshot of the current token. The loop exits if
-- the token has changed, which happens when stopLoop() is called. This means
-- stopLoop() + startLoop() in quick succession always creates a fresh loop
-- rather than having startLoop() bail out because the old loop's flag is stale.
local function startLoop(player: Player)
	local userId = player.UserId
	-- Increment token to own this loop instance
	loopToken[userId] = (loopToken[userId] or 0) + 1
	local myToken = loopToken[userId]

	task.spawn(function()
		while loopToken[userId] == myToken do
			local now  = tick()
			local last = lastAttack[userId] or 0
			local wait = Config.AUTO_ATTACK_INTERVAL - (now - last)
			if wait > 0 then
				task.wait(wait)
			end
			-- Re-check token after wait (it may have changed while sleeping)
			if loopToken[userId] ~= myToken then break end

			lastAttack[userId] = tick()
			local ok, err = pcall(doAttackTick, player)
			if not ok then
				warn("[CombatService] Attack tick error:", err)
				break
			end
		end
	end)
end

-- ─── Chase system ─────────────────────────────────────────────────────────────
local chaseSeq          = {}
local chaseEnemyTile    = {}
local chaseLastSentTime = {}
local chaseLastSentSpeed= {}
local chaseLastSentPath = {}
-- FIX: track the estimated player tile at the time we last sent a path,
-- so we can detect when the player has moved far enough to warrant a re-path
-- even if the enemy hasn't moved.
local chaseLastEstimateTile = {}

local REVAL_INTERVAL = 0.2

local function stopChase(player)
	local userId = player.UserId
	chaseSeq[userId]               = (chaseSeq[userId] or 0) + 1
	chaseEnemyTile[userId]         = nil
	chaseLastSentTime[userId]      = nil
	chaseLastSentSpeed[userId]     = nil
	chaseLastSentPath[userId]      = nil
	chaseLastEstimateTile[userId]  = nil
end

local function estimatePlayerTile(player)
	local ms = getMovementService()
	local userId = player.UserId
	local lastTime  = chaseLastSentTime[userId]
	local lastSpeed = chaseLastSentSpeed[userId]
	local lastPath  = chaseLastSentPath[userId]

	if not lastTime or not lastSpeed or not lastPath or #lastPath == 0 then
		return ms.GetPlayerTile(player)
	end

	local elapsed   = tick() - lastTime
	local stepsDone = math.clamp(math.floor(elapsed / lastSpeed), 0, #lastPath)

	if stepsDone == 0 then
		return ms.GetPlayerTile(player)
	end

	return lastPath[stepsDone][1], lastPath[stepsDone][2]
end

local function findAdjacentTile(fromX, fromZ, targetX, targetZ)
	local tg2 = getTileGrid()
	local es2 = getEnemyService()

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
		if tg2.IsWalkable(tx, tz) and not es2.IsTileBlockedForPlayers(tx, tz) then
			return tx, tz
		end
	end
	return nil, nil
end

startChase = function(player, targetModel)
	local userId   = player.UserId
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

			local eptx, eptz = estimatePlayerTile(player)
			if not eptx then break end

			-- Already in attack range → stop chasing, start attacking
			if Config.manhattan(eptx, eptz, etx, etz) <= Config.AUTO_ATTACK_RANGE then
				startLoop(player)
				break
			end

			-- FIX: also re-path when the estimated player position has shifted
			-- by more than 1 tile since the last path was sent. Without this,
			-- the player can be stuck just outside attack range because the
			-- "enemy hasn't moved" skip prevents any new path from being sent.
			local lastEP = chaseLastEstimateTile[userId]
			local enemyUnchanged = chaseEnemyTile[userId]
				and chaseEnemyTile[userId].tx == etx
				and chaseEnemyTile[userId].tz == etz
			local playerUnchanged = lastEP
				and math.abs(lastEP.tx - eptx) + math.abs(lastEP.tz - eptz) <= 1

			if enemyUnchanged and playerUnchanged then
				task.wait(REVAL_INTERVAL)
				continue
			end

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

			local path = Pathfinder.FindPath(isPassable, eptx, eptz, adjX, adjZ, 400)

			if not path or #path == 0 then
				-- Fallback: try from authoritative server tile
				local sptx, sptz = ms.GetPlayerTile(player)
				if sptx and (sptx ~= eptx or sptz ~= eptz) then
					path = Pathfinder.FindPath(isPassable, sptx, sptz, adjX, adjZ, 400)
				end
			end

			if not path or #path == 0 then
				task.wait(REVAL_INTERVAL)
				continue
			end

			-- Record what we're sending so future iterations can estimate position
			chaseEnemyTile[userId]          = { tx = etx, tz = etz }
			chaseLastEstimateTile[userId]   = { tx = eptx, tz = eptz }
			chaseLastSentTime[userId]       = tick()
			chaseLastSentPath[userId]       = path

			local msSeq = ms.CancelMovement(player)
			PlayerMoved:FireAllClients(player.UserId, adjX, adjZ, path, -1, etx, etz)

			local speed = ms.GetPlayerSpeed(player)
			chaseLastSentSpeed[userId] = speed

			-- Update server tile immediately to first step
			ms.SetPlayerTile(player, path[1][1], path[1][2])

			-- FIX: guard delayed tile-updates with BOTH the move sequence AND
			-- the chase sequence. A new chase cancelling before the delays fire
			-- would previously overwrite the new chase's tile tracking.
			local capturedMsSeq  = msSeq
			local capturedChaseSeq = seq
			for i = 2, #path do
				local step = path[i]
				task.delay((i - 1) * speed, function()
					if ms.GetMoveSeq(player) == capturedMsSeq
						and chaseSeq[userId] == capturedChaseSeq
						and isPlayerAlive(player) then
						ms.SetPlayerTile(player, step[1], step[2])
					end
				end)
			end

			task.wait(REVAL_INTERVAL)
		end

		-- Cleanup
		if chaseSeq[userId] == seq then
			chaseEnemyTile[userId]         = nil
			chaseLastSentTime[userId]      = nil
			chaseLastSentSpeed[userId]     = nil
			chaseLastSentPath[userId]      = nil
			chaseLastEstimateTile[userId]  = nil
		end
	end)
end

-- ─── RequestAttack handler ────────────────────────────────────────────────────
RequestAttack.OnServerEvent:Connect(function(player: Player, enemyId: string)
	if not isPlayerAlive(player) then return end

	local es = getEnemyService()
	local ms = getMovementService()

	-- FIX: validate model is still alive before registering the target
	local model = es.GetEnemy(enemyId)
	if not model then return end
	if model:GetAttribute("State") == "dead" then return end

	attackTarget[player.UserId] = enemyId

	local ptx, ptz = ms.GetPlayerTile(player)
	local etx = model:GetAttribute("CurrentTileX")
	local etz = model:GetAttribute("CurrentTileZ")

	if ptx and etx and Config.manhattan(ptx, ptz, etx, etz) <= Config.AUTO_ATTACK_RANGE then
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

-- ─── Enemy died → immediately clear all players targeting it ──────────────────
-- Register a hook with EnemyService so it can notify us when any enemy dies.
local function onEnemyDied(enemyId: string)
	for userId, targetId in pairs(attackTarget) do
		if targetId == enemyId then
			attackTarget[userId] = nil
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.UserId == userId then
					stopChase(plr)
					stopLoop(plr)
					break
				end
			end
		end
	end
end

-- Hook into EnemyService kill
do
	local es = getEnemyService()
	if es.RegisterOnKill then
		es.RegisterOnKill(onEnemyDied)
	end
end

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
	stopLoop(player)
	lastAttack[userId] = nil
end)

print("[CombatService] Ready — click-to-attack with walk-to-enemy active.")
return {
	CalculateDamage = calculateDamage,
	StopLoop        = stopLoop,
}