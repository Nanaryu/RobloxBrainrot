-- ServerScriptService/Services/KillTrackerService.lua
-- Tracks per-enemy kills and a global kill count per player.
-- Persists to DataStore. Updates the Leaderboard (Kills) on every kill.
--
-- Public API:
--   KillTrackerService.RegisterKill(player, enemyName)
--
-- Called from EnemyService._Kill (add one line there — see comment at bottom).

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")

local oldStore = DataStoreService:GetDataStore("Stats")
local killStore = DataStoreService:GetDataStore("KillTracker_v1")

local KillTrackerService = {}

-- ─── In-memory kill tables ────────────────────────────────────────────────────
-- killData[userId] = {
--   _total = 0,                        ← global kill count
--   ["Noobini Pizzanini"] = 0,         ← per-enemy counts (auto-created on first kill)
--   ...
-- }
local killData = {}

local function getData(player: Player)
	if not killData[player.UserId] then
		killData[player.UserId] = { _total = 0 }
	end
	return killData[player.UserId]
end

-- ─── DataStore helpers ────────────────────────────────────────────────────────
local function savePlayer(player: Player)
	local data = killData[player.UserId]
	if not data then return end
	pcall(function()
		killStore:SetAsync(tostring(player.UserId), data)
	end)
end

local function loadPlayer(player: Player)
	local ok, result = pcall(function()
		return killStore:GetAsync(tostring(player.UserId))
	end)
	if ok and type(result) == "table" then
		killData[player.UserId] = result
		if not killData[player.UserId]._total then
			killData[player.UserId]._total = 0
		end
	else
		killData[player.UserId] = { _total = 0 }
	end

	-- Wait for Leaderboard to create leaderstats, then overwrite Kills
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 10)
		if leaderstats then
			local kills = leaderstats:WaitForChild("Kills", 10)
			if kills then
				kills.Value = getData(player)._total
			end
		end
	end)
end

-- ─── Leaderboard sync ────────────────────────────────────────────────────────
-- Lazy-load Leaderboard to avoid circular require issues.
local Leaderboard
local function syncLeaderboard(player: Player)
	if player.leaderstats then
		local kills = player.leaderstats:FindFirstChild("Kills")
		if kills then
			kills.Value = getData(player)._total
		end
	end
end

-- ─── Public: register one kill ────────────────────────────────────────────────
function KillTrackerService.RegisterKill(player: Player, enemyName: string)
	if not player or not enemyName then return end

	local data = getData(player)

	-- Global total
	data._total += 1

	-- Per-enemy counter (key is the enemy name string)
	if not data[enemyName] then
		data[enemyName] = 0
	end
	data[enemyName] += 1

	-- Update leaderboard display
	syncLeaderboard(player)

	-- Auto-save on every kill (DataStore budget allows ~60 writes/min per key)
	savePlayer(player)

	print(string.format("[KillTracker] %s killed %s (×%d) | Total kills: %d",
		player.Name, enemyName, data[enemyName], data._total))
end

-- ─── Public: get kill count ───────────────────────────────────────────────────
-- Returns the kill count for a specific enemy, or 0 if never killed.
function KillTrackerService.GetKills(player: Player, enemyName: string): number
	local data = getData(player)
	return data[enemyName] or 0
end

-- Returns the total (global) kill count for the player.
function KillTrackerService.GetTotalKills(player: Player): number
	local data = getData(player)
	return data._total or 0
end

-- ─── Player lifecycle ─────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	loadPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	killData[player.UserId] = nil
end)

-- Handle players already in-game (Studio play-solo)
for _, player in ipairs(Players:GetPlayers()) do
	loadPlayer(player)
end

print("[KillTrackerService] Ready.")
return KillTrackerService