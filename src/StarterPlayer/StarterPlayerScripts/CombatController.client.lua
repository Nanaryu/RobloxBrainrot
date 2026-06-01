-- StarterPlayer/StarterPlayerScripts/CombatController.client.lua
-- Passive client — the server now drives all attacking automatically.
-- Responsibilities here: HP bar sync, screen flash on taking damage, hit sound.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult  = Remotes:WaitForChild("AttackResult")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")

local player   = Players.LocalPlayer
local hrp      = nil
local humanoid = nil

local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10)
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

-- ─── Sound helper ─────────────────────────────────────────────────────────────
local function playSound(soundId, parent)
	if type(soundId) ~= "string" or soundId == "" then return end
	local s              = Instance.new("Sound")
	s.SoundId            = soundId
	s.Volume             = 0.6
	s.RollOffMaxDistance = 70
	s.Parent             = parent or workspace
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end

-- ─── HP bar sync ──────────────────────────────────────────────────────────────
EnemyHPUpdate.OnClientEvent:Connect(function(enemyId, currentHP, maxHP)
	local map     = workspace:FindFirstChild("Map")
	local enemies = map and map:FindFirstChild("Enemies")
	if not enemies then return end
	for _, model in ipairs(enemies:GetChildren()) do
		if model:GetAttribute("EnemyId") == enemyId then
			model:SetAttribute("CurrentHP", currentHP)
			model:SetAttribute("MaxHP",     maxHP)
			local bb   = model:FindFirstChild("EnemyUI")
			local bg   = bb and bb:FindFirstChild("BarBG")
			local fill = bg and bg:FindFirstChild("BarFill")
			if fill then
				local ratio = math.max(currentHP, 0) / math.max(maxHP, 1)
				fill.Size             = UDim2.new(ratio, 0, 1, 0)
				fill.BackgroundColor3 = Color3.new(
					math.min(1, 2 * (1 - ratio)),
					math.min(1, 2 * ratio),
					0.1
				)
			end
			return
		end
	end
end)

-- ─── Hit sound (server confirmed a hit this tick) ─────────────────────────────
AttackResult.OnClientEvent:Connect(function(hit)
	if hit then playSound(Config.SOUND_HIT_ID, hrp) end
end)

-- ─── Damage flash (player took a hit) ────────────────────────────────────────
TakeDamage.OnClientEvent:Connect(function(targetUserId, amount)
	if targetUserId ~= player.UserId then return end
	playSound(Config.SOUND_DAMAGE_ID, hrp)

	local gui = player.PlayerGui:FindFirstChild("DamageFlash")
	if not gui then
		gui              = Instance.new("ScreenGui")
		gui.Name         = "DamageFlash"
		gui.ResetOnSpawn = false
		gui.Parent       = player.PlayerGui
		local f                    = Instance.new("Frame")
		f.Name                     = "Flash"
		f.Size                     = UDim2.new(1, 0, 1, 0)
		f.BackgroundColor3         = Color3.fromRGB(255, 0, 0)
		f.BackgroundTransparency   = 1
		f.BorderSizePixel          = 0
		f.Parent                   = gui
	end

	local flash = gui.Flash
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end)