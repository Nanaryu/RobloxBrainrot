-- StarterPlayer/StarterPlayerScripts/IsoCamera.client.lua
-- Static isometric camera. Re-acquires character on respawn.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Lock camera — must also re-lock after respawn (Roblox resets CameraType)
local function lockCamera()
	camera.CameraType = Enum.CameraType.Scriptable
end
lockCamera()

player.CharacterAdded:Connect(function()
	-- Small wait for camera to finish its respawn transition
	task.wait(0.1)
	lockCamera()
end)

-- ─── Static offset ────────────────────────────────────────────────────────────
local hAngle = math.rad(Config.CAM_HORIZONTAL_ANGLE)
local vAngle = math.rad(Config.CAM_VERTICAL_ANGLE)
local dist   = Config.CAM_DISTANCE
local hDist  = dist * math.cos(vAngle)
local vDist  = dist * math.sin(vAngle)

local CAM_OFFSET = Vector3.new(
	hDist * math.sin(hAngle),
	vDist,
	hDist * math.cos(hAngle)
)

-- ─── Follow loop ──────────────────────────────────────────────────────────────
local smoothPos = nil

RunService.RenderStepped:Connect(function(dt)
	-- Re-read character every frame so respawn is seamless
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Always re-lock in case something reset it
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local charPos = hrp.Position
	if not smoothPos then smoothPos = charPos end

	-- Framerate-independent exponential lerp
	local alpha = 1 - (1 - Config.CAM_LERP) ^ (dt * 60)
	smoothPos = smoothPos:Lerp(charPos, alpha)

	camera.CFrame = CFrame.new(smoothPos + CAM_OFFSET, smoothPos)
end)
