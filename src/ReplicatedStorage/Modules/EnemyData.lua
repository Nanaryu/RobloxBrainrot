-- ReplicatedStorage/Modules/EnemyData.lua
-- Combat stats for every brainrot enemy.
-- "tier" maps loosely to zone progression (1 = starter area).
-- defense: subtracted from player raw damage (hard gate — 0 damage if below defense)
-- speed: reduced from original to compensate for removing damage split
-- spawnZones: { zoneId = weight } — dynamically picked up by ZoneData
-- wanderRange / aggroRange: AI behaviour per enemy

local EnemyData = {}

-- ─── Common (tier 1) ─────────────────────────────────────────────────────────
EnemyData["Noobini Pizzanini"]   = { tier=1, hp=30,   dmg=4,  defense=1,  speed=6,  xp=2,   gold={1,3},   lootRarity="Common",   spawnZones={ Grasslands=30 }, wanderRange=4, aggroRange=5 }
EnemyData["Lirili Larila"]       = { tier=1, hp=40,   dmg=5,  defense=2,  speed=6,  xp=3,   gold={2,4},   lootRarity="Common",   spawnZones={ Grasslands=25 }, wanderRange=4, aggroRange=5 }
EnemyData["TIM Cheese"]          = { tier=1, hp=55,   dmg=6,  defense=3,  speed=6,  xp=4,   gold={3,6},   lootRarity="Common",   spawnZones={ Grasslands=18 }, wanderRange=3, aggroRange=5 }
EnemyData["FluriFlura"]          = { tier=1, hp=65,   dmg=7,  defense=3,  speed=7,  xp=5,   gold={4,7},   lootRarity="Common",   spawnZones={ Grasslands=12 }, wanderRange=3, aggroRange=5 }
EnemyData["Talpa Di Fero"]       = { tier=1, hp=80,   dmg=8,  defense=4,  speed=7,  xp=6,   gold={5,9},   lootRarity="Common",   spawnZones={ Grasslands=8 },  wanderRange=3, aggroRange=5 }
EnemyData["Svinina Bombardino"]  = { tier=1, hp=90,   dmg=9,  defense=4,  speed=7,  xp=7,   gold={6,10},  lootRarity="Common",   spawnZones={ Grasslands=4 },  wanderRange=3, aggroRange=5 }
EnemyData["Pipi Kiwi"]           = { tier=1, hp=100,  dmg=10, defense=5,  speed=7,  xp=8,   gold={7,12},  lootRarity="Common",   spawnZones={ Grasslands=2 },  wanderRange=3, aggroRange=5 }
EnemyData["Graipuss Medussi"]    = { tier=1, hp=95,   dmg=10, defense=5,  speed=7,  xp=8,   gold={7,11},  lootRarity="Common",   spawnZones={ Grasslands=1 },  wanderRange=3, aggroRange=5 }
EnemyData["Pipi Corni"]          = { tier=1, hp=110,  dmg=12, defense=6,  speed=7,  xp=9,   gold={8,13},  lootRarity="Common",   spawnZones={ Desert=20 },     wanderRange=3, aggroRange=5 }

-- ─── Rare (tier 2) ───────────────────────────────────────────────────────────
EnemyData["Trippi Troppi"]       = { tier=2, hp=150,  dmg=14, defense=8,  speed=7,  xp=15,  gold={12,20}, lootRarity="Rare",     spawnZones={ Desert=20 },     wanderRange=3, aggroRange=5 }
EnemyData["Gangster Footera"]    = { tier=2, hp=200,  dmg=18, defense=10, speed=8,  xp=22,  gold={18,30}, lootRarity="Rare",     spawnZones={ Desert=16 },     wanderRange=3, aggroRange=5 }
EnemyData["Bandito Bobritto"]    = { tier=2, hp=220,  dmg=20, defense=11, speed=8,  xp=25,  gold={20,33}, lootRarity="Rare",     spawnZones={ Desert=14 },     wanderRange=3, aggroRange=5 }
EnemyData["Boneca Ambalabu"]     = { tier=2, hp=240,  dmg=22, defense=12, speed=8,  xp=28,  gold={22,36}, lootRarity="Rare",     spawnZones={ Desert=12 },     wanderRange=3, aggroRange=5 }
EnemyData["Cacto Hipopotamo"]    = { tier=2, hp=280,  dmg=25, defense=14, speed=7,  xp=33,  gold={25,40}, lootRarity="Rare",     spawnZones={ Desert=8 },      wanderRange=3, aggroRange=5 }
EnemyData["Ta Ta Ta Ta Sahur"]   = { tier=2, hp=300,  dmg=27, defense=15, speed=8,  xp=36,  gold={27,44}, lootRarity="Rare",     spawnZones={ Desert=5 },      wanderRange=3, aggroRange=5 }
EnemyData["Tric Trac Baraboom"]  = { tier=2, hp=340,  dmg=30, defense=16, speed=8,  xp=42,  gold={30,50}, lootRarity="Rare",     spawnZones={ Desert=3 },      wanderRange=3, aggroRange=5 }
EnemyData["Pipi Avocado"]        = { tier=2, hp=360,  dmg=32, defense=17, speed=8,  xp=45,  gold={32,52}, lootRarity="Rare",     spawnZones={ Desert=1.5 },    wanderRange=3, aggroRange=5 }
EnemyData["Bulbito Bandito Traktorito"]     = { tier=2, hp=350,  dmg=31, defense=18, speed=8,  xp=44,  gold={31,51}, lootRarity="Rare",     spawnZones={ Desert=0.5 },    wanderRange=3, aggroRange=5 }

