-- StarterPlayer/StarterPlayerScripts/CombatController.client.lua
-- Visual-only combat feedback. Proximity-based attacking is handled server-side.
-- This script handles:
--   • Red screen flash on taking damage
--   • HP bar updates on enemy billboards
--   • Pointer cursor when hovering enemies (for feel, not for click-targeting)
--   • Attack sound on hit feedback

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult  = Remotes:WaitForChild("AttackResult")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")

local player = Players.LocalPlayer
local hrp    = nil
local humanoid = nil

local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

local function isAlive()
	return humanoid ~= nil and humanoid.Health > 0
end

-- ─── Sound helper ─────────────────────────────────────────────────────────────
local function playSound(soundId, parent)
	if type(soundId) ~= "string" or soundId == "" then return end
	local sound              = Instance.new("Sound")
	sound.SoundId            = soundId
	sound.Volume             = 0.6
	sound.RollOffMaxDistance = 70
	sound.Parent             = parent or workspace
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
	task.delay(3, function()
		if sound.Parent then sound:Destroy() end
	end)
end

-- ─── HP bar update ────────────────────────────────────────────────────────────
EnemyHPUpdate.OnClientEvent:Connect(function(enemyId, currentHP, maxHP)
	local enemyFolder = workspace:FindFirstChild("Map")
		and workspace.Map:FindFirstChild("Enemies")
	if not enemyFolder then return end

	for _, model in ipairs(enemyFolder:GetChildren()) do
		if model:GetAttribute("EnemyId") == enemyId then
			model:SetAttribute("CurrentHP", currentHP)
			model:SetAttribute("MaxHP",     maxHP)

			local billboard = model:FindFirstChild("EnemyUI")
			if not billboard then return end
			local barBG = billboard:FindFirstChild("BarBG")
			if not barBG then return end
			local fill = barBG:FindFirstChild("BarFill")
			if not fill then return end

			local ratio = math.max(currentHP, 0) / math.max(maxHP, 1)
			local r = math.min(1, 2 * (1 - ratio))
			local g = math.min(1, 2 * ratio)
			fill.Size             = UDim2.new(ratio, 0, 1, 0)
			fill.BackgroundColor3 = Color3.new(r, g, 0.1)
			return
		end
	end
end)

-- ─── Attack hit sound ─────────────────────────────────────────────────────────
AttackResult.OnClientEvent:Connect(function(hit)
	if hit then
		playSound(Config.SOUND_HIT_ID, hrp)
	end
end)

-- ─── Player took damage flash ─────────────────────────────────────────────────
TakeDamage.OnClientEvent:Connect(function(targetUserId, amount)
	if targetUserId ~= player.UserId then return end
	playSound(Config.SOUND_DAMAGE_ID, hrp)

	local gui = player.PlayerGui:FindFirstChild("DamageFlash")
	if not gui then
		gui                = Instance.new("ScreenGui")
		gui.Name           = "DamageFlash"
		gui.ResetOnSpawn   = false
		gui.Parent         = player.PlayerGui
		local frame        = Instance.new("Frame")
		frame.Name         = "Flash"
		frame.Size         = UDim2.new(1, 0, 1, 0)
		frame.BackgroundColor3   = Color3.fromRGB(255, 0, 0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel    = 0
		frame.Parent             = gui
	end
	local flash = gui.Flash
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end)

-- ─── Cursor: pointer on enemy hover ──────────────────────────────────────────
local mouse = player:GetMouse()
RunService.RenderStepped:Connect(function()
	if not isAlive() then mouse.Icon = "" return end
	local hit = mouse.Target
	local m   = hit
	while m and not m:GetAttribute("EnemyId") do m = m and m.Parent end
	mouse.Icon = (m and m:GetAttribute("EnemyId")) and "rbxasset://SystemCursors/PointingHand" or ""
end)
