-- ReplicatedStorage/Modules/Pathfinder.lua
-- Tile-based A* pathfinding.
-- Usage:
--   local Pathfinder = require(...)
--   local path = Pathfinder.FindPath(isWalkableFn, startX, startZ, goalX, goalZ, maxNodes)
--   -- returns array of {tx, tz} steps from start→goal (exclusive of start), or nil if unreachable
--
-- FIXES:
--   • Added proper closed set — nodes are never re-expanded, preventing wasted capacity
--     and potential incorrect paths from stale g-scores being re-opened.
--   • key() uses string concatenation instead of arithmetic to guarantee zero collisions
--     regardless of grid dimensions.
--   • orderedNeighbours tie-breaking cleaned up and made deterministic.

local Pathfinder = {}

local function heuristic(ax, az, bx, bz)
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- String key — zero collision risk at any grid size.
local function key(x, z)
	return x .. "_" .. z
end

local BASE_NEIGHBOURS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function orderedNeighbours(cx, cz, goalX, goalZ)
	local neighbours = {}
	for _, off in ipairs(BASE_NEIGHBOURS) do
		local nx, nz = cx + off[1], cz + off[2]
		local h = heuristic(nx, nz, goalX, goalZ)
		-- towardGoal: positive when this step moves closer on each axis
		local towardGoal = 0
		if off[1] ~= 0 then
			if (off[1] > 0) == (goalX > cx) then
				towardGoal = towardGoal + math.abs(goalX - cx)
			end
		end
		if off[2] ~= 0 then
			if (off[2] > 0) == (goalZ > cz) then
				towardGoal = towardGoal + math.abs(goalZ - cz)
			end
		end
		table.insert(neighbours, {
			dx = off[1], dz = off[2],
			h = h,
			towardGoal = towardGoal,
		})
	end

	table.sort(neighbours, function(a, b)
		if a.h ~= b.h then return a.h < b.h end
		if a.towardGoal ~= b.towardGoal then return a.towardGoal > b.towardGoal end
		if a.dz ~= b.dz then return a.dz < b.dz end
		return a.dx < b.dx
	end)

	return neighbours
end

function Pathfinder.FindPath(
	isWalkable: (number, number) -> boolean,
	startX: number, startZ: number,
	goalX:  number, goalZ:  number,
	maxNodes: number?
): { {number} }

	maxNodes = maxNodes or 800

	if startX == goalX and startZ == goalZ then return {} end

	local openSet  = {}
	local cameFrom = {}   -- key → { px, pz }
	local gScore   = {}
	local inOpen   = {}
	local closed   = {}   -- FIX: closed set prevents re-expansion of settled nodes

	local startKey = key(startX, startZ)
	gScore[startKey] = 0

	table.insert(openSet, {
		x = startX, z = startZ,
		f = heuristic(startX, startZ, goalX, goalZ),
		h = heuristic(startX, startZ, goalX, goalZ),
	})
	inOpen[startKey] = true

	local expanded = 0  -- FIX: count unique expansions, not total pops

	while #openSet > 0 do
		-- Pop node with lowest f (linear scan — acceptable for ≤800-node cap)
		local bestIdx = 1
		for i = 2, #openSet do
			if openSet[i].f < openSet[bestIdx].f
				or (openSet[i].f == openSet[bestIdx].f
					and openSet[i].h < openSet[bestIdx].h) then
				bestIdx = i
			end
		end

		local current = table.remove(openSet, bestIdx)
		local cx, cz  = current.x, current.z
		local ck      = key(cx, cz)
		inOpen[ck]    = nil

		-- FIX: skip if already expanded (a better path was found and this is stale)
		if closed[ck] then continue end
		closed[ck] = true
		expanded  += 1

		if cx == goalX and cz == goalZ then
			-- Single-pass path reconstruction
			local path    = {}
			local nodeX   = cx
			local nodeZ   = cz
			table.insert(path, { nodeX, nodeZ })
			local nodeKey = ck
			while cameFrom[nodeKey] do
				local parent = cameFrom[nodeKey]
				nodeX   = parent.px
				nodeZ   = parent.pz
				nodeKey = key(nodeX, nodeZ)
				if nodeX == startX and nodeZ == startZ then break end
				table.insert(path, { nodeX, nodeZ })
			end
			local lo, hi = 1, #path
			while lo < hi do
				path[lo], path[hi] = path[hi], path[lo]
				lo += 1
				hi -= 1
			end
			return path
		end

		if expanded >= maxNodes then
			return nil
		end

		for _, off in ipairs(orderedNeighbours(cx, cz, goalX, goalZ)) do
			local nx, nz = cx + off.dx, cz + off.dz
			local nk     = key(nx, nz)

			-- FIX: skip closed neighbours — their optimal path is already known
			if closed[nk] then continue end

			if isWalkable(nx, nz) then
				local tentG = (gScore[ck] or math.huge) + 1
				if tentG < (gScore[nk] or math.huge) then
					cameFrom[nk] = { px = cx, pz = cz }
					gScore[nk]   = tentG
					if not inOpen[nk] then
						local h = heuristic(nx, nz, goalX, goalZ)
						table.insert(openSet, {
							x = nx, z = nz,
							f = tentG + h,
							h = h,
						})
						inOpen[nk] = true
					end
				end
			end
		end
	end

	return nil
end

return Pathfinder