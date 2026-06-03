-- StarterPlayer/StarterPlayerScripts/DeathScreen.client.lua
-- Handles the death screen overlay, respawn countdown, and post-respawn invincibility.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlayerDied    = Remotes:WaitForChild("PlayerDied")
local PlayerRespawn = Remotes:WaitForChild("PlayerRespawn")

local player = Players.LocalPlayer

local RESPAWN_TIME = Config.RESPAWN_DELAY

-- ─── State ────────────────────────────────────────────────────────────────────
local deathScreenGui = nil
local overlay        = nil
local titleLabel     = nil
local timerLabel     = nil
local countdownThread = nil

-- ─── Build death screen UI ────────────────────────────────────────────────────
local function buildDeathScreen()
	if deathScreenGui then return end

	deathScreenGui            = Instance.new("ScreenGui")
	deathScreenGui.Name       = "DeathScreen"
	deathScreenGui.ResetOnSpawn = false
	deathScreenGui.DisplayOrder = 100
	deathScreenGui.IgnoreGuiInset = true
	deathScreenGui.Parent     = player.PlayerGui

	overlay                = Instance.new("Frame")
	overlay.Name           = "Overlay"
	overlay.Size           = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex          = 1
	overlay.Parent          = deathScreenGui

	titleLabel                 = Instance.new("TextLabel")
	titleLabel.Name            = "Title"
	titleLabel.Size            = UDim2.new(1, 0, 0, 80)
	titleLabel.Position        = UDim2.new(0, 0, 0.35, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text            = "YOU DIED"
	titleLabel.TextColor3      = Color3.fromRGB(200, 30, 30)
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.TextTransparency = 1
	titleLabel.Font            = Enum.Font.GothamBold
	titleLabel.TextSize        = 56
	titleLabel.ZIndex          = 2
	titleLabel.Parent          = overlay

	timerLabel                 = Instance.new("TextLabel")
	timerLabel.Name            = "Timer"
	timerLabel.Size            = UDim2.new(1, 0, 0, 36)
	timerLabel.Position        = UDim2.new(0, 0, 0.50, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text            = ""
	timerLabel.TextColor3      = Color3.fromRGB(200, 200, 200)
	timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	timerLabel.TextStrokeTransparency = 0.3
	timerLabel.TextTransparency = 1
	timerLabel.Font            = Enum.Font.Gotham
	timerLabel.TextSize        = 28
	timerLabel.ZIndex          = 2
	timerLabel.Parent          = overlay
end

-- ─── Show / hide ──────────────────────────────────────────────────────────────
local function showDeathScreen(timeLeft)
	buildDeathScreen()
	deathScreenGui.Enabled = true

	TweenService:Create(overlay,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.35 }
	):Play()

	TweenService:Create(titleLabel,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }
	):Play()

	TweenService:Create(timerLabel,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0.15 }
	):Play()

	timerLabel.Text = "Respawning in " .. tostring(math.ceil(timeLeft)) .. "s"
end

local function hideDeathScreen()
	if not deathScreenGui then return end

	TweenService:Create(overlay,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	TweenService:Create(titleLabel,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1 }
	):Play()

	TweenService:Create(timerLabel,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1 }
	):Play()

	task.delay(0.4, function()
		if deathScreenGui then
			deathScreenGui.Enabled = false
		end
	end)
end

-- ─── Countdown ────────────────────────────────────────────────────────────────
local function startCountdown(totalTime)
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	showDeathScreen(totalTime)

	countdownThread = task.spawn(function()
		local remaining = totalTime
		while remaining > 0 do
			timerLabel.Text = "Respawning in " .. tostring(math.ceil(remaining)) .. "s"
			task.wait(0.25)
			remaining -= 0.25
		end
		timerLabel.Text = "Respawning..."
	end)
end

-- ─── Invincibility visual (brief flash on character) ──────────────────────────
local function watchInvincibility(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local invincibleUntil = player:GetAttribute("InvincibleUntil")
	if not invincibleUntil then return end

	local startTime = tick()
	local flashInterval = 0.18

	while tick() < invincibleUntil and humanoid.Parent do
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 0.6
			end
		end
		task.wait(flashInterval)

		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Transparency = 0
			end
		end
		task.wait(flashInterval)
	end

	-- Restore full visibility
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 0
		end
	end
end

-- ─── Connections ──────────────────────────────────────────────────────────────
PlayerDied.OnClientEvent:Connect(function()
	startCountdown(RESPAWN_TIME)
end)

PlayerRespawn.OnClientEvent:Connect(function()
	hideDeathScreen()
end)

player.CharacterAdded:Connect(function(character)
	hideDeathScreen()
	task.wait(0.1)
	watchInvincibility(character)
end)
