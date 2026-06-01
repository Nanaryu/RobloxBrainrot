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
    │       └── Skills.lua                    ✅  (required by HUDController + SkillService)
    ├── ServerScriptService/
    │   ├── Core/
    │   │   ├── RemotesInit.server.lua        ✅  canonical remote creation
    │   │   ├── Main.server.lua               ✅  boots all services in order
    │   │   └── Leaderboard.server.lua        ✅  Level/Kills/Coins with DataStore
    │   └── Services/
    │       ├── TileGridService.lua           ✅
    │       ├── MovementService.lua           ✅
    │       ├── SkillService.lua              ✅  Attack/Defense XP, level-up, SkillUpdated remote
    │       ├── EnemyService.lua              ✅
    │       ├── LootService.lua               ✅  drop rolls, world items, auto-pickup, inventory
    │       └── CombatService.lua             ✅
    └── StarterPlayer/
        └── StarterPlayerScripts/
            ├── MovementBootstrap.client.lua  ✅  requires MovementController
            ├── MovementController.lua        ✅  canonical movement (no .client. suffix)
            ├── CombatController.client.lua   ✅
            ├── HUDController.client.lua      ✅  HP bar + Attack/Defense skill bars
            ├── IsoCamera.client.lua          ✅  (correct location)
            └── DamageNumbers.client.lua      ✅  floating damage numbers over enemies/player
```

**Still needed:**
```
ServerScriptService/Services/
    ShopService.lua
    DataService.lua           (full inventory/equipment persistence; Leaderboard covers Level/Kills/Coins)
StarterPlayer/StarterPlayerScripts/
    InventoryController.lua
    ShopClient.lua
StarterGui/
    InventoryGui
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
| GRID_WIDTH / HEIGHT | 64 × 64 | |
| MOVE_TWEEN_TIME | 0.18 s | player & enemy slide speed |
| AUTO_ATTACK_RANGE | 1 tile | Manhattan == 1 |
| AUTO_ATTACK_INTERVAL | 1.0 s | |
| ENEMY_ATTACK_INTERVAL | 1.5 s | |
| ELITE_SPAWN_CHANCE | 5 % | |
| ELITE_STAR_MAX | 5 | |
| PREMIUM_NAME | "Crystals" | TBD |

---

## 🏗️ Implemented Systems

### ✅ Tile Grid (TileGridService)
- 64×64 anchored Parts under `Workspace/Map/TileGrid/Tiles`
- Checkerboard coloring; golden spawn tile at grid centre
- `TileToWorld`, `WorldToTile`, `IsWalkable`, `GetNeighbours`, `SetTileType`, `SetTileWalkable`
- `SetTileType(tx, tz, "Water")` marks unwalkable + recolors

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
- Scriptable camera, 45° horizontal / 40° vertical / 40 studs
- Framerate-independent exponential lerp follow; re-locks on respawn

### ✅ A* Pathfinding (Pathfinder.lua)
- Pure module, injected `isWalkable(tx,tz)` — no service deps
- Manhattan heuristic, 4-directional; goal-aware tie-breaking for balanced routes
- `maxNodes` cap (default 400); returns `{tx,tz}[]` start-exclusive

### ✅ Enemy System (EnemyService)
- Models in `Workspace/Map/Enemies`; clones from `ServerStorage/EnemyModels/[name]`, fallback cube
- **3-state AI**: `wander` → A* to random tile in `wanderRange`, 2–4 s pause; `chase` → re-paths toward nearest player; `attack` → faces player, damages every `ENEMY_ATTACK_INTERVAL`
- Occupied-tile set; `CurrentTileX/Z` + `MovingToTileX/Z` both player-blocking
- **Elite system**: 5 % chance, 1–5 stars, HP/DMG multiplied per Config tables
- **Overhead BillboardGui**: rarity-colored name (★ prefix) + green→red HP bar
- `EnemyService.DamageEnemy(id, amount, player)`, `GetEnemy(id)`, `GetEnemyAtTile(tx, tz)`
- `_DamagePlayer` applies `SkillService.GetDefenseReduction` and grants defense XP
- Test spawns hardcoded in init block (tiles 10–30)

### ✅ Combat (CombatService + CombatController)
- Client: click enemy → yellow `SelectionBox` → walk → auto-attack loop; Escape cancels
- Client: faces enemy during attack; red screen flash on taking damage; pointer cursor on hover
- Client: receives `EnemyHPUpdate` and refreshes billboard HP bar
- Server: validates Manhattan == 1 per `RequestAttack`; flat 10 dmg placeholder
- Server: per-player attack loop with `AUTO_ATTACK_INTERVAL` throttle
- Dead players blocked from movement and combat (client + server)

