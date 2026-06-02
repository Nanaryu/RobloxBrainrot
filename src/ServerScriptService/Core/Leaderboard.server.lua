-- ServerScriptService/Core/Leaderboard.server.lua
-- FIX: raw numbers are stored in DataStore; format() is called only at
-- display time. Previously formatted strings like "1.2K" were being saved,
-- which caused format() to error on reload and corrupt the values.

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

local data = DataStoreService:GetDataStore("Stats")

-- ─── Number formatter ─────────────────────────────────────────────────────────
local SUFFIXES = {
	{ "",     1        },
	{ "K",    1e3      },
	{ "M",    1e6      },
	{ "B",    1e9      },
	{ "T",    1e12     },
	{ "Qa",   1e15     },
	{ "Qn",   1e18     },
	{ "Sx",   1e21     },
	{ "Sp",   1e24     },
	{ "Oc",   1e27     },
	{ "No",   1e30     },
	{ "Dc",   1e33     },
	{ "Ud",   1e36     },
	{ "Dd",   1e39     },
	{ "Td",   1e42     },
	{ "Qad",  1e45     },
	{ "Qid",  1e48     },
	{ "Sxd",  1e51     },
	{ "Spd",  1e54     },
	{ "Ocd",  1e57     },
	{ "Nod",  1e60     },
	{ "Vg",   1e63     },
	{ "C",    1e303    },
}

local function format(number)
	-- Guard: ensure we have an actual number (DataStore may return nil on first load)
	if type(number) ~= "number" then return "0" end
	if number < 1000 then return tostring(math.floor(number)) end

	local tier = math.floor(math.log10(number) / 3)
	if tier > #SUFFIXES - 1 then tier = #SUFFIXES - 1 end

	local scale = 10 ^ (tier * 3)
	local value = number / scale
	return string.format("%.1f%s", value, SUFFIXES[tier + 1][1])
end

-- ─── Raw stat table per player: userId → { level, kills, coins } ──────────────
-- We keep raw numbers here so we can save them correctly and also update
-- the display value on the leaderstats NumberValues at any time.
local rawStats = {}

local function getRaw(userId)
	if not rawStats[userId] then
		rawStats[userId] = { level = 1, kills = 0, coins = 0 }
	end
	return rawStats[userId]
end

-- Push formatted display values to leaderstats (called after any change)
local function refreshDisplay(player: Player)
	local raw = getRaw(player.UserId)
	if not player.leaderstats then return end
	-- NumberValues store numbers; the leaderboard uses .Value which Roblox
	-- shows as a string in the tab UI. We keep raw numbers in the Value so
	-- other scripts can do arithmetic, and rely on format() only for labels
	-- where we control the display ourselves (e.g. a custom GUI).
	-- For the default Roblox leaderboard we just store the raw number.
	player.leaderstats.Level.Value = raw.level
	player.leaderstats.Kills.Value = raw.kills
	player.leaderstats.Coins.Value = raw.coins
end

-- ─── Public helpers (called by other services) ────────────────────────────────
-- These allow CombatService / EnemyService / etc. to increment stats.

local Leaderboard = {}

function Leaderboard.AddKill(player: Player, amount: number)
	local raw = getRaw(player.UserId)
	raw.kills += (amount or 1)
	refreshDisplay(player)
end

function Leaderboard.AddCoins(player: Player, amount: number)
	local raw = getRaw(player.UserId)
	raw.coins += (amount or 0)
	refreshDisplay(player)
end

function Leaderboard.SetLevel(player: Player, level: number)
	local raw = getRaw(player.UserId)
	raw.level = level
	refreshDisplay(player)
end

-- ─── Format helper exposed for any UI that wants pretty numbers ───────────────
Leaderboard.Format = format

-- ─── Player added ─────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	local leaderstats      = Instance.new("Folder")
	leaderstats.Name       = "leaderstats"
	leaderstats.Parent     = player

	local levelVal         = Instance.new("NumberValue")
	levelVal.Name          = "Level"
	levelVal.Value         = 1
	levelVal.Parent        = leaderstats

	local killsVal         = Instance.new("NumberValue")
	killsVal.Name          = "Kills"
	killsVal.Value         = 0
	killsVal.Parent        = leaderstats

	local coinsVal         = Instance.new("NumberValue")
	coinsVal.Name          = "Coins"
	coinsVal.Value         = 0
	coinsVal.Parent        = leaderstats

	-- Load from DataStore (raw numbers only)
	local raw = getRaw(player.UserId)
	local ok, result = pcall(function()
		return {
			level = data:GetAsync(player.UserId .. "-Level"),
			kills = data:GetAsync(player.UserId .. "-Kills"),
			coins = data:GetAsync(player.UserId .. "-Coins"),
		}
	end)
	if ok and result then
		-- GetAsync may return a formatted string from before this fix;
		-- tonumber() converts both "1.2K" (returns nil → falls back to 0)
		-- and 1200 (returns 1200) safely.
		raw.level = tonumber(result.level) or 1
		raw.kills = tonumber(result.kills) or 0
		raw.coins = tonumber(result.coins) or 0
	end

	refreshDisplay(player)
end)

-- ─── Player removing ──────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	local raw = getRaw(player.UserId)
	-- Save raw numbers, never formatted strings
	pcall(function()
		data:SetAsync(player.UserId .. "-Level", raw.level)
		data:SetAsync(player.UserId .. "-Kills", raw.kills)
		data:SetAsync(player.UserId .. "-Coins", raw.coins)
	end)
	rawStats[player.UserId] = nil
end)

return Leaderboard
