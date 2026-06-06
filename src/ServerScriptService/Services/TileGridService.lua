-- ServerScriptService/Services/TileGridService.lua
-- Dynamically generates the tile grid under Workspace > Map > TileGrid.
-- Zones are organic blobs assigned via Voronoi + fractal noise.
-- Town is a hard safe boundary around spawn; enemies cannot enter.
-- Includes: height variation, zone border blending, scattered decorations,
-- water pools, rocks, bushes, crystals, town furniture, ambient particles.

local Config    = require(game.ReplicatedStorage.Modules.Config)
local ZoneData  = require(game.ReplicatedStorage.Modules.ZoneData)

local TileGridService = {}

local tileGridFolder: Folder
local tileMap: { [number]: { [number]: BasePart } } = {}

local WATER_COLOR = Color3.fromRGB(60, 160, 240)  -- bright blue

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
		tile.Color = WATER_COLOR
		tile.Material = Enum.Material.Glass
		tile.Transparency = 0.25
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
local function assignZone(tx: number, tz: number, spawnX: number, spawnZ: number, zones)
	local dxSpawn = tx - spawnX
	local dzSpawn = tz - spawnZ
	local distFromSpawn = math.sqrt(dxSpawn * dxSpawn + dzSpawn * dzSpawn)

	-- Hard safe boundary: everything within TOWN_RADIUS is Town
	if distFromSpawn <= Config.TOWN_RADIUS then
		return "Town"
	end

	-- Voronoi with noise perturbation — zones are capped by maxRadius
	local bestZone = nil
	local bestScore = math.huge

	for _, zone in ipairs(zones) do
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local dx = tx - cx
		local dz = tz - cz
		local dist = math.sqrt(dx * dx + dz * dz)

		-- Hard cutoff: tile is outside this zone's maximum reach
		local maxR = zone.maxRadius or (zone.radius * 1.3)
		if dist > maxR + 2 then continue end

		-- Noise displaces the boundary: positive noise pulls tiles toward this zone
		local n = fractalNoise(tx * 0.08, tz * 0.08, 3) * zone.noiseAmp * zone.radius
		local score = dist - n

		if score < bestScore then
			bestScore = score
			bestZone = zone
		end
	end

	return bestZone and bestZone.id or nil
end

-- ─── Decorations ──────────────────────────────────────────────────────────────
local decorFolder: Folder

local ROCK_COLORS = {
	Color3.fromRGB(120, 115, 105),  -- warm stone
	Color3.fromRGB(100, 95, 85),    -- medium stone
	Color3.fromRGB(140, 130, 115),  -- light stone
}

local BUSH_COLORS = {
	Color3.fromRGB(70, 180, 60),    -- bright green
	Color3.fromRGB(60, 160, 50),    -- vivid green
	Color3.fromRGB(80, 200, 65),    -- lime green
}

