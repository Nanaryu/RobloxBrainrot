-- ReplicatedStorage/Modules/ItemData.lua
-- Defines every item template in the game.
-- LootService uses this to generate rolled item instances.
--
-- Item slots:
--   weapon   → ATK value (absolute, replaces BASE_ATK)
--   offhand  → ATK value (adds to total ATK)
--   helmet   → DEF bonus (adds to total DEF)
--   chest    → DEF bonus (adds to total DEF)
--   legs     → DEF bonus (adds to total DEF)
--   boots    → DEF bonus (adds to total DEF)
--
-- Each entry:
--   slot       (string)
--   rarity     (string)  — matches Config.RARITIES names
--   statType   (string)  "atk" | "def"
--   statMin    (number)  rolled range low end (at base rarity)
--   statMax    (number)  rolled range high end
--   name       (string)  display name
--   icon       (string)  rbxassetid — placeholder "" until art is ready
--
-- Weapon ATK values follow Rucoy Online (weapon_data.csv):
--   Common → Dagger (14–19),  Rare → Short Sword (20–26),
--   VeryRare → Sword (27–34), Epic → Broadsword (35–44),
--   Legendary → Slayer (45–56),  Mythic → Icy/Lava (57–70),
--   Secret → Golden (71–90)

local ItemData = {}

-- ─── Helper ───────────────────────────────────────────────────────────────────
local function item(name, slot, statType, rarity, sMin, sMax, icon)
	return {
		name     = name,
		slot     = slot,
		statType = statType,
		rarity   = rarity,
		statMin  = sMin,
		statMax  = sMax,
		icon     = icon or "",
	}
end

-- ─── Weapons (absolute ATK — replaces BASE_ATK when equipped) ────────────────
-- Ranges mapped from Rucoy Online weapon data (weapon_data.csv):
--   Common → Dagger (14–19),  Rare → Short Sword (20–26),
--   VeryRare → Sword (27–34), Epic → Broadsword (35–44),
--   Legendary → Slayer (45–56),  Mythic → Icy/Lava (57–70),
--   Secret → Golden (71–90)
ItemData["Pizza Slicer"]          = item("Pizza Slicer",          "weapon", "atk", "Common",    14,  17)
ItemData["Noobini Stick"]         = item("Noobini Stick",         "weapon", "atk", "Common",    16,  19)
ItemData["Lirili Branch"]         = item("Lirili Branch",         "weapon", "atk", "Rare",      20,  23)
ItemData["Trippi Blade"]          = item("Trippi Blade",          "weapon", "atk", "Rare",      22,  26)
ItemData["Cappuccino Dagger"]     = item("Cappuccino Dagger",     "weapon", "atk", "VeryRare",  27,  31)
ItemData["Brr Brr Fang"]         = item("Brr Brr Fang",         "weapon", "atk", "Epic",      35,  39)
ItemData["Assassino Blade"]       = item("Assassino Blade",       "weapon", "atk", "Epic",      37,  44)
ItemData["Bombardiro Cannon"]     = item("Bombardiro Cannon",     "weapon", "atk", "Legendary", 45,  51)
ItemData["Sigma Sword"]           = item("Sigma Sword",           "weapon", "atk", "Legendary", 49,  56)
ItemData["Crocodilo Fang"]        = item("Crocodilo Fang",        "weapon", "atk", "Mythic",    57,  64)
ItemData["Cavallo Hoof Blade"]    = item("Cavallo Hoof Blade",    "weapon", "atk", "Mythic",    62,  70)
ItemData["Tralalero Spear"]       = item("Tralalero Spear",       "weapon", "atk", "Secret",    71,  80)
ItemData["Dragon Cannelloni Staff"]= item("Dragon Cannelloni Staff","weapon","atk","Secret",    76,  90)

-- ─── Offhand (lower ATK than primary weapon, secondary slot) ───────────────────
ItemData["Kiwi Shield Shard"]     = item("Kiwi Shield Shard",    "offhand","atk", "Common",    6,   9)
ItemData["Troppi Totem"]          = item("Troppi Totem",         "offhand","atk", "Rare",     10,  14)
ItemData["Bambini Tome"]          = item("Bambini Tome",         "offhand","atk", "Epic",     20,  27)
ItemData["Gorillo Knuckle"]       = item("Gorillo Knuckle",      "offhand","atk", "Mythic",   37,  48)
ItemData["Las Sis Orb"]           = item("Las Sis Orb",          "offhand","atk", "Secret",   49,  62)

