-- StarterPlayer/StarterPlayerScripts/IsoCamera.lua
-- Static isometric camera. Fixed angle, no user rotation.
-- WASD directions stay consistent regardless of graphics settings
-- because the camera never moves horizontally.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Lock camera type — disables all default Roblox camera behaviour
camera.CameraType = Enum.CameraType.Scriptable

-- ─── Build static offset from config angles ───────────────────────────────────
local hAngle = math.rad(Config.CAM_HORIZONTAL_ANGLE)
local vAngle = math.rad(Config.CAM_VERTICAL_ANGLE)
local dist   = Config.CAM_DISTANCE

local hDist = dist * math.cos(vAngle)
local vDist = dist * math.sin(vAngle)

-- World-space offset from character to camera
local CAM_OFFSET = Vector3.new(
	hDist * math.sin(hAngle),
	vDist,
	hDist * math.cos(hAngle)
)

-- ─── Block scroll zoom & right-drag pan ───────────────────────────────────────
-- Setting CameraType to Scriptable already does this, but we also consume
-- MouseWheel so the game doesn't accidentally zoom if something re-enables it.
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- intentionally do nothing
	end
end)

-- ─── Follow loop ──────────────────────────────────────────────────────────────
local smoothPos = nil   -- initialised on first valid frame

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local charPos = hrp.Position

	-- Initialise smoothPos to character position on first frame
	-- so the camera doesn't fly in from (0,0,0)
	if not smoothPos then
		smoothPos = charPos
	end

	-- Lerp: framerate-independent exponential smoothing
	local alpha = 1 - (1 - Config.CAM_LERP) ^ (dt * 60)
	smoothPos = smoothPos:Lerp(charPos, alpha)

	camera.CFrame = CFrame.new(smoothPos + CAM_OFFSET, smoothPos)
end)
