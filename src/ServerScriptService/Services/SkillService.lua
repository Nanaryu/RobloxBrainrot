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

local Skills   = require(ReplicatedStorage.Modules.Skills)
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")
local SkillUpdated = Remotes:WaitForChild("SkillUpdated")

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

-- ─── XP debounce: prevent one attack round granting XP multiple times ─────────
-- Key: userId .. skillName → last grant tick
local lastGrantTick = {}
local GRANT_DEBOUNCE = 0.1   -- seconds; one grant per attack swing

local function grantXP(player: Player, skillName: string, amount: number)
	local key = player.UserId .. skillName
	local now = tick()
	if (lastGrantTick[key] or 0) + GRANT_DEBOUNCE > now then return end
	lastGrantTick[key] = now

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
		-- Level-up notification can be expanded later (sound, GUI pop-up, etc.)
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
-- Formula: each Attack level above 1 adds 0.5 flat damage (rounds down at use site).
-- Level 1 = +0, Level 50 = +24.5, Level 99 = +49.
function SkillService.GetAttackBonus(player: Player): number
	local data  = getSkillData(player)
	local level = Skills.LevelFromXP(data[Skills.ATTACK].totalXP)
	return (level - 1) * 0.5
end

-- ─── Public: Defense reduction (proportion of incoming damage negated) ────────
-- Formula: soft-cap curve so it never reaches 1.0.
--   reduction = level / (level + 80)
-- Level 1  ≈ 1.2%  reduction
-- Level 20 ≈ 20%   reduction
-- Level 50 ≈ 38%   reduction
-- Level 99 ≈ 55%   reduction  (hard cap 75% enforced below)
function SkillService.GetDefenseReduction(player: Player): number
	local data  = getSkillData(player)
	local level = Skills.LevelFromXP(data[Skills.DEFENSE].totalXP)
	local raw   = level / (level + 80)
	return math.min(raw, 0.75)
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	initPlayer(player)
	-- Push initial state once character loads (HUD needs it on spawn)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)   -- give HUDController time to connect
		fireUpdate(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	skillData[player.UserId] = nil
	-- Clean up debounce keys
	lastGrantTick[player.UserId .. Skills.ATTACK]  = nil
	lastGrantTick[player.UserId .. Skills.DEFENSE] = nil
end)

-- Handle players already in-game (Studio play-solo)
for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end

print("[SkillService] Ready.")
return SkillService
