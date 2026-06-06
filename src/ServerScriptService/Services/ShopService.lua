-- ServerScriptService/Services/ShopService.lua
-- NPC shop that sells items for coins.
-- Rotating stock generated from ItemData, weighted by rarity.
-- Players spend coins to buy items directly (no player listing yet).
-- Stock refreshes every 5 minutes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config   = require(ReplicatedStorage.Modules.Config)
local ItemData = require(ReplicatedStorage.Modules.ItemData)

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local ShopListUpdated = Remotes:WaitForChild("ShopListUpdated")

local ShopService = {}

-- ─── Constants ────────────────────────────────────────────────────────────────
local STOCK_SIZE        = 12        -- items in shop at any time
local REFRESH_INTERVAL  = 5 * 60    -- 5 minutes in seconds
local PRICE_BASE        = 5         -- base price multiplier

-- Rarity price multipliers (index = rarity tier 1-7)
local RARITY_PRICE_MULT = {
	Common    = 1,
	Rare      = 2,
	VeryRare  = 4,
	Epic      = 8,
	Legendary = 16,
	Mythic    = 32,
	Secret    = 64,
}

-- ─── Weighted rarity pool for stock generation ────────────────────────────────
local rarityPool = {}
local totalWeight = 0
for _, r in ipairs(Config.RARITIES) do
	table.insert(rarityPool, { name = r.name, weight = r.weight })
	totalWeight += r.weight
end

local function weightedRarityPick(): string
	local roll = math.random() * totalWeight
	local cum = 0
	for _, entry in ipairs(rarityPool) do
		cum += entry.weight
		if roll <= cum then return entry.name end
	end
	return rarityPool[#rarityPool].name
end

-- ─── Current stock ────────────────────────────────────────────────────────────
-- Each listing: { id, templateName, name, slot, statType, stat, rarity, icon, price }
local stock = {}
local listingCounter = 0

local function rollListing(): table?
	local rarityName = weightedRarityPick()
	local pool = ItemData._byRarity[rarityName]
	if not pool or #pool == 0 then return nil end

	local templateName = pool[math.random(1, #pool)]
	local template = ItemData[templateName]
	if not template then return nil end

	local stat = math.random(template.statMin, template.statMax)
	local price = math.max(1, math.floor(stat * PRICE_BASE * (RARITY_PRICE_MULT[rarityName] or 1)))

	listingCounter += 1
	return {
		id           = listingCounter,
		templateName = templateName,
		name         = template.name,
		slot         = template.slot,
		statType     = template.statType,
		stat         = stat,
		rarity       = template.rarity,
		icon         = template.icon,
		price        = price,
	}
end

local function refreshStock()
	stock = {}
	for i = 1, STOCK_SIZE do
		local listing = rollListing()
		if listing then
			stock[i] = listing
		end
	end
	print("[ShopService] Stock refreshed —", #stock, "items")

	-- Notify all connected clients
	local serialized = {}
	for _, listing in ipairs(stock) do
		table.insert(serialized, {
			id           = listing.id,
			name         = listing.name,
			slot         = listing.slot,
			statType     = listing.statType,
			stat         = listing.stat,
			rarity       = listing.rarity,
			icon         = listing.icon,
			price        = listing.price,
		})
	end
	ShopListUpdated:FireAllClients(serialized)
end

-- ─── Lazy-load Leaderboard dependency ─────────────────────────────────────────
local Leaderboard

local function getLeaderboard()
	if not Leaderboard then
		local ok, svc = pcall(require,
			game:GetService("ServerScriptService").Core.Leaderboard)
		if ok then Leaderboard = svc end
	end
	return Leaderboard
end

-- ─── Lazy-load LootService dependency ─────────────────────────────────────────
local LootService

local function getLootService()
	if not LootService then
		local ok, svc = pcall(require,
			game:GetService("ServerScriptService").Services.LootService)
		if ok then LootService = svc end
	end
	return LootService
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function ShopService.GetShopList(player: Player): { table }
	local serialized = {}
	for _, listing in ipairs(stock) do
		table.insert(serialized, {
			id           = listing.id,
			name         = listing.name,
			slot         = listing.slot,
			statType     = listing.statType,
			stat         = listing.stat,
			rarity       = listing.rarity,
			icon         = listing.icon,
			price        = listing.price,
		})
	end
	return serialized
end

function ShopService.BuyItem(player: Player, listingId: number): boolean
	local listing = nil
	local listingIndex = nil
	for i, s in ipairs(stock) do
		if s.id == listingId then
			listing = s
			listingIndex = i
			break
		end
	end
	if not listing then
		print("[ShopService] BuyItem FAIL: invalid listing id", listingId)
		return false
	end

	local lb = getLeaderboard()
	if not lb then
		print("[ShopService] BuyItem FAIL: Leaderboard not loaded")
		return false
	end

	-- Check coin balance
	local coins = lb.GetCoins(player)
	if coins < listing.price then
		print("[ShopService] BuyItem FAIL:", player.Name, "has", coins, "coins, needs", listing.price)
		return false
	end

	-- Deduct coins
	lb.AddCoins(player, -listing.price)

	-- Build item instance for inventory
	local item = {
		id           = "S" .. listing.id .. "_" .. player.UserId,
		templateName = listing.templateName,
		name         = listing.name,
		slot         = listing.slot,
		statType     = listing.statType,
		stat         = listing.stat,
		rarity       = listing.rarity,
		icon         = listing.icon,
	}

	-- Give item to player
	local ls = getLootService()
	if ls then
		ls.GiveItem(player, item)
	end

	print("[ShopService]", player.Name, "bought", listing.name, "(" .. listing.rarity .. ") for", listing.price, "coins")

	-- Remove listing from stock and refresh
	table.remove(stock, listingIndex)
	if #stock == 0 then
		refreshStock()
	else
		-- Notify clients of updated stock
		local serialized = {}
		for _, l in ipairs(stock) do
			table.insert(serialized, {
				id           = l.id,
				name         = l.name,
				slot         = l.slot,
				statType     = l.statType,
				stat         = l.stat,
				rarity       = l.rarity,
				icon         = l.icon,
				price        = l.price,
			})
		end
		ShopListUpdated:FireAllClients(serialized)
	end

	return true
end

-- ─── Auto-refresh loop ────────────────────────────────────────────────────────
task.spawn(function()
	-- Initial stock generation
	refreshStock()

	-- Refresh every 5 minutes
	while true do
		task.wait(REFRESH_INTERVAL)
		refreshStock()
	end
end)

-- ─── Remote bindings ──────────────────────────────────────────────────────────
local GetShopListFn = Remotes:WaitForChild("GetShopList")
GetShopListFn.OnServerInvoke = function(player: Player)
	return ShopService.GetShopList(player)
end

local BuyShopItemEvent = Remotes:WaitForChild("BuyShopItem")
BuyShopItemEvent.OnServerEvent:Connect(function(player: Player, listingIndex: number)
	ShopService.BuyItem(player, listingIndex)
end)

print("[ShopService] Ready.")

return ShopService
