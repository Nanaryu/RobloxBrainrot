-- ReplicatedStorage/Modules/EnemyData.lua
-- Combat stats for every brainrot enemy.
-- "tier" maps loosely to zone progression (1 = starter area).

local EnemyData = {}

-- ─── Common ───────────────────────────────────────────────────────────────────
EnemyData["Noobini Pizzanini"]   = { tier=1, hp=30,   dmg=3,  speed=8,  xp=2,   gold={1,3},   lootRarity="Common"   }
EnemyData["Lirili Larila"]       = { tier=1, hp=40,   dmg=4,  speed=8,  xp=3,   gold={2,4},   lootRarity="Common"   }
EnemyData["TIM Cheese"]          = { tier=1, hp=55,   dmg=5,  speed=9,  xp=4,   gold={3,6},   lootRarity="Common"   }
EnemyData["FluriFlura"]          = { tier=1, hp=65,   dmg=6,  speed=9,  xp=5,   gold={4,7},   lootRarity="Common"   }
EnemyData["Talpa Di Fero"]       = { tier=1, hp=80,   dmg=7,  speed=9,  xp=6,   gold={5,9},   lootRarity="Common"   }
EnemyData["Svinina Bombardino"]  = { tier=1, hp=90,   dmg=8,  speed=10, xp=7,   gold={6,10},  lootRarity="Common"   }
EnemyData["Pipi Kiwi"]           = { tier=1, hp=100,  dmg=9,  speed=10, xp=8,   gold={7,12},  lootRarity="Common"   }
EnemyData["Racooni Jandelini"]   = { tier=1, hp=95,   dmg=9,  speed=10, xp=8,   gold={7,11},  lootRarity="Common"   }
EnemyData["Pipi Corni"]          = { tier=1, hp=110,  dmg=10, speed=10, xp=9,   gold={8,13},  lootRarity="Common"   }

-- ─── Rare ─────────────────────────────────────────────────────────────────────
EnemyData["Trippi Troppi"]       = { tier=2, hp=150,  dmg=14, speed=10, xp=15,  gold={12,20}, lootRarity="Rare"     }
EnemyData["Gangster Footera"]    = { tier=2, hp=200,  dmg=18, speed=11, xp=22,  gold={18,30}, lootRarity="Rare"     }
EnemyData["Bandito Bobritto"]    = { tier=2, hp=220,  dmg=20, speed=11, xp=25,  gold={20,33}, lootRarity="Rare"     }
EnemyData["Boneca Ambalabu"]     = { tier=2, hp=240,  dmg=22, speed=11, xp=28,  gold={22,36}, lootRarity="Rare"     }
EnemyData["Cacto Hipopotamo"]    = { tier=2, hp=280,  dmg=25, speed=10, xp=33,  gold={25,40}, lootRarity="Rare"     }
EnemyData["Ta Ta Ta Ta Sahur"]   = { tier=2, hp=300,  dmg=27, speed=12, xp=36,  gold={27,44}, lootRarity="Rare"     }
EnemyData["Tric Trac Baraboom"]  = { tier=2, hp=340,  dmg=30, speed=11, xp=42,  gold={30,50}, lootRarity="Rare"     }
EnemyData["Pipi Avocado"]        = { tier=2, hp=360,  dmg=32, speed=12, xp=45,  gold={32,52}, lootRarity="Rare"     }
EnemyData["Frogo Elfo"]          = { tier=2, hp=350,  dmg=31, speed=12, xp=44,  gold={31,51}, lootRarity="Rare"     }