-- ─── Epic (tier 3) ───────────────────────────────────────────────────────────
EnemyData["Cappuccino Assassino"]            = { tier=3, hp=500,  dmg=45,  defense=25, speed=9,  xp=70,  gold={50,80},   lootRarity="Epic", spawnZones={ Swamp=18 },      wanderRange=3, aggroRange=5 }
EnemyData["Brr Brr Patapim"]                = { tier=3, hp=650,  dmg=55,  defense=27, speed=9,  xp=90,  gold={65,100},  lootRarity="Epic", spawnZones={ Swamp=16 },      wanderRange=3, aggroRange=5 }
EnemyData["Trulimero Trulicina"]             = { tier=3, hp=800,  dmg=65,  defense=29, speed=9,  xp=110, gold={80,120},  lootRarity="Epic", spawnZones={ Swamp=14 },      wanderRange=3, aggroRange=5 }
EnemyData["Bambini Crostini"]               = { tier=3, hp=850,  dmg=68,  defense=30, speed=9,  xp=115, gold={85,130},  lootRarity="Epic", spawnZones={ Swamp=12 },      wanderRange=3, aggroRange=5 }
EnemyData["Bananita Dolphinita"]            = { tier=3, hp=950,  dmg=75,  defense=32, speed=10, xp=130, gold={95,145},  lootRarity="Epic", spawnZones={ Swamp=10 },      wanderRange=3, aggroRange=5 }
EnemyData["Perochello Lemonchello"]         = { tier=3, hp=1000, dmg=80,  defense=34, speed=10, xp=140, gold={100,155}, lootRarity="Epic", spawnZones={ Swamp=8 },       wanderRange=3, aggroRange=5 }
EnemyData["Brri Brri Bicus Dicus Bombicus"] = { tier=3, hp=1100, dmg=88,  defense=36, speed=10, xp=155, gold={110,170}, lootRarity="Epic", spawnZones={ Swamp=6 },       wanderRange=3, aggroRange=5 }
EnemyData["Avocadini Guffo"]                = { tier=3, hp=1300, dmg=100, defense=37, speed=10, xp=185, gold={130,200}, lootRarity="Epic", spawnZones={ Swamp=5 },       wanderRange=3, aggroRange=5 }
EnemyData["Salamino Penguino"]              = { tier=3, hp=1500, dmg=115, defense=39, speed=10, xp=210, gold={150,230}, lootRarity="Epic", spawnZones={ Swamp=4 },       wanderRange=2, aggroRange=5 }
EnemyData["Ti Ti Ti Sahur"]                 = { tier=3, hp=1400, dmg=108, defense=38, speed=10, xp=198, gold={140,215}, lootRarity="Epic", spawnZones={ Swamp=2 },       wanderRange=3, aggroRange=5 }
EnemyData["Antonio"]                   = { tier=3, hp=1600, dmg=120, defense=41, speed=10, xp=225, gold={160,245}, lootRarity="Epic", spawnZones={ Swamp=3 },       wanderRange=2, aggroRange=5 }
EnemyData["Penguino Cocosino"]              = { tier=3, hp=1750, dmg=130, defense=43, speed=10, xp=245, gold={175,265}, lootRarity="Epic", spawnZones={ Swamp=2 },       wanderRange=2, aggroRange=5 }

