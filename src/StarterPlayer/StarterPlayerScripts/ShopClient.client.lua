-- StarterPlayer/StarterPlayerScripts/ShopClient.lua
-- LocalScript: NPC shop stock display.
-- Panel open/close is handled by LeftPanel's handler script.
-- This script listens for ShopPanel.Enabled changes and manages stock fetching + rendering.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

-- ─── Remotes ─────────────────────────────────────────────────────────────────
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local BuyShopItem     = Remotes:WaitForChild("BuyShopItem")
local ShopListUpdated = Remotes:WaitForChild("ShopListUpdated")
local GetShopList     = Remotes:WaitForChild("GetShopList")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

-- ─── Constants ───────────────────────────────────────────────────────────────
local FADE_IN  = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.1,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local PLACEHOLDER_ICON = "rbxassetid://101140058690765"

local RARITY_COLOR = Config.RARITY_COLOR
local RARITY_ORDER = Config.RARITY_ORDER

-- ─── State ───────────────────────────────────────────────────────────────────
local shopPanel    = nil
local scrollFrame  = nil
local templateSlot = nil
local tooltip      = nil
local tooltipGui   = nil
local tooltipTween = nil
local tooltipVisible = false
local currentStock = {}
local refsReady    = false

-- ─── Tooltip ─────────────────────────────────────────────────────────────────
local function buildTooltip()
	tooltipGui = Instance.new("ScreenGui")
	tooltipGui.Name = "ShopTooltipGui"
	tooltipGui.DisplayOrder = 100
	tooltipGui.ResetOnSpawn = false
	tooltipGui.IgnoreGuiInset = true
	tooltipGui.Parent = playerGui

	tooltip = Instance.new("Frame")
	tooltip.Name = "ShopTooltip"
	tooltip.Size = UDim2.new(0, 220, 0, 150)
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

	local function makeDetail(name, order)
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Detail_" .. name
		lbl.Size = UDim2.new(1, 0, 0, 16)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 14
		lbl.TextColor3 = Color3.fromRGB(180, 180, 190)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.RichText = true
		lbl.LayoutOrder = order
		return lbl
	end

	makeDetail("Slot",   3).Parent = tooltip
	makeDetail("Stat",   4).Parent = tooltip
	makeDetail("Rarity", 5).Parent = tooltip
	makeDetail("Price",  6).Parent = tooltip
end

local function showTooltip(listing, slotFrame)
	if not tooltip or not tooltip.Parent then return end
	tooltipVisible = true

	local nameLbl   = tooltip:FindFirstChild("TooltipName")
	local slotLbl   = tooltip:FindFirstChild("Detail_Slot")
	local statLbl   = tooltip:FindFirstChild("Detail_Stat")
	local rarityLbl = tooltip:FindFirstChild("Detail_Rarity")
	local priceLbl  = tooltip:FindFirstChild("Detail_Price")

	if nameLbl then
		nameLbl.Text = listing.name or "?"
		nameLbl.TextColor3 = RARITY_COLOR[listing.rarity] or Color3.new(1, 1, 1)
	end
	if slotLbl then
		slotLbl.Text = "Slot: <b>" .. (listing.slot or "?") .. "</b>"
	end
	if statLbl then
		local label = (listing.statType or "atk") == "atk" and "ATK" or "DEF"
		statLbl.Text = label .. ": <b>" .. tostring(listing.stat or 0) .. "</b>"
	end
	if rarityLbl then
		local c = RARITY_COLOR[listing.rarity]
		local colorHex = c
			and string.format("rgb(%d,%d,%d)", c.R * 255, c.G * 255, c.B * 255)
			or nil
		rarityLbl.Text = "Rarity: " .. (colorHex and "<font color='" .. colorHex .. "'>" or "")
			.. "<b>" .. (listing.rarity or "?") .. "</b>"
			.. (colorHex and "</font>" or "")
	end
	if priceLbl then
		priceLbl.Text = "Price: <b>" .. tostring(listing.price or 0) .. " coins</b>"
	end

	local absPos  = slotFrame.AbsolutePosition
	local absSize = slotFrame.AbsoluteSize
	local guiPos  = tooltipGui and tooltipGui.AbsolutePosition or Vector2.zero
	local guiSize = tooltipGui and tooltipGui.AbsoluteSize or Vector2.new(800, 600)

	local tipX = absPos.X + absSize.X + 6 - guiPos.X
	local tipY = absPos.Y - guiPos.Y

	local tipSize = tooltip.AbsoluteSize
	if tipSize.X < 10 then
		tipSize = Vector2.new(220, 150)
	end
	if absPos.X + absSize.X + 6 + tipSize.X > guiPos.X + guiSize.X then
		tipX = absPos.X - tipSize.X - 6 - guiPos.X
	end
	if absPos.Y + tipSize.Y > guiPos.Y + guiSize.Y then
		tipY = guiSize.Y - tipSize.Y - 4 - guiPos.Y
	end

	tooltip.Position = UDim2.fromOffset(tipX, tipY)

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

-- ─── UI Refs ─────────────────────────────────────────────────────────────────
local function acquireRefs(): boolean
	if not playerGui then return false end
	local mainGui = playerGui:FindFirstChild("MainGui")
	if not mainGui then return false end

	shopPanel = mainGui:FindFirstChild("ShopPanel")
	if not shopPanel then return false end
	local container = shopPanel:FindFirstChild("ShopContainer")
	if not container then return false end
	scrollFrame = container:FindFirstChild("ScrollingFrame")
	if not scrollFrame then return false end
	templateSlot = scrollFrame:FindFirstChild("ShopSlot")
	if not templateSlot then return false end
	templateSlot.Visible = false

	if not tooltip or not tooltip.Parent then
		buildTooltip()
	end
	return true
