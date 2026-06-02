# CLAUDE.md — Brainrot RPG (Working Title)
> Load this file at the start of every session to restore full project context.
> IDE: VS Code / Code OSS + Rojo extension. Roblox Studio for testing.

---

## 🎮 Game Overview
A Roblox game inspired by **Rucoy Online** (auto-attack MMORPG), themed around enemies from **Steal a Brainrot**. Built in **Roblox Studio** with a **pixelated tile-based aesthetic**.

---

## 📁 Project Structure (current state)

```
BrainrotRPG/
├── default.project.json
├── aftman.toml
├── selene.toml
├── .gitignore
├── README.md
└── src/
    ├── ReplicatedStorage/
    │   └── Modules/
    │       ├── Config.lua                    ✅
    │       ├── EnemyData.lua                 ✅
    │       ├── ItemData.lua                  ✅  item templates, stat ranges, rarity pools
    │       ├── Pathfinder.lua                ✅
    │       ├── RerollSystem.lua              ✅
    │       ├── ZoneData.lua                  ✅  zone definitions: 5 blob zones with center+radii, colors, spawn tables
    │       └── Skills.lua                    ✅  (required by HUDController + SkillService)
    ├── ServerScriptService/
    │   ├── Core/
    │   │   ├── RemotesInit.server.lua        ✅  canonical remote creation
    │   │   ├── Main.server.lua               ✅  boots all services in dependency order
    │   │   └── Leaderboard.server.lua        ✅  Level/Coins with DataStore; Kills owned by KillTrackerService
    │   └── Services/
    │       ├── TileGridService.lua           ✅  256×256 irregular map, zone-colored tiles, noise boundary
    │       ├── MovementService.lua           ✅
    │       ├── SkillService.lua              ✅  Attack/Defense XP, level-up, SkillUpdated remote
    │       ├── EnemyService.lua              ✅  zone-based spawning, leash + return state, town boundary
    │       ├── KillTrackerService.lua        ✅  per-enemy + global kills, "KillTracker_v1" DataStore
    │       ├── LootService.lua               ✅  drop rolls, world items, auto-pickup, inventory
    │       ├── ZoneService.lua               ✅  zone lookup, safe-zone checks, random tile-in-zone
    │       └── CombatService.lua             ✅
    └── StarterPlayer/
        └── StarterPlayerScripts/
            ├── MovementBootstrap.client.lua  ✅  requires MovementController
            ├── MovementController.lua        ✅  canonical movement (no .client. suffix)
            ├── CombatController.client.lua   ✅
            ├── HUDController.client.lua      ✅  HP bar + Attack/Defense skill bars
            ├── IsoCamera.client.lua          ✅
            ├── DamageNumbers.client.lua      ✅  floating damage numbers
            └── InventoryController.client.lua ✅ dynamically generates InvSlot instances
```

**Still needed:**
```
ServerScriptService/Services/
    ShopService.lua
    DataService.lua           (full inventory/equipment persistence)
StarterPlayer/StarterPlayerScripts/
    ShopClient.lua
StarterGui/
    ShopGui
```

**Cleanup still pending:**
| File | Action |
|------|--------|
| `src/ReplicatedStorage/Remotes/RemoteInit.server.lua` | Delete — superseded by `SSS/Core/RemotesInit.server.lua` |
| `src/StarterPlayer/StarterPlayerScripts/MovementController.client.lua` | Delete — `MovementController.lua` is canonical |
| `src/StarterPlayer/StarterCharacterScripts/IsoCamera.lua` | Delete — correct copy is in `StarterPlayerScripts` |
| `src/StarterPlayer/StarterCharacterScripts/test.txt` | Delete — junk |

---

## 🔧 Rojo / project.json notes
- `Remotes` folder declared as `$className: "Folder"` — **not** a `$path`
- All remote creation in `SSS/Core/RemotesInit.server.lua`
- `Services/` = ModuleScripts (no `.server.` suffix), required by `Main.server.lua`
- `Core/` = Scripts (`.server.lua`), run automatically
- `MovementController.lua` has no `.client.` suffix but is a LocalScript via `MovementBootstrap.client.lua`

---

