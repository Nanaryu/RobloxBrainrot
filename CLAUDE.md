# CLAUDE.md — Brainrot RPG (Working Title)
> Load this file at the start of every session to restore full project context.
> IDE: VS Code / Code OSS + Rojo extension. Roblox Studio for testing.

---

## 🎮 Game Overview
A Roblox game inspired by **Rucoy Online** (auto-attack MMORPG), themed around enemies from **Steal a Brainrot**. Built in **Roblox Studio** with a **pixelated tile-based aesthetic**.

---

## 📁 Actual Project Structure (current state)

```
BrainrotRPG/
├── default.project.json
├── aftman.toml
├── selene.toml
├── .gitignore
├── README.md
└── src/
    ├── ReplicatedStorage/
    │   ├── Modules/                          ← ModuleScripts (shared server+client)
    │   │   ├── Config.lua                    ✅ done
    │   │   ├── EnemyData.lua                 ✅ done
    │   │   ├── Pathfinder.lua                ✅ done
    │   │   └── RerollSystem.lua              ✅ done
    │   └── Remotes/
    │       └── RemoteInit.server.lua         ⚠️  DUPLICATE — delete; use SSS/Core/RemotesInit instead
    ├── ServerScriptService/
    │   ├── Core/                             ← Scripts (run automatically by Roblox)
    │   │   ├── RemotesInit.server.lua        ✅ done  — canonical remote creation
    │   │   ├── Main.server.lua               ✅ done  — requires all services in order
    │   │   └── Leaderboard.server.lua        ✅ done  — adds leaderstats (Coins IntValue)
    │   └── Services/                         ← ModuleScripts required by Main
    │       ├── TileGridService.lua           ✅ done
    │       ├── MovementService.lua           ✅ done
    │       ├── EnemyService.lua              ✅ done
    │       └── CombatService.lua             ✅ done
    ├── StarterPlayer/
    │   ├── StarterPlayerScripts/             ← LocalScripts (correct location)
    │   │   ├── MovementController.lua        ✅ done  — canonical version (respawn-safe)
    │   │   ├── MovementController.client.lua ⚠️  DUPLICATE — delete this file
    │   │   ├── CombatController.lua          ✅ done
    │   │   └── IsoCamera.lua                 ✅ done
    │   └── StarterCharacterScripts/
    │       ├── IsoCamera.lua                 ⚠️  DUPLICATE — delete (keep PlayerScripts version)
    │       └── test.txt                      ⚠️  JUNK — delete
    ├── StarterGui/                           ← (empty, ready for UI)
    └── Workspace/
        └── Map/                              ← TileGrid generated at runtime
```

**Still needed (not yet created):**
```
ReplicatedStorage/Modules/
    ItemData.lua              — item definitions, slot types, stat ranges
ServerScriptService/Services/
    LootService.lua           — drop table rolls, item creation
    ShopService.lua           — offline player shops
    DataService.lua           — DataStore persistence (inventory, currency, level)
StarterPlayer/StarterPlayerScripts/
    InventoryController.lua   — open/close inventory, equip items
    ShopClient.lua            — browse & buy from player shops
StarterGui/
    InventoryGui              — inventory grid UI
    HUDGui                    — HP bar, gold, level, XP
    ShopGui                   — offline shop browser
    DamageNumbers             — floating damage numbers above enemies
```

---

## 🧹 Cleanup Needed
| File | Action |
|------|--------|
| `src/ReplicatedStorage/Remotes/RemoteInit.server.lua` | Delete — superseded by `SSS/Core/RemotesInit.server.lua` |
| `src/StarterPlayer/StarterPlayerScripts/MovementController.client.lua` | Delete — old version; `MovementController.lua` is canonical |
| `src/StarterPlayer/StarterCharacterScripts/IsoCamera.lua` | Delete — wrong location; correct copy is in `StarterPlayerScripts` |
| `src/StarterPlayer/StarterCharacterScripts/test.txt` | Delete — junk file |

---

## 🔧 Rojo / project.json notes
- `Remotes` folder declared as `$className: "Folder"` in project.json — **not** a $path
- All remote creation happens in `SSS/Core/RemotesInit.server.lua`
- Services folder contains **ModuleScripts** (no `.server.` suffix) — required by `Main.server.lua`
- Core folder contains **Scripts** (`.server.lua` suffix) — run automatically by Roblox
- `init.server.lua` inside a folder = Rojo turns the **folder itself** into a Script — avoid in ReplicatedStorage

---

