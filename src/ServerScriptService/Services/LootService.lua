-- ServerScriptService/Services/LootService.lua
-- Handles everything that happens when an enemy dies:
--   1. Roll whether a drop occurs (based on enemy rarity).
--   2. Pick a random item template from the appropriate rarity pool.
--   3. Roll the item's stat value within its [statMin, statMax] range.
--   4. Spawn a glowing Part in the world at the death position.
--   5. Fire ItemDropped → all nearby clients (visual beacon).
--   6. When a player walks onto the tile, auto-pickup → InventoryUpdated → client.
--   7. Inventory persisted to "Inventory_v1" DataStore.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local DataStoreService  = game:GetService("DataStoreService")

local Config   = require(ReplicatedStorage.Modules.Config)
local ItemData = require(ReplicatedStorage.Modules.ItemData)

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local ItemDropped      = Remotes:WaitForChild("ItemDropped")
local InventoryUpdated = Remotes:WaitForChild("InventoryUpdated")
local EquipmentUpdated = Remotes:WaitForChild("EquipmentUpdated")

local inventoryStore = DataStoreService:GetDataStore("Inventory_v1")

local LootService = {}

-- ─── Equipment slot definitions ────────────────────────────────────────────────
local EQUIP_SLOTS = {
	weapon = true, offhand = true,
	helmet = true, chest  = true,
	legs   = true, boots  = true,
}
local ATK_SLOTS   = { weapon = true, offhand = true }
local DEF_SLOTS   = { helmet = true, chest = true, legs = true, boots = true }

-- ─── In-memory inventory ──────────────────────────────────────────────────────
local inventories = {}  -- userId → { [itemId] = itemData }

-- ─── In-memory equipment ──────────────────────────────────────────────────────
local equipment = {}    -- userId → { [slot] = itemData }

local function getInventory(player: Player)
	if not inventories[player.UserId] then
		inventories[player.UserId] = {}
	end
	return inventories[player.UserId]
end

local function getEquipment(player: Player)
	if not equipment[player.UserId] then
		equipment[player.UserId] = {}
	end
	return equipment[player.UserId]
end

-- ─── Item ID generator ────────────────────────────────────────────────────────
local nextItemId = 0
local function newItemId(): string
	nextItemId += 1
	return "I" .. nextItemId
end

local function refreshIdCounter()
	for _, inv in pairs(inventories) do
		for id in pairs(inv) do
			local num = tonumber(id:match("^I(%d+)$"))
			if num and num >= nextItemId then
				nextItemId = num + 1
			end
		end
	end
end

-- ─── Rarity → drop chance ─────────────────────────────────────────────────────
local DROP_CHANCE = {
	Common    = 0.25,
	Rare      = 0.40,
	VeryRare  = 0.55,
	Epic      = 0.70,
	Legendary = 0.85,
	Mythic    = 0.95,
	Secret    = 1.00,
}

-- ─── Enemy rarity → item rarity pool ─────────────────────────────────────────
local ENEMY_LOOT_TABLE = {
	Common    = { {"Common", 90}, {"Rare", 10} },
	Rare      = { {"Common", 60}, {"Rare", 30}, {"VeryRare", 10} },
	VeryRare  = { {"Rare", 50},   {"VeryRare", 35}, {"Epic", 15} },
	Epic      = { {"VeryRare", 40}, {"Epic", 45}, {"Legendary", 15} },
	Legendary = { {"Epic", 35},   {"Legendary", 50}, {"Mythic", 15} },
	Mythic    = { {"Legendary", 30}, {"Mythic", 55}, {"Secret", 15} },
	Secret    = { {"Mythic", 20}, {"Secret", 80} },
}

