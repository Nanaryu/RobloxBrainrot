-- ServerScriptService/Services/TileGridService.lua
-- Dynamically generates the tile grid under Workspace > Map > TileGrid.
-- Zones are organic blobs assigned via Voronoi + fractal noise.
-- Town is a hard safe boundary around spawn; enemies cannot enter.

local Config    = require(game.ReplicatedStorage.Modules.Config)
local ZoneData  = require(game.ReplicatedStorage.Modules.ZoneData)

local TileGridService = {}

local tileGridFolder: Folder
local tileMap: { [number]: { [number]: BasePart } } = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

function TileGridService.TileToWorld(tx: number, tz: number): Vector3
	local x = (tx - 0.5) * Config.TILE_SIZE
	local z = (tz - 0.5) * Config.TILE_SIZE
	return Vector3.new(x, Config.TILE_HEIGHT / 2, z)
end

function TileGridService.WorldToTile(pos: Vector3): (number, number)
	local tx = math.floor(pos.X / Config.TILE_SIZE) + 1
	local tz = math.floor(pos.Z / Config.TILE_SIZE) + 1
	tx = math.clamp(tx, 1, Config.GRID_WIDTH)
	tz = math.clamp(tz, 1, Config.GRID_HEIGHT)
	return tx, tz
end

function TileGridService.GetTile(tx: number, tz: number)
	if tileMap[tx] then
		return tileMap[tx][tz]
	end
	return nil
end

function TileGridService.IsWalkable(tx: number, tz: number): boolean
	local tile = TileGridService.GetTile(tx, tz)
	if not tile then return false end
	return tile:GetAttribute("Walkable") ~= false
end

function TileGridService.SetTileWalkable(tx: number, tz: number, walkable: boolean)
	local tile = TileGridService.GetTile(tx, tz)
	if not tile then return false end
	tile:SetAttribute("Walkable", walkable)
	return true
end

function TileGridService.SetTileType(tx: number, tz: number, tileType: string)
	local tile = TileGridService.GetTile(tx, tz)
	if not tile then return false end
	tile:SetAttribute("TileType", tileType)
	tile:SetAttribute("Walkable", tileType ~= "Water")
	if tileType == "Water" then
		tile.Color = Color3.fromRGB(45, 105, 165)
		tile.Material = Enum.Material.SmoothPlastic
	end
	return true
end

-- ─── Zone lookup per tile ─────────────────────────────────────────────────────
local tileZoneMap: { [number]: { [number]: string } } = {}

function TileGridService.GetZone(tx: number, tz: number): string?
	if tileZoneMap[tx] then
		return tileZoneMap[tx][tz]
	end
	return nil
end

-- ─── Neighbour Lookup ─────────────────────────────────────────────────────────
function TileGridService.GetNeighbours(tx: number, tz: number): { { number } }
	local neighbours = {}
	local offsets = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	for _, off in ipairs(offsets) do
		local nx, nz = tx + off[1], tz + off[2]
		if TileGridService.IsWalkable(nx, nz) then
			table.insert(neighbours, { nx, nz })
		end
	end
	return neighbours
end

-- ─── Deterministic noise ──────────────────────────────────────────────────────
local noiseSeed = Config.MAP_NOISE_SEED or 42

local function hash(x: number, y: number): number
	local n = x * 374761393 + y * 668265263 + noiseSeed * 1274126177
	n = bit32.bxor(n, bit32.rshift(n, 13))
	n = n * 1274126177
	return (bit32.bxor(n, bit32.rshift(n, 16))) / 4294967296
end

local function smoothNoise(x: number, y: number): number
	local ix = math.floor(x)
	local iy = math.floor(y)
	local fx = x - ix
	local fy = y - iy
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)

	local v00 = hash(ix,     iy)
	local v10 = hash(ix + 1, iy)
	local v01 = hash(ix,     iy + 1)
	local v11 = hash(ix + 1, iy + 1)

	local a = v00 + (v10 - v00) * fx
	local b = v01 + (v11 - v01) * fx
	return a + (b - a) * fy
end

local function fractalNoise(x: number, y: number, octaves: number): number
	local value = 0
	local amplitude = 1
	local frequency = 1
	local totalAmp = 0
	for _ = 1, octaves do
		value += smoothNoise(x * frequency, y * frequency) * amplitude
		totalAmp += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return value / totalAmp
end