## ⚙️ Key Config Values (Config.lua)
| Key | Value | Notes |
|-----|-------|-------|
| TILE_SIZE | 8 studs | width & depth per tile |
| TILE_HEIGHT | 0.5 studs | visual thickness |
| GRID_WIDTH / HEIGHT | 64 × 64 | tiles total |
| MOVE_TWEEN_TIME | 0.18s | player & enemy slide speed |
| AUTO_ATTACK_RANGE | 1 tile | Cardinal-adjacent only (Manhattan distance == 1) |
| AUTO_ATTACK_INTERVAL | 1.0s | player attack speed |
| ENEMY_ATTACK_INTERVAL | 1.5s | enemy attack speed |
| SOUND_HIT_ID | "" | Placeholder SoundId for player hit confirmation |
| SOUND_DAMAGE_ID | "" | Placeholder SoundId for player taking damage |
| ELITE_SPAWN_CHANCE | 5% | chance per spawn |
| ELITE_STAR_MAX | 5 | max star count |
| PREMIUM_NAME | "Crystals" | TBD final name |

---

## 🏗️ Implemented Systems

### ✅ Tile Grid (TileGridService)
- 64×64 grid of anchored Parts under `Workspace > Map > TileGrid > Tiles`
- Checkerboard coloring for pixelated feel
- `TileToWorld(tx, tz)` and `WorldToTile(pos)` helpers
- `IsWalkable(tx, tz)` and `GetNeighbours(tx, tz)` for pathfinding
- Tiles can be made unwalkable by setting `Walkable=false`, or by calling `SetTileType(tx, tz, "Water")`

### ✅ Player Movement (MovementController client + MovementService server)
- WASD + click-to-move on tile parts (named `Tile_X_Z`)
- Client-side: tweens server-approved path tile by tile; destination highlight persists until arrival
- Character **faces direction of travel** — tween to `CFrame.lookAt(pos, pos + dir)`
- Server validates moves, broadcasts `PlayerMoved`; other clients lerp + face using tile delta
- Server pathing blocks non-walkable terrain, other players, and enemy current/moving destination tiles
- Retargeting uses request IDs so stale server approvals are ignored; local player movement is a single Heartbeat constant-speed mover instead of stacked tweens
- Movement is blocked locally and server-side while the player's Humanoid is dead
- `MovementController.GetCurrentTile()` and `IsMoving()` exposed for other scripts
- `MovementService.GetPlayerTile(player)` exposed for EnemyService
- Respawn-safe: re-acquires character refs on `CharacterAdded`

### ✅ Isometric Camera (IsoCamera.lua — StarterPlayerScripts)
- Scriptable camera, fixed angle from Config (45° horizontal, 40° vertical, 40 studs)
- Framerate-independent exponential lerp follow
- Blocks scroll zoom; re-locks CameraType after respawn

### ✅ A* Pathfinding (Pathfinder.lua)
- Pure module, takes `isWalkable(tx,tz)` function — no service deps
- Manhattan heuristic, 4-directional (no diagonal)
- Tie-breaks equal-cost routes with goal-aware neighbour ordering, so diagonal-looking routes alternate X/Z steps instead of exhausting one axis first
- `maxNodes` cap (default 400) prevents freezes
- Returns array of `{tx, tz}` steps from start→goal (start excluded)

### ✅ Enemy System (EnemyService)
- Enemies are Models in `Workspace/Map/Enemies` with PrimaryPart + attributes for all state
- Tries to clone from `ServerStorage/EnemyModels/[name]`; falls back to rarity-colored cube
- **3-state AI loop** per enemy (`task.spawn`):
  - `wander` — A* to random tile within `wanderRange` of spawn, pauses 2–4s, checks aggro each step
  - `chase` — re-paths toward nearest player every 0.5s, one step at a time
  - `attack` — faces player, damages every `ENEMY_ATTACK_INTERVAL`
- Occupied-tile set prevents enemies stacking on each other
- `CurrentTileX/Z` and `MovingToTileX/Z` are both treated as player-blocking obstacles during pathing
- **Elite system**: 5% spawn chance, 1–5 stars, HP/DMG multiplied per Config tables
- **Overhead BillboardGui**: rarity-colored name (★ prefix for elites) + green→yellow→red HP bar
- `EnemyService.DamageEnemy(id, amount, player)` — public API for CombatService
- `EnemyService.GetEnemy(id)` — returns model by id
- Test spawns hardcoded at bottom (tiles 10–30); replace with zone system later

### ✅ Combat (CombatService server + CombatController client)
- **Client**: click enemy → yellow `SelectionBox` highlight → walks toward it → auto-attacks at interval
- **Client**: faces enemy during attack, Escape cancels, enemy death auto-cancels
- **Client**: red screen flash on taking damage; pointer cursor on enemy hover
- **Client**: receives `EnemyHPUpdate` and refreshes billboard HP bar directly
- **Server**: validates Manhattan distance == 1 on every `RequestAttack`, flat 10 dmg (placeholder)
- **Server**: per-player attack loop with `AUTO_ATTACK_INTERVAL` throttle
- **Client + Server**: dead players cannot begin or continue attacks; death clears active combat state

