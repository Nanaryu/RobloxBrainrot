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

	-- Out of range — re-path to enemy instead of giving up
	if dist > Config.AUTO_ATTACK_RANGE then
		stopLoop(player)
		task.defer(function()
			walkToEnemy(player, targetModel)
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
			doAttackTick(player)
		end
		loopActive[userId] = false
	end)
end

-- ─── Walk-to-enemy: find adjacent tile and path there ────────────────────────
local function findAdjacentTile(fromX, fromZ, targetX, targetZ, playerId)
	local ms = getMovementService()
	local tg = getTileGrid()
	local es = getEnemyService()

	local candidates = {
		{ targetX + 1, targetZ },
		{ targetX - 1, targetZ },
		{ targetX, targetZ + 1 },
		{ targetX, targetZ - 1 },
	}

	-- Sort by distance to player (pick closest adjacent tile)
	table.sort(candidates, function(a, b)
		local da = math.abs(a[1] - fromX) + math.abs(a[2] - fromZ)
		local db = math.abs(b[1] - fromX) + math.abs(b[2] - fromZ)
		return da < db
	end)

	for _, c in ipairs(candidates) do
		local tx, tz = c[1], c[2]
		if tg.IsWalkable(tx, tz)
			and not ms.IsPlayerTileOccupied(tx, tz)
			and not es.IsTileBlockedForPlayers(tx, tz) then
			return tx, tz
		end
	end
	return nil, nil
end

local function walkToEnemy(player, targetModel)
	local ms = getMovementService()
	local ptx, ptz = ms.GetPlayerTile(player)
	if not ptx then return false end

	local etx = targetModel:GetAttribute("CurrentTileX")
	local etz = targetModel:GetAttribute("CurrentTileZ")
	if not etx or not etz then return false end

	if manhattan(ptx, ptz, etx, etz) <= Config.AUTO_ATTACK_RANGE then
		return true
	end

	local adjX, adjZ = findAdjacentTile(ptx, ptz, etx, etz, player.UserId)
	if not adjX then return false end

	local function isPassable(px, pz)
		local tg = getTileGrid()
		local ms2 = getMovementService()
		local es2 = getEnemyService()
		if not tg.IsWalkable(px, pz) then return false end
		if ms2.IsPlayerTileOccupied(px, pz, player) then return false end
		if es2.IsTileBlockedForPlayers(px, pz) then return false end
		return true
	end

	local path = Pathfinder.FindPath(isPassable, ptx, ptz, adjX, adjZ, 400)
	if not path or #path == 0 then return false end

	-- Cancel any previous movement (walk or click-to-move) using unified counter
	local userId = player.UserId
	local seq = ms.CancelMovement(player)

	PlayerMoved:FireAllClients(player.UserId, adjX, adjZ, path, -1)

	ms.SetPlayerTile(player, path[1][1], path[1][2])

	local speed = ms.GetPlayerSpeed(player)
	for i = 2, #path do
		local step = path[i]
		task.delay((i - 1) * speed, function()
			if ms.GetMoveSeq(player) == seq and isPlayerAlive(player) then
				ms.SetPlayerTile(player, step[1], step[2])
			end
		end)
	end

	local walkDuration = #path * speed
	task.delay(walkDuration + 0.05, function()
		if ms.GetMoveSeq(player) ~= seq then return end
		if not isPlayerAlive(player) then return end
		if attackTarget[userId] ~= targetModel:GetAttribute("EnemyId") then return end

		local sx, sz = ms.GetPlayerTile(player)
		local ex = targetModel:GetAttribute("CurrentTileX")
		local ez = targetModel:GetAttribute("CurrentTileZ")
		if not sx or not ex then return end

		if manhattan(sx, sz, ex, ez) <= Config.AUTO_ATTACK_RANGE then
			startLoop(player)
			return
		end
		if manhattan(adjX, adjZ, ex, ez) <= Config.AUTO_ATTACK_RANGE then
			ms.SetPlayerTile(player, adjX, adjZ)
			startLoop(player)
		end
	end)

	return false
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
		walkToEnemy(player, model)
	end
end)

StopAttack.OnServerEvent:Connect(function(player: Player)
	local userId = player.UserId
	attackTarget[userId] = nil
	getMovementService().CancelMovement(player)
	stopLoop(player)
end)

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		attackTarget[player.UserId] = nil
		getMovementService().CancelMovement(player)
		stopLoop(player)

		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				attackTarget[player.UserId] = nil
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
	attackTarget[player.UserId] = nil
	loopActive[player.UserId] = nil
	lastAttack[player.UserId] = nil
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

print("[CombatService] Ready — click-to-attack with walk-to-enemy active.")
return {}
