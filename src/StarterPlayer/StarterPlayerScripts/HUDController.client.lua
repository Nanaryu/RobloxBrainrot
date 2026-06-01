-- StarterPlayer/StarterPlayerScripts/HUDController.client.lua
-- Builds and maintains the player HUD:
--   • HP bar (top-left)
--   • Attack skill level + XP bar
--   • Defense skill level + XP bar
-- Updates reactively from SkillUpdated remote and Humanoid.HealthChanged.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Skills"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local SkillUpdated = Remotes:WaitForChild("SkillUpdated")

local player = Players.LocalPlayer

-- ─── Build GUI ────────────────────────────────────────────────────────────────
local screenGui            = Instance.new("ScreenGui")
screenGui.Name             = "HUDGui"
screenGui.ResetOnSpawn     = false
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset   = false
screenGui.Parent           = player.PlayerGui

-- ── Container (bottom-left, stacked vertically) ───────────────────────────────
local container            = Instance.new("Frame")
container.Name             = "Container"
container.Size             = UDim2.new(0, 220, 0, 130)
container.Position         = UDim2.new(0, 14, 1, -144)
container.BackgroundTransparency = 1
container.Parent           = screenGui

local layout               = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Vertical
layout.SortOrder           = Enum.SortOrder.LayoutOrder
layout.Padding             = UDim.new(0, 6)
layout.Parent              = container

-- ── Helper: build a labelled bar ──────────────────────────────────────────────
local function makeBar(parent, name, color, layoutOrder)
	local frame                  = Instance.new("Frame")
	frame.Name                   = name
	frame.Size                   = UDim2.new(1, 0, 0, 34)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder            = layoutOrder
	frame.Parent                 = parent

	-- Label row
	local label                  = Instance.new("TextLabel")
	label.Name                   = "Label"
	label.Size                   = UDim2.new(1, 0, 0, 14)
	label.Position               = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.fromRGB(230, 230, 230)
	label.TextStrokeTransparency = 0.3
	label.Font                   = Enum.Font.GothamBold
	label.TextSize               = 13
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.Text                   = name
	label.Parent                 = frame

	-- Bar background
	local bg                     = Instance.new("Frame")
	bg.Name                      = "BG"
	bg.Size                      = UDim2.new(1, 0, 0, 14)
	bg.Position                  = UDim2.new(0, 0, 0, 17)
	bg.BackgroundColor3          = Color3.fromRGB(30, 30, 30)
	bg.BackgroundTransparency    = 0.3
	bg.BorderSizePixel           = 0
	bg.Parent                    = frame
	local bgCorner               = Instance.new("UICorner")
	bgCorner.CornerRadius        = UDim.new(0, 4)
	bgCorner.Parent              = bg

	-- Bar fill
	local fill                   = Instance.new("Frame")
	fill.Name                    = "Fill"
	fill.Size                    = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3        = color
	fill.BorderSizePixel         = 0
	fill.Parent                  = bg
	local fillCorner             = Instance.new("UICorner")
	fillCorner.CornerRadius      = UDim.new(0, 4)
	fillCorner.Parent            = fill

	return frame, label, fill
end

-- ── HP bar ────────────────────────────────────────────────────────────────────
local hpFrame, hpLabel, hpFill = makeBar(container, "HP", Color3.fromRGB(80, 200, 80), 1)

-- ── Attack skill bar ──────────────────────────────────────────────────────────
local atkFrame, atkLabel, atkFill = makeBar(container, "Attack  Lv.1", Color3.fromRGB(220, 100, 60), 2)

-- ── Defense skill bar ─────────────────────────────────────────────────────────
local defFrame, defLabel, defFill = makeBar(container, "Defense  Lv.1", Color3.fromRGB(80, 140, 220), 3)

-- ─── HP update ────────────────────────────────────────────────────────────────
local function updateHP(current, max)
	local ratio = math.clamp(current / math.max(max, 1), 0, 1)
	local r = math.min(1, 2 * (1 - ratio))
	local g = math.min(1, 2 * ratio)
	TweenService:Create(hpFill,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = Color3.new(r, g, 0.1) }
	):Play()
	hpLabel.Text = string.format("HP  %d / %d", math.ceil(current), math.ceil(max))
end

-- ─── Skill update ─────────────────────────────────────────────────────────────
local function updateSkills(payload)
	if not payload then return end

	local atk = payload[Skills.ATTACK]
	if atk then
		local ratio = atk.neededXP > 0 and (atk.currentXP / atk.neededXP) or 1
		TweenService:Create(atkFill,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(ratio, 0, 1, 0) }
		):Play()
		atkLabel.Text = string.format("Attack  Lv.%d  (%d / %d xp)",
			atk.level, atk.currentXP, atk.neededXP)
	end

	local def = payload[Skills.DEFENSE]
	if def then
		local ratio = def.neededXP > 0 and (def.currentXP / def.neededXP) or 1
		TweenService:Create(defFill,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(ratio, 0, 1, 0) }
		):Play()
		defLabel.Text = string.format("Defense  Lv.%d  (%d / %d xp)",
			def.level, def.currentXP, def.neededXP)
	end
end

-- ─── Hook into character HP ───────────────────────────────────────────────────
local function setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	updateHP(humanoid.Health, humanoid.MaxHealth)
	humanoid.HealthChanged:Connect(function(health)
		updateHP(health, humanoid.MaxHealth)
	end)
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

-- ─── Hook into skill remote ───────────────────────────────────────────────────
SkillUpdated.OnClientEvent:Connect(updateSkills)
