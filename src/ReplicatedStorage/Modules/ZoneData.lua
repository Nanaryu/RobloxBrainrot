-- ReplicatedStorage/Modules/ZoneData.lua
-- Zone definitions for the map. Each zone is an organic blob defined by a
-- centre offset (from grid centre) + base radius + noise amplitude.
-- TileGridService uses Voronoi + noise to assign tiles to zones.

local ZoneData = {}

-- Zone order matters for spawn pool only; assignment is geometry-based.
ZoneData.ZONES = {
	{
		id          = "Town",
		name        = "Brainrot Town",
		center      = { x = 0, z = 0 },       -- offset from grid centre
		radius      = 12,                       -- base radius in tiles
		noiseAmp    = 0.15,                     -- light organic wobble on edges
		safe        = true,                     -- no enemy spawns, enemies blocked
		tileColors  = {
			primary   = Color3.fromRGB(180, 160, 100),  -- warm sandstone
			secondary = Color3.fromRGB(160, 145, 90),
		},
		tileMaterial = Enum.Material.SmoothPlastic,
		spawnEnemies = {},
		leashRange  = 0,
		spawnDensity = 0,
	},
	{
		id          = "Grasslands",
		name        = "Grasslands",
		center      = { x = -22, z = -18 },    -- NW — enemies ~12 tiles from spawn
		radius      = 28,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(80, 120, 60),   -- grass green
			secondary = Color3.fromRGB(70, 110, 55),
		},
		tileMaterial = Enum.Material.Grass,
		spawnEnemies = {
			{ name = "Noobini Pizzanini",    weight = 30, wanderRange = 5, aggroRange = 10 },
			{ name = "Lirili Larila",        weight = 25, wanderRange = 5, aggroRange = 10 },
			{ name = "TIM Cheese",           weight = 18, wanderRange = 4, aggroRange = 9  },
			{ name = "FluriFlura",           weight = 12, wanderRange = 4, aggroRange = 9  },
			{ name = "Talpa Di Fero",        weight = 8,  wanderRange = 4, aggroRange = 10 },
			{ name = "Svinina Bombardino",   weight = 4,  wanderRange = 3, aggroRange = 10 },
			{ name = "Pipi Kiwi",            weight = 2,  wanderRange = 3, aggroRange = 11 },
			{ name = "Racooni Jandelini",    weight = 1,  wanderRange = 3, aggroRange = 11 },
		},
		spawnDensity = 0.007,
		leashRange   = 20,
	},
	{
		id          = "Desert",
		name        = "Scorched Desert",
		center      = { x = 22, z = -20 },     -- NE
		radius      = 28,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(194, 170, 110), -- sand
			secondary = Color3.fromRGB(180, 158, 100),
		},
		tileMaterial = Enum.Material.Sand,
		spawnEnemies = {
			{ name = "Pipi Corni",            weight = 20, wanderRange = 4, aggroRange = 10 },
			{ name = "Trippi Troppi",         weight = 20, wanderRange = 4, aggroRange = 10 },
			{ name = "Gangster Footera",      weight = 16, wanderRange = 4, aggroRange = 10 },
			{ name = "Bandito Bobritto",      weight = 14, wanderRange = 4, aggroRange = 10 },
			{ name = "Boneca Ambalabu",       weight = 12, wanderRange = 3, aggroRange = 10 },
			{ name = "Cacto Hipopotamo",      weight = 8,  wanderRange = 3, aggroRange = 10 },
			{ name = "Ta Ta Ta Ta Sahur",     weight = 5,  wanderRange = 3, aggroRange = 11 },
			{ name = "Tric Trac Baraboom",    weight = 3,  wanderRange = 3, aggroRange = 11 },
			{ name = "Pipi Avocado",          weight = 1.5,wanderRange = 3, aggroRange = 11 },
			{ name = "Frogo Elfo",            weight = 0.5,wanderRange = 3, aggroRange = 11 },
		},
		spawnDensity = 0.005,
		leashRange   = 18,
	},
	{
		id          = "Swamp",
		name        = "Shadow Swamp",
		center      = { x = 20, z = 22 },      -- SE
		radius      = 25,
		noiseAmp    = 0.28,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(55, 80, 50),    -- dark moss
			secondary = Color3.fromRGB(45, 70, 42),
		},
		tileMaterial = Enum.Material.Mud,
		spawnEnemies = {
			{ name = "Cappuccino Assassino",  weight = 18, wanderRange = 3, aggroRange = 10 },
			{ name = "Brr Brr Patapim",       weight = 16, wanderRange = 3, aggroRange = 10 },
			{ name = "Trulimero Trulicina",   weight = 14, wanderRange = 3, aggroRange = 10 },
			{ name = "Bambini Crostini",       weight = 12, wanderRange = 3, aggroRange = 10 },
			{ name = "Bananita Dolphinita",   weight = 10, wanderRange = 3, aggroRange = 10 },
			{ name = "Perochello Lemonchello",weight = 8,  wanderRange = 3, aggroRange = 10 },
			{ name = "Brri Brri Bicus Dicus Bombicus", weight = 6, wanderRange = 3, aggroRange = 11 },
			{ name = "Avocadini Guffo",       weight = 5,  wanderRange = 3, aggroRange = 11 },
			{ name = "Salamino Penguino",     weight = 4,  wanderRange = 2, aggroRange = 11 },
			{ name = "Penguin Tree",          weight = 3,  wanderRange = 2, aggroRange = 11 },
			{ name = "Penguino Cocosino",     weight = 2,  wanderRange = 2, aggroRange = 12 },
			{ name = "Ti Ti Ti Sahur",        weight = 2,  wanderRange = 3, aggroRange = 11 },
		},
		spawnDensity = 0.004,
		leashRange   = 15,
	},
	{
		id          = "Volcano",
		name        = "Volcanic Wasteland",
		center      = { x = -22, z = 22 },     -- SW
		radius      = 28,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(50, 30, 25),    -- dark basalt
			secondary = Color3.fromRGB(60, 35, 28),
		},
		tileMaterial = Enum.Material.Slate,
		spawnEnemies = {
			{ name = "Burbaloni Loliloli",    weight = 14, wanderRange = 3, aggroRange = 10 },
			{ name = "Chimpazini Bananini",   weight = 12, wanderRange = 3, aggroRange = 10 },
			{ name = "Ballerina Cappuccina",  weight = 10, wanderRange = 3, aggroRange = 10 },
			{ name = "Chef Crabracadabra",    weight = 8,  wanderRange = 3, aggroRange = 10 },
			{ name = "Lionel Cactuseli",      weight = 7,  wanderRange = 3, aggroRange = 10 },
			{ name = "Glorbo Fruttodrillo",   weight = 6,  wanderRange = 3, aggroRange = 11 },
			{ name = "Blueberrini Octopusini",weight = 5,  wanderRange = 2, aggroRange = 11 },
			{ name = "Strawberelli Flamingelli", weight = 4, wanderRange = 2, aggroRange = 11 },
			{ name = "Pandaccini Bananini",   weight = 3,  wanderRange = 2, aggroRange = 12 },
			{ name = "Sigma Boy",             weight = 2,  wanderRange = 2, aggroRange = 12 },
			{ name = "Sigma Girl",            weight = 2,  wanderRange = 2, aggroRange = 12 },
			{ name = "Pi Pi Watermelon",      weight = 2,  wanderRange = 3, aggroRange = 11 },
			{ name = "Chocco Bunny",          weight = 1.5,wanderRange = 2, aggroRange = 12 },
			{ name = "Sealo Regalo",          weight = 1,  wanderRange = 2, aggroRange = 12 },
			{ name = "Cocosini Mama",         weight = 1,  wanderRange = 2, aggroRange = 12 },
			{ name = "Spioniro Golubiro",     weight = 0.5,wanderRange = 3, aggroRange = 10 },
		},
		spawnDensity = 0.003,
		leashRange   = 12,
	},
}

-- Lookup by id
ZoneData._byId = {}
for _, zone in ipairs(ZoneData.ZONES) do
	ZoneData._byId[zone.id] = zone
end

function ZoneData.GetZone(id: string)
	return ZoneData._byId[id]
end

-- Build a weighted spawn list for fast random picks
function ZoneData.BuildSpawnPool(zone)
	local pool = {}
	local totalWeight = 0
	for _, entry in ipairs(zone.spawnEnemies) do
		totalWeight += entry.weight
		table.insert(pool, { entry = entry, cumWeight = totalWeight })
	end
	return { pool = pool, totalWeight = totalWeight }
end

-- Pick a random enemy from a zone's spawn pool
function ZoneData.PickEnemy(zone, spawnPool)
	local roll = math.random() * spawnPool.totalWeight
	for _, item in ipairs(spawnPool.pool) do
		if roll <= item.cumWeight then
			return item.entry
		end
	end
	return spawnPool.pool[#spawnPool.pool].entry
end

return ZoneData
