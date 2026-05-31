-- ServerScriptService/Core/Main.server.lua
-- Bootstraps all server services in dependency order.
-- Roblox runs Scripts in ServerScriptService automatically,
-- but explicit require order avoids race conditions.

-- 1. Remotes must exist before anything else tries to use them.
--    RemotesInit.server.lua runs in the same Core folder so it fires first
--    (Roblox runs sibling scripts in alphabetical order: M comes after R).
--    We wait for a key remote to confirm RemotesInit finished.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestMove", 10)

-- 2. TileGrid must be generated before enemies try to walk on it.
local TileGridService  = require(script.Parent.Parent.Services.TileGridService)

-- 3. Movement depends on TileGrid.
local MovementService  = require(script.Parent.Parent.Services.MovementService)

-- 4. Enemy AI depends on TileGrid + Movement.
local EnemyService     = require(script.Parent.Parent.Services.EnemyService)

-- 5. Combat depends on Enemy + Movement.
local CombatService    = require(script.Parent.Parent.Services.CombatService)

print("[Main] All services loaded.")
