-- StarterPlayer/StarterPlayerScripts/CombatController.client.lua
-- Click-to-attack system with hover highlights and walk-to-enemy.
-- Click enemy → RequestAttack → server walks player to enemy → auto-attack.
-- Also handles: HP bar sync, screen flash on damage, hit sound.
-- Skips input when TargetingController (hold-Q) is active.
--
-- FIX: Arc indicator is now driven by its own independent RenderStepped loop
-- inside CombatController, so it updates every frame regardless of whether
-- TargetingController's hold-Q mode is active. Previously refreshArc() was
-- only called on click/hover events and one RenderStepped that bailed early
-- when targeting was active — meaning the yellow "locked" ring never moved.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Config  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local AttackResult  = Remotes:WaitForChild("AttackResult")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")
local RequestAttack = Remotes:WaitForChild("RequestAttack")
local StopAttack    = Remotes:WaitForChild("StopAttack")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")

local player   = Players.LocalPlayer
local hrp      = nil
local humanoid = nil

-- Lazy-loaded reference to hold-Q targeting system
local TargetingController = nil
local function isQTargetingActive()
	if not TargetingController then
		local ok, mod = pcall(require, script.Parent:WaitForChild("TargetingController"))
		if ok then TargetingController = mod end
	end
	return TargetingController and TargetingController.IsActive()
end

-- ─── Attack / hover state ────────────────────────────────────────────────────
local currentTarget:   Model?  = nil
local currentTargetId: string? = nil
local attackMode = false

local hoveredEnemy: Model? = nil

-- ─── Arc indicator state ──────────────────────────────────────────────────────
-- The arc shows a rotating ring around the locked/hovered enemy.
-- LOCKED  (yellow) = player has clicked and is attacking this enemy
-- HOVER   (cyan)   = mouse is over an enemy but not yet clicked
local HOVER_COLOR  = Color3.fromRGB(0, 220, 255)
local LOCKED_COLOR = Color3.fromRGB(255, 220, 50)

-- ─── Find enemy model from a BasePart ─────────────────────────────────────────
local function getEnemyFromPart(part: BasePart): Model?
	local obj = part
	while obj do
		if obj:IsA("Model") and obj:GetAttribute("EnemyId") then
			return obj
		end
		obj = obj.Parent
	end
	return nil
end

-- ─── Arc indicator (driven every frame by RenderStepped) ─────────────────────
-- We drive the arc ourselves so it always follows the target regardless of
-- whether hold-Q is active.

local function getArcWorldPos(): Vector3?
	-- Priority: locked target > hovered enemy
	local model = currentTarget or hoveredEnemy
	if not model or not model.Parent then return nil end
	if model:GetAttribute("State") == "dead" then return nil end
	local pp = model.PrimaryPart
	return pp and pp.Position or model:GetPivot().Position
end

local function getArcColor(): Color3
	if currentTarget then return LOCKED_COLOR end
	return HOVER_COLOR
end

RunService.RenderStepped:Connect(function()
	if not TargetingController then
		local ok, mod = pcall(require, script.Parent:WaitForChild("TargetingController"))
		if ok then TargetingController = mod end
		if not TargetingController then return end
	end

	local wp = getArcWorldPos()
	if wp then
		TargetingController.ShowArc(wp, getArcColor())
	else
		TargetingController.HideArc()
	end
end)

-- ─── Target management ────────────────────────────────────────────────────────
local function setTarget(model: Model?)
	currentTarget   = model
	currentTargetId = model and model:GetAttribute("EnemyId") or nil
	attackMode      = model ~= nil
end

local function clearTarget()
	currentTarget   = nil
	currentTargetId = nil
	attackMode      = false
end

-- ─── Character setup ──────────────────────────────────────────────────────────
local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10)

	clearTarget()
	hoveredEnemy = nil
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

-- ─── Click-to-attack ──────────────────────────────────────────────────────────
local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	if not humanoid or humanoid.Health <= 0 then return end
	if isQTargetingActive() then return end

	local target = mouse.Target
	if not target then return end

	local enemyModel = getEnemyFromPart(target)
	if enemyModel and enemyModel:GetAttribute("State") ~= "dead" then
		local enemyId = enemyModel:GetAttribute("EnemyId")
		if enemyId then
			setTarget(enemyModel)
			RequestAttack:FireServer(enemyId)
			return
		end
	end

	-- Clicked on non-enemy → clear target
	if currentTarget then
		StopAttack:FireServer()
		clearTarget()
	end
end)

-- ─── Hover detection ──────────────────────────────────────────────────────────
mouse.Move:Connect(function()
	if not humanoid or humanoid.Health <= 0 then
		hoveredEnemy = nil
		return
	end
	if isQTargetingActive() then
		hoveredEnemy = nil
		return
	end

	local target = mouse.Target
	if not target then
		hoveredEnemy = nil
		return
	end

	local enemyModel = getEnemyFromPart(target)
	if enemyModel and enemyModel:GetAttribute("State") ~= "dead" then
		hoveredEnemy = enemyModel
	else
		hoveredEnemy = nil
	end
end)

-- ─── Escape key → deselect ────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		if currentTarget then
			StopAttack:FireServer()
			clearTarget()
		end
	end
end)

-- ─── Server confirmed hit ─────────────────────────────────────────────────────
AttackResult.OnClientEvent:Connect(function(hit, damage, enemyId)
	if hit then playSound(Config.SOUND_HIT_ID, hrp) end

	if currentTarget and currentTargetId == enemyId then
		if not currentTarget.Parent or currentTarget:GetAttribute("State") == "dead" then
			clearTarget()
		end
	end
end)

-- ─── Server says enemy died → clear target ────────────────────────────────────
EnemyDied.OnClientEvent:Connect(function(enemyId, worldPos)
	if currentTargetId == enemyId then
		clearTarget()
	end
end)

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

-- ─── Damage flash ─────────────────────────────────────────────────────────────
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

-- ─── Public API for MovementController ────────────────────────────────────────
local M = {}
function M.IsAttackMode() return attackMode end
return M