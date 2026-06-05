-- ServerScriptService/Core/RemotesInit.server.lua
-- Runs at game start (server side). Creates all RemoteEvents and RemoteFunctions
-- inside ReplicatedStorage.Remotes so clients can safely WaitForChild() them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local EVENTS = {
	-- Movement
	"RequestMove",        -- Client → Server  (targetTileX, targetTileZ)
	"PlayerMoved",        -- Server → Client  (userId, tileX, tileZ)

	-- Combat
	"TakeDamage",         -- Server → Client  (targetUserId | enemyId, amount)
	"EnemyDied",          -- Server → Client  (enemyId, worldPosition)
	"EnemyHPUpdate",      -- Server → Client  (enemyId, currentHP, maxHP)
	"PlayerDied",         -- Server → Client  ()
	"PlayerRespawn",      -- Server → Client  ()

	-- Loot
	"ItemDropped",        -- Server → Client  (itemData, worldPosition)
	"InventoryUpdated",   -- Server → Client  (serialisedInventory)
	"EquipmentUpdated",   -- Server → Client  (equipmentTable)
	"EquipRequest",       -- Client → Server  (itemId)
	"UnequipRequest",     -- Client → Server  (slot)

	-- Combat (player attacking enemies)
	"RequestAttack",      -- Client → Server  (enemyId)
	"AttackResult",       -- Server → Client  (hit, damage, enemyId, remainingHP)
	"StopAttack",         -- Client → Server  ()

	-- Damage numbers (server-broadcast)
	"DamageNumber",       -- Server → Client  (attackerUserId, damage, enemyId)

	-- Skills
	"SkillUpdated",       -- Server → Client  (payload table: { Attack={level,currentXP,neededXP}, Defense={...} })

	-- Reroll
	"RerollRequest",      -- Client → Server  (itemId1, itemId2, itemId3)
	"RerollResult",       -- Server → Client  (newItemData | false)

	-- Shops
	"ShopListUpdated",    -- Server → Client  (shopData) — NPC stock refresh broadcast
	"BuyShopItem",        -- Client → Server  (listingIndex) — NPC shop buy
}

local FUNCTIONS = {
	"GetInventory",       -- Client → Server, returns serialised inventory table
	"GetEquipment",       -- Client → Server, returns equipped items table
	"GetNearbyShops",     -- Client → Server, returns nearby shop list table
	"GetShopList",        -- Client → Server, returns NPC shop stock table
}

for _, name in ipairs(EVENTS) do
	if not remotesFolder:FindFirstChild(name) then
		local e    = Instance.new("RemoteEvent")
		e.Name     = name
		e.Parent   = remotesFolder
	end
end

for _, name in ipairs(FUNCTIONS) do
	if not remotesFolder:FindFirstChild(name) then
		local f    = Instance.new("RemoteFunction")
		f.Name     = name
		f.Parent   = remotesFolder
	end
end

print("[RemotesInit] All remotes created.")