### ✅ Leaderboard (Leaderboard.server.lua)
- Adds `leaderstats` folder with `Coins` IntValue (starts at 0) to every player on join

---

## 📡 Remote Events & Functions (all in ReplicatedStorage.Remotes)
| Name | Direction | Args |
|------|-----------|------|
| RequestMove | C→S | tx, tz, fromX, fromZ, requestId |
| PlayerMoved | S→C (all) | userId, tx, tz, path, requestId |
| RequestAttack | C→S | enemyId |
| AttackResult | S→C | hit, damage, enemyId, remainingHP |
| StopAttack | C→S | — |
| TakeDamage | S→C | targetUserId, amount |
| EnemyDied | S→C (all) | enemyId, worldPosition |
| EnemyHPUpdate | S→C (all) | enemyId, currentHP, maxHP |
| ItemDropped | S→C | itemData, worldPosition |
| InventoryUpdated | S→C | serialisedInventory |
| RerollRequest | C→S | itemId1, itemId2, itemId3 |
| RerollResult | S→C | newItemData \| false |
| OpenShopRequest | C→S | durationIndex |
| BuyFromShop | C→S | shopOwnerId, listingId |
| ShopListUpdated | S→C | shopData |
| GetInventory | C→S (Fn) | → serialised inventory |
| GetNearbyShops | C→S (Fn) | → shop list |

---

## 🎯 Rarity System
| Tier | Name | Color (RGB) | Drop weight |
|------|------|-------------|-------------|
| 1 | Common | 180,180,180 | 1000 |
| 2 | Rare | 80,120,255 | 400 |
| 3 | VeryRare | 50,200,180 | 150 |
| 4 | Epic | 163,53,238 | 60 |
| 5 | Legendary | 255,165,0 | 20 |
| 6 | Mythic | 220,20,60 | 5 |
| 7 | Secret | 255,215,0 | 1 |

Reroll: combine 3 items → weighted roll between lowest input rarity and (highest + 1), capped at Secret.

---

## 👾 Enemy Roster (names → EnemyData.lua for full stats)
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
- [x] Leaderboard (Coins placeholder)
- [ ] Floating damage numbers
- [ ] Player HUD (HP bar, XP, gold, level)
- [ ] Loot drops (ItemData + LootService)
- [ ] Inventory system + UI
- [ ] Item equip system + player stat scaling
- [ ] Item reroll UI
- [ ] DataStore persistence
- [ ] Zone/area system (replace hardcoded test spawns)
- [ ] NPC shop (premium currency)
- [ ] Offline player shops
- [x] Sound effect hooks (placeholder IDs for hit and damage)
- [x] Death input lockout for movement and combat
- [ ] Full death/respawn flow polish
- [ ] Game name

---

## 📝 Open Decisions
- [ ] Game name
- [ ] Item types: sword, staff, shield, helmet, chest, legs, boots? (confirm slots)
- [ ] Player stat formula (ATK/DEF scaling with equipment)
- [ ] Zone layout and which enemies spawn where
- [ ] Floating damage number style
- [ ] Respawn mechanic (timer? cost? safe zone?)
- [ ] Premium currency final name (currently "Crystals")
- [ ] Offline shop slot limit and duration tiers (set in Config, needs UX decision)

---

## Latest Movement/Combat Context
- Destination highlights now stay until the accepted path finishes; invalid/unanswered move requests clear if the server does not accept them quickly.
- Mid-route retargeting ignores stale path approvals with `requestId`; accepted routes interrupt from the current visual position through one Heartbeat movement loop, avoiding stacked tween speedups.
- Player pathing is server-authoritative and blocks `Walkable=false` terrain, water tiles, other players, and enemy current/moving destination tiles.
- Dead players are blocked from local movement/targeting and server-side movement/attack remotes.
- Tiles are currently 8 studs wide/deep for easier clicking and smoother perceived movement.
- `TileGridService.SetTileType(tx, tz, "Water")` marks a tile as unwalkable and recolors it; `SetTileWalkable(tx, tz, false)` is the direct toggle.
- A* remains 4-directional but now tie-breaks equal-cost paths so diagonal-looking routes alternate X/Z steps instead of walking all of one axis first.
- Enemy targeting chooses the closest reachable cardinal neighbour tile by actual A* path length before auto-attacking.
- Hit and damage sound hooks are wired through `Config.SOUND_HIT_ID` and `Config.SOUND_DAMAGE_ID`; both are intentionally blank placeholders until final assets are chosen.

## Recommended Next Tweaks
- Add a tiny path preview or hover marker for blocked/water tiles so players learn why clicks are ignored.
- Add server rejection feedback for invalid moves if responsiveness still feels ambiguous under latency.
- Consider reserving player destination tiles server-side during movement to prevent two players choosing the same final tile at the same time.