-- ─── Zone assignment via Voronoi + noise ──────────────────────────────────────
-- For each tile: score = dist(tile, zoneCenter) - noise * noiseAmp * radius
-- Lowest score wins. Town gets a hard cutoff at TOWN_RADIUS.
local function assignZone(tx: number, tz: number, spawnX: number, spawnZ: number, zones)
	local dxSpawn = tx - spawnX
	local dzSpawn = tz - spawnZ
	local distFromSpawn = math.sqrt(dxSpawn * dxSpawn + dzSpawn * dzSpawn)

	-- Hard safe boundary: everything within TOWN_RADIUS is Town
	if distFromSpawn <= Config.TOWN_RADIUS then
		return "Town"
	end

	-- Voronoi with noise perturbation
	local bestZone = nil
	local bestScore = math.huge

	for _, zone in ipairs(zones) do
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local dx = tx - cx
		local dz = tz - cz
		local dist = math.sqrt(dx * dx + dz * dz)

		-- Noise displaces the boundary: positive noise pulls tiles toward this zone
		local n = fractalNoise(tx * 0.08, tz * 0.08, 3) * zone.noiseAmp * zone.radius
		local score = dist - n

		if score < bestScore then
			bestScore = score
			bestZone = zone
		end
	end

	return bestZone and bestZone.id or "Grasslands"
end

-- ─── Generation ───────────────────────────────────────────────────────────────

local SPAWN_TX = math.floor(Config.GRID_WIDTH  / 2)
local SPAWN_TZ = math.floor(Config.GRID_HEIGHT / 2)

function TileGridService.GetSpawnTile()
	return SPAWN_TX, SPAWN_TZ
end

function TileGridService.Generate()
	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	local existing = map:FindFirstChild("TileGrid")
	if existing then existing:Destroy() end

	tileGridFolder = Instance.new("Folder")
	tileGridFolder.Name = "TileGrid"
	tileGridFolder.Parent = map

	local gridModel = Instance.new("Model")
	gridModel.Name = "Tiles"
	gridModel.Parent = tileGridFolder

	local tileSize  = Config.TILE_SIZE
	local tileThick = Config.TILE_HEIGHT
	local gw        = Config.GRID_WIDTH
	local gh        = Config.GRID_HEIGHT
	local zones     = ZoneData.ZONES

	-- Void tile colour (outside map boundary — none for now, all tiles are assigned)
	local VOID_COLOR    = Color3.fromRGB(30, 30, 35)
	local VOID_MATERIAL = Enum.Material.Slate

	local tileCount = 0

	for tx = 1, gw do
		tileMap[tx] = {}
		tileZoneMap[tx] = {}
		for tz = 1, gh do
			-- Assign zone via Voronoi + noise
			local zoneId = assignZone(tx, tz, SPAWN_TX, SPAWN_TZ, zones)
			local zone = ZoneData.GetZone(zoneId)

			tileZoneMap[tx][tz] = zoneId

			local part = Instance.new("Part")
			part.Name         = string.format("Tile_%d_%d", tx, tz)
			part.Size         = Vector3.new(tileSize, tileThick, tileSize)
			part.CFrame       = CFrame.new(TileGridService.TileToWorld(tx, tz))
			part.Anchored     = true
			part.CanCollide   = true
			part.CastShadow   = false

			if zone then
				part:SetAttribute("TileType", zone.id)
				part:SetAttribute("Zone",     zone.id)
				part:SetAttribute("Safe",     zone.safe)
				part:SetAttribute("Walkable", true)
				part.Material = zone.tileMaterial or Enum.Material.SmoothPlastic

				-- Checkerboard within zone colours
				if (tx + tz) % 2 == 0 then
					part.Color = zone.tileColors.primary
				else
					part.Color = zone.tileColors.secondary
				end
			else
				part:SetAttribute("TileType", "Void")
				part:SetAttribute("Walkable", false)
				part.Color    = VOID_COLOR
				part.Material = VOID_MATERIAL
			end

			part.Parent = gridModel
			tileMap[tx][tz] = part
			tileCount += 1
		end
	end

	-- Golden spawn tile
	local spawnTile = tileMap[SPAWN_TX] and tileMap[SPAWN_TX][SPAWN_TZ]
	if spawnTile then
		spawnTile.Color = Color3.fromRGB(220, 200, 80)
		spawnTile:SetAttribute("Safe", true)
	end

	print(string.format("[TileGrid] Generated %d × %d grid — %d tiles, Town radius %d",
		gw, gh, tileCount, Config.TOWN_RADIUS))
end

-- ─── Init ─────────────────────────────────────────────────────────────────────
TileGridService.Generate()

return TileGridService
