-- StarterPlayer/StarterPlayerScripts/DamageNumbers.client.lua
-- Spawns floating damage numbers above enemies and the local player.
--
-- AttackResult  (hit, damage, enemyId, remainingHP)  → white/yellow number over enemy
-- TakeDamage    (targetUserId, amount)               → red number over our character

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local AttackResult  = Remotes:WaitForChild("AttackResult")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")

local player = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────────────────────
local FLOAT_TIME   = 0.9    -- seconds number stays alive
local FLOAT_RISE   = 5      -- studs the number drifts upward
local SPREAD       = 1.2    -- horizontal random scatter (studs)
local FONT         = Enum.Font.GothamBold
local TEXT_SIZE    = 20     -- base pixel size

-- Colours
local COLOR_PLAYER_HIT = Color3.fromRGB(255, 255, 255)   -- white  — damage we deal
local COLOR_SELF_HIT   = Color3.fromRGB(255, 60,  60)    -- red    — damage we take

local TWEEN_INFO = TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ─── Core: spawn one number at a world position ───────────────────────────────
local function spawnNumber(worldPos: Vector3, text: string, color: Color3)
	-- Slight random horizontal offset so multiple numbers don't stack exactly
	local offset = Vector3.new(
		(math.random() - 0.5) * SPREAD,
		0,
		(math.random() - 0.5) * SPREAD
	)
	local startPos = worldPos + offset

	-- Invisible anchor part (will be tweened upward)
	local anchor      = Instance.new("Part")
	anchor.Name       = "DmgAnchor"
	anchor.Size       = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored   = true
	anchor.CanCollide = false
	anchor.CanQuery   = false
	anchor.Transparency = 1
	anchor.CFrame     = CFrame.new(startPos)
	anchor.Parent     = workspace

	-- BillboardGui parented to the anchor
	local billboard             = Instance.new("BillboardGui")
	billboard.Adornee           = anchor
	billboard.Size              = UDim2.new(0, 80, 0, 36)
	billboard.StudsOffset       = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop       = true
	billboard.ResetOnSpawn      = false
	billboard.LightInfluence    = 0
	billboard.Parent            = anchor

	local label                      = Instance.new("TextLabel")
	label.Size                       = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency     = 1
	label.Font                       = FONT
	label.TextSize                   = TEXT_SIZE
	label.TextColor3                 = color
	label.TextStrokeColor3           = Color3.new(0, 0, 0)
	label.TextStrokeTransparency     = 0.2
	label.TextScaled                 = false
	label.Text                       = text
	label.Parent                     = billboard

	-- Tween anchor upward
	local targetCF = CFrame.new(startPos + Vector3.new(0, FLOAT_RISE, 0))
	local moveTween = TweenService:Create(anchor, TWEEN_INFO, { CFrame = targetCF })

	-- Tween label to transparent (fade out in second half)
	local fadeTween = TweenService:Create(label,
		TweenInfo.new(FLOAT_TIME * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In,
			0, false, FLOAT_TIME * 0.45),   -- delay = 45 % of total time
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	moveTween:Play()
	fadeTween:Play()

	-- Clean up after animation completes
	moveTween.Completed:Connect(function()
		anchor:Destroy()
	end)
end

-- ─── Find the top of an enemy model ───────────────────────────────────────────
local function getEnemyTopPos(enemyId: string): Vector3?
	local enemiesFolder = workspace:FindFirstChild("Map")
		and workspace.Map:FindFirstChild("Enemies")
	if not enemiesFolder then return nil end

	for _, model in ipairs(enemiesFolder:GetChildren()) do
		if model:GetAttribute("EnemyId") == enemyId then
			local _, size = model:GetBoundingBox()
			local cf = model:GetPivot()
			return cf.Position + Vector3.new(0, size.Y * 0.5 + 1, 0)
		end
	end
	return nil
end

-- ─── Find the top of our own character ────────────────────────────────────────
local function getSelfTopPos(): Vector3?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position + Vector3.new(0, 3.5, 0)
end

-- ─── Remotes ──────────────────────────────────────────────────────────────────
AttackResult.OnClientEvent:Connect(function(hit: boolean, damage: number, enemyId: string)
	if not hit or not damage or damage <= 0 then return end

	local pos = getEnemyTopPos(enemyId)
	if not pos then return end

	spawnNumber(pos, tostring(damage), COLOR_PLAYER_HIT)
end)

TakeDamage.OnClientEvent:Connect(function(targetUserId: number, amount: number)
	if targetUserId ~= player.UserId then return end
	if not amount or amount <= 0 then return end

	local pos = getSelfTopPos()
	if not pos then return end

	spawnNumber(pos, "-" .. tostring(amount), COLOR_SELF_HIT)
end)
