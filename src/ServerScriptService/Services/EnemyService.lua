-- ServerScriptService/Services/EnemyService.lua
-- Manages all enemy lifecycle: spawn, wander, chase player, attack, die, drop loot.
--
-- Each enemy is a Model in Workspace/Map/Enemies with:
--   PrimaryPart = "HRP" (a Part used as the hitbox/position anchor)
--   Attributes:
--     EnemyId     (string, unique)
--     EnemyName   (string)
--     Rarity      (string)
--     Stars       (number, 0 = normal)
--     MaxHP       (number)
--     CurrentHP   (number)
--     Damage      (number)
--     SpawnTileX  (number)
--     SpawnTileZ  (number)
--     WanderRange (number)  -- tiles from spawn it may wander
--     AggroRange  (number)  -- tiles from enemy to detect player
--     CurrentTileX(number)
--     CurrentTileZ(number)
--     State        (string) "wander" | "chase" | "attack" | "dead"

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Modules.Config)
local EnemyData   = require(ReplicatedStorage.Modules.EnemyData)
local Pathfinder  = require(ReplicatedStorage.Modules.Pathfinder)
local TileGrid    = require(script.Parent.TileGridService)

-- Forward-declare so MovementService can call GetPlayerTile
-- (we import it lazily below after both services load)
local MovementService

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")

local EnemyService = {}

-- ─── Internal state ───────────────────────────────────────────────────────────
local enemies = {}          -- enemyId → Model
local enemyThreads = {}     -- enemyId → coroutine
local enemyFolder

-- Occupied tile set: "tx_tz" → enemyId  (prevents enemies stacking)
-- Players are NOT tracked here — pathfinding avoids the player's tile separately.
local occupiedTiles = {}

local function occupyTile(tx, tz, id)
	occupiedTiles[tx .. "_" .. tz] = id
end
local function releaseTile(tx, tz, id)
	local key = tx .. "_" .. tz
	if occupiedTiles[key] == id then
		occupiedTiles[key] = nil
	end
end
local function isTileOccupied(tx, tz)
	return occupiedTiles[tx .. "_" .. tz] ~= nil
end
-- Walkable AND unoccupied by another enemy
local function isPassable(tx, tz)
	return TileGrid.IsWalkable(tx, tz) and not isTileOccupied(tx, tz)
end

-- ─── Tween config (mirrors player move speed) ─────────────────────────────────
local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)
local TURN_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ─── Unique ID generator ──────────────────────────────────────────────────────
local nextId = 0
local function newId(): string
	nextId += 1
	return "E" .. nextId
end

-- ─── Tile helpers ─────────────────────────────────────────────────────────────
local function isWalkable(tx, tz)
	-- Pathfinding uses isPassable so enemies don't route through each other.
	-- We still allow the goal tile even if occupied (so pathfinder can reach it
	-- then the AI stops one tile short).
	return TileGrid.IsWalkable(tx, tz)
end

local function tileToWorld(tx, tz): Vector3
	return TileGrid.TileToWorld(tx, tz)
end

local function chebyshev(ax, az, bx, bz): number
	return math.max(math.abs(ax - bx), math.abs(az - bz))
end

-- ─── Movement helper for enemies ─────────────────────────────────────────────
local function moveEnemyToTile(model, tx, tz)
	local hrp = model.PrimaryPart
	if not hrp then return end

	local id    = model:GetAttribute("EnemyId")
	local fromX = model:GetAttribute("CurrentTileX")
	local fromZ = model:GetAttribute("CurrentTileZ")
	local dx    = tx - fromX
	local dz    = tz - fromZ

	-- Don't move onto a tile already claimed by another enemy
	if isTileOccupied(tx, tz) then return end

	releaseTile(fromX, fromZ, id)
	model:SetAttribute("CurrentTileX", tx)
	model:SetAttribute("CurrentTileZ", tz)
	occupyTile(tx, tz, id)

	local targetPos = tileToWorld(tx, tz)

	-- Face direction of travel + slide in one tween
	local targetCF
	if dx ~= 0 or dz ~= 0 then
		targetCF = CFrame.lookAt(targetPos, targetPos + Vector3.new(dx, 0, dz))
	else
		targetCF = CFrame.new(targetPos)
	end
	TweenService:Create(hrp, MOVE_TWEEN, { CFrame = targetCF }):Play()

	task.wait(Config.MOVE_TWEEN_TIME)
