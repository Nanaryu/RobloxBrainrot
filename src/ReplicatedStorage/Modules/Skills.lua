-- ReplicatedStorage/Modules/Skills.lua
-- Shared constants for the skill system.
-- Required by both server (SkillService) and client (HUDController).

local Skills = {}

Skills.ATTACK  = "Attack"
Skills.DEFENSE = "Defense"

-- XP needed to reach each level (index = level, value = total XP needed from level 1).
-- Level 1 → 2 costs 100 XP, 2 → 3 costs 150, scaling by ×1.35 each tier.
-- Cap at level 99.
local BASE_XP   = 100
local XP_SCALE  = 1.35
local MAX_LEVEL = 99

Skills.MAX_LEVEL = MAX_LEVEL

-- Pre-build cumulative XP table: XP_TABLE[level] = total XP needed to BE that level.
-- XP_TABLE[1] = 0 (you start at level 1 with 0 XP spent).
local XP_TABLE = { 0 }
for lvl = 2, MAX_LEVEL do
	XP_TABLE[lvl] = math.floor(XP_TABLE[lvl - 1] + BASE_XP * (XP_SCALE ^ (lvl - 2)))
end
Skills.XP_TABLE = XP_TABLE

-- Returns the level corresponding to a total accumulated XP value.
function Skills.LevelFromXP(totalXP: number): number
	local level = 1
	for lvl = MAX_LEVEL, 2, -1 do
		if totalXP >= XP_TABLE[lvl] then
			level = lvl
			break
		end
	end
	return level
end

-- Returns how much XP the player currently has within their current level,
-- and how much is needed to reach the next level.
function Skills.XPProgress(totalXP: number): (number, number)
	local level = Skills.LevelFromXP(totalXP)
	if level >= MAX_LEVEL then
		return 0, 0   -- maxed out
	end
	local currentFloor = XP_TABLE[level]
	local nextFloor    = XP_TABLE[level + 1]
	return totalXP - currentFloor, nextFloor - currentFloor
end

return Skills
