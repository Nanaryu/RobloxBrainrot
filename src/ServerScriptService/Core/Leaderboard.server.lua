local dataStore = game:GetService("DataStoreService")
local data = dataStore:GetDataStore("Stats")

local Players = game:GetService("Players")

local function format(number)
    local suffixes = {
        {"",   1},
        {"K",  1e3},
        {"M",  1e6},
        {"B",  1e9},
        {"T",  1e12},
        {"Qa", 1e15},
        {"Qn", 1e18},
        {"Sx", 1e21},
        {"Sp", 1e24},
        {"Oc", 1e27},
        {"No", 1e30},
        {"Dc", 1e33},
        {"Ud", 1e36},
        {"Dd", 1e39},
        {"Td", 1e42},
        {"Qad",1e45},
        {"Qid",1e48},
        {"Sxd",1e51},
        {"Spd",1e54},
        {"Ocd",1e57},
        {"Nod",1e60},
        {"Vg", 1e63},
        {"Uvg",1e66},
        {"Dvg",1e69},
        {"Tvg",1e72},
        {"Qavg",1e75},
        {"Qivg",1e78},
        {"Sxvg",1e81},
        {"Spvg",1e84},
        {"Ocvg",1e87},
        {"Novg",1e90},
        {"C", 1e303} -- Centillion
    }
    if number < 1000 then
        return tostring(math.floor(number))
    end

    local tier = math.floor(math.log10(number) / 3)

    if tier > #suffixes - 1 then
        tier = #suffixes - 1
    end

    local scale = 10^(tier * 3)
    local value = number / scale

    return string.format("%.1f%s", value, suffixes[tier + 1])
end



Players.PlayerAdded:Connect(function(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local level = Instance.new("NumberValue")
    level.Name = "Level"
    level.Parent = leaderstats

    local PlayerLevel = data:GetAsync(player.UserId.."-Level")
    if PlayerLevel ~= nil then
        player.leaderstats.Level.Value = format(PlayerLevel)
    end

    local kills = Instance.new("NumberValue")
    kills.Name = "Kills"
    kills.Parent = leaderstats

    local PlayerKills = data:GetAsync(player.UserId.."-Kills")
    if PlayerKills ~= nil then
        player.leaderstats.Kills.Value = format(PlayerKills)
    end

    local coins = Instance.new("NumberValue")
    coins.Name = "Coins"
    coins.Parent = leaderstats

    local PlayerCoins = data:GetAsync(player.UserId.."-Coins")
    if PlayerCoins ~= nil then
        player.leaderstats.Coins.Value = format(PlayerCoins)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local success, errorMsg = pcall(function()
        data:SetAsync(player.UserId.."-Level", player.leaderstats.Level.Value)
        data:SetAsync(player.UserId.."-Kills", player.leaderstats.Kills.Value)
        data:SetAsync(player.UserId.."-Coins", player.leaderstats.Coins.Value)
    end)
end)