## ⚙️ Key Config Values (Config.lua)
| Key | Value | Notes |
|-----|-------|-------|
| TILE_SIZE | 8 studs | |
| TILE_HEIGHT | 0.5 studs | |
| GRID_WIDTH / HEIGHT | 256 × 256 | |
| MAP_NOISE_AMPLITUDE | 0.55 | Zone boundary organic wobble |
| MAP_NOISE_SEED | 42 | Change for different map shapes |
| TOWN_RADIUS | 12 tiles | Hard safe boundary — enemies blocked |
| MAX_CLICK_DISTANCE | 25 tiles | Client click-to-move range cap |
| MOVE_TWEEN_TIME | 0.18 s | player & enemy slide speed |
| AUTO_ATTACK_RANGE | 1 tile | Manhattan == 1 |
| AUTO_ATTACK_INTERVAL | 1.0 s | |
| ENEMY_ATTACK_INTERVAL | 1.5 s | |
| CAM_VERTICAL_ANGLE | 56 | Higher = more top-down, better click balance |
| ELITE_SPAWN_CHANCE | 5 % | |
| ELITE_STAR_MAX | 5 | |
| PREMIUM_NAME | "Crystals" | TBD |

---

## 🏗️ Implemented Systems

### ✅ Tile Grid (TileGridService)
- 256×256 anchored Parts under `Workspace/Map/TileGrid/Tiles`
- Irregular boundary via fractal noise (deterministic, seed = 42)
- Voronoi + noise zone assignment: each tile assigned to nearest zone centre with organic wobble
- 5 zones with unique tile colours + materials
- `TileToWorld`, `WorldToTile`, `IsWalkable`, `GetNeighbours`, `SetTileType`, `SetTileWalkable`
- `GetZone(tx, tz)` returns zone id string for a tile
- `SetTileType(tx, tz, "Water")` marks unwalkable + recolors

### ✅ Zone System (ZoneService + ZoneData)
- 5 zones: Town (safe), Grasslands (Tier 1), Desert (Tier 2), Swamp (Tier 3), Volcano (Tier 4)
- Zones are organic blobs — centre offset + radius + noise amplitude (not concentric rings)
- Town is a hard safe boundary (`TOWN_RADIUS = 12` tiles) — enemies cannot enter
- `ZoneService.GetZoneAt(tx, tz)` → zone table or nil (void tile)
- `ZoneService.IsSafeZone(tx, tz)` — true for Town only
- `ZoneService.GetRandomTileInZone(zoneId)` — random walkable tile in a zone
- `ZoneData.BuildSpawnPool(zone)` / `ZoneData.PickEnemy(zone, pool)` — weighted random enemy selection
- Each zone has `spawnDensity`, `leashRange`, and `spawnEnemies` weighted list

### ✅ Player Movement (MovementController + MovementService)
- WASD + click-to-move on `Tile_X_Z` parts
- Client tweens server-approved path; destination highlight until arrival
- Faces direction of travel; `CFrame.lookAt` tween
- Server validates, broadcasts `PlayerMoved`; other clients lerp
- Blocks non-walkable terrain, other players, enemy current/moving tiles
- Retargeting uses `requestId` to ignore stale approvals
- Single Heartbeat constant-speed mover (no stacked tweens)
- Blocked while Humanoid is dead; respawn-safe via `CharacterAdded`
- `MovementController.GetCurrentTile()`, `IsMoving()` exposed
- `MovementService.GetPlayerTile(player)` exposed

### ✅ Isometric Camera (IsoCamera.client.lua — StarterPlayerScripts)
- Scriptable camera, 45° horizontal / 56° vertical / 40 studs
- Framerate-independent exponential lerp follow; re-locks on respawn

### ✅ A* Pathfinding (Pathfinder.lua)
- Pure module, injected `isWalkable(tx,tz)` — no service deps
- Manhattan heuristic, 4-directional; goal-aware tie-breaking
- `maxNodes` cap (default 800); returns `{tx,tz}[]` start-exclusive

### ✅ Enemy System (EnemyService)
- Models in `Workspace/Map/Enemies`; clones from `ServerStorage/EnemyModels/[name]`, fallback cube
- **4-state AI**: `wander` → A* to random tile in `wanderRange`, 2–4 s pause; `chase` → re-paths toward nearest player; `attack` → faces player, damages every `ENEMY_ATTACK_INTERVAL`; `return` → walks back to spawn after leash break
- Occupied-tile set; `CurrentTileX/Z` + `MovingToTileX/Z` both player-blocking
- **Leash system**: enemy drops aggro and enters `return` state when > `leashRange` tiles from spawn
- **Town boundary**: enemies cannot path into Town zone tiles (`isPassableForEnemy` rejects safe-zone tiles)
- **Elite system**: 5 % chance, 1–5 stars, HP/DMG multiplied per Config tables
- **Overhead BillboardGui**: rarity-colored name (★ prefix) + green→red HP bar
- **Zone-based spawning**: enemies fill non-safe zones based on `spawnDensity`; weighted random picks from `ZoneData.spawnEnemies`
- **Respawn timer**: killed enemies queue respawn in their zone (8–15 s delay)
- `EnemyService.DamageEnemy(id, amount, player)`, `GetEnemy(id)`, `GetEnemyAtTile(tx, tz)`
- `_Kill` calls `KillTrackerService.RegisterKill(killer, enemyName)` and `LootService.Drop(model, killer)`

