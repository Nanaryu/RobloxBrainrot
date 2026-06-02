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
    │   │   ├── Main.server.lua               ✅  boots all services in dependency order
    │   │   └── Leaderboard.server.lua        ✅  Level/Coins with DataStore; Kills owned by KillTrackerService
    │   └── Services/
    │       ├── TileGridService.lua           ✅
    │       ├── MovementService.lua           ✅
    │       ├── SkillService.lua              ✅  Attack/Defense XP, level-up, SkillUpdated remote
    │       ├── EnemyService.lua              ✅  calls KillTrackerService.RegisterKill on _Kill
    │       ├── KillTrackerService.lua        ✅  per-enemy + global kills, "KillTracker_v1" DataStore
    │       ├── LootService.lua               ✅  drop rolls, world items, auto-pickup, inventory
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
- Manhattan heuristic, 4-directional; goal-aware tie-breaking
- `maxNodes` cap (default 400); returns `{tx,tz}[]` start-exclusive

### ✅ Enemy System (EnemyService)
- Models in `Workspace/Map/Enemies`; clones from `ServerStorage/EnemyModels/[name]`, fallback cube
- **3-state AI**: `wander` → A* to random tile in `wanderRange`, 2–4 s pause; `chase` → re-paths toward nearest player; `attack` → faces player, damages every `ENEMY_ATTACK_INTERVAL`
- Occupied-tile set; `CurrentTileX/Z` + `MovingToTileX/Z` both player-blocking
- **Elite system**: 5 % chance, 1–5 stars, HP/DMG multiplied per Config tables
- **Overhead BillboardGui**: rarity-colored name (★ prefix) + green→red HP bar
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
- Client: click enemy → yellow `SelectionBox` → walk → auto-attack loop; Escape cancels
- Client: faces enemy during attack; red screen flash on taking damage; pointer cursor on hover
- Client: receives `EnemyHPUpdate` and refreshes billboard HP bar
- Server: per-player auto-attack loop at `AUTO_ATTACK_INTERVAL`; damage = `10 + GetAttackBonus()` ±10%, grants 2 Attack XP per hit
- Equipment stat not yet factored in (pending inventory/equip system)
- Dead players blocked from movement and combat (client + server)

### ✅ Skills (Skills.lua + SkillService.lua)
- Constants: `Skills.ATTACK`, `Skills.DEFENSE`, `Skills.MAX_LEVEL = 99`
- Pre-built `XP_TABLE[level]` — cumulative XP; base 100 XP, ×1.35 scale per tier
- `GrantAttackXP(player, amount)` / `GrantDefenseXP(player, amount)` — 0.1s debounce
- `GetAttackBonus(player)` → `(level-1) * 0.5` flat ATK
- `GetDefenseReduction(player)` → `level / (level + 80)`, capped at 0.75
- Fires `SkillUpdated` after every grant with full payload for both skills

### ✅ Loot System (ItemData.lua + LootService.lua)
- 50+ item templates across 6 slots (weapon, offhand, helmet, chest, legs, boots), all 7 rarities
- Drop chain: `EnemyService._Kill` → `LootService.Drop` → world neon sphere in `Workspace/Map/Loot` → 0.3s pickup loop → `InventoryUpdated` remote
- Auto-pickup within 1 tile (Manhattan); first player wins
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
- [ ] Respawn mechanic (timer? cost? safe zone?)
- [ ] Premium currency final name (currently "Crystals")
- [ ] Offline shop slot limit and duration tiers

---

## 🔑 Key Implementation Notes
- **Kill tracking ownership**: KillTrackerService is sole owner of kill counts. Leaderboard.server.lua does NOT write `Kills.Value` in `refreshDisplay` or save it in `PlayerRemoving`. KillTracker sets `leaderstats.Kills.Value` via `WaitForChild` after load to win the race condition.
- **DataStores in use**: `"Stats"` (Level, Coins via Leaderboard), `"KillTracker_v1"` (kills via KillTrackerService), inventory TBD
- Enemy defense reduction: `level / (level + 80)` capped at 0.75
- Attack bonus: `(level-1) * 0.5` flat, added before ±10% roll
- Attack XP: 2 per hit (CombatService); Defense XP: 1 per hit taken (EnemyService._DamagePlayer)
- `SkillUpdated` fires after every XP grant + on CharacterAdded (0.5s delay) for HUD init
- Loot drop chain: `EnemyService._Kill` → `KillTrackerService.RegisterKill` + `LootService.Drop` → world Part → pickup loop → `InventoryUpdated`
- `ItemData._byRarity[rarityName]` pre-built array for fast random picks
- Inventory slot template children must be named `ItemIcon` (ImageLabel) and `ItemLabel` (TextLabel)
- Main.server.lua boot order: TileGrid → Movement → Skills → Enemy → KillTracker → Loot → Combat