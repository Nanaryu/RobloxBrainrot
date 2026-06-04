-- ReplicatedStorage/Modules/ZoneData.lua
-- Zone definitions for the map. Each zone is an organic blob defined by a
-- centre offset (from grid centre) + base radius + noise amplitude.
-- TileGridService uses Voronoi + noise to assign to assign tiles to zones.
-- Zones are compact: 10-12 tile radii, centers 12-13 tiles from spawn.

local ZoneData = {}

-- Zone order matters for spawn pool only; assignment is geometry-based.
ZoneData.ZONES = {
	{
		id          = "Town",
		name        = "Brainrot Town",
		center      = { x = 0, z = 0 },       -- offset from grid centre
		radius      = 10,                       -- base radius in tiles
		maxRadius   = 12,                       -- hard cutoff — no tiles beyond this
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
		center      = { x = -13, z = -12 },    -- NW — just outside town
		radius      = 12,
		maxRadius   = 16,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(80, 120, 60),   -- grass green
			secondary = Color3.fromRGB(70, 110, 55),
		},
		tileMaterial = Enum.Material.Grass,
		spawnEnemies = {
			{ name = "Noobini Pizzanini",    weight = 30, wanderRange = 4, aggroRange = 5 },
			{ name = "Lirili Larila",        weight = 25, wanderRange = 4, aggroRange = 5 },
			{ name = "TIM Cheese",           weight = 18, wanderRange = 3, aggroRange = 5 },
			{ name = "FluriFlura",           weight = 12, wanderRange = 3, aggroRange = 5 },
			{ name = "Talpa Di Fero",        weight = 8,  wanderRange = 3, aggroRange = 5 },
			{ name = "Svinina Bombardino",   weight = 4,  wanderRange = 3, aggroRange = 5 },
			{ name = "Pipi Kiwi",            weight = 2,  wanderRange = 3, aggroRange = 5 },
			{ name = "Graipuss Medussi",    weight = 1,  wanderRange = 3, aggroRange = 5 },
		},
		spawnDensity = 0.012,
		leashRange   = 6,
	},
	{
		id          = "Desert",
		name        = "Scorched Desert",
		center      = { x = 13, z = -13 },     -- NE
		radius      = 11,
		maxRadius   = 15,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(194, 170, 110), -- sand
			secondary = Color3.fromRGB(180, 158, 100),
		},
		tileMaterial = Enum.Material.Sand,
		spawnEnemies = {
			{ name = "Pipi Corni",            weight = 20, wanderRange = 3, aggroRange = 5 },
			{ name = "Trippi Troppi",         weight = 20, wanderRange = 3, aggroRange = 5 },
			{ name = "Gangster Footera",      weight = 16, wanderRange = 3, aggroRange = 5 },
			{ name = "Bandito Bobritto",      weight = 14, wanderRange = 3, aggroRange = 5 },
			{ name = "Boneca Ambalabu",       weight = 12, wanderRange = 3, aggroRange = 5 },
			{ name = "Cacto Hipopotamo",      weight = 8,  wanderRange = 3, aggroRange = 5 },
			{ name = "Ta Ta Ta Ta Sahur",     weight = 5,  wanderRange = 3, aggroRange = 5 },
			{ name = "Tric Trac Baraboom",    weight = 3,  wanderRange = 3, aggroRange = 5 },
			{ name = "Pipi Avocado",          weight = 1.5,wanderRange = 3, aggroRange = 5 },
			{ name = "Bulbito Bandito Traktorito",            weight = 0.5,wanderRange = 3, aggroRange = 5 },
		},
		spawnDensity = 0.012,
		leashRange   = 6,
	},
	{
		id          = "Swamp",
		name        = "Shadow Swamp",
		center      = { x = 12, z = 13 },      -- SE
		radius      = 11,
		maxRadius   = 15,
		noiseAmp    = 0.28,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(55, 80, 50),    -- dark moss
			secondary = Color3.fromRGB(45, 70, 42),
		},
		tileMaterial = Enum.Material.Mud,
		spawnEnemies = {
			{ name = "Cappuccino Assassino",  weight = 18, wanderRange = 3, aggroRange = 5 },
			{ name = "Brr Brr Patapim",       weight = 16, wanderRange = 3, aggroRange = 5 },
			{ name = "Trulimero Trulicina",   weight = 14, wanderRange = 3, aggroRange = 5 },
			{ name = "Bambini Crostini",       weight = 12, wanderRange = 3, aggroRange = 5 },
			{ name = "Bananita Dolphinita",   weight = 10, wanderRange = 3, aggroRange = 5 },
			{ name = "Perochello Lemonchello",weight = 8,  wanderRange = 3, aggroRange = 5 },
			{ name = "Brri Brri Bicus Dicus Bombicus", weight = 6, wanderRange = 3, aggroRange = 5 },
			{ name = "Avocadini Guffo",       weight = 5,  wanderRange = 3, aggroRange = 5 },
			{ name = "Salamino Penguino",     weight = 4,  wanderRange = 2, aggroRange = 5 },
			{ name = "Antonio",          weight = 3,  wanderRange = 2, aggroRange = 5 },
			{ name = "Penguino Cocosino",     weight = 2,  wanderRange = 2, aggroRange = 5 },
			{ name = "Ti Ti Ti Sahur",        weight = 2,  wanderRange = 3, aggroRange = 5 },
		},
		spawnDensity = 0.012,
		leashRange   = 6,
	},
	{
		id          = "Volcano",
		name        = "Volcanic Wasteland",
		center      = { x = -13, z = 13 },     -- SW
		radius      = 12,
		maxRadius   = 16,
		noiseAmp    = 0.30,
		safe        = false,
		tileColors  = {
			primary   = Color3.fromRGB(50, 30, 25),    -- dark basalt
			secondary = Color3.fromRGB(60, 35, 28),
		},
		tileMaterial = Enum.Material.Slate,
		spawnEnemies = {
			{ name = "Burbaloni Loliloli",    weight = 14, wanderRange = 3, aggroRange = 5 },
			{ name = "Chimpanzini Bananini",   weight = 12, wanderRange = 3, aggroRange = 5 },
			{ name = "Ballerina Cappuccina",  weight = 10, wanderRange = 3, aggroRange = 5 },
			{ name = "Chef Crabracadabra",    weight = 8,  wanderRange = 3, aggroRange = 5 },
			{ name = "Lionel Cactuseli",      weight = 7,  wanderRange = 3, aggroRange = 5 },
			{ name = "Glorbo Fruttodrillo",   weight = 6,  wanderRange = 3, aggroRange = 5 },
			{ name = "Blueberrinni Octopusini",weight = 5,  wanderRange = 2, aggroRange = 5 },
			{ name = "Strawberrelli Flamingelli", weight = 4, wanderRange = 2, aggroRange = 5 },
			{ name = "Pandaccini Bananini",   weight = 3,  wanderRange = 2, aggroRange = 5 },
			{ name = "Sigma Boy",             weight = 2,  wanderRange = 2, aggroRange = 5 },
			{ name = "Sigma Girl",            weight = 2,  wanderRange = 2, aggroRange = 5 },
			{ name = "Pakrahmatmamat",      weight = 2,  wanderRange = 3, aggroRange = 5 },
			{ name = "Job Job Job Sahur",          weight = 1.5,wanderRange = 2, aggroRange = 5 },
			{ name = "Avocadini Antilopini",          weight = 1,  wanderRange = 2, aggroRange = 5 },
			{ name = "Crabbo Limonetta",         weight = 1,  wanderRange = 2, aggroRange = 5 },
			{ name = "Spioniro Golubiro",     weight = 0.5,wanderRange = 3, aggroRange = 5 },
		},
		spawnDensity = 0.012,
		leashRange   = 6,
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
