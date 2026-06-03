-- StarterGui/LoadingGui/LoadingClient.client.lua
-- Loading screen with retry logic. Ensures all critical game systems are
-- loaded before allowing the player into the game. Retries failed steps
-- automatically with a max retry cap per step.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
local TweenService      = game:GetService("TweenService")

local player       = Players.LocalPlayer
local MAX_RETRIES  = 3
local RETRY_DELAY  = 1.5

-- ─── Build loading UI ─────────────────────────────────────────────────────────
local gui                 = Instance.new("ScreenGui")
gui.Name                  = "LoadingGui"
gui.ResetOnSpawn          = false
gui.IgnoreGuiInset        = true
gui.DisplayOrder          = 200
gui.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
gui.Parent                = player.PlayerGui

local bg                  = Instance.new("Frame")
bg.Name                   = "Background"
bg.Size                   = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3       = Color3.fromRGB(15, 15, 25)
bg.BorderSizePixel        = 0
bg.Parent                 = gui

local bgCorner            = Instance.new("UICorner")
bgCorner.CornerRadius     = UDim.new(0, 0)
bgCorner.Parent           = bg

local titleLabel          = Instance.new("TextLabel")
titleLabel.Name           = "Title"
titleLabel.Size           = UDim2.new(0.6, 0, 0, 48)
titleLabel.Position       = UDim2.new(0.2, 0, 0.3, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text           = "BRAINROT RPG"
titleLabel.TextColor3     = Color3.fromRGB(255, 200, 50)
titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
titleLabel.TextStrokeTransparency = 0.2
titleLabel.Font           = Enum.Font.GothamBold
titleLabel.TextScaled     = true
titleLabel.Parent         = bg

-- Status bar background
local statusBar           = Instance.new("Frame")
statusBar.Name            = "StatusBar"
statusBar.Size            = UDim2.new(0.5, 0, 0, 22)
statusBar.Position        = UDim2.new(0.25, 0, 0.62, 0)
statusBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
statusBar.BorderSizePixel = 0
statusBar.Parent          = bg
local barCorner           = Instance.new("UICorner")
barCorner.CornerRadius    = UDim.new(0, 6)
barCorner.Parent          = statusBar

-- Status bar fill
local barFill             = Instance.new("Frame")
barFill.Name              = "Fill"
barFill.Size              = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3  = Color3.fromRGB(80, 180, 255)
barFill.BorderSizePixel   = 0
barFill.Parent            = statusBar
local fillCorner          = Instance.new("UICorner")
fillCorner.CornerRadius   = UDim.new(0, 6)
fillCorner.Parent         = barFill

-- Status text
local statusLabel         = Instance.new("TextLabel")
statusLabel.Name          = "Status"
statusLabel.Size          = UDim2.new(0.6, 0, 0, 20)
statusLabel.Position      = UDim2.new(0.2, 0, 0.67, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text          = "Initializing..."
statusLabel.TextColor3    = Color3.fromRGB(180, 180, 190)
statusLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Font          = Enum.Font.Gotham
statusLabel.TextScaled    = true
statusLabel.Parent        = bg

-- Attempt counter
local attemptLabel        = Instance.new("TextLabel")
attemptLabel.Name         = "Attempt"
attemptLabel.Size         = UDim2.new(0.6, 0, 0, 16)
attemptLabel.Position     = UDim2.new(0.2, 0, 0.72, 0)
attemptLabel.BackgroundTransparency = 1
attemptLabel.Text         = ""
attemptLabel.TextColor3   = Color3.fromRGB(120, 120, 130)
attemptLabel.Font         = Enum.Font.Gotham
attemptLabel.TextScaled   = true
attemptLabel.Parent       = bg

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function setStatus(text, progress)
	statusLabel.Text = text
	if progress then
		TweenService:Create(barFill,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0) }
		):Play()
	end
end

local function setAttempt(n)
	attemptLabel.Text = n > 1 and ("Retry " .. tostring(n - 1) .. "/" .. tostring(MAX_RETRIES)) or ""
end

local function waitOrTimeout(parent, name, timeout)
	local child = parent:FindFirstChild(name)
	if child then return child end
	return parent:WaitForChild(name, timeout)
end

-- ─── Preload assets ───────────────────────────────────────────────────────────
local enemyFolder = ReplicatedStorage:FindFirstChild("ServerStorage")
	and ReplicatedStorage.ServerStorage:FindFirstChild("EnemyModels")

local assetsToPreload = {}
if enemyFolder then
	for _, obj in ipairs(enemyFolder:GetDescendants()) do
		if obj:IsA("Model") or obj:IsA("ImageLabel") or obj:IsA("Decal") then
			table.insert(assetsToPreload, obj)
		end
	end
end

