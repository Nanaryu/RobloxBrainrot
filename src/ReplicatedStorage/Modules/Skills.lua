-- ReplicatedStorage/Modules/Skills.lua
-- Shared constants for the skill system.
-- Required by both server (SkillService) and client (HUDController).
--
-- Two independent XP tracks:
--   1. Character Level XP: granted per enemy kill (enemy.xp value)
--   2. Stat XP (ATK/DEF): 1 tick per hit (ATK) or per damage taken (DEF)
--
-- XP curves sourced from Rucoy Online (damage_formulas/formulas.js).

local Skills = {}

Skills.ATTACK  = "Attack"
Skills.DEFENSE = "Defense"
Skills.MAX_LEVEL = 99

-- ─── Character Level XP (grind rate) ─────────────────────────────────────────
-- xp_for_level(n) = floor(n ^ (n/1000 + 3))
-- XP_TABLE[level] = cumulative XP needed to reach that level.
-- XP_TABLE[1] = 0 (start at level 1 with 0 XP).
local XP_TABLE = { [1] = 0 }
for lvl = 2, Skills.MAX_LEVEL do
	XP_TABLE[lvl] = math.floor(lvl ^ (lvl / 1000 + 3))
end
Skills.XP_TABLE = XP_TABLE

-- Returns the character level for a given cumulative XP value.
function Skills.LevelFromXP(totalXP: number): number
	for lvl = Skills.MAX_LEVEL, 2, -1 do
		if totalXP >= XP_TABLE[lvl] then
			return lvl
		end
	end
	return 1
end

-- Returns current XP within level, and XP needed for next level.
function Skills.XPProgress(totalXP: number): (number, number)
	local level = Skills.LevelFromXP(totalXP)
	if level >= Skills.MAX_LEVEL then
		return 0, 0
	end
	return totalXP - XP_TABLE[level], XP_TABLE[level + 1] - XP_TABLE[level]
end

-- ─── Stat XP — ATK / DEF (stat rate) ────────────────────────────────────────
-- stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.373))   for levels 0–54
-- stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.171))   for levels 55–99
-- These formulas give the DELTA (per-level cost) not cumulative.
-- STAT_XP_TABLE[stat] = cumulative ticks needed to reach that stat level.
-- STAT_XP_TABLE[0] = 0 (stat level 0 = no bonus).
local STAT_XP_TABLE = { [0] = 0 }
local function statDelta(s: number): number
	if s <= 54 then
		return math.floor(s ^ (s / 1000 + 2.373))
	else
		return math.floor(s ^ (s / 1000 + 2.171))
	end
end
for s = 1, Skills.MAX_LEVEL do
	STAT_XP_TABLE[s] = STAT_XP_TABLE[s - 1] + statDelta(s)
end
Skills.STAT_XP_TABLE = STAT_XP_TABLE

-- Returns the stat level for a given cumulative tick count.
function Skills.StatLevelFromXP(totalStatXP: number): number
	for lvl = Skills.MAX_LEVEL, 1, -1 do
		if totalStatXP >= STAT_XP_TABLE[lvl] then
			return lvl
		end
	end
	return 0
end

-- Returns current ticks within level, and ticks needed for next level.
function Skills.StatXPProgress(totalStatXP: number): (number, number)
	local level = Skills.StatLevelFromXP(totalStatXP)
	if level >= Skills.MAX_LEVEL then
		return 0, 0
	end
	return totalStatXP - STAT_XP_TABLE[level], STAT_XP_TABLE[level + 1] - STAT_XP_TABLE[level]
end

return Skills
