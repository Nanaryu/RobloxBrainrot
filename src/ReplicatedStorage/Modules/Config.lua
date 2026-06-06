-- ReplicatedStorage/Modules/Config.lua
-- Central config. Change values here; everything else reads from this.

local Config = {}

-- ─── Tile Grid ────────────────────────────────────────────────────────────────
Config.TILE_SIZE       = 8       -- studs per tile (width & depth)
Config.TILE_HEIGHT     = 0.5     -- visual thickness of each tile part
Config.GRID_WIDTH      = 128     -- number of tiles horizontally
Config.GRID_HEIGHT     = 128     -- number of tiles vertically

-- ─── Map Shape ────────────────────────────────────────────────────────────────
-- Noise amplitude for zone boundaries (0 = perfect circles, 1 = very jagged)
Config.MAP_NOISE_AMPLITUDE = 0.55
-- Seed for deterministic noise (change for different map shapes)
Config.MAP_NOISE_SEED      = 42

-- ─── Town / Safe Zone ─────────────────────────────────────────────────────────
Config.TOWN_RADIUS     = 10      -- tiles from spawn — hard safe boundary

-- ─── Movement ─────────────────────────────────────────────────────────────────
Config.MOVE_TWEEN_TIME = 0.35    -- base seconds to slide between tiles (enemies; player scales with level)

-- ─── Camera ───────────────────────────────────────────────────────────────────
Config.CAM_DISTANCE         = 40       -- studs from character
Config.CAM_HORIZONTAL_ANGLE = 45       -- degrees, rotated around Y axis
Config.CAM_VERTICAL_ANGLE   = 56       -- degrees, tilt down (higher = more top-down, better click range)
Config.CAM_LERP             = 0.15     -- follow smoothing (0 = instant, higher = more lag)

-- ─── Combat ───────────────────────────────────────────────────────────────────
Config.BASE_ATK         = 15      -- base weapon attack (scales with equipment later)
Config.PLAYER_SPEED_BASE= 0.35    -- tween time at level 1 (seconds per tile; lower = faster)
Config.PLAYER_SPEED_MIN = 0.22    -- tween time at max level (quick reflexes endgame)
Config.PLAYER_SPEED_LEVEL= 200    -- level at which player reaches max speed
Config.ENEMY_SPEED_BASE = 0.55    -- tween time for tier 1 enemies (slower than player early)
Config.ENEMY_SPEED_MIN  = 0.15    -- tween time for tier 8 enemies (fast endgame)
Config.ENEMY_RENDER_DISTANCE = 200  -- studs — enemies beyond this skip AI, GUI, and path checks
Config.AUTO_ATTACK_RANGE   = 1   -- cardinal-adjacent tile only
Config.AUTO_ATTACK_INTERVAL= 1.0 -- seconds between player attacks
Config.ENEMY_ATTACK_INTERVAL= 1.5
Config.SOUND_HIT_ID        = ""  -- placeholder: set to rbxassetid://... for player hit SFX
Config.SOUND_DAMAGE_ID     = ""  -- placeholder: set to rbxassetid://... for player takes damage SFX
Config.SOUND_DEATH_ID      = ""  -- placeholder: set to rbxassetid://... for player death SFX

-- ─── Death / Respawn ──────────────────────────────────────────────────────────
Config.RESPAWN_DELAY          = 5    -- seconds between death and respawn
Config.INVINCIBILITY_DURATION = 3    -- seconds of invincibility after respawn

-- ─── Click Limit ──────────────────────────────────────────────────────────────
Config.MAX_CLICK_DISTANCE  = 25  -- max Manhattan distance for click-to-move

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

-- Derived lookup tables (avoids duplicating in every consumer)
Config.RARITY_COLOR = {}
Config.RARITY_ORDER = {}
for i, r in ipairs(Config.RARITIES) do
	Config.RARITY_COLOR[r.name] = r.color
	Config.RARITY_ORDER[r.name] = i
end

-- ─── Equipment Slots ──────────────────────────────────────────────────────────
Config.EQUIP_SLOTS = {
	weapon = true, offhand = true,
	helmet = true, chest  = true,
	legs   = true, boots  = true,
}

-- ─── Utility ──────────────────────────────────────────────────────────────────
function Config.manhattan(ax: number, az: number, bx: number, bz: number): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

function Config.getEnemyFromPart(part: BasePart)
	local obj = part
	while obj do
		if obj:IsA("Model") and obj:GetAttribute("EnemyId") then return obj end
		obj = obj.Parent
	end
	return nil
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