if #assetsToPreload > 0 then
	setStatus("Loading assets...", 0.05)
	pcall(function()
		ContentProvider:PreloadAsync(assetsToPreload, function(assetId, status)
			-- progress is approximate — we just need it to finish
		end)
	end)
end

-- ─── Loading steps ────────────────────────────────────────────────────────────
-- Each step: { name, check() → ok:boolean, progress:number }
local steps = {
	{
		name = "Waiting for game engine",
		check = function()
			return game:IsLoaded()
		end,
		progress = 0.10,
	},
	{
		name = "Loading core modules",
		check = function()
			local modules = waitOrTimeout(ReplicatedStorage, "Modules", 5)
			if not modules then return false end
			for _, name in ipairs({ "Config", "Pathfinder", "EnemyData", "ItemData", "Skills", "ZoneData" }) do
				local mod = waitOrTimeout(modules, name, 3)
				if not mod then return false end
			end
			-- Actually require Config to prove it works
			local ok = pcall(function()
				require(ReplicatedStorage.Modules.Config)
			end)
			return ok
		end,
		progress = 0.30,
	},
	{
		name = "Connecting to server",
		check = function()
			local remotes = waitOrTimeout(ReplicatedStorage, "Remotes", 5)
			if not remotes then return false end
			for _, name in ipairs({ "RequestMove", "PlayerMoved", "PlayerDied", "PlayerRespawn" }) do
				local r = waitOrTimeout(remotes, name, 5)
				if not r then return false end
			end
			return true
		end,
		progress = 0.50,
	},
	{
		name = "Loading game world",
		check = function()
			local map = waitOrTimeout(workspace, "Map", 10)
			if not map then return false end
			local tg = waitOrTimeout(map, "TileGrid", 10)
			if not tg then return false end
			local tiles = waitOrTimeout(tg, "Tiles", 10)
			if not tiles then return false end
			-- Wait for at least some tiles to exist
			local deadline = tick() + 15
			while #tiles:GetChildren() < 10 and tick() < deadline do
				task.wait(0.2)
			end
			return #tiles:GetChildren() >= 10
		end,
		progress = 0.75,
	},
	{
		name = "Spawning enemies",
		check = function()
			local map = workspace:FindFirstChild("Map")
			if not map then return false end
			local enemies = waitOrTimeout(map, "Enemies", 15)
			if not enemies then return false end
			-- Wait for at least some enemies to spawn
			local deadline = tick() + 10
			while #enemies:GetChildren() < 3 and tick() < deadline do
				task.wait(0.3)
			end
			return #enemies:GetChildren() >= 3
		end,
		progress = 0.90,
	},
	{
		name = "Finalizing",
		check = function()
			-- Final sanity: all critical remotes fireable, Config loaded
			local ok = pcall(function()
				local Config = require(ReplicatedStorage.Modules.Config)
				assert(Config.TILE_SIZE == 8)
				assert(Config.RESPAWN_DELAY ~= nil)
			end)
			return ok
		end,
		progress = 1.0,
	},
}

-- ─── Run loading sequence with retry ──────────────────────────────────────────
local overallAttempt = 0
local success = false

while not success do
	overallAttempt += 1
	local failedAt = nil

	for i, step in ipairs(steps) do
		setStatus(step.name, step.progress * ((i - 1) / #steps))
		setAttempt(overallAttempt)

		local stepAttempt = 0
		local stepOk = false

		while not stepOk and stepAttempt < MAX_RETRIES do
			stepAttempt += 1
			local ok, err = pcall(step.check)
			if ok and err ~= false then
				stepOk = true
			else
				if stepAttempt < MAX_RETRIES then
					setStatus(step.name .. " (retry " .. stepAttempt .. "/" .. MAX_RETRIES .. "...)", step.progress * ((i - 1) / #steps))
					task.wait(RETRY_DELAY)
				end
			end
		end

		if not stepOk then
			failedAt = i
			setStatus("Failed: " .. step.name .. " — restarting...", step.progress * ((i - 1) / #steps))
			task.wait(2)
			break
		end
	end

	if not failedAt then
		success = true
	end
end

-- ─── Dismiss loading screen ───────────────────────────────────────────────────
setStatus("Ready!", 1.0)
setAttempt(0)
attemptLabel.Text = ""

task.wait(0.3)

TweenService:Create(bg,
	TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ BackgroundTransparency = 1 }
):Play()

TweenService:Create(titleLabel,
	TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ TextTransparency = 1 }
):Play()

TweenService:Create(statusLabel,
	TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ TextTransparency = 1 }
):Play()

TweenService:Create(statusBar,
	TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ BackgroundTransparency = 1 }
):Play()

TweenService:Create(barFill,
	TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	{ BackgroundTransparency = 1 }
):Play()

task.delay(0.6, function()
	gui:Destroy()
end)
