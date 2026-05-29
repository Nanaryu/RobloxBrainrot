-- ReplicatedStorage/Remotes/init.server.lua
-- Creates all RemoteEvents and RemoteFunctions on server start.
-- Any script can safely do:
--   local Remotes = game.ReplicatedStorage.Remotes
--   Remotes.TakeDamage.OnClientEvent:Connect(...)

local Remotes = script.Parent  -- this script lives inside the Remotes folder

local EVENTS = {
	-- Combat
	"TakeDamage",         -- Server → Client  (target, amount)
	"EnemyDied",          -- Server → Client  (enemyId, position)
	"PlayerDied",         -- Server → Client  ()

	-- Loot
	"ItemDropped",        -- Server → Client  (itemData, worldPosition)
	"InventoryUpdated",   -- Server → Client  (serialisedInventory)

	-- Movement
	"RequestMove",        -- Client → Server  (targetTileX, targetTileZ)
	"PlayerMoved",        -- Server → Client  (userId, tileX, tileZ)  -- broadcast

	-- Shops
	"OpenShopRequest",    -- Client → Server  (duration index)
	"BuyFromShop",        -- Client → Server  (shopOwnerId, listingId)
	"ShopListUpdated",    -- Server → Client  (shopData)

	-- Reroll
	"RerollRequest",      -- Client → Server  (itemId1, itemId2, itemId3)
	"RerollResult",       -- Server → Client  (newItemData | false)
}

local FUNCTIONS = {
	"GetInventory",       -- Client calls → Server returns serialised inventory
	"GetNearbyShops",     -- Client calls → Server returns shop list
}

for _, name in ipairs(EVENTS) do
	if not Remotes:FindFirstChild(name) then
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = Remotes
	end
end

for _, name in ipairs(FUNCTIONS) do
	if not Remotes:FindFirstChild(name) then
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = Remotes
	end
end

print("[Remotes] All remotes initialised.")