-- ServerScriptService/Services/SkillService.lua
-- Tracks Attack and Defense stat XP per player.
-- Fires SkillUpdated → client whenever XP or level changes.
--
-- Public API (called by CombatService and EnemyService):
--   SkillService.GrantAttackXP(player, amount)
--   SkillService.GrantDefenseXP(player, amount)
--   SkillService.GetAttackLevel(player)   → ATK stat level (for damage formula)
--   SkillService.GetDefenseLevel(player)  → DEF stat level (for defense formula)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local Skills   = require(ReplicatedStorage.Modules.Skills)
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local SkillUpdated = Remotes:WaitForChild("SkillUpdated")

local skillStore = DataStoreService:GetDataStore("Skills_v1")

local SkillService = {}

-- ─── Constants ─────────────────────────────────────────────────────────────────
-- Rucoy starts all skills at level 5. Match that here.
local STARTING_STAT_LEVEL = 5
local STARTING_STAT_XP   = Skills.STAT_XP_TABLE[STARTING_STAT_LEVEL]

-- ─── Per-player skill state ───────────────────────────────────────────────────
-- skillData[userId] = { Attack = { totalXP = 0 }, Defense = { totalXP = 0 } }
-- totalXP = cumulative stat ticks (1 per hit / per damage taken)
local skillData = {}

local function initPlayer(player: Player)
	skillData[player.UserId] = {
		[Skills.ATTACK]  = { totalXP = STARTING_STAT_XP },
		[Skills.DEFENSE] = { totalXP = STARTING_STAT_XP },
	}
end

local function getSkillData(player: Player)
	local data = skillData[player.UserId]
	if not data then
		initPlayer(player)
		data = skillData[player.UserId]
	end
	return data
end

-- ─── Fire SkillUpdated to client ──────────────────────────────────────────────
local function fireUpdate(player: Player)
	local data = getSkillData(player)
	local payload = {}

	for _, skillName in ipairs({ Skills.ATTACK, Skills.DEFENSE }) do
		local totalXP = data[skillName].totalXP
		local level   = Skills.StatLevelFromXP(totalXP)
		local curXP, neededXP = Skills.StatXPProgress(totalXP)
		payload[skillName] = {
			level     = level,
			currentXP = curXP,
			neededXP  = neededXP,
			totalXP   = totalXP,
		}
	end

	SkillUpdated:FireClient(player, payload)
end

-- ─── Grant XP (no debounce — each enemy hit grants independently) ─────────────
local function grantXP(player: Player, skillName: string, amount: number)
	local data    = getSkillData(player)
	local skill   = data[skillName]
	local oldLevel = Skills.StatLevelFromXP(skill.totalXP)

	skill.totalXP += amount

	-- Cap at max level's XP floor so totalXP doesn't grow forever at cap
	if Skills.StatLevelFromXP(skill.totalXP) >= Skills.MAX_LEVEL then
		skill.totalXP = Skills.STAT_XP_TABLE[Skills.MAX_LEVEL]
	end

	local newLevel = Skills.StatLevelFromXP(skill.totalXP)
	if newLevel ~= oldLevel then
		print(string.format("[SkillService] %s: %s levelled up → %d",
			player.Name, skillName, newLevel))
	end

	fireUpdate(player)
end

-- ─── Public: grant XP ─────────────────────────────────────────────────────────
function SkillService.GrantAttackXP(player: Player, amount: number)
	grantXP(player, Skills.ATTACK, amount)
end

function SkillService.GrantDefenseXP(player: Player, amount: number)
	grantXP(player, Skills.DEFENSE, amount)
end

-- ─── Public: ATK level (used by CombatService damage formula) ────────────────
function SkillService.GetAttackLevel(player: Player): number
	local data = getSkillData(player)
	return Skills.StatLevelFromXP(data[Skills.ATTACK].totalXP)
end

-- ─── Public: DEF level (used by EnemyService defense formula) ────────────────
function SkillService.GetDefenseLevel(player: Player): number
	local data = getSkillData(player)
	return Skills.StatLevelFromXP(data[Skills.DEFENSE].totalXP)
end

-- ─── DataStore helpers ────────────────────────────────────────────────────────
local function loadPlayer(player: Player)
	initPlayer(player)

	local ok, result = pcall(function()
		return skillStore:GetAsync(tostring(player.UserId))
	end)
	if ok and type(result) == "table" then
		skillData[player.UserId][Skills.ATTACK].totalXP  = tonumber(result[Skills.ATTACK])  or 0
		skillData[player.UserId][Skills.DEFENSE].totalXP = tonumber(result[Skills.DEFENSE]) or 0
	end
end

-- ─── Deferred save (stagger writes, avoid DataStore budget spike) ─────────────
local pendingSaves = {} -- userId → snapshot data

local function scheduleSave(userId: number, data: table)
	pendingSaves[userId] = data
	task.delay(1.0, function()
		if pendingSaves[userId] then
			pcall(function()
				skillStore:SetAsync(tostring(userId), data)
			end)
			pendingSaves[userId] = nil
		end
	end)
end

local function flushSaves()
	local toSave = pendingSaves
	pendingSaves = {}
	for userId, data in pairs(toSave) do
		pcall(function()
			skillStore:SetAsync(tostring(userId), data)
		end)
	end
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
local function setupPlayer(player: Player)
	loadPlayer(player)

	-- Fire initial update (in case character already exists)
	task.spawn(function()
		task.wait(0.5)
		fireUpdate(player)
	end)

	-- Also fire on every respawn
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		fireUpdate(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	local data = skillData[player.UserId]
	skillData[player.UserId] = nil
	if not data then return end
	scheduleSave(player.UserId, {
		[Skills.ATTACK]  = data[Skills.ATTACK].totalXP,
		[Skills.DEFENSE] = data[Skills.DEFENSE].totalXP,
	})
end)

game:BindToClose(function()
	flushSaves()
end)

-- Handle players already in-game (Studio play-solo)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

print("[SkillService] Ready.")
return SkillService
