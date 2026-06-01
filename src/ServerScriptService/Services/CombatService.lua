-- ServerScriptService/Services/CombatService.lua
-- Receives AttackRequest from a client (player clicked enemy or is auto-attacking).
-- Validates range, applies damage, responds with result.
-- The client handles the walk-to-enemy logic locally; this is the damage authority.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config        = require(ReplicatedStorage.Modules.Config)
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")

-- Lazy-require to avoid circular dependency at load time
local EnemyService
local MovementService
local SkillService

-- Remotes needed
local RequestAttack  = Remotes:WaitForChild("RequestAttack")   -- Client → Server  (enemyId)
local AttackResult   = Remotes:WaitForChild("AttackResult")    -- Server → Client  (hit, damage, enemyId, enemyHP)
local StopAttack     = Remotes:WaitForChild("StopAttack")      -- Client → Server  (cancel current target)

-- Per-player attack state
local playerTargets:    { [number]: string  } = {}  -- userId → enemyId
local playerLastAttack: { [number]: number  } = {}  -- userId → tick()

local CombatService = {}
local playerLoops: { [number]: boolean } = {}

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- ─── Validate that player is in attack range of enemy ─────────────────────────
local function inRange(player: Player, enemyId: string): boolean
	if not isPlayerAlive(player) then return false end
	if not MovementService then MovementService = require(script.Parent.MovementService) end
	if not EnemyService    then EnemyService    = require(script.Parent.EnemyService)    end

	local ptx, ptz = MovementService.GetPlayerTile(player)
	if not ptx then return false end

	local model = EnemyService.GetEnemy(enemyId)
	if not model then return false end
	if model:GetAttribute("State") == "dead" then return false end

	local etx = model:GetAttribute("CurrentTileX")
	local etz = model:GetAttribute("CurrentTileZ")

	-- Cardinal adjacent only: Manhattan distance must be exactly 1
	local dist = math.abs(ptx - etx) + math.abs(ptz - etz)
	return dist == 1
end

-- ─── Attack tick (called by the per-player loop) ──────────────────────────────
local function doAttack(player: Player)
	if not EnemyService then EnemyService = require(script.Parent.EnemyService) end
	if not SkillService  then SkillService  = require(script.Parent.SkillService)  end
	if not isPlayerAlive(player) then
		playerTargets[player.UserId] = nil
		playerLoops[player.UserId] = false
		return
	end

	local userId  = player.UserId
	local enemyId = playerTargets[userId]
	if not enemyId then return end

	if not inRange(player, enemyId) then
		AttackResult:FireClient(player, false, 0, enemyId, 0)
		return
	end

	local baseDamage = 10 + SkillService.GetAttackBonus(player)
	local damage     = math.random(math.floor(baseDamage * 0.9), math.ceil(baseDamage * 1.1))

	EnemyService.DamageEnemy(enemyId, damage, player)
	SkillService.GrantAttackXP(player, 2)

	local model = EnemyService.GetEnemy(enemyId)
	local remainingHP = model and model:GetAttribute("CurrentHP") or 0
	AttackResult:FireClient(player, true, damage, enemyId, remainingHP)
end

	-- Simple flat damage for now — replace with player stat lookup later
	local baseDamage = 10  -- TODO: read from player equipment stats
	local damage     = math.random(math.floor(baseDamage * 0.9), math.ceil(baseDamage * 1.1))

	EnemyService.DamageEnemy(enemyId, damage, player)

	local model = EnemyService.GetEnemy(enemyId)
	local remainingHP = model and model:GetAttribute("CurrentHP") or 0
	AttackResult:FireClient(player, true, damage, enemyId, remainingHP)
end

-- ─── Per-player attack loop ───────────────────────────────────────────────────
local function startAttackLoop(player: Player)
	local userId = player.UserId
	if playerLoops[userId] then return end
	playerLoops[userId] = true

	task.spawn(function()
		while playerLoops[userId] and playerTargets[userId] do
			local now  = tick()
			local last = playerLastAttack[userId] or 0
			local wait = Config.AUTO_ATTACK_INTERVAL - (now - last)

			if wait > 0 then
				task.wait(wait)
			end

			if not playerLoops[userId] or not playerTargets[userId] then break end

			playerLastAttack[userId] = tick()
			doAttack(player)

			-- If target died, clear it
			if not EnemyService or not EnemyService.GetEnemy(playerTargets[userId]) then
				playerTargets[userId] = nil
			end
		end
		playerLoops[userId] = false
	end)
end

-- ─── Remote: player sets a target ─────────────────────────────────────────────
RequestAttack.OnServerEvent:Connect(function(player: Player, enemyId: string)
	if type(enemyId) ~= "string" then return end
	if not isPlayerAlive(player) then return end

	playerTargets[player.UserId] = enemyId
	startAttackLoop(player)
end)

-- ─── Remote: player cancels attack ────────────────────────────────────────────
StopAttack.OnServerEvent:Connect(function(player: Player)
	playerTargets[player.UserId] = nil
	playerLoops[player.UserId]   = false
end)

-- ─── Cleanup on leave ─────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player: Player)
	playerTargets[player.UserId]    = nil
	playerLoops[player.UserId]      = false
	playerLastAttack[player.UserId] = nil
end)

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		playerTargets[player.UserId] = nil
		playerLoops[player.UserId] = false
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				playerTargets[player.UserId] = nil
				playerLoops[player.UserId] = false
			end)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

-- ─── Add missing remotes (CombatService-specific ones not in RemotesInit) ─────
-- These are added here so they're always present when this script loads.
-- RemotesInit runs first but we double-check gracefully.
local function ensureRemote(name: string, isFunction: boolean)
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	if not folder:FindFirstChild(name) then
		local r = Instance.new(isFunction and "RemoteFunction" or "RemoteEvent")
		r.Name   = name
		r.Parent = folder
	end
end

ensureRemote("RequestAttack", false)
ensureRemote("AttackResult",  false)
ensureRemote("StopAttack",    false)

print("[CombatService] Ready.")

return CombatService
