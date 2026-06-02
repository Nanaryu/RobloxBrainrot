-- StarterPlayer/StarterPlayerScripts/CombatController.client.lua
-- Click-to-attack system with hover highlights and walk-to-enemy.
-- Click enemy → RequestAttack → server walks player to enemy → auto-attack.
-- Also handles: HP bar sync, screen flash on damage, hit sound.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
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

-- Attack state
local currentTarget: Model?     = nil
local currentTargetId: string?  = nil
local selectionBox: SelectionBox? = nil
local attackMode = false -- when true, MovementController skips tile clicks

-- Hover highlight state
local hoverHighlight: Highlight? = nil
local hoveredEnemy: Model? = nil

-- ─── Hover helpers (defined early so setupCharacter can call them) ────────────
local function clearHover()
	if hoverHighlight then
		hoverHighlight:Destroy()
		hoverHighlight = nil
	end
	hoveredEnemy = nil
end

local function setHover(model: Model)
	clearHover()
	if not model or not model.Parent then return end

	local adornee = model.PrimaryPart
	if not adornee then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				adornee = part
				break
			end
		end
	end
	if not adornee then return end

	hoverHighlight = Instance.new("Highlight")
	hoverHighlight.Adornee       = model
	hoverHighlight.FillColor     = Color3.fromRGB(255, 255, 255)
	hoverHighlight.FillTransparency = 0.85
	hoverHighlight.OutlineColor  = Color3.fromRGB(255, 255, 200)
	hoverHighlight.OutlineTransparency = 0.3
	hoverHighlight.DepthMode     = Enum.HighlightDepthMode.AlwaysOnTop
	hoverHighlight.Parent        = adornee
	hoveredEnemy = model
end

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

-- ─── Selection box ────────────────────────────────────────────────────────────
local function clearSelection()
	if selectionBox then
		selectionBox:Destroy()
		selectionBox = nil
	end
end

local function setSelection(model: Model)
	clearSelection()
	if not model or not model.Parent then return end

	local adornee = model.PrimaryPart
	if not adornee then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				adornee = part
				break
			end
		end
	end
	if not adornee then return end

	selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee       = adornee
	selectionBox.Color3        = Color3.fromRGB(255, 255, 0)
	selectionBox.LineThickness = 0.05
	selectionBox.SurfaceColor3 = Color3.fromRGB(255, 255, 200)
	selectionBox.SurfaceTransparency = 0.85
	selectionBox.Parent        = adornee
end

-- ─── Target management ────────────────────────────────────────────────────────
local function setTarget(model: Model?)
	currentTarget   = model
	currentTargetId = model and model:GetAttribute("EnemyId") or nil
	attackMode      = model ~= nil
	setSelection(model)
end

local function clearTarget()
	currentTarget   = nil
	currentTargetId = nil
	attackMode      = false
	clearSelection()
end

-- ─── Character setup ──────────────────────────────────────────────────────────
local function setupCharacter(character)
	hrp      = character:WaitForChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10)

	currentTarget   = nil
	currentTargetId = nil
	attackMode      = false
	if selectionBox then selectionBox:Destroy() selectionBox = nil end
	clearHover()
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

	local target = mouse.Target
	if not target then return end

	-- Check if clicked on an enemy (walk up hierarchy to find Model with EnemyId)
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
		clearHover()
		return
	end

	local target = mouse.Target
	if not target then
		clearHover()
		return
	end

	local enemyModel = getEnemyFromPart(target)
	if enemyModel and enemyModel:GetAttribute("State") ~= "dead" then
		if hoveredEnemy ~= enemyModel then
			setHover(enemyModel)
		end
	else
		clearHover()
	end
end)

-- ─── Escape key → deselect ───────────────────────────────────────────────────
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