-- ─── Weighted random pick ─────────────────────────────────────────────────────
local function weightedPick(tbl)
	local total = 0
	for _, entry in ipairs(tbl) do total += entry[2] end
	local roll = math.random() * total
	local cum  = 0
	for _, entry in ipairs(tbl) do
		cum += entry[2]
		if roll <= cum then return entry[1] end
	end
	return tbl[#tbl][1]
end

-- ─── Roll a concrete item instance ───────────────────────────────────────────
local function rollItem(templateName: string): table?
	local template = ItemData[templateName]
	if not template then return nil end
	local stat = math.random(template.statMin, template.statMax)
	return {
		id           = newItemId(),
		templateName = templateName,
		name         = template.name,
		slot         = template.slot,
		statType     = template.statType,
		stat         = stat,
		rarity       = template.rarity,
		icon         = template.icon,
	}
end

local function pickTemplate(rarityName: string): string?
	local pool = ItemData._byRarity[rarityName]
	if not pool or #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

-- ─── Rarity tier helpers ──────────────────────────────────────────────────────
local RARITY_ORDER = {}
for i, r in ipairs(Config.RARITIES) do
	RARITY_ORDER[r.name] = i
end
local function bumpRarity(rarityName: string, bump: number): string
	local idx = (RARITY_ORDER[rarityName] or 1) + bump
	idx = math.clamp(idx, 1, #Config.RARITIES)
	return Config.RARITIES[idx].name
end

local RARITY_COLOR = {}
for _, r in ipairs(Config.RARITIES) do
	RARITY_COLOR[r.name] = r.color
end

-- ─── World drop state ─────────────────────────────────────────────────────────
local PICKUP_RANGE = 0 -- must be on exact same tile
local BOB_HEIGHT   = 0.6
local BOB_PERIOD   = 1.4

local worldDrops = {}  -- itemId → { part, item, tileX, tileZ }

local lootFolder: Folder

local function spawnWorldDrop(item: table, worldPos: Vector3, tx: number, tz: number, killerId: number?)
	local color = RARITY_COLOR[item.rarity] or Color3.new(1, 1, 1)

	local part            = Instance.new("Part")
	part.Name             = "Drop_" .. item.id
	part.Size             = Vector3.new(0.7, 0.7, 0.7)
	part.Shape            = Enum.PartType.Ball
	part.Anchored         = true
	part.CanCollide       = false
	part.CanQuery         = false
	part.CastShadow       = false
	part.Color            = color
	part.Material         = Enum.Material.Neon
	part.CFrame           = CFrame.new(worldPos + Vector3.new(0, 1.5, 0))
	part.Parent           = lootFolder

	local baseY = worldPos.Y + 1.5
	task.spawn(function()
		local up = true
		while part and part.Parent do
			local targetY = up and (baseY + BOB_HEIGHT) or baseY
			TweenService:Create(part,
				TweenInfo.new(BOB_PERIOD * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = CFrame.new(worldPos.X, targetY, worldPos.Z) }
			):Play()
			up = not up
			task.wait(BOB_PERIOD * 0.5)
		end
	end)

	local light        = Instance.new("PointLight")
	light.Brightness   = 3
	light.Range        = 8
	light.Color        = color
	light.Parent       = part

	local billboard           = Instance.new("BillboardGui")
	billboard.Size            = UDim2.new(0, 130, 0, 24)
	billboard.StudsOffset     = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop     = false
	billboard.ResetOnSpawn    = false
	billboard.Adornee         = part
	billboard.Parent          = part

	local nameLabel                  = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3             = color
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextScaled             = true
	nameLabel.Text                   = item.name
	nameLabel.Parent                 = billboard

	worldDrops[item.id] = { part = part, item = item, tileX = tx, tileZ = tz, killerId = killerId }
end

-- ─── Serialize inventory + equipped items (for client display) ─────────────────
local function serializeInventory(player: Player): { table }
	local inv = getInventory(player)
	local eq  = getEquipment(player)
	local result = {}
	for _, item in pairs(inv) do
		table.insert(result, item)
	end
	for _, item in pairs(eq) do
		local entry = table.clone(item)
		entry.equipped = true
		table.insert(result, entry)
	end
	return result
end

-- ─── Give item to player ──────────────────────────────────────────────────────
local function giveItem(player: Player, item: table)
	local inv = getInventory(player)
	inv[item.id] = item
	InventoryUpdated:FireClient(player, serializeInventory(player))
end

-- ─── Fire equipment update to client ──────────────────────────────────────────
local function fireEquipmentUpdate(player: Player)
	local eq = getEquipment(player)
	EquipmentUpdated:FireClient(player, eq)
end

-- ─── Equip an item from inventory ─────────────────────────────────────────────
function LootService.EquipItem(player: Player, itemId: string): boolean
	local inv = getInventory(player)
	local item = inv[itemId]
	if not item then
		print("[EquipItem] FAIL: item not in inventory:", itemId)
		return false
	end
	if not EQUIP_SLOTS[item.slot] then
		print("[EquipItem] FAIL: invalid slot:", item.slot, "for item:", itemId)
		return false
	end

	local eq = getEquipment(player)

	-- If slot already occupied, swap the old item back to inventory
	local oldItem = eq[item.slot]
	if oldItem then
		inv[oldItem.id] = oldItem
	end

	-- Move item from inventory to equipped slot
	inv[itemId] = nil
	eq[item.slot] = item

	print("[EquipItem] Equipped", itemId, "(" .. item.name .. ", slot=" .. item.slot .. ")")
	local snapshot = {}
	for s, it in pairs(eq) do snapshot[s] = it.id .. "(" .. it.name .. ")" end
	print("[EquipItem] Equipment after:", snapshot)

	fireEquipmentUpdate(player)
	InventoryUpdated:FireClient(player, serializeInventory(player))

	return true
end

-- ─── Unequip an item from a slot ──────────────────────────────────────────────
function LootService.UnequipItem(player: Player, slot: string): boolean
	if not EQUIP_SLOTS[slot] then
		print("[UnequipItem] FAIL: invalid slot:", slot)
		return false
	end
	local eq = getEquipment(player)
	local item = eq[slot]
	if not item then
		print("[UnequipItem] FAIL: nothing equipped in slot:", slot)
		return false
	end

	eq[slot] = nil

	-- Return item to inventory
	local inv = getInventory(player)
	inv[item.id] = item

	print("[UnequipItem] Unequipped", item.id, "(" .. item.name .. ") from slot", slot)
	local snapshot = {}
	for s, it in pairs(eq) do snapshot[s] = it.id .. "(" .. it.name .. ")" end
	print("[UnequipItem] Equipment after:", snapshot)

	fireEquipmentUpdate(player)
	InventoryUpdated:FireClient(player, serializeInventory(player))

	return true
end

-- ─── Query equipped weapon ATK ────────────────────────────────────────────────
function LootService.GetEquippedWeaponAttack(player: Player): number
	local eq = getEquipment(player)
	local total = 0
	for slot, item in pairs(eq) do
		if ATK_SLOTS[slot] and item.statType == "atk" then
			total += item.stat
		end
	end
	return total
end

-- ─── Query equipped armor DEF ─────────────────────────────────────────────────
function LootService.GetEquippedArmorDefense(player: Player): number
	local eq = getEquipment(player)
	local total = 0
	for slot, item in pairs(eq) do
		if DEF_SLOTS[slot] and item.statType == "def" then
			total += item.stat
		end
	end
	return total
end

-- ─── Get full equipment table ─────────────────────────────────────────────────
function LootService.GetEquipment(player: Player): { [string]: table }
	return getEquipment(player)
end

-- ─── Remove world drop ────────────────────────────────────────────────────────
local function removeWorldDrop(itemId: string)
	local drop = worldDrops[itemId]
	if not drop then return nil end
	worldDrops[itemId] = nil
	if drop.part and drop.part.Parent then
		drop.part:Destroy()
	end
	return drop
end

-- ─── Proximity pickup loop ────────────────────────────────────────────────────
local MovementService

task.spawn(function()
	while true do
		task.wait(0.3)
		if not MovementService then
			local ok, svc = pcall(require,
				game:GetService("ServerScriptService").Services.MovementService)
			if ok then MovementService = svc end
		end
		if not MovementService then continue end

		local ids = {}
		for itemId in pairs(worldDrops) do
			table.insert(ids, itemId)
		end

		for _, itemId in ipairs(ids) do
			local drop = worldDrops[itemId]
			if not drop then continue end

			for _, player in ipairs(Players:GetPlayers()) do
				-- Only the killer can pick up the drop
				if drop.killerId and player.UserId ~= drop.killerId then continue end

				local ptx, ptz = MovementService.GetPlayerTile(player)
				if ptx then
					local dist = math.abs(ptx - drop.tileX) + math.abs(ptz - drop.tileZ)
					if dist <= PICKUP_RANGE then
						local claimed = removeWorldDrop(itemId)
						if claimed then
							giveItem(player, claimed.item)
						end
						break
					end
				end
			end
		end
	end
end)

-- ─── Public: Drop from a killed enemy model ───────────────────────────────────
function LootService.Drop(model: Model, killer: Player?)
	local enemyRarity = model:GetAttribute("Rarity") or "Common"
	local stars       = model:GetAttribute("Stars")  or 0
	local tx          = model:GetAttribute("CurrentTileX") or 1
	local tz          = model:GetAttribute("CurrentTileZ") or 1

	local dropChance = DROP_CHANCE[enemyRarity] or 0.25
	if math.random() > dropChance then return end

	local lootTable  = ENEMY_LOOT_TABLE[enemyRarity] or ENEMY_LOOT_TABLE["Common"]
	local itemRarity = weightedPick(lootTable)
	if stars > 0 then
		local bump = Config.ELITE_LOOT_TIER_BUMP[stars] or 0
		itemRarity = bumpRarity(itemRarity, bump)
	end

	local templateName = pickTemplate(itemRarity)
	if not templateName then return end
	local item = rollItem(templateName)
	if not item then return end

	local worldPos = Vector3.new(
		(tx - 0.5) * Config.TILE_SIZE,
		Config.TILE_HEIGHT + 0.5,
		(tz - 0.5) * Config.TILE_SIZE
	)
	spawnWorldDrop(item, worldPos, tx, tz, killer and killer.UserId)
	ItemDropped:FireAllClients(item, worldPos)
end

-- ─── Public: get serialized inventory ────────────────────────────────────────
function LootService.GetInventory(player: Player): { table }
	return serializeInventory(player)
end

-- ─── Deferred save (stagger writes, avoid DataStore budget spike) ─────────────
local pendingSaves = {} -- userId → snapshot data

local function scheduleSave(userId: number, data: table)
	pendingSaves[userId] = data
	task.delay(1.5, function()
		if pendingSaves[userId] then
			pcall(function()
				inventoryStore:SetAsync(tostring(userId), data)
			end)
			pendingSaves[userId] = nil
		end
	end)
end

local function flushSaves()
	local toSave = pendingSaves
	pendingSaves = {}
	for userId, data in pairs(toSave) do
		pcall(function()
			inventoryStore:SetAsync(tostring(userId), data)
		end)
	end
end

-- ─── Persistence helpers ──────────────────────────────────────────────────────
local function packSaveData(userId: number): table
	local inv = inventories[userId] or {}
	local eq  = equipment[userId] or {}
	return {
		inventory = inv,
		equipment = eq,
	}
end

local function unpackSaveData(userId: number, data: table)
	-- Support legacy flat-format saves (pre-equipment system)
	if data.inventory ~= nil or data.equipment ~= nil then
		inventories[userId] = data.inventory or {}
		equipment[userId]   = data.equipment or {}
	else
		-- Legacy: data IS the inventory table directly
		inventories[userId] = data
		equipment[userId]   = {}
	end
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	local ok, result = pcall(function()
		return inventoryStore:GetAsync(tostring(player.UserId))
	end)
	if ok and type(result) == "table" then
		unpackSaveData(player.UserId, result)
	else
		inventories[player.UserId] = {}
		equipment[player.UserId]   = {}
	end
	refreshIdCounter()
end)

Players.PlayerRemoving:Connect(function(player)
	local data = packSaveData(player.UserId)
	inventories[player.UserId] = nil
	equipment[player.UserId]   = nil
	scheduleSave(player.UserId, data)
end)

-- Handle Studio stop button / server shutdown
game:BindToClose(function()
	flushSaves()
end)

-- Handle players already in-game (Studio play-solo)
for _, player in ipairs(Players:GetPlayers()) do
	local ok, result = pcall(function()
		return inventoryStore:GetAsync(tostring(player.UserId))
	end)
	if ok and type(result) == "table" then
		unpackSaveData(player.UserId, result)
	else
		inventories[player.UserId] = {}
		equipment[player.UserId]   = {}
	end
end
refreshIdCounter()

-- ─── GetInventory RemoteFunction ──────────────────────────────────────────────
local GetInventoryFn = Remotes:WaitForChild("GetInventory")
GetInventoryFn.OnServerInvoke = function(player: Player)
	return LootService.GetInventory(player)
end

-- ─── Equip/Unequip RemoteEvents ──────────────────────────────────────────────
local EquipRequest   = Remotes:WaitForChild("EquipRequest")
local UnequipRequest = Remotes:WaitForChild("UnequipRequest")

EquipRequest.OnServerEvent:Connect(function(player: Player, itemId: string)
	LootService.EquipItem(player, itemId)
end)

UnequipRequest.OnServerEvent:Connect(function(player: Player, slot: string)
	LootService.UnequipItem(player, slot)
end)

-- ─── GetEquipment RemoteFunction ──────────────────────────────────────────────
local GetEquipmentFn = Remotes:WaitForChild("GetEquipment")
GetEquipmentFn.OnServerInvoke = function(player: Player)
	return LootService.GetEquipment(player)
end

-- ─── Init folder ──────────────────────────────────────────────────────────────
do
	local map = workspace:WaitForChild("Map", 30)
	lootFolder = map:FindFirstChild("Loot")
	if not lootFolder then
		lootFolder        = Instance.new("Folder")
		lootFolder.Name   = "Loot"
		lootFolder.Parent = map
	end
	print("[LootService] Ready.")
end

return LootService