-- ─── Legendary (tier 4) ──────────────────────────────────────────────────────
EnemyData["Burbaloni Loliloli"]    = { tier=4, hp=2500,  dmg=180, defense=80,  speed=10, xp=350,  gold={250,400},  lootRarity="Legendary", spawnZones={ Volcano=14 },       wanderRange=3, aggroRange=5 }
EnemyData["Chimpanzini Bananini"]   = { tier=4, hp=3000,  dmg=210, defense=90,  speed=10, xp=420,  gold={300,480},  lootRarity="Legendary", spawnZones={ Volcano=12 },       wanderRange=3, aggroRange=5 }
EnemyData["Ballerina Cappuccina"]  = { tier=4, hp=5000,  dmg=300, defense=100, speed=11, xp=700,  gold={500,800},  lootRarity="Legendary", spawnZones={ Volcano=10 },       wanderRange=3, aggroRange=5 }
EnemyData["Chef Crabracadabra"]    = { tier=4, hp=6500,  dmg=370, defense=110, speed=10, xp=910,  gold={650,1000}, lootRarity="Legendary", spawnZones={ Volcano=8 },        wanderRange=3, aggroRange=5 }
EnemyData["Lionel Cactuseli"]      = { tier=4, hp=7500,  dmg=420, defense=115, speed=11, xp=1050, gold={750,1150}, lootRarity="Legendary", spawnZones={ Volcano=7 },        wanderRange=3, aggroRange=5 }
EnemyData["Glorbo Fruttodrillo"]   = { tier=4, hp=8500,  dmg=470, defense=120, speed=11, xp=1190, gold={850,1300}, lootRarity="Legendary", spawnZones={ Volcano=6 },        wanderRange=3, aggroRange=5 }
EnemyData["Blueberrinni Octopusini"]= { tier=4, hp=10000, dmg=550, defense=125, speed=11, xp=1400, gold={1000,1550},lootRarity="Legendary", spawnZones={ Volcano=5 },        wanderRange=2, aggroRange=5 }
EnemyData["Strawberrelli Flamingelli"]={ tier=4,hp=11000, dmg=600, defense=130, speed=12, xp=1540, gold={1100,1700},lootRarity="Legendary", spawnZones={ Volcano=4 },        wanderRange=2, aggroRange=5 }
EnemyData["Pandaccini Bananini"]   = { tier=4, hp=12000, dmg=650, defense=135, speed=12, xp=1680, gold={1200,1850},lootRarity="Legendary", spawnZones={ Volcano=3 },        wanderRange=2, aggroRange=5 }
EnemyData["Crabbo Limonetta"]         = { tier=4, hp=11500, dmg=625, defense=132, speed=12, xp=1610, gold={1150,1775},lootRarity="Legendary", spawnZones={ Volcano=1 },        wanderRange=2, aggroRange=5 }
EnemyData["Sigma Boy"]             = { tier=4, hp=13000, dmg=700, defense=140, speed=12, xp=1820, gold={1300,2000},lootRarity="Legendary", spawnZones={ Volcano=2 },        wanderRange=2, aggroRange=5 }
EnemyData["Sigma Girl"]            = { tier=4, hp=14000, dmg=750, defense=150, speed=12, xp=1960, gold={1400,2150},lootRarity="Legendary", spawnZones={ Volcano=2 },        wanderRange=2, aggroRange=5 }
EnemyData["Pakrahmatmamat"]      = { tier=4, hp=9000,  dmg=500, defense=110, speed=11, xp=1260, gold={900,1400}, lootRarity="Legendary", spawnZones={ Volcano=2 },        wanderRange=3, aggroRange=5 }
EnemyData["Job Job Job Sahur"]          = { tier=4, hp=13500, dmg=720, defense=145, speed=12, xp=1890, gold={1350,2075},lootRarity="Legendary", spawnZones={ Volcano=1.5 },      wanderRange=2, aggroRange=5 }
EnemyData["Avocadini Antilopini"]          = { tier=4, hp=14500, dmg=760, defense=155, speed=12, xp=2030, gold={1450,2225},lootRarity="Legendary", spawnZones={ Volcano=1 },        wanderRange=2, aggroRange=5 }

