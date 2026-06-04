-- ReplicatedStorage/Modules/Pathfinder.lua
-- Tile-based A* pathfinding with binary min-heap open set.
-- Usage:
--   local Pathfinder = require(...)
--   local path = Pathfinder.FindPath(isWalkableFn, startX, startZ, goalX, goalZ, maxNodes)
--   -- returns array of {tx, tz} steps from start→goal (exclusive of start), or nil if unreachable

local Pathfinder = {}

local function heuristic(ax, az, bx, bz)
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- Numeric key: safe for grids up to 2000×2000. No string allocation.
local GRID_W = 2000
local function nkey(x, z)
	return x * GRID_W + z
end

local NEIGHBOURS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

-- ─── Binary min-heap (f-score, then h as tiebreaker) ─────────────────────────
-- Stores { x, z, f, h } nodes. Heap[1] is always the lowest f.
local function heapInsert(heap, node)
	local i = #heap + 1
	heap[i] = node
	-- bubble up
	while i > 1 do
		local p = math.floor(i / 2)
		local a, b = heap[i], heap[p]
		if a.f < b.f or (a.f == b.f and a.h < b.h) then
			heap[i], heap[p] = heap[p], heap[i]
			i = p
		else
			break
		end
	end
end

local function heapPop(heap)
	local top = heap[1]
	local last = #heap
	heap[1] = heap[last]
	heap[last] = nil
	-- sink down
	local i = 1
	local n = #heap
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= n then
			local a, b = heap[l], heap[smallest]
			if a.f < b.f or (a.f == b.f and a.h < b.h) then
				smallest = l
			end
		end
		if r <= n then
			local a, b = heap[r], heap[smallest]
			if a.f < b.f or (a.f == b.f and a.h < b.h) then
				smallest = r
			end
		end
		if smallest ~= i then
			heap[i], heap[smallest] = heap[smallest], heap[i]
			i = smallest
		else
			break
		end
	end
	return top
end

-- Pre-allocated neighbour buffer to avoid per-call table creation.
-- Each entry: { nx, nz, h, towardGoal } — reused across calls.
local nbBuf = {
	{ nx=0, nz=0, h=0, towardGoal=0 },
	{ nx=0, nz=0, h=0, towardGoal=0 },
	{ nx=0, nz=0, h=0, towardGoal=0 },
	{ nx=0, nz=0, h=0, towardGoal=0 },
}

local function getNeighbours(cx, cz, goalX, goalZ)
	local count = 0
	for _, off in ipairs(NEIGHBOURS) do
		local nx, nz = cx + off[1], cz + off[2]
		count += 1
		local nb = nbBuf[count]
		nb.nx = nx
		nb.nz = nz
		nb.h = heuristic(nx, nz, goalX, goalZ)
		-- towardGoal: positive when this step moves closer on each axis
		local tg = 0
		if off[1] ~= 0 and (off[1] > 0) == (goalX > cx) then
			tg += math.abs(goalX - cx)
		end
		if off[2] ~= 0 and (off[2] > 0) == (goalZ > cz) then
			tg += math.abs(goalZ - cz)
		end
		nb.towardGoal = tg
	end
	return nbBuf, count
end

function Pathfinder.FindPath(
	isWalkable: (number, number) -> boolean,
	startX: number, startZ: number,
	goalX:  number, goalZ:  number,
	maxNodes: number?
): { {number} }

	maxNodes = maxNodes or 1200

	if startX == goalX and startZ == goalZ then return {} end

	local openSet  = {}   -- binary min-heap
	local cameFrom = {}   -- nkey → { px, pz }
	local gScore   = {}   -- nkey → number
	local inOpen   = {}   -- nkey → true
	local closed   = {}   -- nkey → true

	local sk = nkey(startX, startZ)
	gScore[sk] = 0

	heapInsert(openSet, {
		x = startX, z = startZ,
		f = heuristic(startX, startZ, goalX, goalZ),
		h = heuristic(startX, startZ, goalX, goalZ),
	})
	inOpen[sk] = true

	local expanded = 0

	while #openSet > 0 do
		local current = heapPop(openSet)
		local cx, cz  = current.x, current.z
		local ck      = nkey(cx, cz)
		inOpen[ck]    = nil

		-- Skip if already expanded (stale entry in heap)
		if closed[ck] then continue end
		closed[ck] = true
		expanded  += 1

		if cx == goalX and cz == goalZ then
			-- Path reconstruction
			local path    = {}
			local nodeX   = cx
			local nodeZ   = cz
			table.insert(path, { nodeX, nodeZ })
			local nodeKey = ck
			while cameFrom[nodeKey] do
				local parent = cameFrom[nodeKey]
				nodeX   = parent.px
				nodeZ   = parent.pz
				nodeKey = nkey(nodeX, nodeZ)
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

		-- Expand neighbours (reuses pre-allocated buffer)
		local nbs, nCount = getNeighbours(cx, cz, goalX, goalZ)
		for i = 1, nCount do
			local nb = nbs[i]
			local nx, nz = nb.nx, nb.nz
			local nk = nkey(nx, nz)

			if not closed[nk] and isWalkable(nx, nz) then
				local tentG = (gScore[ck] or math.huge) + 1
				if tentG < (gScore[nk] or math.huge) then
					cameFrom[nk] = { px = cx, pz = cz }
					gScore[nk]   = tentG
					if not inOpen[nk] then
						heapInsert(openSet, {
							x = nx, z = nz,
							f = tentG + nb.h,
							h = nb.h,
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
