-- ServerScriptService/Services/SkillService.lua
-- Tracks Attack and Defense skill XP per player.
-- Fires SkillUpdated → client whenever XP or level changes.
--
-- Public API (called by CombatService and EnemyService):
--   SkillService.GrantAttackXP(player, amount)
--   SkillService.GrantDefenseXP(player, amount)
--   SkillService.GetAttackBonus(player)   → flat ATK bonus from Attack level
--   SkillService.GetDefenseReduction(player) → damage reduction ratio (0–0.75)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local Skills   = require(ReplicatedStorage.Modules.Skills)
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local SkillUpdated = Remotes:WaitForChild("SkillUpdated")

local skillStore = DataStoreService:GetDataStore("Skills_v1")

local SkillService = {}

-- ─── Per-player skill state ───────────────────────────────────────────────────
-- skillData[userId] = { Attack = { totalXP = 0 }, Defense = { totalXP = 0 } }
local skillData = {}

local function initPlayer(player: Player)
	skillData[player.UserId] = {
		[Skills.ATTACK]  = { totalXP = 0 },
		[Skills.DEFENSE] = { totalXP = 0 },
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
		local level   = Skills.LevelFromXP(totalXP)
		local curXP, neededXP = Skills.XPProgress(totalXP)
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
	local oldLevel = Skills.LevelFromXP(skill.totalXP)

	skill.totalXP += amount

	-- Cap at max level's XP floor so totalXP doesn't grow forever at cap
	if Skills.LevelFromXP(skill.totalXP) >= Skills.MAX_LEVEL then
		skill.totalXP = Skills.XP_TABLE[Skills.MAX_LEVEL]
	end

	local newLevel = Skills.LevelFromXP(skill.totalXP)
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

-- ─── Public: Attack bonus (flat ATK added to base damage) ────────────────────
function SkillService.GetAttackBonus(player: Player): number
	local data  = getSkillData(player)
	local level = Skills.LevelFromXP(data[Skills.ATTACK].totalXP)
	return (level - 1) * 0.5
end

-- ─── Public: Defense reduction ──────────────────────────────────────────────
function SkillService.GetDefenseReduction(player: Player): number
	local data  = getSkillData(player)
	local level = Skills.LevelFromXP(data[Skills.DEFENSE].totalXP)
	local raw   = level / (level + 80)
	return math.min(raw, 0.75)
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
