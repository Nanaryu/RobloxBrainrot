-- StarterPlayer/StarterPlayerScripts/CombatController.client.lua
-- Click enemy → walk to cardinal-adjacent tile → auto-attack.
-- Re-initialises character refs on respawn.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")

local RequestAttack = Remotes:WaitForChild("RequestAttack")
local AttackResult  = Remotes:WaitForChild("AttackResult")
local StopAttack    = Remotes:WaitForChild("StopAttack")
local TakeDamage    = Remotes:WaitForChild("TakeDamage")
local EnemyDied     = Remotes:WaitForChild("EnemyDied")
local EnemyHPUpdate = Remotes:WaitForChild("EnemyHPUpdate")

local MovementController = require(script.Parent:WaitForChild("MovementController"))

local player = Players.LocalPlayer
local hrp    = nil  -- updated on respawn

local stopAttacking

local function setupCharacter(character)
	hrp = character:WaitForChild("HumanoidRootPart")
	if stopAttacking then
		stopAttacking()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			if stopAttacking then
				stopAttacking()
			end
		end)
	end
end
player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

-- ─── State ────────────────────────────────────────────────────────────────────
local targetModel     = nil
local targetId        = nil
local attackActive    = false
local targetHighlight = nil

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function tileToWorld(tx, tz)
	return Vector3.new(
		(tx - 0.5) * Config.TILE_SIZE,
		Config.TILE_HEIGHT + 3.0,
		(tz - 0.5) * Config.TILE_SIZE
	)
end

local function getEnemyTile(model)
	local tx = model:GetAttribute("CurrentTileX")
	local tz = model:GetAttribute("CurrentTileZ")
	return tx, tz
end

-- Cardinal Manhattan distance
local function manhattan(ax, az, bx, bz)
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- ─── Selection highlight ──────────────────────────────────────────────────────
local function setHighlight(model)
	if targetHighlight then targetHighlight:Destroy() targetHighlight = nil end
	if not model then return end
	local highlight = Instance.new("Highlight")
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 220, 60)
	highlight.FillTransparency = 0.78
	highlight.OutlineColor = Color3.fromRGB(255, 245, 140)
	highlight.OutlineTransparency = 0
	highlight.Parent = model
	targetHighlight = highlight
end

-- ─── Stop attacking ───────────────────────────────────────────────────────────
function stopAttacking()
	attackActive  = false
	targetModel   = nil
	targetId      = nil
	setHighlight(nil)
	StopAttack:FireServer()
end

-- ─── Find the best cardinal neighbour tile for approaching enemy ──────────────
-- Returns the cardinal tile adjacent to enemy that is closest to player.
local function bestApproachTile(etx, etz, ptx, ptz)
	local cardinals = { {etx+1,etz}, {etx-1,etz}, {etx,etz+1}, {etx,etz-1} }
	local bestTx, bestTz, bestDist = ptx, ptz, math.huge
	for _, t in ipairs(cardinals) do
		local tx, tz = t[1], t[2]
		local inBounds = tx >= 1 and tz >= 1 and tx <= Config.GRID_WIDTH and tz <= Config.GRID_HEIGHT
		local d = manhattan(ptx, ptz, tx, tz)
		if inBounds and d < bestDist then
			bestDist = d
			bestTx   = tx
			bestTz   = tz
		end
	end
	return bestTx, bestTz
end

