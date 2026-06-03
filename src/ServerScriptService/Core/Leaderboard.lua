-- ServerScriptService/Core/Leaderboard.lua
-- Proper XP-based level progression.
-- Level.Value on leaderboard is the computed level (not raw XP).
-- cumulative XP is stored server-side in rawStats and DataStore.

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage.Modules.Skills)
local data   = DataStoreService:GetDataStore("Stats")

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
	if type(number) ~= "number" then return "0" end
	if number < 1000 then return tostring(math.floor(number)) end

	local tier = math.floor(math.log10(number) / 3)
	if tier > #SUFFIXES - 1 then tier = #SUFFIXES - 1 end

	local scale = 10 ^ (tier * 3)
	local value = number / scale
	return string.format("%.1f%s", value, SUFFIXES[tier + 1][1])
end

-- ─── Raw stat table per player: userId → { totalXP, coins } ──────────────────
-- totalXP = cumulative character XP (converted to level via Skills.LevelFromXP)
local rawStats = {}

local function getRaw(userId)
	if not rawStats[userId] then
		rawStats[userId] = { totalXP = 0, coins = 0 }
	end
	return rawStats[userId]
end

-- Push display values to leaderstats
local function refreshDisplay(player: Player)
	local raw = rawStats[player.UserId]
	if not raw or not player.leaderstats then return end
	local level = Skills.LevelFromXP(raw.totalXP)
	player.leaderstats.Level.Value = level
	player.leaderstats.Coins.Value = raw.coins
end

-- ─── Public helpers (called by other services) ────────────────────────────────
local Leaderboard = {}

function Leaderboard.AddKill(player: Player, amount: number)
end

function Leaderboard.AddCoins(player: Player, amount: number)
	local raw = getRaw(player.UserId)
	raw.coins += (amount or 0)
	refreshDisplay(player)
end

-- Add character XP and recompute display level.
-- Called by EnemyService on enemy kill.
function Leaderboard.AddXP(player: Player, amount: number)
	local raw = getRaw(player.UserId)
	raw.totalXP += amount
	refreshDisplay(player)
end

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

	local raw = getRaw(player.UserId)

	-- Try new single-key format first
	local ok, result = pcall(function()
		return data:GetAsync(tostring(player.UserId))
	end)

	if ok and type(result) == "table" then
		raw.totalXP = tonumber(result.totalXP) or 0
		raw.coins   = tonumber(result.coins) or 0

		-- Migration: old data stored level, not totalXP
		if raw.totalXP == 0 and tonumber(result.level) and tonumber(result.level) > 1 then
			raw.totalXP = Skills.XP_TABLE[tonumber(result.level)] or 0
		end
	else
		-- Fall back to legacy separate keys
		local ok2, result2 = pcall(function()
			return {
				level = data:GetAsync(player.UserId .. "-Level"),
				coins = data:GetAsync(player.UserId .. "-Coins"),
			}
		end)
		if ok2 and type(result2) == "table" then
			local legacyLevel = tonumber(result2.level) or 1
			raw.totalXP = legacyLevel > 1 and (Skills.XP_TABLE[legacyLevel] or 0) or 0
			raw.coins   = tonumber(result2.coins) or 0
		end
	end

	refreshDisplay(player)
end)

-- ─── Deferred save (single key per player) ───────────────────────────────────
local pendingSaves = {}

local function scheduleSave(userId: number, raw: table)
	pendingSaves[userId] = { totalXP = raw.totalXP, coins = raw.coins }
	task.delay(0.2, function()
		if pendingSaves[userId] then
			pcall(function()
				data:SetAsync(tostring(userId), pendingSaves[userId])
			end)
			pendingSaves[userId] = nil
		end
	end)
end

local function flushSaves()
	local toSave = pendingSaves
	pendingSaves = {}
	for userId, snap in pairs(toSave) do
		pcall(function()
			data:SetAsync(tostring(userId), snap)
		end)
	end
end

-- ─── Player removing ──────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	local raw = rawStats[player.UserId]
	rawStats[player.UserId] = nil
	if not raw then return end
	scheduleSave(player.UserId, raw)
end)

game:BindToClose(function()
	flushSaves()
end)

return Leaderboard
