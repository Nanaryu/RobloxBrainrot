-- ReplicatedStorage/Modules/Config.lua
-- Central config. Change values here; everything else reads from this.

local Config = {}

-- ─── Tile Grid ────────────────────────────────────────────────────────────────
Config.TILE_SIZE       = 4       -- studs per tile (width & depth)
Config.TILE_HEIGHT     = 0.5     -- visual thickness of each tile part
Config.GRID_WIDTH      = 64      -- number of tiles horizontally
Config.GRID_HEIGHT     = 64      -- number of tiles vertically

-- ─── Movement ─────────────────────────────────────────────────────────────────
Config.MOVE_TWEEN_TIME = 0.18    -- seconds to slide between tiles

-- ─── Camera ───────────────────────────────────────────────────────────────────
Config.CAM_DISTANCE         = 40       -- studs from character
Config.CAM_HORIZONTAL_ANGLE = 45       -- degrees, rotated around Y axis
Config.CAM_VERTICAL_ANGLE   = 40       -- degrees, tilt down (35 = true iso, 40 = RPG feel)
Config.CAM_LERP             = 0.15     -- follow smoothing (0 = instant, higher = more lag)

-- ─── Combat ───────────────────────────────────────────────────────────────────
Config.AUTO_ATTACK_RANGE   = 2   -- tiles (Chebyshev distance)
Config.AUTO_ATTACK_INTERVAL= 1.0 -- seconds between player attacks
Config.ENEMY_ATTACK_INTERVAL= 1.5

-- ─── Item Rarities ────────────────────────────────────────────────────────────
-- Order = weakest → strongest. Used for reroll math and display colour.
Config.RARITIES = {
	{ name = "Common",    color = Color3.fromRGB(180, 180, 180), weight = 1000 },
	{ name = "Rare",      color = Color3.fromRGB( 80, 120, 255), weight = 400  },
	{ name = "VeryRare",  color = Color3.fromRGB( 50, 200, 180), weight = 150  },
	{ name = "Epic",      color = Color3.fromRGB(163,  53, 238), weight = 60   },
	{ name = "Legendary", color = Color3.fromRGB(255, 165,   0), weight = 20   },
	{ name = "Mythic",    color = Color3.fromRGB(220,  20,  60), weight = 5    },
	{ name = "Secret",    color = Color3.fromRGB(255, 215,   0), weight = 1    },
}

-- Lookup by name → index (built at require time)
Config.RARITY_INDEX = {}
for i, r in ipairs(Config.RARITIES) do
	Config.RARITY_INDEX[r.name] = i
end

-- ─── Reroll ───────────────────────────────────────────────────────────────────
-- Combining 3 items rerolls into a rarity between (lowestInput) and (ceiling).
-- Ceiling = min(highestInput + 1 tier, MAX_RARITY).
Config.REROLL_REQUIRES = 3   -- items needed per reroll

-- ─── Currency ─────────────────────────────────────────────────────────────────
Config.GOLD_NAME            = "Gold"
Config.PREMIUM_NAME         = "Crystals"   -- TODO: pick final name
Config.PREMIUM_ROBUX_COST   = 100          -- robux per premium bundle (placeholder)
Config.PREMIUM_BUNDLE_AMOUNT= 100          -- crystals per bundle

-- ─── Elite Enemies ────────────────────────────────────────────────────────────
Config.ELITE_STAR_MAX       = 5
Config.ELITE_SPAWN_CHANCE   = 0.05         -- 5 % of spawns are elites
-- Per-star multipliers (index = star count)
Config.ELITE_HP_MULT        = { 1.5, 2.0, 3.0, 5.0, 10.0 }
Config.ELITE_DMG_MULT       = { 1.2, 1.5, 2.0, 3.0,  5.0 }
Config.ELITE_LOOT_TIER_BUMP = { 1,   1,   2,   2,    3   } -- rarity tiers added

-- ─── Offline Shops ────────────────────────────────────────────────────────────
Config.SHOP_DURATIONS = {         -- {label, hours, crystalCost}
	{ label = "6h",  hours = 6,  cost = 10 },
	{ label = "12h", hours = 12, cost = 18 },
	{ label = "24h", hours = 24, cost = 30 },
	{ label = "3d",  hours = 72, cost = 75 },
}
Config.SHOP_MAX_LISTINGS = 20

return Config
