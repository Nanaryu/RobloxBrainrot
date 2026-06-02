-- ServerScriptService/Services/EnemyService.lua
-- Manages all enemy lifecycle: spawn, wander, chase player, attack, die, drop loot.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Modules.Config)
local EnemyData   = require(ReplicatedStorage.Modules.EnemyData)
local Pathfinder  = require(ReplicatedStorage.Modules.Pathfinder)
local TileGrid    = require(script.Parent.TileGridService)

local MovementService
local SkillService
local LootService

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")

local EnemyService = {}

-- ─── Internal state ───────────────────────────────────────────────────────────
local enemies      = {}
local enemyThreads = {}
local enemyFolder

-- occupiedTiles: key "tx_tz" → enemyId
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
-- FIX: wander/chase pathfinding uses this variant so the enemy's own
-- current tile is not treated as blocked (it owns that tile).
local function isPassableForEnemy(tx, tz, id)
	if not TileGrid.IsWalkable(tx, tz) then return false end
	if isPlayerTileOccupied(tx, tz) then return false end
	local occupant = occupiedTiles[tx .. "_" .. tz]
	-- Passable if unoccupied OR occupied by self
	return occupant == nil or occupant == id
end

-- ─── Tween config ─────────────────────────────────────────────────────────────
local MOVE_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME, Enum.EasingStyle.Linear)
local TURN_TWEEN = TweenInfo.new(Config.MOVE_TWEEN_TIME * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
	model:PivotTo(baseCF)
	local boundsCF, boundsSize = model:GetBoundingBox()
	local bottomY  = boundsCF.Position.Y - boundsSize.Y * 0.5
	local tileTopY = Config.TILE_HEIGHT
	local groundedCF = baseCF + Vector3.new(0, tileTopY - bottomY, 0)
	model:PivotTo(groundedCF)
	model:SetAttribute("PivotYOffset", model:GetPivot().Position.Y - tileToWorld(tx, tz).Y)
end

local function getTilePivotPosition(model: Model, tx: number, tz: number): Vector3
	return tileToWorld(tx, tz) + Vector3.new(0, model:GetAttribute("PivotYOffset") or 0, 0)
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
	tweenModelPivot(model, targetCF, MOVE_TWEEN)

	model:SetAttribute("CurrentTileX", tx)
	model:SetAttribute("CurrentTileZ", tz)
	-- FIX: always clear MovingTo after the tween completes so _Kill
	-- does not try to double-release a tile that is already released.
	model:SetAttribute("MovingToTileX", nil)
	model:SetAttribute("MovingToTileZ", nil)
end

-- ─── Overhead BillboardGui ────────────────────────────────────────────────────
local RARITY_COLORS = {}
for _, r in ipairs(Config.RARITIES) do
	RARITY_COLORS[r.name] = r.color
end
RARITY_COLORS["Brainrot God"] = Color3.fromRGB(255, 50, 200)
RARITY_COLORS["OG"]           = Color3.fromRGB(255, 100, 0)

local function buildOverheadGui(model: Model, enemyName: string, rarity: string, stars: number)
	local hrp = model.PrimaryPart

	local billboard         = Instance.new("BillboardGui")
	billboard.Name          = "EnemyUI"
	billboard.Adornee       = hrp
	billboard.Size          = UDim2.new(0, 160, 0, 44)
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
	nameLabel.Text   = starStr .. enemyName
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

-- ─── Spawn ────────────────────────────────────────────────────────────────────
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
		-- FIX: use self-aware passable check so the enemy's own tile
		-- is always considered walkable (avoids immediate nil path).
		if isPassableForEnemy(tx, tz, id) then return tx, tz end
	end
	return sx, sz
end

-- ─── AI Loop ──────────────────────────────────────────────────────────────────
function EnemyService._AILoop(id: string)
	task.wait(math.random() * 2)

	local WANDER_PAUSE_MIN = 2.0
	local WANDER_PAUSE_MAX = 4.0
	local CHASE_TICK       = 0.05
	local ATTACK_CHECK     = 0.3  -- seconds between attack/check; unused directly below

	while true do
		local model = enemies[id]
		if not model or not model.Parent then break end

		local state      = model:GetAttribute("State")
		local cx         = model:GetAttribute("CurrentTileX")
		local cz         = model:GetAttribute("CurrentTileZ")
		local aggroRange = model:GetAttribute("AggroRange")

		local targetPlayer, ptx, ptz, dist = getClosestPlayerTile(cx, cz)

		-- FIX: replaced all task.wait(0)+continue patterns with
		-- if/elseif so the scheduler isn't yielded on every state change.
		if state == "dead" then
			break

		elseif state == "wander" then
			if targetPlayer and dist <= aggroRange then
				model:SetAttribute("State", "chase")
				-- No wait — loop immediately with new state
			else
				-- FIX: pass id so wander finder uses self-aware passable
				local wx, wz = pickWanderTarget(model, id)
				local function isPassableW(tx, tz)
					return isPassableForEnemy(tx, tz, id)
				end
				local path = Pathfinder.FindPath(isPassableW, cx, cz, wx, wz, 200)

				if path and #path > 0 then
					for _, step in ipairs(path) do
						local m2 = enemies[id]
						if not m2 or not m2.Parent then break end
						if m2:GetAttribute("State") ~= "wander" then break end

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

			if not targetPlayer or dist > aggroRange * 1.5 then
				m:SetAttribute("State", "wander")
				-- No wait — loop immediately
			elseif dist == 1 then
				m:SetAttribute("State", "attack")
				-- No wait — loop immediately
			else
				local cx2 = m:GetAttribute("CurrentTileX")
				local cz2 = m:GetAttribute("CurrentTileZ")

				local function isPassableC(tx, tz)
					return isPassableForEnemy(tx, tz, id)
				end

				local goals = { {ptx+1,ptz}, {ptx-1,ptz}, {ptx,ptz+1}, {ptx,ptz-1} }
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

		elseif state == "attack" then
			local m = enemies[id]
			if not m or not m.Parent then break end

			if not targetPlayer then
				m:SetAttribute("State", "wander")
				-- No wait — loop immediately
			else
				local cx2 = m:GetAttribute("CurrentTileX")
				local cz2 = m:GetAttribute("CurrentTileZ")
				local _, ptx2, ptz2, dist2 = getClosestPlayerTile(cx2, cz2)

				if dist2 ~= 1 then
					m:SetAttribute("State", "chase")
					-- No wait — loop immediately
				else
					if m.PrimaryPart then
						local playerWorldPos = tileToWorld(ptx2, ptz2)
						local pivotPos = m:GetPivot().Position
						local facedCF  = CFrame.new(pivotPos,
							Vector3.new(playerWorldPos.X, pivotPos.Y, playerWorldPos.Z))
						task.spawn(tweenModelPivot, m, facedCF, TURN_TWEEN)
					end

					local dmg = m:GetAttribute("Damage")
					EnemyService._DamagePlayer(targetPlayer, dmg, id)

					task.wait(Config.ENEMY_ATTACK_INTERVAL)
				end
			end
		else
			-- Unknown state: reset to wander
			model:SetAttribute("State", "wander")
			task.wait(1)
		end
	end
end

-- ─── Damage player ────────────────────────────────────────────────────────────
function EnemyService._DamagePlayer(player: Player, amount: number, sourceId: string)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if not SkillService then
		SkillService = require(script.Parent.SkillService)
	end

	local reduction   = SkillService.GetDefenseReduction(player)
	local finalDamage = math.max(1, math.floor(amount * (1 - reduction)))

	humanoid:TakeDamage(finalDamage)
	TakeDamage:FireClient(player, player.UserId, finalDamage)
	SkillService.GrantDefenseXP(player, 1)
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

-- ─── Kill ─────────────────────────────────────────────────────────────────────
function EnemyService._Kill(id: string, killer: Player?)
	local model = enemies[id]
	if not model then return end

	model:SetAttribute("State", "dead")

	local dtx     = model:GetAttribute("CurrentTileX")
	local dtz     = model:GetAttribute("CurrentTileZ")
	local movingX = model:GetAttribute("MovingToTileX")
	local movingZ = model:GetAttribute("MovingToTileZ")

	-- FIX: release current tile unconditionally; only release the moving
	-- tile if it differs from current (tween may have already cleared it).
	releaseTile(dtx, dtz, id)
	if movingX and movingZ and (movingX ~= dtx or movingZ ~= dtz) then
		releaseTile(movingX, movingZ, id)
	end

	local worldPos = tileToWorld(dtx, dtz)
	EnemyDied:FireAllClients(id, worldPos)

	if not LootService then
		LootService = require(script.Parent.LootService)
	end
	LootService.Drop(model, killer)
	local KillTracker = require(script.Parent.KillTrackerService)
	KillTracker.RegisterKill(killer, model:GetAttribute("EnemyName"))

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
		task.wait(2)
		EnemyService.Spawn({ name = "Noobini Pizzanini",    tx = 10, tz = 10, wanderRange = 5 })
		EnemyService.Spawn({ name = "Noobini Pizzanini",    tx = 14, tz = 10, wanderRange = 5 })
		EnemyService.Spawn({ name = "Lirili Larila",        tx = 18, tz = 12, wanderRange = 6 })
		EnemyService.Spawn({ name = "Trippi Troppi",        tx = 22, tz = 15, wanderRange = 4, aggroRange = 8 })
		EnemyService.Spawn({ name = "Cappuccino Assassino", tx = 30, tz = 20, wanderRange = 3, aggroRange = 7 })
	end)

	print("[EnemyService] Ready.")
end

return EnemyService