-- ─── Epic ─────────────────────────────────────────────────────────────────────
EnemyData["Cappuccino Assassino"]            = { tier=3, hp=500,  dmg=45,  speed=13, xp=70,  gold={50,80},   lootRarity="Epic" }
EnemyData["Brr Brr Patapim"]                = { tier=3, hp=650,  dmg=55,  speed=13, xp=90,  gold={65,100},  lootRarity="Epic" }
EnemyData["Trulimero Trulicina"]             = { tier=3, hp=800,  dmg=65,  speed=13, xp=110, gold={80,120},  lootRarity="Epic" }
EnemyData["Bambini Crostini"]               = { tier=3, hp=850,  dmg=68,  speed=13, xp=115, gold={85,130},  lootRarity="Epic" }
EnemyData["Bananita Dolphinita"]            = { tier=3, hp=950,  dmg=75,  speed=14, xp=130, gold={95,145},  lootRarity="Epic" }
EnemyData["Perochello Lemonchello"]         = { tier=3, hp=1000, dmg=80,  speed=14, xp=140, gold={100,155}, lootRarity="Epic" }
EnemyData["Brri Brri Bicus Dicus Bombicus"] = { tier=3, hp=1100, dmg=88,  speed=14, xp=155, gold={110,170}, lootRarity="Epic" }
EnemyData["Avocadini Guffo"]                = { tier=3, hp=1300, dmg=100, speed=14, xp=185, gold={130,200}, lootRarity="Epic" }
EnemyData["Salamino Penguino"]              = { tier=3, hp=1500, dmg=115, speed=15, xp=210, gold={150,230}, lootRarity="Epic" }
EnemyData["Ti Ti Ti Sahur"]                 = { tier=3, hp=1400, dmg=108, speed=15, xp=198, gold={140,215}, lootRarity="Epic" }
EnemyData["Penguin Tree"]                   = { tier=3, hp=1600, dmg=120, speed=14, xp=225, gold={160,245}, lootRarity="Epic" }
EnemyData["Penguino Cocosino"]              = { tier=3, hp=1750, dmg=130, speed=15, xp=245, gold={175,265}, lootRarity="Epic" }

-- ─── Legendary ────────────────────────────────────────────────────────────────
EnemyData["Burbaloni Loliloli"]    = { tier=4, hp=2500,  dmg=180, speed=15, xp=350,  gold={250,400},  lootRarity="Legendary" }
EnemyData["Chimpazini Bananini"]   = { tier=4, hp=3000,  dmg=210, speed=15, xp=420,  gold={300,480},  lootRarity="Legendary" }
EnemyData["Ballerina Cappuccina"]  = { tier=4, hp=5000,  dmg=300, speed=16, xp=700,  gold={500,800},  lootRarity="Legendary" }
EnemyData["Chef Crabracadabra"]    = { tier=4, hp=6500,  dmg=370, speed=15, xp=910,  gold={650,1000}, lootRarity="Legendary" }
EnemyData["Lionel Cactuseli"]      = { tier=4, hp=7500,  dmg=420, speed=16, xp=1050, gold={750,1150}, lootRarity="Legendary" }
EnemyData["Glorbo Fruttodrillo"]   = { tier=4, hp=8500,  dmg=470, speed=16, xp=1190, gold={850,1300}, lootRarity="Legendary" }
EnemyData["Blueberrini Octopusini"]= { tier=4, hp=10000, dmg=550, speed=16, xp=1400, gold={1000,1550},lootRarity="Legendary" }
EnemyData["Strawberelli Flamingelli"]={ tier=4,hp=11000, dmg=600, speed=17, xp=1540, gold={1100,1700},lootRarity="Legendary" }
EnemyData["Pandaccini Bananini"]   = { tier=4, hp=12000, dmg=650, speed=17, xp=1680, gold={1200,1850},lootRarity="Legendary" }
EnemyData["Cocosini Mama"]         = { tier=4, hp=11500, dmg=625, speed=17, xp=1610, gold={1150,1775},lootRarity="Legendary" }
EnemyData["Sigma Boy"]             = { tier=4, hp=13000, dmg=700, speed=17, xp=1820, gold={1300,2000},lootRarity="Legendary" }
EnemyData["Sigma Girl"]            = { tier=4, hp=14000, dmg=750, speed=18, xp=1960, gold={1400,2150},lootRarity="Legendary" }
EnemyData["Pi Pi Watermelon"]      = { tier=4, hp=9000,  dmg=500, speed=16, xp=1260, gold={900,1400}, lootRarity="Legendary" }
EnemyData["Chocco Bunny"]          = { tier=4, hp=13500, dmg=720, speed=17, xp=1890, gold={1350,2075},lootRarity="Legendary" }
EnemyData["Sealo Regalo"]          = { tier=4, hp=14500, dmg=760, speed=18, xp=2030, gold={1450,2225},lootRarity="Legendary" }