local CRYSTAL_COLORS = {
	Color3.fromRGB(100, 200, 255),  -- bright cyan
	Color3.fromRGB(200, 100, 255),  -- vivid purple
	Color3.fromRGB(255, 100, 200),  -- hot pink
	Color3.fromRGB(100, 255, 200),  -- bright teal
}

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function scatterWater(spawnX, spawnZ, zones)
	for _, zone in ipairs(zones) do
		if zone.safe then continue end
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local poolCount = math.random(2, 3)
		for _ = 1, poolCount do
			local angle = math.random() * math.pi * 2
			local r = math.random(3, math.floor(zone.radius * 0.6))
			local sx = math.floor(cx + math.cos(angle) * r)
			local sz = math.floor(cz + math.sin(angle) * r)
			if not TileGridService.IsWalkable(sx, sz) then continue end
			if not (tileZoneMap[sx] and tileZoneMap[sx][sz] == zone.id) then continue end

			-- Flood-fill blob from seed
			local blobSize = math.random(5, 10)
			local filled = {}
			local queue = { {sx, sz} }
			filled[sx .. "," .. sz] = true

			while #queue > 0 and blobSize > 0 do
				local idx = math.random(1, #queue)
				local cur = queue[idx]
				table.remove(queue, idx)

				local tx, tz = cur[1], cur[2]
				TileGridService.SetTileType(tx, tz, "Water")
				blobSize -= 1

				local offsets = { {1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {-1,1}, {1,-1}, {-1,-1} }
				for _, off in ipairs(offsets) do
					local nx, nz = tx + off[1], tz + off[2]
					local key = nx .. "," .. nz
					if not filled[key] and math.random() < 0.6 then
						if TileGridService.IsWalkable(nx, nz)
							and tileZoneMap[nx] and tileZoneMap[nx][nz] == zone.id then
							filled[key] = true
							table.insert(queue, {nx, nz})
						end
					end
				end
			end
		end
	end
end

local function scatterRocks(spawnX, spawnZ, zones)
	for _, zone in ipairs(zones) do
		if zone.safe then continue end
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local blobCount = math.random(3, 5)
		for _ = 1, blobCount do
			local angle = math.random() * math.pi * 2
			local r = math.random(2, math.floor(zone.radius * 0.8))
			local sx = math.floor(cx + math.cos(angle) * r)
			local sz = math.floor(cz + math.sin(angle) * r)
			if not TileGridService.IsWalkable(sx, sz) then continue end
			if not (tileZoneMap[sx] and tileZoneMap[sx][sz] == zone.id) then continue end

			-- Flood-fill blob from seed
			local blobSize = math.random(4, 8)
			local filled = {}
			local queue = { {sx, sz} }
			filled[sx .. "," .. sz] = true

			while #queue > 0 and blobSize > 0 do
				local idx = math.random(1, #queue)
				local cur = queue[idx]
				table.remove(queue, idx)

				local tx, tz = cur[1], cur[2]
				TileGridService.SetTileWalkable(tx, tz, false)
				local tile = TileGridService.GetTile(tx, tz)
				if tile then
					tile.Color = ROCK_COLORS[math.random(1, #ROCK_COLORS)]
					tile.Material = Enum.Material.Slate
					tile:SetAttribute("TileType", "Rock")
				end
				blobSize -= 1

				local offsets = { {1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {-1,1}, {1,-1}, {-1,-1} }
				for _, off in ipairs(offsets) do
					local nx, nz = tx + off[1], tz + off[2]
					local key = nx .. "," .. nz
					if not filled[key] and math.random() < 0.5 then
						if TileGridService.IsWalkable(nx, nz)
							and tileZoneMap[nx] and tileZoneMap[nx][nz] == zone.id then
							filled[key] = true
							table.insert(queue, {nx, nz})
						end
					end
				end
			end
		end
	end
end

local function scatterBushes(spawnX, spawnZ, zones)
	for _, zone in ipairs(zones) do
		if zone.safe then continue end
		if zone.id == "Volcano" then continue end
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local count = math.random(15, 30)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local r = math.random(1, math.floor(zone.radius * 0.85))
			local tx = math.floor(cx + math.cos(angle) * r)
			local tz = math.floor(cz + math.sin(angle) * r)
			if TileGridService.IsWalkable(tx, tz)
				and tileZoneMap[tx] and tileZoneMap[tx][tz] == zone.id then
				local worldPos = TileGridService.TileToWorld(tx, tz)
				local bush = Instance.new("Part")
				bush.Name = "Bush"
				bush.Shape = Enum.PartType.Ball
				local size = math.random(15, 30) / 10
				bush.Size = Vector3.new(size, size * 0.7, size)
				bush.Anchored = true
				bush.CanCollide = false
				bush.CastShadow = false
				bush.Color = BUSH_COLORS[math.random(1, #BUSH_COLORS)]
				bush.Material = Enum.Material.Grass
				bush.CFrame = CFrame.new(worldPos + Vector3.new(0, size * 0.25, 0))
				bush.Parent = decorFolder
			end
		end
	end
end

local function scatterCrystals(spawnX, spawnZ, zones)
	for _, zone in ipairs(zones) do
		if zone.safe then continue end
		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z
		local count = math.random(4, 10)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local r = math.random(2, math.floor(zone.radius * 0.7))
			local tx = math.floor(cx + math.cos(angle) * r)
			local tz = math.floor(cz + math.sin(angle) * r)
			if TileGridService.IsWalkable(tx, tz)
				and tileZoneMap[tx] and tileZoneMap[tx][tz] == zone.id then
				local worldPos = TileGridService.TileToWorld(tx, tz)
				local crystal = Instance.new("Part")
				crystal.Name = "Crystal"
				crystal.Shape = Enum.PartType.Cylinder
				local h = math.random(20, 40) / 10
				crystal.Size = Vector3.new(h, 0.6, 0.6)
				crystal.Anchored = true
				crystal.CanCollide = false
				crystal.CastShadow = false
				crystal.Color = CRYSTAL_COLORS[math.random(1, #CRYSTAL_COLORS)]
				crystal.Material = Enum.Material.Neon
				crystal.Transparency = 0.2
				crystal.CFrame = CFrame.new(worldPos + Vector3.new(0, h * 0.35, 0))
					* CFrame.Angles(0, math.random() * math.pi * 2, math.rad(math.random(-20, 20)))
				crystal.Parent = decorFolder
			end
		end
	end
end



local ZONE_PARTICLE_CONFIG = {
	Grasslands = {
		color = Color3.fromRGB(140, 220, 80),  -- bright lime petals
		rate = 6,
		lifetime = NumberRange.new(3, 6),
		speed = NumberRange.new(0.5, 1.5),
		spread = Vector3.new(12, 0, 12),
	},
	Desert = {
		color = Color3.fromRGB(240, 210, 120),  -- golden sand dust
		rate = 10,
		lifetime = NumberRange.new(2, 5),
		speed = NumberRange.new(1, 3),
		spread = Vector3.new(14, 0, 14),
	},
	Swamp = {
		color = Color3.fromRGB(80, 200, 180),  -- teal mist
		rate = 8,
		lifetime = NumberRange.new(4, 8),
		speed = NumberRange.new(0.2, 0.8),
		spread = Vector3.new(10, 0, 10),
	},
	Volcano = {
		color = Color3.fromRGB(255, 80, 40),  -- bright ember
		rate = 12,
		lifetime = NumberRange.new(1, 3),
		speed = NumberRange.new(2, 5),
		spread = Vector3.new(8, 0, 8),
	},
}

local function spawnZoneParticles(spawnX, spawnZ, zones)
	for _, zone in ipairs(zones) do
		if zone.safe then continue end
		local cfg = ZONE_PARTICLE_CONFIG[zone.id]
		if not cfg then continue end

		local cx = spawnX + zone.center.x
		local cz = spawnZ + zone.center.z

		for _ = 1, 6 do
			local ox = (math.random() - 0.5) * cfg.spread.X * 2
			local oz = (math.random() - 0.5) * cfg.spread.Z * 2
			local worldX = (cx + ox - 0.5) * Config.TILE_SIZE
			local worldZ = (cz + oz - 0.5) * Config.TILE_SIZE

			local anchor = Instance.new("Part")
			anchor.Name = "ParticleAnchor"
			anchor.Size = Vector3.new(1, 1, 1)
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.Transparency = 1
			anchor.Position = Vector3.new(worldX, 2, worldZ)
			anchor.Parent = decorFolder

			local attach = Instance.new("Attachment")
			attach.Parent = anchor

			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(cfg.color)
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.7, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Lifetime = cfg.lifetime
			emitter.Rate = cfg.rate
			emitter.Speed = cfg.speed
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.RotSpeed = NumberRange.new(-30, 30)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.LightEmission = zone.id == "Volcano" and 0.6 or 0.1
			emitter.LightInfluence = zone.id == "Volcano" and 0.3 or 0.8
			emitter.Parent = attach
		end
	end
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

	decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decorations"
	decorFolder.Parent = map

	local tileSize  = Config.TILE_SIZE
	local tileThick = Config.TILE_HEIGHT
	local gw        = Config.GRID_WIDTH
	local gh        = Config.GRID_HEIGHT
	local zones     = ZoneData.ZONES

	local VOID_COLOR    = Color3.fromRGB(45, 42, 55)  -- soft dark purple
	local VOID_MATERIAL = Enum.Material.Slate

	local tileCount = 0

	-- Height noise for terrain variation
	local heightSeed = noiseSeed + 1000

	for tx = 1, gw do
		tileMap[tx] = {}
		tileZoneMap[tx] = {}
		for tz = 1, gh do
			local zoneId = assignZone(tx, tz, SPAWN_TX, SPAWN_TZ, zones)
			local zone = ZoneData.GetZone(zoneId)

			tileZoneMap[tx][tz] = zoneId

			local part = Instance.new("Part")
			part.Name         = string.format("Tile_%d_%d", tx, tz)
			part.Size         = Vector3.new(tileSize, tileThick, tileSize)
			part.Anchored     = true
			part.CanCollide   = true
			part.CastShadow   = false

			if zone then
				part:SetAttribute("TileType", zone.id)
				part:SetAttribute("Zone",     zone.id)
				part:SetAttribute("Safe",     zone.safe)
				part:SetAttribute("Walkable", true)
				part.Material = zone.tileMaterial or Enum.Material.SmoothPlastic

				-- Height variation: slight random Y offset for bumpy terrain
				local heightNoise = fractalNoise(tx * 0.15 + heightSeed, tz * 0.15, 2)
				local yOffset = (heightNoise - 0.5) * 0.3
				part.CFrame = CFrame.new(
					(tx - 0.5) * tileSize,
					tileThick / 2 + yOffset,
					(tz - 0.5) * tileSize
				)

				-- Zone border blending: check if any neighbour is a different zone
				local borderBlend = false
				for _, off in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
					local nx, nz = tx + off[1], tz + off[2]
					if nx >= 1 and nx <= gw and nz >= 1 and nz <= gh then
						local nZone = tileZoneMap[nx] and tileZoneMap[nx][nz]
						if nZone and nZone ~= zoneId then
							borderBlend = true
							break
						end
					end
				end

				if borderBlend then
					-- Blend toward a neutral midpoint
					local neutralColor = Color3.fromRGB(180, 170, 150)  -- warm light neutral
					part.Color = lerpColor(zone.tileColors.primary, neutralColor, 0.4)
					part.Material = Enum.Material.SmoothPlastic
				else
					-- Checkerboard within zone colours
					if (tx + tz) % 2 == 0 then
						part.Color = zone.tileColors.primary
					else
						part.Color = zone.tileColors.secondary
					end
				end
			else
				part:SetAttribute("TileType", "Void")
				part:SetAttribute("Walkable", false)
				part.CFrame  = CFrame.new(
					(tx - 0.5) * tileSize,
					tileThick / 2 - 0.1,
					(tz - 0.5) * tileSize
				)
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

	-- Scatter non-walkable features (water, rocks)
	scatterWater(SPAWN_TX, SPAWN_TZ, zones)
	scatterRocks(SPAWN_TX, SPAWN_TZ, zones)

	-- Scatter walkable decorations (bushes, crystals)
	scatterBushes(SPAWN_TX, SPAWN_TZ, zones)
	scatterCrystals(SPAWN_TX, SPAWN_TZ, zones)

	-- Ambient particles per zone
	spawnZoneParticles(SPAWN_TX, SPAWN_TZ, zones)

	print(string.format("[TileGrid] Generated %d × %d grid — %d tiles, Town radius %d",
		gw, gh, tileCount, Config.TOWN_RADIUS))
end

-- ─── Init ─────────────────────────────────────────────────────────────────────
TileGridService.Generate()

return TileGridService