### ✅ Kill Tracker (KillTrackerService)
- `KillTrackerService.RegisterKill(player, enemyName)` — called from `EnemyService._Kill`
- Tracks `_total` (global kills) + per-enemy counters keyed by enemy name string
- Persists to `"KillTracker_v1"` DataStore (saves on every kill + PlayerRemoving)
- On load: uses `player:WaitForChild("leaderstats")` then sets `Kills.Value = _total` — wins race vs Leaderboard
- `GetKills(player, enemyName)` and `GetTotalKills(player)` exposed
- **Leaderboard.server.lua** does NOT touch `Kills` in `refreshDisplay` or `PlayerRemoving` — KillTracker owns it entirely

### ✅ Combat (CombatService + CombatController)
- **Click-to-attack**: click enemy → `RequestAttack(enemyId)` → yellow SelectionBox → auto-attack loop
- Escape key → `StopAttack` → deselect; target dies / out of range / player moves → deselect
- Server: per-player auto-attack loop at `AUTO_ATTACK_INTERVAL`; single target only
- **Damage formula** (PENDING): `(ATK_Level × BASE_ATK) / 20` to `/10`, minus enemy_DEF
- **Defense formula** (PENDING): `max(1, enemy_damage - DEF_Level)` — flat subtraction
- If accuracy = 0 (max_raw ≤ enemy_DEF): deal 0 — hard progression gate
- No damage split — Rucoy-style 1v1 targeting
- Grants ATK stat XP per hit; DEF stat XP granted in EnemyService._DamagePlayer
- Equipment stat not yet factored in (pending inventory/equip system)
- Dead players blocked from movement and combat (client + server)

### ✅ Skills (Skills.lua + SkillService.lua)
- Constants: `Skills.ATTACK`, `Skills.DEFENSE`, `Skills.MAX_LEVEL = 99`
- **Dual XP system** (two independent progression tracks):
  - Character Level XP: `xp_for_level(n) = floor(n ^ (n/1000 + 3))` — granted per enemy kill via `enemy.xp`
  - Stat XP (ATK/DEF): `stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.373))` for 0-54, `floor(n ^ (n/1000 + 2.171))` for 55-99 — 1 tick per hit (ATK) or per damage taken (DEF)
- `GrantAttackXP(player, amount)` / `GrantDefenseXP(player, amount)` — no debounce, each enemy hit grants independently
- `GetAttackBonus(player)` → `(level-1) * 0.5` flat ATK (PENDING: will use new formula)
- `GetDefenseReduction(player)` → `level / (level + 80)`, capped at 0.75 (PENDING: will use flat subtraction)
- Fires `SkillUpdated` after every grant with full payload for both skills
- Persisted to `"Skills_v1"` DataStore (saved on PlayerRemoving + BindToClose)

### ✅ Loot System (ItemData.lua + LootService.lua)
- 50+ item templates across 6 slots (weapon, offhand, helmet, chest, legs, boots), all 7 rarities
- Drop chain: `EnemyService._Kill` → `LootService.Drop` → world neon sphere in `Workspace/Map/Loot` → 0.3s pickup loop → `InventoryUpdated` remote
- Auto-pickup on exact tile (Manhattan == 0); first player wins
- In-memory `inventories[userId]`; `GetInventory` RemoteFunction wired
- Elite star count bumps item rarity tier on drop

### ✅ Inventory UI (InventoryController.client.lua)
- Listens to `InventoryUpdated` remote; calls `GetInventory` RemoteFunction on spawn
- Clears and rebuilds `ScrollingFrame` inside `InventoryPanel > InventoryContainer` on every update
- Clones `InvSlot` template for each item; sets `ItemIcon` ImageLabel + `ItemLabel` TextLabel
- `UIStroke` colored by rarity; item data stored as slot Attributes for equip system later
- Sorted by rarity ascending then name; canvas height adjusted for UIGridLayout
- Placeholder icon: `rbxassetid://101140058690765`
- Template slot children expected: `ItemIcon` (ImageLabel), `ItemLabel` (TextLabel)

