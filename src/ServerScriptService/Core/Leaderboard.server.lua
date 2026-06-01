local dataStore = game:GetService("DataStoreService")
local data = dataStore:GetDataStore("Stats")

local Players = game:GetService("Players")

local function format(number)
	local suffixes = {
		{"",    1},      -- One
		{"K",   1e3},    -- Thousand
		{"M",   1e6},    -- Million
		{"B",   1e9},    -- Billion
		{"T",   1e12},   -- Trillion
		{"Qa",  1e15},   -- Quadrillion
		{"Qn",  1e18},   -- Quintillion
		{"Sx",  1e21},   -- Sextillion
		{"Sp",  1e24},   -- Septillion
		{"Oc",  1e27},   -- Octillion
		{"No",  1e30},   -- Nonillion
		{"Dc",  1e33},   -- Decillion
		{"Ud",  1e36},   -- Undecillion
		{"Dd",  1e39},   -- Duodecillion
		{"Td",  1e42},   -- Tredecillion
		{"Qad", 1e45},   -- Quattuordecillion
		{"Qid", 1e48},   -- Quindecillion
		{"Sxd", 1e51},   -- Sexdecillion
		{"Spd", 1e54},   -- Septendecillion
		{"Ocd", 1e57},   -- Octodecillion
		{"Nod", 1e60},   -- Novemdecillion
		{"Vg",  1e63},   -- Vigintillion
		{"Uvg", 1e66},   -- Unvigintillion
		{"Dvg", 1e69},   -- Duovigintillion
		{"Tvg", 1e72},   -- Trevigintillion
		{"Qavg",1e75},   -- Quattuorvigintillion
		{"Qivg",1e78},   -- Quinvigintillion
		{"Sxvg",1e81},   -- Sexvigintillion
		{"Spvg",1e84},   -- Septenvigintillion
		{"Ocvg",1e87},   -- Octovigintillion
		{"Novg",1e90},   -- Novemvigintillion
		{"C",   1e303}   -- Centillion
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