end

-- ─── Overhead BillboardGui (HP bar + name + rarity) ──────────────────────────
local RARITY_COLORS = {}
for _, r in ipairs(Config.RARITIES) do
	RARITY_COLORS[r.name] = r.color
end
RARITY_COLORS["Brainrot God"] = Color3.fromRGB(255, 50, 200)
RARITY_COLORS["OG"]           = Color3.fromRGB(255, 100, 0)

local function buildOverheadGui(model: Model, enemyName: string, rarity: string, stars: number)
	local hrp = model.PrimaryPart

	local billboard      = Instance.new("BillboardGui")
	billboard.Name       = "EnemyUI"
	billboard.Adornee    = hrp
	billboard.Size       = UDim2.new(0, 160, 0, 44)
	billboard.StudsOffset= Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop= false
	billboard.ResetOnSpawn = false
	billboard.Parent     = model

	-- Name label (+ stars prefix)
	local nameLabel       = Instance.new("TextLabel")
	nameLabel.Name        = "NameLabel"
	nameLabel.Size        = UDim2.new(1, 0, 0.45, 0)
	nameLabel.Position    = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3  = RARITY_COLORS[rarity] or Color3.new(1,1,1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Font        = Enum.Font.GothamBold
	nameLabel.TextScaled  = true

	local starStr = stars > 0 and (string.rep("★", stars) .. " ") or ""
	nameLabel.Text = starStr .. enemyName
	nameLabel.Parent = billboard

	-- HP bar background
	local barBG           = Instance.new("Frame")
	barBG.Name            = "BarBG"
	barBG.Size            = UDim2.new(1, 0, 0.32, 0)
	barBG.Position        = UDim2.new(0, 0, 0.55, 0)
	barBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBG.BorderSizePixel  = 0
	barBG.Parent           = billboard

	local corner1 = Instance.new("UICorner")
	corner1.CornerRadius = UDim.new(0, 3)
	corner1.Parent = barBG

	-- HP bar fill
	local barFill         = Instance.new("Frame")
	barFill.Name          = "BarFill"
	barFill.Size          = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	barFill.BorderSizePixel  = 0
	barFill.Parent           = barBG

	local corner2 = Instance.new("UICorner")
	corner2.CornerRadius = UDim.new(0, 3)
	corner2.Parent = barFill

	return billboard
end

-- Updates the HP bar fill width; called after any HP change
function EnemyService.RefreshHPBar(model: Model)
	local billboard = model:FindFirstChild("EnemyUI")
	if not billboard then return end
	local fill = billboard:FindFirstChild("BarBG") and billboard.BarBG:FindFirstChild("BarFill")
	if not fill then return end

	local maxHP = model:GetAttribute("MaxHP") or 1
	local curHP = math.max(model:GetAttribute("CurrentHP") or 0, 0)
	local ratio = curHP / maxHP

	-- Color shifts green → yellow → red
	local r = math.min(1, 2 * (1 - ratio))
	local g = math.min(1, 2 * ratio)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	fill.BackgroundColor3 = Color3.new(r, g, 0.1)
end

-- ─── Spawn one enemy ──────────────────────────────────────────────────────────
-- spawnDef = { name, tx, tz, wanderRange?, aggroRange?, forceStars? }
function EnemyService.Spawn(spawnDef: {
	name:        string,
	tx:          number,
	tz:          number,
	wanderRange: number?,
	aggroRange:  number?,
	forceStars:  number?,
})

	local data = EnemyData[spawnDef.name]
	if not data then
		warn("[EnemyService] Unknown enemy: " .. tostring(spawnDef.name))
		return nil
	end

	-- Elite roll
	local stars = spawnDef.forceStars or 0
	if stars == 0 and math.random() < Config.ELITE_SPAWN_CHANCE then
		stars = math.random(1, Config.ELITE_STAR_MAX)
	end

	local hpMult  = stars > 0 and Config.ELITE_HP_MULT[stars]  or 1
	local dmgMult = stars > 0 and Config.ELITE_DMG_MULT[stars] or 1

	local maxHP = math.floor(data.hp  * hpMult)
	local dmg   = math.floor(data.dmg * dmgMult)

	local id = newId()

	-- ── Clone real model from ServerStorage > EnemyModels > [enemy name] ────────
	-- Each model must have PrimaryPart = RootPart.
	-- The weld (FakeRootPart → RootPart) drags the whole rig along when we tween
	-- RootPart.CFrame, so we never touch any other part of the hierarchy.
	local templateFolder = game:GetService("ServerStorage"):FindFirstChild("EnemyModels")
	local template = templateFolder and templateFolder:FindFirstChild(spawnDef.name)

	local model: Model
	if template then
		model = template:Clone()
		model.Name = spawnDef.name .. "_" .. id

		local rootPart = model.PrimaryPart
		if rootPart then
			-- Anchor so we can tween CFrame directly; weld carries rest of rig.
			rootPart.Anchored = true
			rootPart.CanCollide = false
			rootPart.CFrame = CFrame.new(tileToWorld(spawnDef.tx, spawnDef.tz))
		else
			warn("[EnemyService] '" .. spawnDef.name .. "' has no PrimaryPart — set it to RootPart in Studio.")
		end
	else
		-- Fallback placeholder cube — shown when model isn't in ServerStorage yet.
		warn("[EnemyService] No model for '" .. spawnDef.name .. "' in ServerStorage.EnemyModels — using cube.")
		model = Instance.new("Model")
		model.Name = spawnDef.name .. "_" .. id
		local cube      = Instance.new("Part")
		cube.Name       = "RootPart"
		cube.Size       = Vector3.new(Config.TILE_SIZE * 0.7, Config.TILE_SIZE * 0.7, Config.TILE_SIZE * 0.7)
		cube.Anchored   = true
		cube.CanCollide = false
		cube.Color      = RARITY_COLORS[data.lootRarity] or Color3.new(0.8, 0.8, 0.8)
		cube.Material   = Enum.Material.SmoothPlastic
		cube.CFrame     = CFrame.new(tileToWorld(spawnDef.tx, spawnDef.tz))
		cube.Parent     = model
		model.PrimaryPart = cube
	end

	-- Attributes
	model:SetAttribute("EnemyId",      id)
	model:SetAttribute("EnemyName",    spawnDef.name)
	model:SetAttribute("Rarity",       data.lootRarity)
	model:SetAttribute("Stars",        stars)
	model:SetAttribute("MaxHP",        maxHP)
	model:SetAttribute("CurrentHP",    maxHP)
	model:SetAttribute("Damage",       dmg)
	model:SetAttribute("Speed",        data.speed)
	model:SetAttribute("SpawnTileX",   spawnDef.tx)
	model:SetAttribute("SpawnTileZ",   spawnDef.tz)
	model:SetAttribute("WanderRange",  spawnDef.wanderRange or 6)
	model:SetAttribute("AggroRange",   spawnDef.aggroRange  or 10)
	model:SetAttribute("CurrentTileX", spawnDef.tx)
	model:SetAttribute("CurrentTileZ", spawnDef.tz)
	model:SetAttribute("State",        "wander")

	model.Parent = enemyFolder
	enemies[id]  = model
	occupyTile(spawnDef.tx, spawnDef.tz, id)

	-- Build overhead UI
	buildOverheadGui(model, spawnDef.name, data.lootRarity, stars)
	EnemyService.RefreshHPBar(model)

	-- Start AI loop
	local thread = task.spawn(EnemyService._AILoop, id)
	enemyThreads[id] = thread

	return id
end

-- ─── Get closest player tile position ─────────────────────────────────────────
local function getClosestPlayerTile(fromX: number, fromZ: number)
	-- Lazy import to avoid circular require at top level
	if not MovementService then
		MovementService = require(script.Parent.MovementService)
	end

	local bestPlayer = nil
	local bestDist   = math.huge
	local bestTx, bestTz = fromX, fromZ

	for _, player in ipairs(Players:GetPlayers()) do
		local tx, tz = MovementService.GetPlayerTile(player)
		if tx then
			local d = chebyshev(fromX, fromZ, tx, tz)
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

-- ─── Wander: pick a random tile within wanderRange of spawn ──────────────────
local function pickWanderTarget(model: Model): (number, number)
	local sx    = model:GetAttribute("SpawnTileX")
	local sz    = model:GetAttribute("SpawnTileZ")
	local range = model:GetAttribute("WanderRange")

	-- Try up to 8 random candidates, pick first walkable one
	for _ = 1, 8 do
		local dx = math.random(-range, range)
		local dz = math.random(-range, range)
		local tx = math.clamp(sx + dx, 1, Config.GRID_WIDTH)
		local tz = math.clamp(sz + dz, 1, Config.GRID_HEIGHT)
		if isWalkable(tx, tz) then
			return tx, tz
		end
	end
	return sx, sz  -- fallback to spawn
end

-- ─── AI Loop ──────────────────────────────────────────────────────────────────
-- Runs as a task.spawn per enemy. Handles state transitions and movement.
function EnemyService._AILoop(id: string)
	-- Stagger startup so all enemies don't tick simultaneously
	task.wait(math.random() * 2)

	local WANDER_PAUSE_MIN = 2.0   -- seconds to idle between wander steps
	local WANDER_PAUSE_MAX = 4.0
	local CHASE_TICK       = 0.5   -- seconds between path recalculations while chasing
	local ATTACK_CHECK     = 0.3   -- seconds between attack opportunity checks

	while true do
		local model = enemies[id]
		if not model or not model.Parent then break end  -- enemy was removed

		local state = model:GetAttribute("State")
		local cx    = model:GetAttribute("CurrentTileX")
		local cz    = model:GetAttribute("CurrentTileZ")
		local aggroRange = model:GetAttribute("AggroRange")

		-- ── Check for nearby players regardless of state ────────────────────
		local targetPlayer, ptx, ptz, dist = getClosestPlayerTile(cx, cz)

		-- ── State machine ───────────────────────────────────────────────────
		if state == "dead" then
			break

		elseif state == "wander" then
			-- Aggro check
			if targetPlayer and dist <= aggroRange then
				model:SetAttribute("State", "chase")
				task.wait(0)
				continue
			end

			-- Pick a wander destination and walk there one step at a time
			local wx, wz = pickWanderTarget(model)
			local path   = Pathfinder.FindPath(isWalkable, cx, cz, wx, wz, 200)

			if path and #path > 0 then
				-- Walk the path step by step, re-checking aggro each tile
				for _, step in ipairs(path) do
					local m2 = enemies[id]
					if not m2 or not m2.Parent then break end
					if m2:GetAttribute("State") ~= "wander" then break end

					-- Re-check aggro
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

			-- Idle pause between wanders
			task.wait(math.random() * (WANDER_PAUSE_MAX - WANDER_PAUSE_MIN) + WANDER_PAUSE_MIN)

		elseif state == "chase" then
			local m = enemies[id]
			if not m or not m.Parent then break end

			if not targetPlayer or dist > aggroRange * 1.5 then
				-- Lost the player — return to wander
				m:SetAttribute("State", "wander")
				task.wait(0)
				continue
			end

			local attackRange = Config.AUTO_ATTACK_RANGE

			-- Already adjacent? Switch to attack state
			if dist <= attackRange then
				m:SetAttribute("State", "attack")
				task.wait(0)
				continue
			end

			-- A* toward player, stop one tile away
			local cx2 = m:GetAttribute("CurrentTileX")
			local cz2 = m:GetAttribute("CurrentTileZ")

			-- Pathfind to a tile adjacent to player instead of the player's tile
			-- (so we don't try to walk onto occupied tile)
			local path = Pathfinder.FindPath(isWalkable, cx2, cz2, ptx, ptz, 300)

			if path and #path > 0 then
				-- Walk one step, then re-evaluate
				local step = path[1]
				-- Don't step onto player's exact tile
				if step[1] ~= ptx or step[2] ~= ptz then
					moveEnemyToTile(m, step[1], step[2])
				end
			end

			task.wait(CHASE_TICK)

		elseif state == "attack" then
			local m = enemies[id]
			if not m or not m.Parent then break end

			if not targetPlayer then
				m:SetAttribute("State", "wander")
				task.wait(0)
				continue
			end

			local cx2 = m:GetAttribute("CurrentTileX")
			local cz2 = m:GetAttribute("CurrentTileZ")
			local _, ptx2, ptz2, dist2 = getClosestPlayerTile(cx2, cz2)

			-- Player moved out of attack range → chase
			if dist2 > Config.AUTO_ATTACK_RANGE then
				m:SetAttribute("State", "chase")
				task.wait(0)
				continue
			end

			-- Face the player
			local hrp = m.PrimaryPart
			if hrp then
				local playerWorldPos = tileToWorld(ptx2, ptz2)
				local facedCF = CFrame.new(hrp.Position, Vector3.new(playerWorldPos.X, hrp.Position.Y, playerWorldPos.Z))
				TweenService:Create(hrp, TURN_TWEEN, { CFrame = facedCF }):Play()
			end

			-- Deal damage
			local dmg = m:GetAttribute("Damage")
			EnemyService._DamagePlayer(targetPlayer, dmg, id)

			task.wait(Config.ENEMY_ATTACK_INTERVAL)
		end
	end
end

-- ─── Damage player ────────────────────────────────────────────────────────────
function EnemyService._DamagePlayer(player: Player, amount: number, sourceId: string)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid:TakeDamage(amount)
	TakeDamage:FireClient(player, player.UserId, amount)
end

-- ─── Receive damage (called by CombatService) ─────────────────────────────────
function EnemyService.DamageEnemy(id: string, amount: number, attacker: Player)
	local model = enemies[id]
	if not model then return end

	local state = model:GetAttribute("State")
	if state == "dead" then return end

	local curHP = model:GetAttribute("CurrentHP") - amount
	model:SetAttribute("CurrentHP", curHP)
	EnemyService.RefreshHPBar(model)

	-- Aggro toward attacker immediately
	if state == "wander" then
		model:SetAttribute("State", "chase")
	end

	-- Fire HP update to all clients so their billboard bars stay in sync
	EnemyHPUpdate:FireAllClients(id, curHP, model:GetAttribute("MaxHP"))

	if curHP <= 0 then
		EnemyService._Kill(id, attacker)
	end
end

-- ─── Kill ──────────────────────────────────────────────────────────────────────
function EnemyService._Kill(id: string, killer: Player?)
	local model = enemies[id]
	if not model then return end

	model:SetAttribute("State", "dead")

	local dtx = model:GetAttribute("CurrentTileX")
	local dtz = model:GetAttribute("CurrentTileZ")
	releaseTile(dtx, dtz, id)

	local worldPos = tileToWorld(dtx, dtz)

	EnemyDied:FireAllClients(id, worldPos)

	-- TODO: trigger LootService.Drop(model, killer) here

	-- Small death delay then remove
	task.delay(0.5, function()
		if model and model.Parent then
			model:Destroy()
		end
		enemies[id] = nil
	end)
end

-- ─── Public: get model by id ──────────────────────────────────────────────────
function EnemyService.GetEnemy(id: string)
	return enemies[id]
end

-- ─── Init ─────────────────────────────────────────────────────────────────────
do
	local map = workspace:WaitForChild("Map", 30)
	enemyFolder = map:FindFirstChild("Enemies")
	if not enemyFolder then
		enemyFolder = Instance.new("Folder")
		enemyFolder.Name   = "Enemies"
		enemyFolder.Parent = map
	end

	-- Test spawns — replace with zone-based spawning later
	task.defer(function()
		task.wait(2)  -- wait for TileGrid to finish generating
		EnemyService.Spawn({ name = "Noobini Pizzanini", tx = 10, tz = 10, wanderRange = 5 })
		EnemyService.Spawn({ name = "Noobini Pizzanini", tx = 14, tz = 10, wanderRange = 5 })
		EnemyService.Spawn({ name = "Lirili Larila",     tx = 18, tz = 12, wanderRange = 6 })
		EnemyService.Spawn({ name = "Trippi Troppi",     tx = 22, tz = 15, wanderRange = 4, aggroRange = 8 })
		EnemyService.Spawn({ name = "Cappuccino Assassino", tx = 30, tz = 20, wanderRange = 3, aggroRange = 7 })
	end)

	print("[EnemyService] Ready.")
end

return EnemyService