### ✅ Floating Damage Numbers (DamageNumbers.client.lua)
- `AttackResult` → white number over enemy; `TakeDamage` → red number over own character
- Invisible anchor Part tweened upward 5 studs over 0.9s; label fades in second half

### ✅ HUD (HUDController.client.lua)
- Bottom-left panel: HP bar, Attack skill bar, Defense skill bar
- Reactive: `Humanoid.HealthChanged` for HP; `SkillUpdated` remote for skill bars
- Color-interpolated HP fill (green → red)

### ✅ Leaderboard (Leaderboard.server.lua)
- `leaderstats`: Level, Kills, Coins
- Level + Coins persisted in `"Stats"` DataStore; Kills excluded (owned by KillTrackerService)
- `refreshDisplay` does NOT write `Kills.Value` — KillTracker sets it directly after WaitForChild
- Large-number formatting with suffix table (K, M, B…)

### ✅ Left Panel UI (LocalScript in LeftPanel)
- Button hover: UIScale tween 1→1.1 (Back easing), icon rotation ±12°
- Click/hover sounds via `UIClickSound` / `UIHoverSound`
- Panel open: UIScale on panel root 0→1 (Back easing, 0.35s); close: instant Enabled=false
- Toggle behaviour: clicking open panel closes it; clicking another switches
- ExitButton inside each panel fires `closePanel`; gets same hover/sound treatment
- Panels: StorePanel, IndexPanel, InventoryPanel, UpgradesPanel (all disabled by default)

---

## 📡 Remotes (ReplicatedStorage.Remotes)
| Name | Dir | Args |
|------|-----|------|
| RequestMove | C→S | tx, tz, fromX, fromZ, requestId |
| PlayerMoved | S→C all | userId, tx, tz, path, requestId |
| RequestAttack | C→S | enemyId |
| AttackResult | S→C | hit, damage, enemyId, remainingHP |
| StopAttack | C→S | — |
| TakeDamage | S→C | targetUserId, amount |
| EnemyDied | S→C all | enemyId, worldPosition |
| EnemyHPUpdate | S→C all | enemyId, currentHP, maxHP |
| SkillUpdated | S→C | { Attack={…}, Defense={…} } |
| ItemDropped | S→C | itemData, worldPosition |
| InventoryUpdated | S→C | serialisedInventory |
| RerollRequest | C→S | itemId×3 |
| RerollResult | S→C | newItemData \| false |
| OpenShopRequest | C→S | durationIndex |
| BuyFromShop | C→S | shopOwnerId, listingId |
| ShopListUpdated | S→C | shopData |
| GetInventory | C→S fn | → inventory |
| GetNearbyShops | C→S fn | → shop list |

---

## 🎯 Rarity System
| Tier | Name | RGB | Weight |
|------|------|-----|--------|
| 1 | Common | 180,180,180 | 1000 |
| 2 | Rare | 80,120,255 | 400 |
| 3 | VeryRare | 50,200,180 | 150 |
| 4 | Epic | 163,53,238 | 60 |
| 5 | Legendary | 255,165,0 | 20 |
| 6 | Mythic | 220,20,60 | 5 |
| 7 | Secret | 255,215,0 | 1 |

Reroll: 3 items → weighted roll between lowest input rarity and (highest+1), capped at Secret.

---

