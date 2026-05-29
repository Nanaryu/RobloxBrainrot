-- ServerScriptService/Services/TileGridService.lua
-- Dynamically generates the tile grid under Workspace > Map > TileGrid.
-- Other systems read TileGrid to resolve world positions ↔ tile coordinates.

local Config = require(game.ReplicatedStorage.Modules.Config)

local TileGridService = {}

-- Reference to the folder that will hold all tile parts
local tileGridFolder: Folder

-- 2-D array [x][z] → Part (so pathfinding can look up parts by coord)
local tileMap: { [number]: { [number]: BasePart } } = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- World position of the centre of tile (tx, tz)  (Y is ground level)
function TileGridService.TileToWorld(tx: number, tz: number): Vector3
	local x = (tx - 0.5) * Config.TILE_SIZE
	local z = (tz - 0.5) * Config.TILE_SIZE
	return Vector3.new(x, Config.TILE_HEIGHT / 2, z)
end

-- Nearest tile coordinate from a world position
function TileGridService.WorldToTile(pos: Vector3): (number, number)
	local tx = math.floor(pos.X / Config.TILE_SIZE) + 1
	local tz = math.floor(pos.Z / Config.TILE_SIZE) + 1
	tx = math.clamp(tx, 1, Config.GRID_WIDTH)
	tz = math.clamp(tz, 1, Config.GRID_HEIGHT)
	return tx, tz
end

-- Returns the Part for a given tile, or nil if out of bounds
function TileGridService.GetTile(tx: number, tz: number): BasePart?
	if tileMap[tx] then
		return tileMap[tx][tz]
	end
	return nil
end

-- Returns true if the tile exists (is walkable)
function TileGridService.IsWalkable(tx: number, tz: number): boolean
	return TileGridService.GetTile(tx, tz) ~= nil
end

-- ─── Neighbour Lookup (for pathfinding) ───────────────────────────────────────
-- Returns array of {tx, tz} for the 4 cardinal neighbours that are walkable.
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

-- ─── Generation ───────────────────────────────────────────────────────────────

local TILE_COLOR   = Color3.fromRGB( 80, 120,  60)  -- grass-ish base
local TILE_COLOR_B = Color3.fromRGB( 70, 110,  55)  -- checkerboard alt
local TILE_MATERIAL = Enum.Material.SmoothPlastic

function TileGridService.Generate()
	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Clear any existing grid
	local existing = map:FindFirstChild("TileGrid")
	if existing then existing:Destroy() end

	tileGridFolder = Instance.new("Folder")
	tileGridFolder.Name = "TileGrid"
	tileGridFolder.Parent = map

	-- Use a Model so we can anchor all tiles at once and keep Explorer tidy
	local gridModel = Instance.new("Model")
	gridModel.Name = "Tiles"
	gridModel.Parent = tileGridFolder

	local tileSize  = Config.TILE_SIZE
	local tileThick = Config.TILE_HEIGHT
	local gw        = Config.GRID_WIDTH
	local gh        = Config.GRID_HEIGHT

	for tx = 1, gw do
		tileMap[tx] = {}
		for tz = 1, gh do
			local part = Instance.new("Part")
			part.Name         = string.format("Tile_%d_%d", tx, tz)
			part.Size         = Vector3.new(tileSize, tileThick, tileSize)
			part.CFrame       = CFrame.new(TileGridService.TileToWorld(tx, tz))
			part.Anchored     = true
			part.CanCollide   = true
			-- Subtle checkerboard to give the pixelated feel
			part.Color        = ((tx + tz) % 2 == 0) and TILE_COLOR or TILE_COLOR_B
			part.Material     = TILE_MATERIAL
			part.CastShadow   = false   -- performance
			part.Parent       = gridModel

			-- Tag for CollectionService if needed later
			-- CollectionService:AddTag(part, "Tile")

			tileMap[tx][tz] = part
		end
	end

	print(string.format("[TileGrid] Generated %d × %d grid (%d tiles)",
		gw, gh, gw * gh))
end

-- ─── Init ─────────────────────────────────────────────────────────────────────
TileGridService.Generate()

return TileGridService