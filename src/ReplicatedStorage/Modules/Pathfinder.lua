-- ReplicatedStorage/Modules/Pathfinder.lua
-- Tile-based A* pathfinding.
-- Usage:
--   local Pathfinder = require(...)
--   local path = Pathfinder.FindPath(isWalkableFn, startX, startZ, goalX, goalZ, maxNodes)
--   -- returns array of {tx, tz} steps from start→goal (exclusive of start), or nil if unreachable

local Pathfinder = {}

-- isWalkable(tx, tz) → bool  — injected so this module stays pure (no service deps)
-- maxNodes caps search size to prevent server freezes on huge grids

local function heuristic(ax, az, bx, bz)
	-- Manhattan distance (no diagonals)
	return math.abs(ax - bx) + math.abs(az - bz)
end

local BASE_NEIGHBOURS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function orderedNeighbours(cx, cz, goalX, goalZ)
	local neighbours = {}
	local remainingX = math.abs(goalX - cx)
	local remainingZ = math.abs(goalZ - cz)

	for _, off in ipairs(BASE_NEIGHBOURS) do
		local nx, nz = cx + off[1], cz + off[2]
		local axisNeed = (off[1] ~= 0) and remainingX or remainingZ
		local balanceNeed = (off[1] ~= 0) and remainingZ or remainingX
		table.insert(neighbours, {
			dx = off[1],
			dz = off[2],
			h = heuristic(nx, nz, goalX, goalZ),
			axisNeed = axisNeed,
			balanceNeed = balanceNeed,
		})
	end

	table.sort(neighbours, function(a, b)
		if a.h ~= b.h then return a.h < b.h end
		if a.axisNeed ~= b.axisNeed then return a.axisNeed > b.axisNeed end
		if a.balanceNeed ~= b.balanceNeed then return a.balanceNeed < b.balanceNeed end
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

	maxNodes = maxNodes or 400

	if startX == goalX and startZ == goalZ then return {} end

	-- Node key helper
	local function key(x, z) return x * 10000 + z end

	local openSet   = {}   -- min-heap (we use a simple sorted insert for now)
	local cameFrom  = {}   -- key → {px, pz}
	local gScore    = {}   -- key → number
	local inOpen    = {}   -- key → bool

	local startKey  = key(startX, startZ)
	gScore[startKey] = 0

	table.insert(openSet, {
		x = startX, z = startZ,
		f = heuristic(startX, startZ, goalX, goalZ),
		h = heuristic(startX, startZ, goalX, goalZ),
	})
	inOpen[startKey] = true

	local visited = 0

	while #openSet > 0 do
		-- Pop node with lowest f  (linear scan — fine for tile RPG distances ≤ ~64)
		local bestIdx = 1
		for i = 2, #openSet do
			if openSet[i].f < openSet[bestIdx].f
				or (openSet[i].f == openSet[bestIdx].f and openSet[i].h < openSet[bestIdx].h) then
				bestIdx = i
			end
		end
		local current = table.remove(openSet, bestIdx)
		local cx, cz  = current.x, current.z
		local ck      = key(cx, cz)
		inOpen[ck]    = nil
		visited       = visited + 1

		if cx == goalX and cz == goalZ then
			-- Reconstruct path
			local path = {}
			local node = ck
			while cameFrom[node] do
				local p = cameFrom[node]
				table.insert(path, 1, { p.nx, p.nz })
				node = key(p.px, p.pz)
			end
			-- path currently holds parent coords; rebuild as forward steps
			-- Actually reconstruct properly:
			path = {}
			local trace = { x = cx, z = cz }
			while cameFrom[key(trace.x, trace.z)] do
				table.insert(path, 1, { trace.x, trace.z })
				local prev = cameFrom[key(trace.x, trace.z)]
				trace = { x = prev.px, z = prev.pz }
			end
			table.insert(path, 1, { trace.x, trace.z })
			-- Remove start node if it crept in
			if path[1][1] == startX and path[1][2] == startZ then
				table.remove(path, 1)
			end
			return path
		end

		if visited >= maxNodes then
			-- Too far / blocked — return nil
			return nil
		end

		for _, off in ipairs(orderedNeighbours(cx, cz, goalX, goalZ)) do
			local nx, nz = cx + off.dx, cz + off.dz
			if isWalkable(nx, nz) then
				local nk      = key(nx, nz)
				local tentG   = (gScore[ck] or math.huge) + 1
				if tentG < (gScore[nk] or math.huge) then
					cameFrom[nk] = { px = cx, pz = cz, nx = nx, nz = nz }
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

	return nil  -- no path found
end

return Pathfinder
