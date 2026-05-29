-- ReplicatedStorage/Modules/RerollSystem.lua
-- Handles the 3-item reroll mechanic.
-- Called by the server; client sends a RerollRequest remote.

local Config = require(script.Parent.Config)

local RerollSystem = {}

-- Returns the rarity name string resulting from a reroll attempt.
-- items: array of 3 item instances, each with item.rarity = "Common" | "Rare" | ...
function RerollSystem.Roll(items)
	assert(#items == Config.REROLL_REQUIRES, "RerollSystem.Roll expects exactly " .. Config.REROLL_REQUIRES .. " items")

	-- Find lowest and highest rarity indices among the 3 items
	local minIdx = math.huge
	local maxIdx = 0

	for _, item in ipairs(items) do
		local idx = Config.RARITY_INDEX[item.rarity]
		assert(idx, "Unknown rarity: " .. tostring(item.rarity))
		if idx < minIdx then
			minIdx = idx
		end
		if idx > maxIdx then
			maxIdx = idx
		end
	end

	-- Ceiling = highest input rarity + 1, capped at max tier
	local ceiling = math.min(maxIdx + 1, #Config.RARITIES)

	-- Build a weighted pool between minIdx and ceiling (inclusive)
	local pool = {}
	local totalWeight = 0
	for i = minIdx, ceiling do
		local r = Config.RARITIES[i]
		table.insert(pool, { name = r.name, weight = r.weight })
		totalWeight = totalWeight + r.weight
	end

	-- Weighted random pick
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.name
		end
	end

	-- Fallback (shouldn't reach here)
	return Config.RARITIES[ceiling].name
end

-- Convenience: returns true if a reroll is possible (player owns 3+ of this item)
function RerollSystem.CanReroll(count)
	return count >= Config.REROLL_REQUIRES
end

return RerollSystem