## 👾 Enemy Roster (full stats in EnemyData.lua)
**Common** (tier 1): Noobini Pizzanini, Lirili Larila, TIM Cheese, FluriFlura, Talpa Di Fero, Svinina Bombardino, Pipi Kiwi, Racooni Jandelini, Pipi Corni  
**Rare** (tier 2): Trippi Troppi, Gangster Footera, Bandito Bobritto, Boneca Ambalabu, Cacto Hipopotamo, Ta Ta Ta Ta Sahur, Tric Trac Baraboom, Pipi Avocado, Frogo Elfo  
**Epic** (tier 3): Cappuccino Assassino, Brr Brr Patapim, Trulimero Trulicina, Bambini Crostini, Bananita Dolphinita, Perochello Lemonchello, Brri Brri Bicus Dicus Bombicus, Avocadini Guffo, Salamino Penguino, Ti Ti Ti Sahur, Penguin Tree, Penguino Cocosino  
**Legendary** (tier 4): Burbaloni Loliloli, Chimpazini Bananini, Ballerina Cappuccina, Chef Crabracadabra, Lionel Cactuseli, Glorbo Fruttodrillo, Blueberrini Octopusini, Strawberelli Flamingelli, Pandaccini Bananini, Cocosini Mama, Sigma Boy, Sigma Girl, Pi Pi Watermelon, Chocco Bunny, Sealo Regalo  
**Mythic** (tier 5): Frigo Camelo, Bombardiro Crocodilo, Bombombini Gusini, Cavallo Virtuso, Gorillo Watermelondrillo, Avocadorilla, Tob Tobi Tobi, Ganganzelli Trulala, Cachorrito Melonito, Elefanto Frigo, Toiletto Focaccino, Tree Tree Tree Sahur, Carloo, Spioniro Golubiro  
**Brainrot God** (tier 6): Coco Elefanto, Girafa Celestre, Gattatino Nyanino, Tralalero Tralala, Espresso Signora, Trenostruzzo Turbo 3000, Los Orcalitos  
**Secret** (tier 7): Las Sis, La Grande Combinasion, Dragon Cannelloni  
**OG** (tier 8): Skibidi Toilet, Strawberry Elephant, Meowl  

---

## ✅ Build Progress
- [x] Tile grid generation
- [x] Smooth tile-based player movement (WASD + click)
- [x] Player facing direction on move
- [x] Isometric camera
- [x] A* pathfinding module
- [x] Enemy spawning + wander AI
- [x] Enemy chase + attack AI
- [x] Elite enemy variants (stars, stat multipliers)
- [x] Overhead enemy UI (name, rarity color, HP bar)
- [x] Player click-to-attack + auto-attack loop
- [x] Enemy aggro on damage
- [x] Screen flash on player taking damage
- [x] Attack / Defense skill system with XP and level-ups
- [x] Player HUD (HP bar, Attack XP bar, Defense XP bar)
- [x] Leaderboard with DataStore (Level, Coins)
- [x] Kill tracking with DataStore persistence (per-enemy + global)
- [x] Floating damage numbers
- [x] Loot drops (ItemData + LootService)
- [x] Inventory UI (dynamic slot generation on item pickup)
- [x] Left panel UI (hover anims, sounds, panel open/close)
- [x] Sound effect hooks (placeholder IDs)
- [x] Death input lockout (movement + combat)
- [x] Map expansion (256×256 Voronoi + noise blob zones)
- [x] Zone system (5 organic blobs: Town + 4 biome quadrants)
- [x] Zone-based enemy spawning with density + respawn timer
- [x] Safe zone (Brainrot Town — 12 tile radius, no enemies)
- [x] Enemy leash system (return-to-spawn after exceeding leash range)
- [x] Click-to-move distance cap (25 tiles)
- [ ] Item equip system + player stat scaling
- [ ] Item reroll UI
- [ ] Full DataStore persistence (inventory, equipment)
- [ ] NPC shop (premium currency)
- [ ] Offline player shops
- [ ] Full death/respawn flow polish
- [ ] Game name
- [ ] Rucoy-style damage formula (multiplicative ATK × baseATK, flat DEF subtraction)
- [ ] Click-to-attack enemy selection (restore RequestAttack/StopAttack flow)
- [ ] Dual XP system (character level from kills + stat XP from using skills)
- [ ] Enemy speed nerf (reduce by 2-3 across all tiers)

---

## 📝 Open Decisions
- [ ] Game name
- [ ] Item slots (sword, staff, shield, helmet, chest, legs, boots?)
- [ ] Respawn mechanic (timer? cost? safe zone?)
- [ ] Premium currency final name (currently "Crystals")
- [ ] Offline shop slot limit and duration tiers

---

## 🔑 Key Implementation Notes
- **Kill tracking ownership**: KillTrackerService is sole owner of kill counts. Leaderboard.server.lua does NOT write `Kills.Value` in `refreshDisplay` or save it in `PlayerRemoving`. KillTracker sets `leaderstats.Kills.Value` via `WaitForChild` after load to win the race condition.
- **DataStores in use**: `"Stats"` (Level, Coins via Leaderboard), `"KillTracker_v1"` (kills via KillTrackerService), `"Skills_v1"` (Attack/Defense XP via SkillService), `"Inventory_v1"` (inventory via LootService) — all saved on PlayerRemoving + BindToClose only (batched, no per-kill writes)
- Enemy defense reduction: `level / (level + 80)` capped at 0.75
- Attack bonus: `(level-1) * 0.5` flat, added before ±10% roll
- Attack XP: 1 per enemy hit (CombatService); Defense XP: 1 per hit taken (EnemyService._DamagePlayer)
- `SkillUpdated` fires after every XP grant + on CharacterAdded (0.5s delay) for HUD init
- Loot drop chain: `EnemyService._Kill` → `KillTrackerService.RegisterKill` + `LootService.Drop` → world Part → pickup loop → `InventoryUpdated`
- `ItemData._byRarity[rarityName]` pre-built array for fast random picks
- Inventory slot template children must be named `ItemIcon` (ImageLabel) and `ItemLabel` (TextLabel)
- Main.server.lua boot order: TileGrid → Movement → Skills → Enemy → KillTracker → Loot → Combat

