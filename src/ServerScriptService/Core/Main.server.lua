-- ServerScriptService/Core/Main.server.lua
-- Bootstraps all server services in dependency order.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestMove", 10)

-- Disable Roblox default respawning — we handle it manually
Players.CharacterAutoLoads = false

-- 1. TileGrid first — everything walks on it
local TileGridService  = require(script.Parent.Parent.Services.TileGridService)

-- 2. Movement depends on TileGrid
local MovementService  = require(script.Parent.Parent.Services.MovementService)

-- 3. Skills must load before Enemy and Combat (both use it for XP/multipliers)
local SkillService     = require(script.Parent.Parent.Services.SkillService)

-- 4. Enemy AI depends on TileGrid + Movement + Skills (defense XP)
local EnemyService     = require(script.Parent.Parent.Services.EnemyService)

-- 5. Kill tracking depends on EnemyService (registers kills on death)
local KillTrackerService = require(script.Parent.Parent.Services.KillTrackerService)

-- 6. Loot depends on ItemData (shared) and EnemyService drop hook
local LootService      = require(script.Parent.Parent.Services.LootService)

-- 7. Combat depends on Enemy + Movement + Skills (attack XP + multipliers)
local CombatService    = require(script.Parent.Parent.Services.CombatService)

-- 8. Leaderboard (ModuleScript — must be required to register event handlers)
local LeaderboardService = require(script.Parent.Leaderboard)

print("[Main] All services loaded.")

-- ─── Death / Respawn ──────────────────────────────────────────────────────────
local Config    = require(ReplicatedStorage.Modules.Config)
local Remotes   = ReplicatedStorage:WaitForChild("Remotes")
local PlayerDied    = Remotes:WaitForChild("PlayerDied")
local PlayerRespawn = Remotes:WaitForChild("PlayerRespawn")

local respawning = {} -- [userId] = true while death timer is running

local function setupDeathHandler(player: Player)
	player.CharacterAdded:Connect(function(character)
		respawning[player.UserId] = nil

		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end

		humanoid.Died:Connect(function()
			if respawning[player.UserId] then return end
			respawning[player.UserId] = true

			PlayerDied:FireClient(player)

			task.delay(Config.RESPAWN_DELAY, function()
				if not player.Parent then return end

				-- Destroy the dead character; Roblox won't auto-respawn
				-- because CharacterAutoLoads = false, so we clone manually.
				if character and character.Parent then
					character:Destroy()
				end

				-- Wait a beat for cleanup, then spawn a fresh character
				task.wait(0.3)
				if not player.Parent then return end

				player:LoadCharacter()
				PlayerRespawn:FireClient(player)

				-- Grant invincibility window
				local spawnTime = tick()
				player:SetAttribute("InvincibleUntil", spawnTime + Config.INVINCIBILITY_DURATION)
			end)
		end)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	setupDeathHandler(player)
	player:LoadCharacter()
end
Players.PlayerAdded:Connect(function(player)
	setupDeathHandler(player)
	player:LoadCharacter()
end)