end

task.spawn(function()
	while not refsReady do
		refsReady = acquireRefs()
		if not refsReady then
			task.wait(0.5)
		end
	end
end)

-- ─── Refresh stock display ───────────────────────────────────────────────────
local function refreshStock(stock)
	currentStock = stock or {}
	hideTooltip()

	if not refsReady then return end

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= templateSlot then
			child:Destroy()
		end
	end

	if #currentStock == 0 then
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	table.sort(currentStock, function(a, b)
		local ra = RARITY_ORDER[a.rarity] or 0
		local rb = RARITY_ORDER[b.rarity] or 0
		if ra ~= rb then return ra < rb end
		if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
		return (a.id or 0) < (b.id or 0)
	end)

	for idx, listing in ipairs(currentStock) do
		local cl = listing
		local slot = templateSlot:Clone()
		slot.Name    = "ShopSlot_" .. idx
		slot.Visible = true

		local icon = slot:FindFirstChild("ItemIcon")
			or slot:FindFirstChildWhichIsA("ImageLabel")
		if icon then
			icon.Image = (cl.icon ~= nil and cl.icon ~= "")
				and cl.icon or PLACEHOLDER_ICON
		end

		local label = slot:FindFirstChild("ItemLabel")
			or slot:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text       = cl.name or "?"
			label.TextColor3 = RARITY_COLOR[cl.rarity] or Color3.new(1, 1, 1)
		end

		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 1.5
			stroke.Color = RARITY_COLOR[cl.rarity] or Color3.new(1, 1, 1)
		end

		slot:SetAttribute("ListingId",     cl.id)
		slot:SetAttribute("ListingIndex",  idx)
		slot:SetAttribute("ListingName",   cl.name or "")
		slot:SetAttribute("ListingRarity", cl.rarity or "")
		slot:SetAttribute("ListingPrice",  cl.price or 0)

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
			local listingId = slot:GetAttribute("ListingId")
			if not listingId then return end

			BuyShopItem:FireServer(listingId)

			local s = slot:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = Color3.new(1, 1, 1)
				s.Thickness = 4
				task.delay(0.12, function()
					if s and s.Parent then
						s.Thickness = 1.5
						s.Color = RARITY_COLOR[slot:GetAttribute("ListingRarity")] or Color3.new(1, 1, 1)
					end
				end)
			end
		end)

		overlay.MouseEnter:Connect(function()
			showTooltip(cl, slot)
		end)
		overlay.MouseLeave:Connect(hideTooltip)

		slot.Parent = scrollFrame
	end

	task.defer(function()
		local grid = scrollFrame:FindFirstChildOfClass("UIGridLayout")
		if not grid then
			scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #currentStock * 80)
			return
		end
		local cols = math.max(1, math.floor(
			scrollFrame.AbsoluteSize.X /
			(grid.CellSize.X.Offset + grid.CellPadding.X.Offset + 1)))
		local rows = math.ceil(#currentStock / cols)
		local cellH = grid.CellSize.Y.Offset + grid.CellPadding.Y.Offset
		local padding = scrollFrame:FindFirstChildOfClass("UIPadding")
		local padV = padding
			and (padding.PaddingTop.Offset + padding.PaddingBottom.Offset) or 0
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, rows * cellH + padV + 8)
	end)
end

-- ─── Fetch stock from server ─────────────────────────────────────────────────
local function fetchStock()
	task.spawn(function()
		local ok, result = pcall(function()
			return GetShopList:InvokeServer()
		end)
		if ok and type(result) == "table" then
			refreshStock(result)
		end
	end)
end

-- ─── React to panel open/close (handler owns Enabled) ────────────────────────
local function onShopPanelEnabledChanged()
	if not shopPanel then return end
	if shopPanel.Enabled then
		fetchStock()
	else
		hideTooltip()
	end
end

-- ─── Keyboard shortcut: B to toggle ──────────────────────────────────────────
-- Fires ShopButton click so the handler's togglePanel logic runs.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.B then return end
	if not shopPanel then return end

	-- Find the ShopButton in LeftPanel and fire its click
	local mainGui = playerGui:FindFirstChild("MainGui")
	if not mainGui then return end
	local leftPanel = mainGui:FindFirstChild("LeftPanel")
	if not leftPanel then return end
	local shopButton = leftPanel:FindFirstChild("ShopButton", true)
	if shopButton then
		-- Programmatically click by firing the handler's connection
		-- The handler listens to MouseButton1Click, so we just fire it
		for _, conn in ipairs(getconnections(shopButton.MouseButton1Click)) do
			conn:Fire()
		end
	end
end)

-- ─── Remote listeners ────────────────────────────────────────────────────────
ShopListUpdated.OnClientEvent:Connect(function(stock)
	refreshStock(stock)
end)

-- ─── Init ────────────────────────────────────────────────────────────────────
local function onCharacterAdded()
	if not acquireRefs() then
		task.spawn(function()
			while not refsReady do
				refsReady = acquireRefs()
				if not refsReady then task.wait(0.5) end
			end
		end)
	end
	task.spawn(function()
		while not refsReady do task.wait(0.2) end
		shopPanel:GetPropertyChangedSignal("Enabled"):Connect(onShopPanelEnabledChanged)
		onShopPanelEnabledChanged()
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded)
end
