local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local InventoryUpdated = Remotes:WaitForChild("InventoryUpdated")
local EquipmentUpdated = Remotes:WaitForChild("EquipmentUpdated")
local GetInventory     = Remotes:WaitForChild("GetInventory")
local GetEquipment     = Remotes:WaitForChild("GetEquipment")
local EquipRequest     = Remotes:WaitForChild("EquipRequest")
local UnequipRequest   = Remotes:WaitForChild("UnequipRequest")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local scrollFrame    = nil
local templateSlot   = nil
local mainGui        = nil
local tooltipGui     = nil
local tooltip        = nil
local tooltipTween   = nil
local tooltipVisible = false
local pendingItems   = nil
local pendingEquip   = nil

local FADE_IN  = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.1,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local RARITY_COLOR = Config.RARITY_COLOR
local RARITY_ORDER = Config.RARITY_ORDER

local PLACEHOLDER_ICON = "rbxassetid://101140058690765"

local EQUIP_SLOTS = Config.EQUIP_SLOTS

local function buildTooltip()
	-- Create a dedicated ScreenGui so tooltip always renders above the main GUI
	tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "TooltipGui"
	tooltipGui.DisplayOrder = 99
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.Parent = playerGui

	tooltip = Instance.new("Frame")
	tooltip.Name = "ItemTooltip"
	tooltip.Size = UDim2.new(0, 220, 0, 130)
	tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	tooltip.BackgroundTransparency = 1
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 1
	tooltip.Parent = tooltipGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(60, 60, 80)
	stroke.Transparency = 0.4
	stroke.Parent = tooltip

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = tooltip

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = tooltip

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TooltipName"
	nameLabel.Size = UDim2.new(1, 0, 0, 22)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = tooltip

	local divider = Instance.new("Frame")
	divider.Name = "TooltipDivider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 2
	divider.Parent = tooltip

	local detailTpl = Instance.new("TextLabel")
	detailTpl.Size = UDim2.new(1, 0, 0, 16)
	detailTpl.BackgroundTransparency = 1
	detailTpl.Font = Enum.Font.Gotham
	detailTpl.TextSize = 14
	detailTpl.TextColor3 = Color3.fromRGB(180, 180, 190)
	detailTpl.TextXAlignment = Enum.TextXAlignment.Left
	detailTpl.RichText = true

	local function makeDetail(name: string, order: number): TextLabel
		local lbl = detailTpl:Clone()
		lbl.Name = "Detail_" .. name
		lbl.LayoutOrder = order
		return lbl
	end

	makeDetail("Slot",      3).Parent = tooltip
	makeDetail("Stat",      4).Parent = tooltip
	makeDetail("Rarity",    5).Parent = tooltip
	makeDetail("ID",        6).Parent = tooltip
end

local function showTooltip(item: table, slotFrame: Frame)
	if not tooltip or not tooltip.Parent then return end

	tooltipVisible = true

	local nameLbl    = tooltip:FindFirstChild("TooltipName")
	local slotLbl    = tooltip:FindFirstChild("Detail_Slot")
	local statLbl    = tooltip:FindFirstChild("Detail_Stat")
	local rarityLbl  = tooltip:FindFirstChild("Detail_Rarity")
	local idLbl      = tooltip:FindFirstChild("Detail_ID")

	if nameLbl then
		nameLbl.Text = item.name or "?"
		nameLbl.TextColor3 = RARITY_COLOR[item.rarity] or Color3.new(1,1,1)
	end
	if slotLbl then
		slotLbl.Text = "Slot: <b>" .. (item.slot or "?") .. "</b>"
	end
	if statLbl then
		local label = (item.statType or "atk") == "atk" and "ATK" or "DEF"
		statLbl.Text = label .. ": <b>" .. tostring(item.stat or 0) .. "</b>"
	end
	if rarityLbl then
		local colorHex = nil
		local c = RARITY_COLOR[item.rarity]
		if c then
			colorHex = string.format("rgb(%d,%d,%d)", c.R*255, c.G*255, c.B*255)
		end
		rarityLbl.Text = "Rarity: " .. (colorHex and "<font color='"..colorHex.."'>" or "")
			.. "<b>" .. (item.rarity or "?") .. "</b>"
			.. (colorHex and "</font>" or "")
	end
	if idLbl then
		idLbl.Text = "ID: <b>" .. (item.id or "?") .. "</b>"
	end

	-- Position: to the right of the slot (convert screen-absolute → tooltipGui-relative)
	local absPos  = slotFrame.AbsolutePosition
	local absSize = slotFrame.AbsoluteSize
	local guiPos  = tooltipGui and tooltipGui.AbsolutePosition or Vector2.zero
	local guiSize = tooltipGui and tooltipGui.AbsoluteSize or Vector2.new(800, 600)

	local tipX = absPos.X + absSize.X + 6 - guiPos.X
	local tipY = absPos.Y - guiPos.Y

	-- Keep on-screen (use guiPos-relative bounds)
	local tipSize = tooltip.AbsoluteSize
	if tipSize.X < 10 then
		tipSize = Vector2.new(220, 130)
	end
	if absPos.X + absSize.X + 6 + tipSize.X > guiPos.X + guiSize.X then
		tipX = absPos.X - tipSize.X - 6 - guiPos.X
	end
	if absPos.Y + tipSize.Y > guiPos.Y + guiSize.Y then
		tipY = guiSize.Y - tipSize.Y - 4 - guiPos.Y
	end

	tooltip.Position = UDim2.fromOffset(tipX, tipY)

	-- Cancel existing tween
	if tooltipTween then
		tooltipTween:Cancel()
		tooltipTween = nil
	end

	tooltip.Visible = true
	tooltip.BackgroundTransparency = 1
	tooltipTween = TweenService:Create(tooltip, FADE_IN, { BackgroundTransparency = 0.08 })
	tooltipTween:Play()
