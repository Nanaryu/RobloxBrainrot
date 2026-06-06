-- ReplicatedStorage/Modules/ZoneData.lua
-- Zone definitions for the map. Each zone is an organic blob defined by a
-- centre offset (from grid centre) + base radius + noise amplitude.
-- TileGridService uses Voronoi + noise to assign to assign tiles to zones.
-- Zones are compact: 10-12 tile radii, centers 12-13 tiles from spawn.
-- Spawn enemies are pulled dynamically from EnemyData.spawnZones.

local ZoneData = {}
local EnemyData = require(script.Parent.EnemyData)

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
			primary   = Color3.fromRGB(240, 210, 120),  -- warm golden town
			secondary = Color3.fromRGB(220, 195, 110),
		},
		tileMaterial = Enum.Material.SmoothPlastic,
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
			primary   = Color3.fromRGB(100, 200, 70),   -- vivid green
			secondary = Color3.fromRGB(85, 185, 60),
		},
		tileMaterial = Enum.Material.Grass,
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
			primary   = Color3.fromRGB(230, 190, 100), -- bright golden sand
			secondary = Color3.fromRGB(210, 175, 90),
		},
		tileMaterial = Enum.Material.Sand,
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
			primary   = Color3.fromRGB(50, 160, 140),    -- vibrant teal
			secondary = Color3.fromRGB(40, 140, 125),
		},
		tileMaterial = Enum.Material.Mud,
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
			primary   = Color3.fromRGB(200, 60, 50),    -- bright volcanic red
			secondary = Color3.fromRGB(180, 50, 45),
		},
		tileMaterial = Enum.Material.Slate,
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

-- Returns true if the zone has at least one enemy defined in EnemyData
function ZoneData.HasSpawns(zone)
	if zone.safe then return false end
	for _, data in pairs(EnemyData) do
		if data.spawnZones and data.spawnZones[zone.id] then
			return true
		end
	end
	return false
end

-- Build a weighted spawn list for fast random picks
-- Dynamically queries EnemyData for enemies that list this zone in spawnZones
function ZoneData.BuildSpawnPool(zone)
	local pool = {}
	local totalWeight = 0
	for name, data in pairs(EnemyData) do
		if data.spawnZones then
			local weight = data.spawnZones[zone.id]
			if weight and weight > 0 then
				totalWeight += weight
				table.insert(pool, {
					entry = {
						name        = name,
						wanderRange = data.wanderRange or 3,
						aggroRange  = data.aggroRange or 5,
					},
					cumWeight = totalWeight,
				})
			end
		end
	end
	return { pool = pool, totalWeight = totalWeight }
end

-- Pick a random enemy from a zone's spawn pool
function ZoneData.PickEnemy(zone, spawnPool)
	if spawnPool.totalWeight <= 0 then return nil end
	local roll = math.random() * spawnPool.totalWeight
	for _, item in ipairs(spawnPool.pool) do
		if roll <= item.cumWeight then
			return item.entry
		end
	end
	return spawnPool.pool[#spawnPool.pool].entry
end

return ZoneData
