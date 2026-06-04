-- ServerScriptService/Services/EnemyService.lua
-- Manages all enemy lifecycle: spawn, wander, chase player, attack, die, drop loot.
-- Defense formula (Rucoy): final_damage = max(1, enemy_damage - DEF_Level)
--
-- FIXES IN THIS REVISION:
--   • Enemy facing: tweenModelPivot for the face-toward-player turn during the
--     "attack" state was spawned in a detached task.spawn, meaning the facing
--     tween ran concurrently with task.wait(ENEMY_ATTACK_INTERVAL). Now the
--     turn is done inline (no spawn) so the enemy reliably faces the player
--     before swinging.
--   • Stale dist in chase/attack: the outer `dist` from getClosestPlayerTile
--     at the top of the while loop was reused inside the "chase" and "attack"
--     branches after moveEnemyToTile may have advanced the enemy. Both branches
--     now call getClosestPlayerTile again from the current tile (cx2/cz2) so
--     the leash, aggro-drop, and attack-range checks are never stale. This was
--     also causing the "running away" bug: a stale dist > aggroRange * 1.5
--     (from the top of the loop, before the enemy moved closer) triggered a
--     wander transition even though the enemy was right next to the player.
--   • Isolated-tile spawn guard: before accepting a spawn tile, the code now
--     attempts a short A* path (maxNodes=150) from that tile to the zone
--     centre. If no path exists the tile is rejected. This prevents enemies
--     from spawning on isolated walkable patches (e.g. the small island in a
--     water pool) where they could never reach a player.
--   • _Kill: MovingToTileX/Z nil-check (from previous revision) preserved.
--   • processDamageAccumulator: snapshot pattern (from previous revision) preserved.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Modules.Config)
local EnemyData   = require(ReplicatedStorage.Modules.EnemyData)
local Pathfinder  = require(ReplicatedStorage.Modules.Pathfinder)
local ZoneData    = require(ReplicatedStorage.Modules.ZoneData)
local TileGrid    = require(script.Parent.TileGridService)

local MovementService
local SkillService
local LootService
local LeaderboardService

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")

local EnemyService = {}

-- ─── Internal state ───────────────────────────────────────────────────────────
local enemies      = {}
local enemyThreads = {}
local enemyFolder

local pendingDamage = {}
local DAMAGE_TICK   = 0.5

local occupiedTiles = {}

local function occupyTile(tx, tz, id)
	occupiedTiles[tx .. "_" .. tz] = id
end
local function releaseTile(tx, tz, id)
	local k = tx .. "_" .. tz
	if occupiedTiles[k] == id then
		occupiedTiles[k] = nil
	end
end
local function isTileOccupied(tx, tz)
	return occupiedTiles[tx .. "_" .. tz] ~= nil
end
local function isTileOccupiedByOther(tx, tz, id)
	local occupant = occupiedTiles[tx .. "_" .. tz]
	return occupant ~= nil and occupant ~= id
end
local function isModelBlockingTile(model: Model, tx: number, tz: number): boolean
	if model:GetAttribute("State") == "dead" then return false end
	local currentX = model:GetAttribute("CurrentTileX")
	local currentZ = model:GetAttribute("CurrentTileZ")
	local movingX  = model:GetAttribute("MovingToTileX")
	local movingZ  = model:GetAttribute("MovingToTileZ")
	return (currentX == tx and currentZ == tz) or (movingX == tx and movingZ == tz)
end
local function isPlayerTileOccupied(tx, tz)
	if not MovementService then
		MovementService = require(script.Parent.MovementService)
	end
	return MovementService.IsPlayerTileOccupied(tx, tz)
end
local function isPassable(tx, tz)
	return TileGrid.IsWalkable(tx, tz)
		and not isTileOccupied(tx, tz)
		and not isPlayerTileOccupied(tx, tz)
end
local function isPassableForEnemy(tx, tz, id)
	if not TileGrid.IsWalkable(tx, tz) then return false end
	if isPlayerTileOccupied(tx, tz) then return false end
	local zone = TileGrid.GetZone(tx, tz)
	if zone == "Town" then return false end
	local occupant = occupiedTiles[tx .. "_" .. tz]
	return occupant == nil or occupant == id
end