end

local function hideTooltip()
	if not tooltip then return end
	tooltipVisible = false
	if tooltipTween then
		tooltipTween:Cancel()
		tooltipTween = nil
	end
	tooltipTween = TweenService:Create(tooltip, FADE_OUT, { BackgroundTransparency = 1 })
	tooltipTween:Play()
	tooltipTween.Completed:Once(function()
		if not tooltipVisible then
			tooltip.Visible = false
		end
	end)
end

local function acquireRefs()
	if not playerGui then return false end
	mainGui = playerGui:FindFirstChild("MainGui")
	if not mainGui then return false end
	if not tooltip or not tooltip.Parent then
		buildTooltip()
	end

	local inventoryPanel = mainGui:FindFirstChild("InventoryPanel")
	if not inventoryPanel then return false end
	local container      = inventoryPanel:FindFirstChild("InventoryContainer")
	if not container then return false end
	scrollFrame          = container:FindFirstChild("ScrollingFrame")
	if not scrollFrame then return false end
	templateSlot         = scrollFrame:FindFirstChild("InvSlot")
	if not templateSlot then return false end
	templateSlot.Visible = false
	return true
end

-- Retry until UI is ready, then flush any pending data
task.spawn(function()
	while not acquireRefs() do
		task.wait(0.5)
	end
	if pendingItems then
		refreshInventory(pendingItems)
	end
	if pendingEquip then
		refreshEquipment(pendingEquip)
	end
end)

-- ─── Local equip state ────────────────────────────────────────────────────────
local equipped = {}  -- slot → itemId

local function refreshEquipment(eq)
	equipped = {}
	if eq then
		for slot, item in pairs(eq) do
			equipped[slot] = item.id
		end
	end
	print("[refreshEquipment] Received eq, rebuilt equipped:", equipped)
	if not scrollFrame or not templateSlot then
		pendingEquip = eq
		return
	end
	pendingEquip = nil
	-- UI is fully rebuilt by refreshInventory which always fires after this.
	-- Only update stroke/attributes on existing slots for immediate visual feedback
	-- in the gap before refreshInventory arrives.
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= templateSlot then
			local childId   = child:GetAttribute("ItemId")
			local childSlot = child:GetAttribute("ItemSlot")
			local stroke    = child:FindFirstChildOfClass("UIStroke")
			local isEq = childId and childSlot and equipped[childSlot] == childId
			child:SetAttribute("ItemEquipped", isEq or false)
			if stroke then
				if isEq then
					stroke.Thickness = 3
					stroke.Color = Color3.fromRGB(0, 255, 100)
				else
					stroke.Thickness = 1.5
					stroke.Color = RARITY_COLOR[child:GetAttribute("ItemRarity")] or Color3.new(1, 1, 1)
				end
			end
			if isEq then
				print("[refreshEquipment] GREEN on slot:", childId, "(" .. (child:GetAttribute("ItemName") or "?") .. ", " .. (childSlot or "?") .. ")")
			end
		end
	end
end