---

## 🎯 Rucoy Online Formulas (reference: `damage_formulas/formulas.js`)

### Character Level XP (grind rate section)
```
xp_for_level(n) = floor(n ^ (n/1000 + 3))
```
- Level 1 = 1, Level 10 ≈ 1,260, Level 50 ≈ 163K, Level 99 ≈ 1.1M cumulative
- Granted per enemy kill: `enemy.xp` value from EnemyData

### Stat XP — ATK / DEF (stat rate section)
```
stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.373))   -- levels 0–54
stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.171))   -- levels 55–99
```
- 1 tick per auto-attack hit → ATK levels up
- 1 tick per damage taken → DEF levels up
- Separate from character level (two independent progression tracks)

### Damage Formula (auto-attack)
```
baseATK = Config.BASE_ATK (10, scales with equipment later)
min_raw = (ATK_Level × baseATK) / 20
max_raw = (ATK_Level × baseATK) / 10
accuracy = clamp((max_raw - enemy_DEF) / (max_raw - min_raw), 0, 1)
```
- If accuracy = 0 (max_raw ≤ enemy_DEF): deal 0 damage — hard progression gate
- If accuracy > 0: roll `random(min_raw, max_raw) - enemy_DEF`
- No damage split — single target only (player-selected via click-to-attack)
- Source: `formulas.js` lines 45-54, 76-88, 100-118

### Defense Formula (player taking damage)
```
final_damage = max(1, enemy_damage - DEF_Level)
```
- Flat subtraction, no cap, no %
- DEF 15 → tier 1 enemies (dmg 3-10) deal 1 damage
- DEF 50 → tier 2 enemies (dmg 14-32) deal 1 damage
- Source: Rucoy wiki — mob damage reduced by player DEF level

### Enemy Defense Values (EnemyData)
| Tier | Defense Range | Example |
|------|--------------|---------|
| 1 (Common) | 2-8 | Noobini: 2, Pipi Kiwi: 6 |
| 2 (Rare) | 12-25 | Trippi Troppi: 12, Frogo Elfo: 22 |
| 3 (Epic) | 35-55 | Cappuccino: 35, Penguino: 55 |
| 4 (Legendary) | 80-150 | Burbaloni: 80, Sigma Girl: 150 |

### Enemy Speed Nerf
| Tier | Old Range | New Range |
|------|-----------|-----------|
| 1 | 8-10 | 6-7 |
| 2 | 10-12 | 7-8 |
| 3 | 13-15 | 9-10 |
| 4 | 15-18 | 10-12 |

### Click-to-Attack (restoring from old system)
- Client: click enemy → `RequestAttack(enemyId)` → yellow SelectionBox
- Server: tracks `attackTarget[userId] = enemyId`; auto-attack hits only selected target
- Target dies / moves out of range / player moves → deselect
- Escape key → `StopAttack` → deselect
- Walk-to-enemy if not adjacent (server validates range)

### Rucoy Mob Reference Data (from `formulas.js`)
| Mob | Level | Defense | HP |
|-----|-------|---------|-----|
| Rat | 1 | 4 | 25 |
| Mummy | 25 | 36 | 80 |
| Assassin | 50 | 81 | 140 |
| Vampire | 100 | 171 | 450 |
| Yeti | 350 | 826 | 60,000 |

### Design Decisions (from user discussion)
- Game should NOT be too easy — hard defense gates are fine
- No damage below enemy defense — player must level up to progress
- Two XP tracks: level XP (from kills) and stat XP (from using skills)
- Training weapons (low baseATK) can be added later for XP farming
- AoE power skill can be added later as separate feature
- Damage split removed — Rucoy-style 1v1 targeting
- Enemy speed reduced to compensate for removing split