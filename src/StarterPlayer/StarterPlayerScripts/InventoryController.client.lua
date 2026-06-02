-- StarterPlayer/StarterPlayerScripts/InventoryController.client.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local InventoryUpdated = Remotes:WaitForChild("InventoryUpdated")
local GetInventory     = Remotes:WaitForChild("GetInventory")

local mainGui        = playerGui:WaitForChild("MainGui")
local inventoryPanel = mainGui:WaitForChild("InventoryPanel")
local container      = inventoryPanel:WaitForChild("InventoryContainer")
local scrollFrame    = container:WaitForChild("ScrollingFrame")
local templateSlot   = scrollFrame:WaitForChild("InvSlot")

-- Hide the template immediately so it never shows
templateSlot.Visible = false

local RARITY_COLOR = {
	Common    = Color3.fromRGB(180, 180, 180),
	Rare      = Color3.fromRGB( 80, 120, 255),
	VeryRare  = Color3.fromRGB( 50, 200, 180),
	Epic      = Color3.fromRGB(163,  53, 238),
	Legendary = Color3.fromRGB(255, 165,   0),
	Mythic    = Color3.fromRGB(220,  20,  60),
	Secret    = Color3.fromRGB(255, 215,   0),
}

local RARITY_ORDER = {
	Common=1, Rare=2, VeryRare=3, Epic=4, Legendary=5, Mythic=6, Secret=7
}

local PLACEHOLDER_ICON = "rbxassetid://101140058690765"

local function refreshInventory(items)
	-- Remove all clones (everything except the template)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= templateSlot then
			child:Destroy()
		end
	end

	if not items or #items == 0 then
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	table.sort(items, function(a, b)
		local ra = RARITY_ORDER[a.rarity] or 0
		local rb = RARITY_ORDER[b.rarity] or 0
		if ra ~= rb then return ra < rb end
		return (a.name or "") < (b.name or "")
	end)

	for _, item in ipairs(items) do
		local slot = templateSlot:Clone()
		slot.Name    = "InvSlot_" .. item.id
		slot.Visible = true

		local icon = slot:FindFirstChild("ItemIcon")
			or slot:FindFirstChildWhichIsA("ImageLabel")
		if icon then
			icon.Image = (item.icon ~= nil and item.icon ~= "")
				and item.icon or PLACEHOLDER_ICON
		end

		local label = slot:FindFirstChild("ItemLabel")
			or slot:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text       = item.name or "?"
			label.TextColor3 = RARITY_COLOR[item.rarity] or Color3.new(1,1,1)
		end

		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = RARITY_COLOR[item.rarity] or Color3.new(1,1,1)
		end

		slot:SetAttribute("ItemId",       item.id)
		slot:SetAttribute("ItemName",     item.name or "")
		slot:SetAttribute("ItemRarity",   item.rarity or "")
		slot:SetAttribute("ItemSlot",     item.slot or "")
		slot:SetAttribute("ItemStat",     item.stat or 0)
		slot:SetAttribute("ItemStatType", item.statType or "")

		slot.Parent = scrollFrame
	end

	-- Resize canvas to fit content
	task.defer(function()
		local grid = scrollFrame:FindFirstChildOfClass("UIGridLayout")
		if not grid then return end
		local cols = math.max(1, math.floor(
			scrollFrame.AbsoluteSize.X /
			(grid.CellSize.X.Offset + grid.CellPadding.X.Offset + 1)))
		local rows = math.ceil(#items / cols)
		local cellH = grid.CellSize.Y.Offset + grid.CellPadding.Y.Offset
		local padding = scrollFrame:FindFirstChildOfClass("UIPadding")
		local padV = padding
			and (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) or 0
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, rows * cellH + padV + 8)
	end)
end

-- Listen for server pushes
InventoryUpdated.OnClientEvent:Connect(refreshInventory)

-- Load on spawn (and respawn)
local function loadInventory()
	task.wait(0.5)
	local ok, result = pcall(function()
		return GetInventory:InvokeServer()
	end)
	if ok and type(result) == "table" then
		refreshInventory(result)
	else
		refreshInventory({})
	end
end

player.CharacterAdded:Connect(loadInventory)
if player.Character then
	loadInventory()
end