-- ─── Mythic ───────────────────────────────────────────────────────────────────
EnemyData["Frigo Camelo"]             = { tier=5, hp=20000,  dmg=1000, speed=17, xp=3000,  gold={2000,3200},  lootRarity="Mythic" }
EnemyData["Bombardiro Crocodilo"]     = { tier=5, hp=35000,  dmg=1600, speed=18, xp=5000,  gold={3500,5500},  lootRarity="Mythic" }
EnemyData["Bombombini Gusini"]        = { tier=5, hp=65000,  dmg=2800, speed=18, xp=9500,  gold={6500,10000}, lootRarity="Mythic" }
EnemyData["Cavallo Virtuso"]          = { tier=5, hp=120000, dmg=5000, speed=19, xp=18000, gold={12000,19000},lootRarity="Mythic" }
EnemyData["Gorillo Watermelondrillo"] = { tier=5, hp=140000, dmg=5600, speed=19, xp=21000, gold={14000,22000},lootRarity="Mythic" }
EnemyData["Avocadorilla"]             = { tier=5, hp=110000, dmg=4800, speed=19, xp=16500, gold={11000,17500},lootRarity="Mythic" }
EnemyData["Tob Tobi Tobi"]            = { tier=5, hp=155000, dmg=6000, speed=19, xp=23000, gold={15500,24500},lootRarity="Mythic" }
EnemyData["Ganganzelli Trulala"]      = { tier=5, hp=170000, dmg=6500, speed=19, xp=25500, gold={17000,27000},lootRarity="Mythic" }
EnemyData["Cachorrito Melonito"]      = { tier=5, hp=200000, dmg=7500, speed=20, xp=30000, gold={20000,32000},lootRarity="Mythic" }
EnemyData["Elefanto Frigo"]           = { tier=5, hp=220000, dmg=8000, speed=20, xp=33000, gold={22000,35000},lootRarity="Mythic" }
EnemyData["Toiletto Focaccino"]       = { tier=5, hp=245000, dmg=8800, speed=20, xp=37000, gold={24500,39000},lootRarity="Mythic" }
EnemyData["Tree Tree Tree Sahur"]     = { tier=5, hp=260000, dmg=9200, speed=20, xp=39000, gold={26000,41500},lootRarity="Mythic" }
EnemyData["Carloo"]                   = { tier=5, hp=230000, dmg=8200, speed=20, xp=34500, gold={23000,36500},lootRarity="Mythic" }
EnemyData["Spioniro Golubiro"]        = { tier=5, hp=45000,  dmg=2000, speed=18, xp=7000,  gold={4500,7200},  lootRarity="Mythic" }

-- ─── Brainrot God ─────────────────────────────────────────────────────────────
EnemyData["Coco Elefanto"]           = { tier=6, hp=500000,   dmg=20000,  speed=21, xp=80000,  gold={50000,80000},  lootRarity="Secret" }
EnemyData["Girafa Celestre"]         = { tier=6, hp=800000,   dmg=30000,  speed=21, xp=130000, gold={80000,130000}, lootRarity="Secret" }
EnemyData["Gattatino Nyanino"]       = { tier=6, hp=900000,   dmg=35000,  speed=22, xp=150000, gold={90000,150000}, lootRarity="Secret" }
EnemyData["Tralalero Tralala"]       = { tier=6, hp=1200000,  dmg=45000,  speed=22, xp=200000, gold={120000,200000},lootRarity="Secret" }
EnemyData["Espresso Signora"]        = { tier=6, hp=2000000,  dmg=65000,  speed=22, xp=330000, gold={200000,330000},lootRarity="Secret" }
EnemyData["Trenostruzzo Turbo 3000"] = { tier=6, hp=2500000,  dmg=80000,  speed=23, xp=420000, gold={250000,420000},lootRarity="Secret" }
EnemyData["Los Orcalitos"]           = { tier=6, hp=4000000,  dmg=120000, speed=23, xp=660000, gold={400000,660000}, lootRarity="Secret" }

-- ─── Secret / OG ──────────────────────────────────────────────────────────────
-- These are rare world bosses. Stats are intentionally extreme.
EnemyData["Las Sis"]               = { tier=7, hp=10000000,  dmg=300000,  speed=24, xp=2000000,  gold={1000000,2000000},  lootRarity="Secret" }
EnemyData["La Grande Combinasion"] = { tier=7, hp=50000000,  dmg=1000000, speed=24, xp=10000000, gold={5000000,10000000},  lootRarity="Secret" }
EnemyData["Dragon Cannelloni"]     = { tier=7, hp=500000000, dmg=5000000, speed=25, xp=100000000,gold={50000000,100000000},lootRarity="Secret" }

EnemyData["Skibidi Toilet"]        = { tier=8, hp=1000000000,dmg=10000000,speed=25, xp=300000000,gold={100000000,300000000},lootRarity="Secret" }
EnemyData["Strawberry Elephant"]   = { tier=8, hp=800000000, dmg=8000000, speed=25, xp=250000000,gold={80000000,250000000}, lootRarity="Secret" }
EnemyData["Meowl"]                 = { tier=8, hp=1200000000,dmg=12000000,speed=26, xp=400000000,gold={120000000,400000000}, lootRarity="Secret" }

return EnemyData