-- ─── Mythic (tier 5) ─────────────────────────────────────────────────────────
EnemyData["Frigo Camelo"]             = { tier=5, hp=20000,  dmg=1000, defense=200, speed=12, xp=3000,  gold={2000,3200},  lootRarity="Mythic" }
EnemyData["Bombardiro Crocodilo"]     = { tier=5, hp=35000,  dmg=1600, defense=250, speed=13, xp=5000,  gold={3500,5500},  lootRarity="Mythic" }
EnemyData["Bombombini Gusini"]        = { tier=5, hp=65000,  dmg=2800, defense=320, speed=13, xp=9500,  gold={6500,10000}, lootRarity="Mythic" }
EnemyData["Cavallo Virtuso"]          = { tier=5, hp=120000, dmg=5000, defense=400, speed=14, xp=18000, gold={12000,19000},lootRarity="Mythic" }
EnemyData["Gorillo Watermelondrillo"] = { tier=5, hp=140000, dmg=5600, defense=420, speed=14, xp=21000, gold={14000,22000},lootRarity="Mythic" }
EnemyData["Avocadorilla"]             = { tier=5, hp=110000, dmg=4800, defense=390, speed=14, xp=16500, gold={11000,17500},lootRarity="Mythic" }
EnemyData["Bandito Axolito"]          = { tier=5, hp=155000, dmg=6000, defense=440, speed=14, xp=23000, gold={15500,24500},lootRarity="Mythic" }
EnemyData["Ganganzelli Trulala"]      = { tier=5, hp=170000, dmg=6500, defense=460, speed=14, xp=25500, gold={17000,27000},lootRarity="Mythic" }
EnemyData["Los Bros"]                 = { tier=5, hp=200000, dmg=7500, defense=500, speed=15, xp=30000, gold={20000,32000},lootRarity="Mythic" }
EnemyData["Tigrilini Watermelini"]    = { tier=5, hp=220000, dmg=8000, defense=520, speed=15, xp=33000, gold={22000,35000},lootRarity="Mythic" }
EnemyData["To to to Sahur"]           = { tier=5, hp=245000, dmg=8800, defense=550, speed=15, xp=37000, gold={24500,39000},lootRarity="Mythic" }
EnemyData["Las Capuchinas"]     = { tier=5, hp=260000, dmg=9200, defense=570, speed=15, xp=39000, gold={26000,41500},lootRarity="Mythic" }
EnemyData["Carloo"]                   = { tier=5, hp=230000, dmg=8200, defense=530, speed=15, xp=34500, gold={23000,36500},lootRarity="Mythic" }
EnemyData["Spioniro Golubiro"]        = { tier=5, hp=45000,  dmg=2000, defense=280, speed=13, xp=7000,  gold={4500,7200},  lootRarity="Mythic", spawnZones={ Volcano=0.5 }, wanderRange=3, aggroRange=5 }

-- ─── Brainrot God (tier 6) ───────────────────────────────────────────────────
EnemyData["Coco Elefanto"]           = { tier=6, hp=500000,   dmg=20000,  defense=800,  speed=16, xp=80000,  gold={50000,80000},  lootRarity="Secret" }
EnemyData["Girafa Celestre"]         = { tier=6, hp=800000,   dmg=30000,  defense=1000, speed=16, xp=130000, gold={80000,130000}, lootRarity="Secret" }
EnemyData["Gattatino Nyanino"]       = { tier=6, hp=900000,   dmg=35000,  defense=1100, speed=17, xp=150000, gold={90000,150000}, lootRarity="Secret" }
EnemyData["Tralalero Tralala"]       = { tier=6, hp=1200000,  dmg=45000,  defense=1300, speed=17, xp=200000, gold={120000,200000},lootRarity="Secret" }
EnemyData["Espresso Signora"]        = { tier=6, hp=2000000,  dmg=65000,  defense=1600, speed=17, xp=330000, gold={200000,330000},lootRarity="Secret" }
EnemyData["Trenostruzzo Turbo 3000"] = { tier=6, hp=2500000,  dmg=80000,  defense=1800, speed=18, xp=420000, gold={250000,420000},lootRarity="Secret" }
EnemyData["Los Orcalitos"]           = { tier=6, hp=4000000,  dmg=120000, defense=2200, speed=18, xp=660000, gold={400000,660000}, lootRarity="Secret" }

-- ─── Secret / OG ──────────────────────────────────────────────────────────────
EnemyData["Las Sis"]               = { tier=7, hp=10000000,  dmg=300000,  defense=4000,  speed=19, xp=2000000,  gold={1000000,2000000},  lootRarity="Secret" }
EnemyData["La Grande Combinasion"] = { tier=7, hp=50000000,  dmg=1000000, defense=8000,  speed=19, xp=10000000, gold={5000000,10000000},  lootRarity="Secret" }
EnemyData["Dragon Cannelloni"]     = { tier=7, hp=500000000, dmg=5000000, defense=20000, speed=20, xp=100000000,gold={50000000,100000000},lootRarity="Secret" }

EnemyData["Los Tralaleritos"]        = { tier=8, hp=1000000000,dmg=10000000,defense=50000, speed=20, xp=300000000,gold={100000000,300000000},lootRarity="Secret" }
EnemyData["Strawberry Elephant"]   = { tier=8, hp=800000000, dmg=8000000, defense=45000, speed=20, xp=250000000,gold={80000000,250000000}, lootRarity="Secret" }
EnemyData["Tung Tung Tung Sahur"]                 = { tier=8, hp=1200000000,dmg=12000000,defense=55000, speed=21, xp=400000000,gold={120000000,400000000}, lootRarity="Secret" }

return EnemyData
