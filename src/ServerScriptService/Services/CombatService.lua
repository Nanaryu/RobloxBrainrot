-- ServerScriptService/Services/CombatService.lua
-- Fully server-driven auto-attack.
-- Every AUTO_ATTACK_INTERVAL the server checks each player for cardinal-adjacent
-- (manhattan == 1) enemies and splits the player's damage evenly among them.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage.Modules.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult = Remotes:WaitForChild("AttackResult")

-- ─── Lazy service references ──────────────────────────────────────────────────
local EnemyService
local MovementService
local SkillService

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

-- ─── Per-player loop state ────────────────────────────────────────────────────
local loopActive: { [number]: boolean } = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function getAdjacentEnemies(ptx: number, ptz: number): { Model }
	local map    = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Enemies")
	if not folder then return {} end

	local adjacent = {}
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("State") ~= "dead" then
			local etx = model:GetAttribute("CurrentTileX")
			local etz = model:GetAttribute("CurrentTileZ")
			if etx and etz then
				local dist = math.abs(ptx - etx) + math.abs(ptz - etz)
				if dist == Config.AUTO_ATTACK_RANGE then
					table.insert(adjacent, model)
				end
			end
		end
	end
	return adjacent
end

-- ─── Single attack tick for one player ───────────────────────────────────────
local function doAttackTick(player: Player)
	if not isPlayerAlive(player) then return end

	local ms = getMovementService()
	local ss = getSkillService()
	local es = getEnemyService()

	local ptx, ptz = ms.GetPlayerTile(player)
	if not ptx then return end

	local targets = getAdjacentEnemies(ptx, ptz)
	if #targets == 0 then return end

	-- Base damage (with ±10 % variance) divided equally among targets
	local baseDamage = 10 + ss.GetAttackBonus(player)
	local rolled     = math.random(math.floor(baseDamage * 0.9), math.ceil(baseDamage * 1.1))
	local share      = math.max(1, math.floor(rolled / #targets))

	for _, model in ipairs(targets) do
		local enemyId = model:GetAttribute("EnemyId")
		if enemyId and model:GetAttribute("State") ~= "dead" then
			es.DamageEnemy(enemyId, share, player)
			ss.GrantAttackXP(player, 2)

			-- FIX: pass damage and enemyId so DamageNumbers.client.lua can
			-- spawn a floating number above the correct enemy model.
			AttackResult:FireClient(player, true, share, enemyId)
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
			doAttackTick(player)
		end
		loopActive[userId] = false
	end)
end

local function stopLoop(player: Player)
	loopActive[player.UserId] = false
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		stopLoop(player)

		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			task.wait(0.2)
			if humanoid.Health > 0 then
				startLoop(player)
			end

			humanoid.Died:Connect(function()
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
	loopActive[player.UserId] = false
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

print("[CombatService] Ready — server-driven auto-attack active.")
return {}