### ✅ Skills (SkillService + Skills.lua module)
- Attack and Defense skills with XP and level-up curve
- `SkillService.GrantAttackXP(player, amount)` — called by CombatService on hit
- `SkillService.GrantDefenseXP(player, amount)` — called by EnemyService._DamagePlayer
- `SkillService.GetDefenseReduction(player)` — returns damage reduction ratio
- Fires `SkillUpdated` remote to client with `{ Attack={level,currentXP,neededXP}, Defense={...} }`

### ✅ Loot System (ItemData.lua + LootService.lua)

**ItemData.lua** — 50+ item templates across 6 slots (weapon, offhand, helmet, chest, legs, boots) and all 7 rarities. Each template has `slot`, `statType` (atk/def), `rarity`, `statMin/Max`, `name`, `icon`. Pre-builds `_byRarity` lookup table for O(1) pool access.

**LootService.lua:**
- `LootService.Drop(model, killer)` — called from `EnemyService._Kill`; checks drop chance by enemy rarity (25–100%), picks item rarity via weighted table, bumps tier for elite stars, rolls stat in `[statMin, statMax]`, spawns world Part
- World drops: neon glowing sphere with PointLight and BillboardGui name label, bobbing animation, parented under `Workspace/Map/Loot`
- Auto-pickup: 0.3 s tick loop checks if any player is within 1 tile (Manhattan); first player wins the item
- On pickup: adds to in-memory `inventories[userId]` table, fires `InventoryUpdated` → client with serialized list
- `LootService.GetInventory(player)` exposed; `GetInventory` RemoteFunction wired
- Player inventories cleared on `PlayerRemoving`; DataService will persist them later

**EnemyService._Kill patch:** `LootService` lazy-loaded and `Drop(model, killer)` called where the TODO was.

### ✅ Floating Damage Numbers (DamageNumbers.client.lua)
- Listens to `AttackResult` (damage we deal → white number over enemy) and `TakeDamage` (damage we take → red number over own character)
- Spawns an invisible anchor Part at world position + random horizontal scatter, with a BillboardGui `AlwaysOnTop` label
- Tweens anchor upward (`FLOAT_RISE = 5` studs over `0.9 s`); fades text out in the second half via delayed tween
- Cleans up anchor + billboard on completion; no memory leak

### ✅ HUD (HUDController.client.lua)
- Bottom-left panel: HP bar, Attack skill bar, Defense skill bar
- Reactive: `Humanoid.HealthChanged` for HP; `SkillUpdated` remote for skill bars
- Color-interpolated HP fill (green → red); XP ratio fill for skills

### ✅ Leaderboard (Leaderboard.server.lua)
- `leaderstats`: Level, Kills, Coins — all persisted to DataStore
- Large-number formatting with suffix table (K, M, B … up to Centillion)
- Loads on `PlayerAdded`, saves on `PlayerRemoving`

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
- [x] Leaderboard with DataStore (Level, Kills, Coins)
- [x] Sound effect hooks (placeholder IDs)
- [x] Death input lockout (movement + combat)
- [x] Floating damage numbers
- [x] Loot drops (ItemData + LootService)
- [ ] Inventory system + UI
- [ ] Item equip system + player stat scaling
- [ ] Item reroll UI
- [ ] Full DataStore persistence (inventory, equipment)
- [ ] Zone/area system (replace hardcoded test spawns)
- [ ] NPC shop (premium currency)
- [ ] Offline player shops
- [ ] Full death/respawn flow polish
- [ ] Game name

---

## 📝 Open Decisions
- [ ] Game name
- [ ] Item slots (sword, staff, shield, helmet, chest, legs, boots?)
- [ ] Player stat formula (ATK/DEF scaling with equipment)
- [ ] Zone layout — which enemies spawn where
- [ ] Floating damage number style
- [ ] Respawn mechanic (timer? cost? safe zone?)
- [ ] Premium currency final name (currently "Crystals")
- [ ] Offline shop slot limit and duration tiers

---

## 🔑 Key Implementation Notes
- Enemy defense reduction: `SkillService.GetDefenseReduction(player)` → ratio; `finalDamage = max(1, floor(amount*(1-reduction)))`
- Attack XP granted in CombatService on successful hit; Defense XP in EnemyService._DamagePlayer
- `SkillUpdated` fires after every XP grant with full payload for both skills
- Leaderboard uses formatted suffixes (K/M/B…) — raw numbers stored in DataStore, formatted on display
- `MovementBootstrap.client.lua` wraps `MovementController.lua` so it runs as a LocalScript without the `.client.` suffix
- `Skills.lua` module in ReplicatedStorage/Modules defines `Skills.ATTACK` / `Skills.DEFENSE` string constants shared by server and client
- Loot drop chain: `EnemyService._Kill` → `LootService.Drop(model, killer)` → world Part in `Workspace/Map/Loot` → 0.3s pickup loop → `InventoryUpdated` remote
- Item stat is a single rolled integer (`stat`); `statType` is "atk" or "def" — equip system will apply it as a flat bonus
- `ItemData._byRarity[rarityName]` is a pre-built array of template name strings for fast random picks
