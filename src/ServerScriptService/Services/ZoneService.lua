-- ServerScriptService/Services/ZoneService.lua
-- Zone lookup and safe-zone checks. Reads from TileGridService zone data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config   = require(ReplicatedStorage.Modules.Config)
local ZoneData = require(ReplicatedStorage.Modules.ZoneData)
local TileGrid

local ZoneService = {}

local function ensureTileGrid()
	if not TileGrid then
		TileGrid = require(script.Parent.TileGridService)
	end
end

-- Returns the zone table from ZoneData for the tile at (tx, tz).
function ZoneService.GetZoneAt(tx: number, tz: number)
	ensureTileGrid()
	local zoneId = TileGrid.GetZone(tx, tz)
	if zoneId then
		return ZoneData.GetZone(zoneId)
	end
	return nil
end

-- Pick a random walkable tile inside a zone using blob geometry.
function ZoneService.GetRandomTileInZone(zoneId: string, attempts: number?): (number?, number?)
	ensureTileGrid()
	local zone = ZoneData.GetZone(zoneId)
	if not zone then return nil, nil end

	attempts = attempts or 300
	local spawnX = math.floor(Config.GRID_WIDTH  / 2)
	local spawnZ = math.floor(Config.GRID_HEIGHT / 2)
	local cx = spawnX + zone.center.x
	local cz = spawnZ + zone.center.z

	for _ = 1, attempts do
		-- Random angle + random radius within the zone's base radius
		local angle = math.random() * math.pi * 2
		local r = math.random(0, math.floor(zone.radius * 0.9))
		local tx = math.floor(cx + math.cos(angle) * r)
		local tz = math.floor(cz + math.sin(angle) * r)

		if TileGrid.IsWalkable(tx, tz) then
			local tileZone = TileGrid.GetZone(tx, tz)
			if tileZone == zoneId then
				return tx, tz
			end
		end
	end

	-- Fallback: scan a bounding box around the zone centre
	local boxR = zone.radius + 10
	for tx = math.max(1, cx - boxR), math.min(Config.GRID_WIDTH, cx + boxR) do
		for tz = math.max(1, cz - boxR), math.min(Config.GRID_HEIGHT, cz + boxR) do
			if TileGrid.IsWalkable(tx, tz) and TileGrid.GetZone(tx, tz) == zoneId then
				return tx, tz
			end
		end
	end

	return nil, nil
end

print("[ZoneService] Ready.")
return ZoneService