-- ─── Attack loop ──────────────────────────────────────────────────────────────
local function startAttackLoop(model, id)
	attackActive = false
	task.wait(0)

	targetModel  = model
	targetId     = id
	attackActive = true
	setHighlight(model)

	task.spawn(function()
		while attackActive and targetModel and targetModel.Parent do
			if targetModel:GetAttribute("State") == "dead" then
				stopAttacking() break
			end

			local ptx, ptz = MovementController.GetCurrentTile()
			local etx, etz = getEnemyTile(targetModel)
			if not etx then stopAttacking() break end

			local dist = manhattan(ptx, ptz, etx, etz)

			if dist == 1 then
				-- Adjacent: face enemy, fire attack
				if hrp then
					local enemyPos = tileToWorld(etx, etz)
					local myPos    = tileToWorld(ptx, ptz)
					local facedCF  = CFrame.lookAt(myPos, Vector3.new(enemyPos.X, myPos.Y, enemyPos.Z))
					TweenService:Create(hrp,
						TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ CFrame = facedCF }
					):Play()
				end
				RequestAttack:FireServer(id)
				task.wait(Config.AUTO_ATTACK_INTERVAL)

			else
				-- Walk to best cardinal tile next to enemy
				local atx, atz = bestApproachTile(etx, etz, ptx, ptz)
				MovementController.RequestMove(atx, atz)
				task.wait(Config.MOVE_TWEEN_TIME + 0.05)
			end
		end
	end)
end

-- ─── HP bar update from server ────────────────────────────────────────────────
EnemyHPUpdate.OnClientEvent:Connect(function(enemyId, currentHP, maxHP)
	-- Find the enemy model in workspace by EnemyId attribute
	local enemyFolder = workspace:FindFirstChild("Map")
		and workspace.Map:FindFirstChild("Enemies")
	if not enemyFolder then return end

	for _, model in ipairs(enemyFolder:GetChildren()) do
		if model:GetAttribute("EnemyId") == enemyId then
			-- Update the attribute so RefreshHPBar logic works
			model:SetAttribute("CurrentHP", currentHP)
			model:SetAttribute("MaxHP", maxHP)

			-- Directly update the billboard fill
			local billboard = model:FindFirstChild("EnemyUI")
			if not billboard then return end
			local barBG = billboard:FindFirstChild("BarBG")
			if not barBG then return end
			local fill = barBG:FindFirstChild("BarFill")
			if not fill then return end

			local ratio = math.max(currentHP, 0) / math.max(maxHP, 1)
			local r = math.min(1, 2 * (1 - ratio))
			local g = math.min(1, 2 * ratio)
			fill.Size = UDim2.new(ratio, 0, 1, 0)
			fill.BackgroundColor3 = Color3.new(r, g, 0.1)
			return
		end
	end
end)

-- ─── Mouse click detection ────────────────────────────────────────────────────
local mouse = player:GetMouse()

mouse.Button1Down:Connect(function()
	local hit = mouse.Target
	if not hit then return end

	local model = hit
	while model and not model:GetAttribute("EnemyId") do
		model = model.Parent
	end

	if model and model:GetAttribute("EnemyId") then
		local id = model:GetAttribute("EnemyId")
		if id ~= targetId then
			startAttackLoop(model, id)
		end
	else
		-- Clicked tile/space — cancel
		if targetModel then stopAttacking() end
	end
end)

-- ─── Escape cancels ───────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then stopAttacking() end
end)

-- ─── Enemy died ───────────────────────────────────────────────────────────────
EnemyDied.OnClientEvent:Connect(function(enemyId)
	if enemyId == targetId then stopAttacking() end
end)

-- ─── Player took damage flash ─────────────────────────────────────────────────
TakeDamage.OnClientEvent:Connect(function(targetUserId, amount)
	if targetUserId ~= player.UserId then return end
	local gui = player.PlayerGui:FindFirstChild("DamageFlash")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "DamageFlash"
		gui.ResetOnSpawn = false
		gui.Parent = player.PlayerGui
		local frame = Instance.new("Frame")
		frame.Name = "Flash"
		frame.Size = UDim2.new(1,0,1,0)
		frame.BackgroundColor3 = Color3.fromRGB(255,0,0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
	end
	local flash = gui.Flash
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end)

-- ─── Cursor hover ─────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
	local hit = mouse.Target
	local m = hit
	while m and not m:GetAttribute("EnemyId") do m = m and m.Parent end
	mouse.Icon = (m and m:GetAttribute("EnemyId")) and "rbxasset://SystemCursors/PointingHand" or ""
end)