-- ─── Refresh inventory display ────────────────────────────────────────────────
local function refreshInventory(items)
	if not scrollFrame or not templateSlot then
		pendingItems = items
		return
	end
	pendingItems = nil
	hideTooltip()

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
		if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
		return (a.id or "") < (b.id or "")
	end)

	for _, item in ipairs(items) do
		local ci = item
		local slot = templateSlot:Clone()
		slot.Name    = "InvSlot_" .. ci.id
		slot.Visible = true

		local icon = slot:FindFirstChild("ItemIcon")
			or slot:FindFirstChildWhichIsA("ImageLabel")
		if icon then
			icon.Image = (ci.icon ~= nil and ci.icon ~= "")
				and ci.icon or PLACEHOLDER_ICON
		end

		local label = slot:FindFirstChild("ItemLabel")
			or slot:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text       = (ci.name or "?") .. " (#" .. (ci.id or "?") .. ")"
			label.TextColor3 = RARITY_COLOR[ci.rarity] or Color3.new(1,1,1)
		end

		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			if ci.equipped then
				stroke.Thickness = 3
				stroke.Color = Color3.fromRGB(0, 255, 100)
			else
				stroke.Thickness = 1.5
				stroke.Color = RARITY_COLOR[ci.rarity] or Color3.new(1,1,1)
			end
		end

		slot:SetAttribute("ItemId",       ci.id)
		slot:SetAttribute("ItemName",     ci.name or "")
		slot:SetAttribute("ItemRarity",   ci.rarity or "")
		slot:SetAttribute("ItemSlot",     ci.slot or "")
		slot:SetAttribute("ItemStat",     ci.stat or 0)
		slot:SetAttribute("ItemStatType", ci.statType or "")
		slot:SetAttribute("ItemEquipped", ci.equipped or false)

		-- Equip/unequip on click (transparent overlay button) + hover tooltip
		if ci.slot and EQUIP_SLOTS[ci.slot] then
			local overlay = Instance.new("TextButton")
			overlay.Size                  = UDim2.new(1, 0, 1, 0)
			overlay.BackgroundTransparency = 1
			overlay.Text                  = ""
			overlay.BorderSizePixel       = 0
			overlay.AutoButtonColor       = false
			overlay.Active                = true
			overlay.ZIndex                = 5
			overlay.Parent               = slot

		overlay.MouseButton1Click:Connect(function()
			-- Read fresh state from attributes (kept in sync by refreshEquipment)
			local id       = slot:GetAttribute("ItemId")
			local eq       = slot:GetAttribute("ItemEquipped")
			local itemSlot = slot:GetAttribute("ItemSlot")
			if not id then return end

			print("[Click] ItemId:", id, "Name:", (slot:GetAttribute("ItemName") or "?"), "Slot:", itemSlot, "Equipped:", eq)
			if eq then
				UnequipRequest:FireServer(itemSlot)
			else
				EquipRequest:FireServer(id)
			end

				-- Brief click feedback flash
				local s = slot:FindFirstChildOfClass("UIStroke")
				if s then
					s.Color = Color3.new(1, 1, 1)
					s.Thickness = 4
					task.delay(0.12, function()
						if s and s.Parent then
							local curEq = slot:GetAttribute("ItemEquipped")
							local rarity = slot:GetAttribute("ItemRarity")
							if curEq then
								s.Thickness = 3
								s.Color = Color3.fromRGB(0, 255, 100)
							else
								s.Thickness = 1.5
								s.Color = RARITY_COLOR[rarity] or Color3.new(1, 1, 1)
							end
						end
					end)
				end
			end)

			overlay.MouseEnter:Connect(function()
				showTooltip(ci, slot)
			end)
			overlay.MouseLeave:Connect(hideTooltip)
		end

		slot.Parent = scrollFrame
	end

	-- Resize canvas
	task.defer(function()
		local grid = scrollFrame:FindFirstChildOfClass("UIGridLayout")
		if not grid then
			scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #items * 80)
			return
		end
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

-- ─── Remote listeners ─────────────────────────────────────────────────────────
InventoryUpdated.OnClientEvent:Connect(refreshInventory)
EquipmentUpdated.OnClientEvent:Connect(refreshEquipment)

-- ─── Load on spawn ────────────────────────────────────────────────────────────
local function loadData()
	acquireRefs()
	task.wait(0.5)
	local ok1, invResult = pcall(function()
		return GetInventory:InvokeServer()
	end)
	if ok1 and type(invResult) == "table" then
		refreshInventory(invResult)
	else
		refreshInventory({})
	end
	local ok2, eqResult = pcall(function()
		return GetEquipment:InvokeServer()
	end)
	if ok2 and type(eqResult) == "table" then
		refreshEquipment(eqResult)
	else
		refreshEquipment({})
	end
end

player.CharacterAdded:Connect(loadData)
if player.Character then
	loadData()
end