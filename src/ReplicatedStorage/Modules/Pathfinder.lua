-- ReplicatedStorage/Modules/Pathfinder.lua
-- Tile-based A* pathfinding.
-- Usage:
--   local Pathfinder = require(...)
--   local path = Pathfinder.FindPath(isWalkableFn, startX, startZ, goalX, goalZ, maxNodes)
--   -- returns array of {tx, tz} steps from start→goal (exclusive of start), or nil if unreachable

local Pathfinder = {}

local function heuristic(ax, az, bx, bz)
	return math.abs(ax - bx) + math.abs(az - bz)
end

local BASE_NEIGHBOURS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function orderedNeighbours(cx, cz, goalX, goalZ)
	local neighbours = {}
	local remainingX = math.abs(goalX - cx)
	local remainingZ = math.abs(goalZ - cz)

	for _, off in ipairs(BASE_NEIGHBOURS) do
		local nx, nz = cx + off[1], cz + off[2]
		local h = heuristic(nx, nz, goalX, goalZ)
		-- towardGoal: does this move reduce the dominant remaining distance?
		local towardGoal = 0
		if off[1] ~= 0 and remainingX > 0 then
			-- Horizontal move: toward goal if in the right direction
			local correctDir = (off[1] > 0) == (goalX > cx)
			if correctDir then towardGoal = towardGoal + remainingX end
		end
		if off[2] ~= 0 and remainingZ > 0 then
			-- Vertical move: toward goal if in the right direction
			local correctDir = (off[2] > 0) == (goalZ > cz)
			if correctDir then towardGoal = towardGoal + remainingZ end
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

	local function key(x, z) return x * 100000 + z end

	local openSet  = {}
	local cameFrom = {}   -- key → { px, pz }  (parent tile coords)
	local gScore   = {}
	local inOpen   = {}

	local startKey = key(startX, startZ)
	gScore[startKey] = 0

	table.insert(openSet, {
		x = startX, z = startZ,
		f = heuristic(startX, startZ, goalX, goalZ),
		h = heuristic(startX, startZ, goalX, goalZ),
	})
	inOpen[startKey] = true

	local visited = 0

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

		local current  = table.remove(openSet, bestIdx)
		local cx, cz   = current.x, current.z
		local ck       = key(cx, cz)
		inOpen[ck]     = nil
		visited       += 1

		if cx == goalX and cz == goalZ then
			-- ── Single-pass reconstruction ──────────────────────────────
			-- Walk cameFrom chain from goal back to start, then reverse.
			local path  = {}
			local nodeX = cx
			local nodeZ = cz
			-- Always include goal
			table.insert(path, { nodeX, nodeZ })
			local nodeKey = ck
			while cameFrom[nodeKey] do
				local parent = cameFrom[nodeKey]
				nodeX = parent.px
				nodeZ = parent.pz
				nodeKey = key(nodeX, nodeZ)
				-- Stop before re-inserting the start node
				if nodeX == startX and nodeZ == startZ then break end
				table.insert(path, { nodeX, nodeZ })
			end
			-- Reverse so path goes start→goal (start excluded, goal included)
			local lo, hi = 1, #path
			while lo < hi do
				path[lo], path[hi] = path[hi], path[lo]
				lo += 1
				hi -= 1
			end
			return path
		end

		if visited >= maxNodes then
			return nil
		end

		for _, off in ipairs(orderedNeighbours(cx, cz, goalX, goalZ)) do
			local nx, nz = cx + off.dx, cz + off.dz
			if isWalkable(nx, nz) then
				local nk     = key(nx, nz)
				local tentG  = (gScore[ck] or math.huge) + 1
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
