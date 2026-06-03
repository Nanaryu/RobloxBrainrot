-- ServerScriptService/Core/Main.server.lua
-- Bootstraps all server services in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestMove", 10)

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