-- ─── Tween config ─────────────────────────────────────────────────────────────
local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)
local TURN_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getEnemyTweenTime(tier: number): number
	local t = math.clamp(tier or 1, 1, 8)
	return Config.ENEMY_SPEED_BASE + (Config.ENEMY_SPEED_MIN - Config.ENEMY_SPEED_BASE) * ((t - 1) / 7)
end

-- ─── Unique ID generator ──────────────────────────────────────────────────────
local nextId = 0
local function newId(): string
	nextId += 1
	return "E" .. nextId
end

-- ─── Tile helpers ─────────────────────────────────────────────────────────────
local function tileToWorld(tx, tz): Vector3
	return TileGrid.TileToWorld(tx, tz)
end

local function prepareModelParts(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored   = true
			inst.CanCollide = false
			inst.CanQuery   = true
		end
	end
end

local function groundModelOnTile(model: Model, tx: number, tz: number)
	local baseCF = CFrame.new(tileToWorld(tx, tz))
	local boundsCF, boundsSize = model:GetBoundingBox()
	local halfH = boundsSize.Y * 0.5
	local groundedCF = baseCF + Vector3.new(0, halfH, 0)
	model:PivotTo(groundedCF)
end

local function getTilePivotPosition(model: Model, tx: number, tz: number): Vector3
	return tileToWorld(tx, tz)
end

local function tweenModelPivot(model: Model, targetCF: CFrame, tweenInfo: TweenInfo)
	local pivotValue   = Instance.new("CFrameValue")
	pivotValue.Value   = model:GetPivot()
	local connection   = pivotValue.Changed:Connect(function(value)
		if model.Parent then model:PivotTo(value) end
	end)
	local tween = TweenService:Create(pivotValue, tweenInfo, { Value = targetCF })
	tween:Play()
	tween.Completed:Wait()
	connection:Disconnect()
	pivotValue:Destroy()
end

local function manhattan(ax, az, bx, bz): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- ─── Movement helper ──────────────────────────────────────────────────────────
local function moveEnemyToTile(model, tx, tz)
	if not model.PrimaryPart then return end
	local id    = model:GetAttribute("EnemyId")
	local fromX = model:GetAttribute("CurrentTileX")
	local fromZ = model:GetAttribute("CurrentTileZ")
	local dx    = tx - fromX
	local dz    = tz - fromZ

	if isTileOccupiedByOther(tx, tz, id) or isPlayerTileOccupied(tx, tz) then return end

	model:SetAttribute("MovingToTileX", tx)
	model:SetAttribute("MovingToTileZ", tz)
	releaseTile(fromX, fromZ, id)
	occupyTile(tx, tz, id)

	local targetPos = getTilePivotPosition(model, tx, tz)
	local targetCF
	if dx ~= 0 or dz ~= 0 then
		local pivotPos = model:GetPivot().Position
		model:PivotTo(CFrame.lookAt(pivotPos, pivotPos + Vector3.new(dx, 0, dz)))
		targetCF = CFrame.lookAt(targetPos, targetPos + Vector3.new(dx, 0, dz))
	else
		targetCF = CFrame.new(targetPos)
	end

	local tier = model:GetAttribute("Tier") or 1
	local tweenTime = getEnemyTweenTime(tier)
	local enemyTween = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear)
	tweenModelPivot(model, targetCF, enemyTween)

	model:SetAttribute("CurrentTileX", tx)
	model:SetAttribute("CurrentTileZ", tz)
	model:SetAttribute("MovingToTileX", nil)
	model:SetAttribute("MovingToTileZ", nil)
end

-- ─── Invisible hitbox ────────────────────────────────────────────────────────
local function buildHitbox(model: Model)
	local hrp = model.PrimaryPart
	if not hrp then return end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(Config.TILE_SIZE * 1.2, Config.TILE_SIZE * 1.8, Config.TILE_SIZE * 1.2)
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.Transparency = 1
	hitbox.Massless = true
	hitbox.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = hitbox
	weld.Parent = hitbox
end

-- ─── Overhead BillboardGui ────────────────────────────────────────────────────
local RARITY_COLORS = {}
for _, r in ipairs(Config.RARITIES) do
	RARITY_COLORS[r.name] = r.color
end
RARITY_COLORS["Brainrot God"] = Color3.fromRGB(255, 50, 200)
RARITY_COLORS["OG"]           = Color3.fromRGB(255, 100, 0)

local function getEnemyLevel(enemyName: string): number
	local data = EnemyData[enemyName]
	if not data then return 1 end
	return math.max(1, math.floor((data.defense or 0) * 0.6))