-- ─── Helmets ──────────────────────────────────────────────────────────────────
ItemData["Cheese Cap"]            = item("Cheese Cap",           "helmet", "def", "Common",    1,   3)
ItemData["Racooni Hood"]          = item("Racooni Hood",         "helmet", "def", "Rare",      5,   8)
ItemData["Cactus Helm"]           = item("Cactus Helm",          "helmet", "def", "VeryRare",  10,  15)
ItemData["Penguin Crown"]         = item("Penguin Crown",        "helmet", "def", "Epic",      22,  32)
ItemData["Chimpazini Crown"]      = item("Chimpazini Crown",     "helmet", "def", "Legendary", 44,  62)
ItemData["Elefanto Tusk Helm"]    = item("Elefanto Tusk Helm",   "helmet", "def", "Mythic",    80, 115)
ItemData["Girafa Celestial Helm"] = item("Girafa Celestial Helm","helmet", "def", "Secret",   150, 215)

-- ─── Chest ────────────────────────────────────────────────────────────────────
ItemData["Pipi Vest"]             = item("Pipi Vest",            "chest",  "def", "Common",    2,   5)
ItemData["Bobritto Coat"]         = item("Bobritto Coat",        "chest",  "def", "Rare",      8,  13)
ItemData["Bananita Wrap"]         = item("Bananita Wrap",        "chest",  "def", "VeryRare",  15,  22)
ItemData["Patapim Armour"]        = item("Patapim Armour",       "chest",  "def", "Epic",      30,  44)
ItemData["Ballerina Tutu Plate"]  = item("Ballerina Tutu Plate", "chest",  "def", "Legendary", 60,  86)
ItemData["Toiletto Plate"]        = item("Toiletto Plate",       "chest",  "def", "Mythic",   110, 158)
ItemData["Espresso Robe"]         = item("Espresso Robe",        "chest",  "def", "Secret",   200, 285)

-- ─── Legs ─────────────────────────────────────────────────────────────────────
ItemData["FluriFlura Skirt"]      = item("FluriFlura Skirt",     "legs",   "def", "Common",    1,   3)
ItemData["Hipopotamo Pants"]      = item("Hipopotamo Pants",     "legs",   "def", "Rare",      5,   8)
ItemData["Dolphinita Fins"]       = item("Dolphinita Fins",      "legs",   "def", "Epic",      20,  28)
ItemData["Pandaccini Trousers"]   = item("Pandaccini Trousers",  "legs",   "def", "Legendary", 40,  57)
ItemData["Tob Tobi Wraps"]        = item("Tob Tobi Wraps",       "legs",   "def", "Mythic",    72, 103)
ItemData["Coco Elefanto Greaves"] = item("Coco Elefanto Greaves","legs",   "def", "Secret",   130, 185)

-- ─── Boots ────────────────────────────────────────────────────────────────────
ItemData["Pipi Sandals"]          = item("Pipi Sandals",         "boots",  "def", "Common",    1,   2)
ItemData["Gangster Footera Boots"]= item("Gangster Footera Boots","boots", "def", "Rare",      3,   5)
ItemData["Lemonchello Slippers"]  = item("Lemonchello Slippers", "boots",  "def", "VeryRare",   7,  10)
ItemData["Sigma Sneakers"]        = item("Sigma Sneakers",       "boots",  "def", "Legendary", 25,  36)
ItemData["Carloo Stompers"]       = item("Carloo Stompers",      "boots",  "def", "Mythic",    46,  65)
ItemData["Gattatino Paws"]        = item("Gattatino Paws",       "boots",  "def", "Secret",    85, 120)

-- ─── Index by rarity for LootService drop tables ──────────────────────────────
-- Pre-build: rarityPool[rarityName] = { itemTemplateName, ... }
ItemData._byRarity = {}
for name, def in pairs(ItemData) do
	if type(def) == "table" and def.rarity then
		local list = ItemData._byRarity[def.rarity]
		if not list then
			list = {}
			ItemData._byRarity[def.rarity] = list
		end
		table.insert(list, name)
	end
end

return ItemData