end

local function buildOverheadGui(model: Model, enemyName: string, rarity: string, stars: number)
	local hrp = model.PrimaryPart
	local enemyLevel = getEnemyLevel(enemyName)
	model:SetAttribute("Level", enemyLevel)

	local billboard         = Instance.new("BillboardGui")
	billboard.Name          = "EnemyUI"
	billboard.Adornee       = hrp
	billboard.Size          = UDim2.new(0, 180, 0, 44)
	billboard.StudsOffset   = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop   = false
	billboard.ResetOnSpawn  = false
	billboard.Parent        = model

	local nameLabel                  = Instance.new("TextLabel")
	nameLabel.Name                   = "NameLabel"
	nameLabel.Size                   = UDim2.new(1, 0, 0.45, 0)
	nameLabel.Position               = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3             = RARITY_COLORS[rarity] or Color3.new(1,1,1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextScaled             = true
	local starStr = stars > 0 and (string.rep("★", stars) .. " ") or ""
	nameLabel.Text   = starStr .. "[Lv." .. enemyLevel .. "] " .. enemyName
	nameLabel.Parent = billboard

	local barBG              = Instance.new("Frame")
	barBG.Name               = "BarBG"
	barBG.Size               = UDim2.new(1, 0, 0.32, 0)
	barBG.Position           = UDim2.new(0, 0, 0.55, 0)
	barBG.BackgroundColor3   = Color3.fromRGB(40, 40, 40)
	barBG.BorderSizePixel    = 0
	barBG.Parent             = billboard
	local corner1            = Instance.new("UICorner")
	corner1.CornerRadius     = UDim.new(0, 3)
	corner1.Parent           = barBG

	local barFill            = Instance.new("Frame")
	barFill.Name             = "BarFill"
	barFill.Size             = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	barFill.BorderSizePixel  = 0
	barFill.Parent           = barBG
	local corner2            = Instance.new("UICorner")
	corner2.CornerRadius     = UDim.new(0, 3)
	corner2.Parent           = barFill

	return billboard
end

function EnemyService.RefreshHPBar(model: Model)
	local billboard = model:FindFirstChild("EnemyUI")
	if not billboard then return end
	local fill = billboard:FindFirstChild("BarBG") and billboard.BarBG:FindFirstChild("BarFill")
	if not fill then return end
	local maxHP = model:GetAttribute("MaxHP") or 1
	local curHP = math.max(model:GetAttribute("CurrentHP") or 0, 0)
	local ratio = curHP / maxHP
	local r = math.min(1, 2 * (1 - ratio))
	local g = math.min(1, 2 * ratio)
	fill.Size             = UDim2.new(ratio, 0, 1, 0)
	fill.BackgroundColor3 = Color3.new(r, g, 0.1)
end

-- ─── Reachability check for spawn validation ─────────────────────────────────
-- Returns true if the tile at (tx, tz) can reach the target tile via a short
-- A* search. Used to reject isolated walkable patches (islands in water pools).
local function isTileReachable(tx: number, tz: number, targetX: number, targetZ: number): boolean
	-- Quick Manhattan pre-check: if already close, skip pathfinding
	if manhattan(tx, tz, targetX, targetZ) <= 2 then return true end

	local function isWalkableNoEnemy(px, pz)
		return TileGrid.IsWalkable(px, pz)
	end

	local path = Pathfinder.FindPath(isWalkableNoEnemy, tx, tz, targetX, targetZ, 150)
	return path ~= nil
end

-- ─── Spawn ────────────────────────────────────────────────────────────────────
function EnemyService.Spawn(spawnDef)
	local data = EnemyData[spawnDef.name]
	if not data then
		warn("[EnemyService] Unknown enemy: " .. tostring(spawnDef.name))
		return nil
	end

	local stars   = spawnDef.forceStars or 0
	if stars == 0 and math.random() < Config.ELITE_SPAWN_CHANCE then
		stars = math.random(1, Config.ELITE_STAR_MAX)
	end

	local hpMult  = stars > 0 and Config.ELITE_HP_MULT[stars]  or 1
	local dmgMult = stars > 0 and Config.ELITE_DMG_MULT[stars] or 1
	local maxHP   = math.floor(data.hp  * hpMult)
	local dmg     = math.floor(data.dmg * dmgMult)

	local id = newId()
	if isTileOccupied(spawnDef.tx, spawnDef.tz)
		or isPlayerTileOccupied(spawnDef.tx, spawnDef.tz) then
		warn("[EnemyService] Spawn tile occupied: "
			.. tostring(spawnDef.tx) .. "," .. tostring(spawnDef.tz))
		return nil
	end

	local templateFolder = game:GetService("ServerStorage"):FindFirstChild("EnemyModels")
	local template       = templateFolder and templateFolder:FindFirstChild(spawnDef.name)

	local model: Model
	if template then
		model      = template:Clone()
		model.Name = spawnDef.name .. "_" .. id
		if model.PrimaryPart then
			prepareModelParts(model)
			groundModelOnTile(model, spawnDef.tx, spawnDef.tz)
		else
			warn("[EnemyService] '" .. spawnDef.name .. "' has no PrimaryPart.")
		end
	else
		warn("[EnemyService] No model for '" .. spawnDef.name .. "' — using cube.")
		model      = Instance.new("Model")
		model.Name = spawnDef.name .. "_" .. id
		local cube           = Instance.new("Part")
		cube.Name            = "RootPart"
		cube.Size            = Vector3.new(Config.TILE_SIZE * 0.7, Config.TILE_SIZE * 0.7, Config.TILE_SIZE * 0.7)
		cube.Anchored        = true
		cube.CanCollide      = false
		cube.Color           = RARITY_COLORS[data.lootRarity] or Color3.new(0.8, 0.8, 0.8)
		cube.Material        = Enum.Material.SmoothPlastic
		cube.Parent          = model
		model.PrimaryPart    = cube
		prepareModelParts(model)
		groundModelOnTile(model, spawnDef.tx, spawnDef.tz)
	end

	model:SetAttribute("EnemyId",      id)
	model:SetAttribute("EnemyName",    spawnDef.name)
	model:SetAttribute("Rarity",       data.lootRarity)
	model:SetAttribute("Stars",        stars)
	model:SetAttribute("MaxHP",        maxHP)
	model:SetAttribute("CurrentHP",    maxHP)
	model:SetAttribute("Damage",       dmg)
	model:SetAttribute("Defense",      data.defense or 0)
	model:SetAttribute("Speed",        data.speed)
	model:SetAttribute("Tier",         data.tier)
	model:SetAttribute("SpawnTileX",   spawnDef.tx)
	model:SetAttribute("SpawnTileZ",   spawnDef.tz)
	model:SetAttribute("WanderRange",  spawnDef.wanderRange or 6)
	model:SetAttribute("AggroRange",   spawnDef.aggroRange  or 10)
	model:SetAttribute("CurrentTileX", spawnDef.tx)
	model:SetAttribute("CurrentTileZ", spawnDef.tz)
	model:SetAttribute("State",        "wander")
	model:SetAttribute("LeashRange",   spawnDef.leashRange or 15)

	model.Parent = enemyFolder
	enemies[id]  = model
	occupyTile(spawnDef.tx, spawnDef.tz, id)

	buildHitbox(model)
	buildOverheadGui(model, spawnDef.name, data.lootRarity, stars)
	EnemyService.RefreshHPBar(model)

	local thread = task.spawn(EnemyService._AILoop, id)
	enemyThreads[id] = thread

	return id
end

-- ─── Get closest player tile ──────────────────────────────────────────────────
local function getClosestPlayerTile(fromX: number, fromZ: number)
	if not MovementService then
		MovementService = require(script.Parent.MovementService)
	end
	local bestPlayer         = nil
	local bestDist           = math.huge
	local bestTx, bestTz     = fromX, fromZ

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
		local tx, tz    = MovementService.GetPlayerTile(player)
		if tx and humanoid and humanoid.Health > 0 then
			local d = manhattan(fromX, fromZ, tx, tz)
			if d < bestDist then
				bestDist   = d
				bestPlayer = player
				bestTx     = tx
				bestTz     = tz
			end
		end
	end
	return bestPlayer, bestTx, bestTz, bestDist
end

-- ─── Wander target ────────────────────────────────────────────────────────────
local function pickWanderTarget(model: Model, id: string): (number, number)
	local sx    = model:GetAttribute("SpawnTileX")
	local sz    = model:GetAttribute("SpawnTileZ")
	local range = model:GetAttribute("WanderRange")
	for _ = 1, 8 do
		local dx = math.random(-range, range)
		local dz = math.random(-range, range)
		local tx = math.clamp(sx + dx, 1, Config.GRID_WIDTH)
		local tz = math.clamp(sz + dz, 1, Config.GRID_HEIGHT)
		if isPassableForEnemy(tx, tz, id) then return tx, tz end
	end
	return sx, sz
end

-- ─── Damage accumulator forward declaration ───────────────────────────────────
local queueDamage

-- ─── AI Loop ──────────────────────────────────────────────────────────────────
function EnemyService._AILoop(id: string)
	task.wait(math.random() * 2)

	local WANDER_PAUSE_MIN = 2.0
	local WANDER_PAUSE_MAX = 4.0
	local CHASE_TICK       = 0.05

	while true do
		local model = enemies[id]
		if not model or not model.Parent then break end

		local state      = model:GetAttribute("State")
		-- FIX: always read the current tile fresh at the top of the loop
		local cx         = model:GetAttribute("CurrentTileX")
		local cz         = model:GetAttribute("CurrentTileZ")
		local aggroRange = model:GetAttribute("AggroRange")

		-- FIX: dist from the outer call is only used as an early-out / wander
		-- trigger. All subsequent state-specific logic re-queries distance from
		-- the updated tile (cx2/cz2) after any move to avoid stale values
		-- triggering incorrect state transitions.
		local targetPlayer, ptx, ptz, dist = getClosestPlayerTile(cx, cz)

		if not targetPlayer or dist * Config.TILE_SIZE > Config.ENEMY_RENDER_DISTANCE then
			if state ~= "wander" and state ~= "dead" then
				model:SetAttribute("State", "wander")
			end
			task.wait(2)
			continue
		end

		if state == "dead" then
			break

		elseif state == "wander" then
			if targetPlayer and dist <= aggroRange then
				model:SetAttribute("State", "chase")
			else
				local function isPassableW(tx, tz)
					return isPassableForEnemy(tx, tz, id)
				end
				local wx, wz = pickWanderTarget(model, id)
				local path = Pathfinder.FindPath(isPassableW, cx, cz, wx, wz, 200)

				if path and #path > 0 then
					for _, step in ipairs(path) do
						local m2 = enemies[id]
						if not m2 or not m2.Parent then break end
						if m2:GetAttribute("State") ~= "wander" then break end

						-- FIX: re-read tile after each move step (not stale cx/cz)
						local cx2 = m2:GetAttribute("CurrentTileX")
						local cz2 = m2:GetAttribute("CurrentTileZ")
						local _, _, _, d2 = getClosestPlayerTile(cx2, cz2)
						if d2 and d2 <= aggroRange then
							m2:SetAttribute("State", "chase")
							break
						end
						moveEnemyToTile(m2, step[1], step[2])
					end
				end

				task.wait(math.random() * (WANDER_PAUSE_MAX - WANDER_PAUSE_MIN) + WANDER_PAUSE_MIN)
			end

		elseif state == "chase" then
			local m = enemies[id]
			if not m or not m.Parent then break end

			local sx = m:GetAttribute("SpawnTileX")
			local sz = m:GetAttribute("SpawnTileZ")
			local leashRange = m:GetAttribute("LeashRange") or 15

			-- FIX: always re-read current tile here — it may have changed during
			-- a previous move step. Using stale cx/cz caused the leash check to
			-- compare the wrong position and could make enemies "flee" when they
			-- were actually still in range.
			local cx2 = m:GetAttribute("CurrentTileX")
			local cz2 = m:GetAttribute("CurrentTileZ")

			if manhattan(cx2, cz2, sx, sz) > leashRange then
				m:SetAttribute("State", "return")
			else
				-- FIX: re-query player distance from the current (up-to-date) tile,
				-- not the outer dist which was sampled before any move this frame.
				local _, ptx2, ptz2, dist2 = getClosestPlayerTile(cx2, cz2)

				if not targetPlayer or dist2 > aggroRange * 1.5 then
					m:SetAttribute("State", "wander")
				elseif manhattan(cx2, cz2, ptx2, ptz2) <= 1 then
					m:SetAttribute("State", "attack")
				else
					local function isPassableC(tx, tz)
						return isPassableForEnemy(tx, tz, id)
					end

					local goals = { {ptx2+1,ptz2}, {ptx2-1,ptz2}, {ptx2,ptz2+1}, {ptx2,ptz2-1} }
					local bestPath = nil
					for _, goal in ipairs(goals) do
						local gx, gz = goal[1], goal[2]
						if gx == cx2 and gz == cz2 then bestPath = {} break end
						if isPassableC(gx, gz) then
							local candidate = Pathfinder.FindPath(isPassableC, cx2, cz2, gx, gz, 300)
							if candidate and (not bestPath or #candidate < #bestPath) then
								bestPath = candidate
							end
						end
					end

					if bestPath and #bestPath > 0 then
						local step = bestPath[1]
						moveEnemyToTile(m, step[1], step[2])
					end

					task.wait(CHASE_TICK)
				end
			end

		elseif state == "attack" then
			local m = enemies[id]
			if not m or not m.Parent then break end

			local sx = m:GetAttribute("SpawnTileX")
			local sz = m:GetAttribute("SpawnTileZ")
			local leashRange = m:GetAttribute("LeashRange") or 15

			-- FIX: re-read tile for accurate leash and distance checks
			local cx2 = m:GetAttribute("CurrentTileX")
			local cz2 = m:GetAttribute("CurrentTileZ")

			if manhattan(cx2, cz2, sx, sz) > leashRange then
				m:SetAttribute("State", "return")
			elseif not targetPlayer then
				m:SetAttribute("State", "wander")
			else
				-- FIX: re-query from current tile so dist2 is accurate
				local tp2, ptx2, ptz2, dist2 = getClosestPlayerTile(cx2, cz2)

				if dist2 ~= 1 then
					m:SetAttribute("State", "chase")
				else
					-- FIX: face the player INLINE (not task.spawn) so the tween
					-- completes before we queue the attack hit and wait.
					-- Previously task.spawn ran the turn concurrently with the
					-- wait, so the enemy often never visually turned to face the
					-- player before attacking.
					if m.PrimaryPart then
						local playerWorldPos = tileToWorld(ptx2, ptz2)
						local pivotPos = m:GetPivot().Position
						local facedCF  = CFrame.new(pivotPos,
							Vector3.new(playerWorldPos.X, pivotPos.Y, playerWorldPos.Z))
						tweenModelPivot(m, facedCF, TURN_TWEEN)
					end

					local dmg = m:GetAttribute("Damage")
					queueDamage(tp2, dmg)

					task.wait(Config.ENEMY_ATTACK_INTERVAL)
				end
			end

		elseif state == "return" then
			local m = enemies[id]
			if not m or not m.Parent then break end
			local sx = m:GetAttribute("SpawnTileX")
			local sz = m:GetAttribute("SpawnTileZ")
			local cx2 = m:GetAttribute("CurrentTileX")
			local cz2 = m:GetAttribute("CurrentTileZ")
			if cx2 == sx and cz2 == sz then
				m:SetAttribute("State", "wander")
			else
				local function isPassableR(tx, tz)
					return isPassableForEnemy(tx, tz, id)
				end
				local path = Pathfinder.FindPath(isPassableR, cx2, cz2, sx, sz, 300)
				if path and #path > 0 then
					moveEnemyToTile(m, path[1][1], path[1][2])
				else
					m:SetAttribute("State", "wander")
				end
				task.wait(Config.MOVE_TWEEN_TIME)
			end

		else
			model:SetAttribute("State", "wander")
			task.wait(1)
		end
	end
end

-- ─── Damage accumulator ───────────────────────────────────────────────────────
queueDamage = function(player: Player, amount: number)
	if not player or not player.Parent then return end
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local userId = player.UserId
	pendingDamage[userId] = (pendingDamage[userId] or 0) + amount
end

local function processDamageAccumulator()
	local snapshot = pendingDamage
	pendingDamage  = {}

	for userId, totalRaw in pairs(snapshot) do
		if totalRaw > 0 then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local invincibleUntil = player:GetAttribute("InvincibleUntil")
					if invincibleUntil and tick() < invincibleUntil then
						-- consume but don't apply
					else
						if not SkillService then
							SkillService = require(script.Parent.SkillService)
						end
						if not LootService then
							LootService = require(script.Parent.LootService)
						end

						local defLevel    = SkillService.GetDefenseLevel(player)
						local armorDef    = LootService.GetEquippedArmorDefense(player)
						local finalDamage = math.max(1, totalRaw - defLevel - armorDef)

						humanoid:TakeDamage(finalDamage)
						TakeDamage:FireClient(player, player.UserId, finalDamage)
						SkillService.GrantDefenseXP(player, 1)
					end
				end
			end
		end
	end
end

-- ─── Direct damage (backward compat) ─────────────────────────────────────────
function EnemyService._DamagePlayer(player: Player, amount: number, sourceId: string)
	queueDamage(player, amount)
end

-- ─── Receive damage from CombatService ────────────────────────────────────────
function EnemyService.DamageEnemy(id: string, amount: number, attacker: Player)
	local model = enemies[id]
	if not model then return end

	local state = model:GetAttribute("State")
	if state == "dead" then return end

	local curHP = model:GetAttribute("CurrentHP") - amount
	model:SetAttribute("CurrentHP", curHP)
	EnemyService.RefreshHPBar(model)

	if state == "wander" then
		model:SetAttribute("State", "chase")
	end

	EnemyHPUpdate:FireAllClients(id, curHP, model:GetAttribute("MaxHP"))

	if curHP <= 0 then
		EnemyService._Kill(id, attacker)
	end
end

-- ─── Respawn tracking ─────────────────────────────────────────────────────────
local RESPAWN_DELAY_MIN = 8
local RESPAWN_DELAY_MAX = 15

local function queueRespawn(zoneId: string)
	task.delay(math.random(RESPAWN_DELAY_MIN, RESPAWN_DELAY_MAX), function()
		if not ZoneData then return end
		local zone = ZoneData.GetZone(zoneId)
		if not zone or zone.safe then return end

		local ZoneService = require(script.Parent.ZoneService)
		local tx, tz = ZoneService.GetRandomTileInZone(zoneId)
		if tx and tz and not isTileOccupied(tx, tz) and not isPlayerTileOccupied(tx, tz) then
			local spawnPool = ZoneData.BuildSpawnPool(zone)
			local entry = ZoneData.PickEnemy(zone, spawnPool)
			EnemyService.Spawn({
				name        = entry.name,
				tx          = tx,
				tz          = tz,
				wanderRange = entry.wanderRange,
				aggroRange  = entry.aggroRange,
			})
		end
	end)
end

-- ─── Kill ─────────────────────────────────────────────────────────────────────
function EnemyService._Kill(id: string, killer: Player?)
	local model = enemies[id]
	if not model then return end

	model:SetAttribute("State", "dead")

	local dtx     = model:GetAttribute("CurrentTileX")
	local dtz     = model:GetAttribute("CurrentTileZ")
	local movingX = model:GetAttribute("MovingToTileX")
	local movingZ = model:GetAttribute("MovingToTileZ")

	if dtx and dtz then
		releaseTile(dtx, dtz, id)
	end

	if movingX ~= nil and movingZ ~= nil
		and (movingX ~= dtx or movingZ ~= dtz) then
		releaseTile(movingX, movingZ, id)
	end

	local worldPos = dtx and dtz and tileToWorld(dtx, dtz) or Vector3.zero
	EnemyDied:FireAllClients(id, worldPos)

	if not LootService then
		LootService = require(script.Parent.LootService)
	end
	LootService.Drop(model, killer)
	local KillTracker = require(script.Parent.KillTrackerService)
	KillTracker.RegisterKill(killer, model:GetAttribute("EnemyName"))

	if killer and killer.Parent then
		local data = EnemyData[model:GetAttribute("EnemyName")]
		if data and data.xp then
			if not LeaderboardService then
				LeaderboardService = require(script.Parent.Parent.Core.Leaderboard)
			end
			LeaderboardService.AddXP(killer, data.xp)
		end
	end

	local zoneId = dtx and dtz and TileGrid.GetZone(dtx, dtz)
	if zoneId then
		queueRespawn(zoneId)
	end

	task.delay(0.5, function()
		if model and model.Parent then model:Destroy() end
		enemies[id] = nil
	end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function EnemyService.GetEnemy(id: string)
	return enemies[id]
end

function EnemyService.GetEnemyAtTile(tx: number, tz: number): Model?
	for _, model in pairs(enemies) do
		if model:GetAttribute("State") ~= "dead" then
			if model:GetAttribute("CurrentTileX") == tx
				and model:GetAttribute("CurrentTileZ") == tz then
				return model
			end
		end
	end
	return nil
end

function EnemyService.IsTileOccupied(tx: number, tz: number)
	return isTileOccupied(tx, tz)
end

function EnemyService.IsCurrentTileOccupied(tx: number, tz: number)
	for _, model in pairs(enemies) do
		if isModelBlockingTile(model, tx, tz)
			and model:GetAttribute("CurrentTileX") == tx
			and model:GetAttribute("CurrentTileZ") == tz then
			return true
		end
	end
	return false
end

function EnemyService.IsTileBlockedForPlayers(tx: number, tz: number)
	if isTileOccupied(tx, tz) then return true end
	for _, model in pairs(enemies) do
		if isModelBlockingTile(model, tx, tz) then return true end
	end
	return false
end

-- ─── Init ─────────────────────────────────────────────────────────────────────
do
	local map = workspace:WaitForChild("Map", 30)
	enemyFolder = map:FindFirstChild("Enemies")
	if not enemyFolder then
		enemyFolder        = Instance.new("Folder")
		enemyFolder.Name   = "Enemies"
		enemyFolder.Parent = map
	end

	task.defer(function()
		task.wait(3)

		local spawnX = Config.GRID_WIDTH  / 2
		local spawnZ = Config.GRID_HEIGHT / 2

		for _, zone in ipairs(ZoneData.ZONES) do
			if not zone.safe and #zone.spawnEnemies > 0 then
				local spawnPool = ZoneData.BuildSpawnPool(zone)
				local walkableCount = 0
				local zoneCx = spawnX + zone.center.x
				local zoneCz = spawnZ + zone.center.z
				local scanR  = zone.radius + 10
				for tx = math.max(1, math.floor(zoneCx - scanR)), math.min(Config.GRID_WIDTH, math.ceil(zoneCx + scanR)) do
					for tz = math.max(1, math.floor(zoneCz - scanR)), math.min(Config.GRID_HEIGHT, math.ceil(zoneCz + scanR)) do
						if TileGrid.IsWalkable(tx, tz) and TileGrid.GetZone(tx, tz) == zone.id then
							walkableCount += 1
						end
					end
				end

				local density = zone.spawnDensity or 0.01
				local spawnCount = math.clamp(math.floor(walkableCount * density), 5, 80)
				print(string.format("[EnemyService] Spawning %d enemies in %s (%d walkable tiles, density %.3f)",
					spawnCount, zone.name, walkableCount, density))

				-- The zone centre tile is used as the reachability anchor.
				-- Any spawn tile that cannot path to this anchor is rejected.
				local anchorX = math.floor(zoneCx)
				local anchorZ = math.floor(zoneCz)

				local spawned = 0
				local attempts = 0
				local maxAttempts = spawnCount * 12   -- generous budget

				while spawned < spawnCount and attempts < maxAttempts do
					attempts += 1
					local tx, tz = nil, nil

					-- Try a random tile within the zone radius first
					local angle = math.random() * math.pi * 2
					local r = math.random(0, math.floor(zone.radius * 0.9))
					local cx = math.floor(zoneCx + math.cos(angle) * r)
					local cz = math.floor(zoneCz + math.sin(angle) * r)

					if TileGrid.IsWalkable(cx, cz)
						and TileGrid.GetZone(cx, cz) == zone.id
						and not isTileOccupied(cx, cz)
						and not isPlayerTileOccupied(cx, cz) then
						tx, tz = cx, cz
					end

					-- FIX: reject tiles that have no path to the zone centre —
					-- these are isolated walkable patches (lake islands etc.) where
					-- the enemy would be permanently stuck and unable to chase anyone.
					if tx and tz then
						if not isTileReachable(tx, tz, anchorX, anchorZ) then
							tx, tz = nil, nil
						end
					end

					if tx and tz then
						local entry = ZoneData.PickEnemy(zone, spawnPool)
						local result = EnemyService.Spawn({
							name        = entry.name,
							tx          = tx,
							tz          = tz,
							wanderRange = entry.wanderRange,
							aggroRange  = entry.aggroRange,
							leashRange  = zone.leashRange or 15,
						})
						if result then
							spawned += 1
						end
					end
				end

				if spawned < spawnCount then
					print(string.format("[EnemyService] Warning: only spawned %d/%d in %s after %d attempts",
						spawned, spawnCount, zone.name, attempts))
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DAMAGE_TICK)
			processDamageAccumulator()
		end
	end)

	print("[EnemyService] Ready.")
end

return EnemyService