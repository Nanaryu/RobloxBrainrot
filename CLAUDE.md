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
    │   │   └── Leaderboard.lua               ✅  Level/Coins with DataStore; Kills owned by KillTrackerService
    │   └── Services/
    │       ├── TileGridService.lua           ✅  256×256 irregular map, zone-colored tiles, noise boundary
    │       ├── MovementService.lua           ✅
    │       ├── SkillService.lua              ✅  Attack/Defense XP, level-up, SkillUpdated remote
    │       ├── EnemyService.lua              ✅  zone-based spawning, leash + return state, town boundary
    │       ├── KillTrackerService.lua        ✅  per-enemy + global kills, "KillTracker_v1" DataStore
    │       ├── LootService.lua               ✅  drop rolls, world items, auto-pickup, inventory, equip/unequip
    │       ├── ShopService.lua               ✅  NPC shop with rotating stock, coin purchases, 5-min refresh
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
            ├── InventoryController.client.lua ✅ dynamically generates InvSlot instances
            ├── DeathScreen.client.lua         ✅  death overlay, respawn countdown, invincibility flash
            ├── ShopClient.lua                 ✅  NPC shop UI controller (template-based, UIScale anim)
            └── TargetingController.lua          ✅  hold-E circle-on-chain auto-snap targeting
    └── StarterGui/
        └── LoadingGui/
            └── LoadingClient.client.lua      ✅  loading screen with retry logic
```

**Still needed:**
```
ServerScriptService/Services/
    DataService.lua           (full inventory/equipment persistence)
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

## 🖼️ Roblox GUI Object Reference
> Quick reference for building UI programmatically in LocalScripts.
> Roblox GUI objects do NOT exist as files on disk — they are created at runtime via `Instance.new()`.

### Core Hierarchy
```
StarterGui
  └─ ScreenGui              ← top-level container, renders on screen
       ├─ Frame              ← rectangular container (the "panel")
       │    ├─ UICorner      ← rounds the corners
       │    ├─ UIStroke      ← border outline
       │    ├─ UIListLayout  ← auto-arranges children vertically/horizontally
       │    ├─ UIGridLayout  ← auto-arranges children in a grid
       │    ├─ UIPadding     ← inner spacing
       │    └─ UISizeConstraint ← max/min size
       ├─ TextLabel          ← non-interactive text display
       ├─ TextButton         ← clickable text
       ├─ ImageButton        ← clickable image
       ├─ ImageLabel         ← non-interactive image display
       ├─ ScrollingFrame     ← scrollable container (has CanvasSize, ScrollBarThickness)
       │    └─ (children arranged by UIListLayout/UIGridLayout)
       └─ BillboardGui       ← attached to 3D part, renders in world space
            └─ TextLabel / ImageLabel
```

### Key Properties (most-used)
| Object | Property | Type | Notes |
|--------|----------|------|-------|
| Frame | `Size` | UDim2 | `{scale, offset, scale, offset}` — e.g. `UDim2.new(0, 200, 0, 100)` = 200px × 100px |
| Frame | `Position` | UDim2 | Anchor point is top-left by default |
| Frame | `AnchorPoint` | Vector2 | `(0.5, 0.5)` centers the frame at its Position |
| Frame | `BackgroundColor3` | Color3 | Fill color |
| Frame | `BackgroundTransparency` | number | 0 = opaque, 1 = invisible |
| Frame | `BorderSizePixel` | number | Set to 0 when using UIStroke |
| TextLabel/TextButton | `Text` | string | Display text |
| TextLabel/TextButton | `TextColor3` | Color3 | Text color |
| TextLabel/TextButton | `Font` | Enum.Font | `GothamBold`, `Gotham`, `SourceSans` |
| TextLabel/TextButton | `TextScaled` | boolean | Auto-size text to fit container |
| TextLabel/TextButton | `TextStrokeTransparency` | number | 0 = full outline, 1 = no outline |
| TextLabel/TextButton | `TextXAlignment` | Enum | `Left`, `Center`, `Right` |
| ImageLabel/ImageButton | `Image` | string | `"rbxassetid://123456"` |
| ImageLabel/ImageButton | `ImageColor3` | Color3 | Tint the image |
| ImageLabel/ImageButton | `ScaleType` | Enum | `Fit`, `Stretch`, `Tile`, `Crop` |
| ScrollingFrame | `CanvasSize` | UDim2 | Total scrollable area (set dynamically) |
| ScrollingFrame | `ScrollBarThickness` | number | 0 = hidden scrollbar |
| ScrollingFrame | `AutomaticCanvasSize` | Enum.AutomaticSize | `Y` = auto-height from children |
| BillboardGui | `Size` | UDim2 | Pixel size of the billboard |
| BillboardGui | `StudsOffset` | Vector3 | Offset from the 3D part |
| BillboardGui | `AlwaysOnTop` | boolean | Renders above 3D geometry |
| BillboardGui | `Adornee` | Instance | The Part to attach to |

### Layout Objects
| Object | Key Properties | Notes |
|--------|---------------|-------|
| `UIListLayout` | `FillDirection`, `HorizontalAlignment`, `VerticalAlignment`, `Padding`, `SortOrder` | Arranges children in a line |
| `UIGridLayout` | `CellSize`, `CellPadding`, `FillDirection`, `HorizontalAlignment` | Grid arrangement |
| `UIPadding` | `PaddingTop`, `PaddingBottom`, `PaddingLeft`, `PaddingRight` | UDim values (scale + offset) |
| `UICorner` | `CornerRadius` | UDim — `UDim.new(0, 8)` = 8px radius |
| `UIStroke` | `Color`, `Thickness`, `Transparency` | Border outline |
| `UISizeConstraint` | `MaxSize`, `MinSize` | Constrains parent size |
| `UITextSizeConstraint` | `MaxTextSize`, `MinTextSize` | Constrains TextScaled range |

### Creating Objects (Lua pattern)
```lua
-- Standard panel pattern used throughout this project:
local frame = Instance.new("Frame")
frame.Name = "ShopPanel"
frame.Size = UDim2.new(0, 400, 0, 300)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)  -- center screen
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 80)
stroke.Thickness = 1
stroke.Transparency = 0.4
stroke.Parent = frame
```

### UDim2 Cheat Sheet
```lua
UDim2.new(scaleX, offsetX, scaleY, offsetY)
-- scaleX: fraction of parent (0.5 = 50% of parent width)
-- offsetX: absolute pixels added after scale
-- Examples:
UDim2.new(1, 0, 1, 0)       -- fill parent exactly
UDim2.new(0, 200, 0, 100)    -- fixed 200×100 pixels
UDim2.new(0.5, 0, 0, 50)     -- 50% parent width, 50px tall
UDim2.new(1, -20, 1, -20)    -- fill parent minus 20px padding each side
```

### Tweening (animations)
```lua
local TweenService = game:GetService("TweenService")
local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tween = TweenService:Create(frame, info, { Size = UDim2.new(0, 300, 0, 200) })
tween:Play()
-- EasingStyle: Linear, Quad, Cubic, Back, Bounce, Elastic
-- EasingDirection: Out, In, InOut
```

### ZIndex / Rendering Order
- `ZIndex` on individual objects (1–1000, higher = renders on top)
- `DisplayOrder` on ScreenGui (higher = renders above other ScreenGuis)
- `GuiObject.Archivable` — set false to exclude from recording/saves
- `IgnoreGuiInset = true` on ScreenGui lets it cover the top bar

### Common Patterns in This Project
- **TooltipGui**: separate ScreenGui with `DisplayOrder = 99` so it renders above inventory
- **InvSlot template**: Frame with `ItemIcon` (ImageLabel) + `ItemLabel` (TextLabel) children
- **Rarity strokes**: `UIStroke.Color` set from `Config.RARITIES[rarity].color`
- **Placeholder icons**: `rbxassetid://101140058690765`
- **Fonts**: `Enum.Font.GothamBold` for all text
- **All UI built programmatically** in LocalScripts (no Studio GUI editors)

### Project GUI Hierarchy (from Studio export)
> Exact structure of all existing GUI objects. New panels MUST match this pattern.

```
StarterGui
  └─ MainGui (ScreenGui, ZIndexBehavior=Sibling)
       ├─ LeftPanel (ScreenGui)
       │    ├─ UIGridLayout (2×2, CellSize=80×80, Padding=20, VerticalAlignment=Center)
       │    ├─ StoreButton (TextButton, LayoutOrder=1)
       │    │    ├─ Frame + UIGradient (red→white, rot=45) + UICorner + UIStroke(thick=2)
       │    │    ├─ BackgroundTexture (ImageLabel, rbxassetid://139594762000290)
       │    │    ├─ ImageLabel (icon, rbxassetid://72491857349071)
       │    │    └─ TextLabel ("Store", LuckiestGuy, 16, white, stroke)
       │    ├─ IndexButton (LayoutOrder=2, blue gradient)
       │    │    └─ icon: rbxassetid://113643318652668, text: "Index"
       │    ├─ InventoryButton (LayoutOrder=3, brown/gold gradient)
       │    │    └─ icon: rbxassetid://101140058690765, text: "Inventory"
       │    ├─ UpgradesButton (LayoutOrder=4, green→orange gradient)
       │    │    └─ icon: rbxassetid://128726239575400, text: "Upgrades"
       │    └─ UIPadding (PaddingLeft=0.01)
       ├─ TopPanel (ScreenGui)
       │    ├─ UIListLayout (HorizontalAlignment=Center)
       │    ├─ XPProgressBar (Frame, 20% width, 2% height, Position=0.343,0.035)
       │    │    └─ UICorner (radius=3)
       │    └─ CurrentLevel (TextLabel, "Level 0", LuckiestGuy)
       ├─ StorePanel (ScreenGui, Enabled=false)
       │    ├─ StoreContainer (Frame, 639×354, Position=0.274,0.314)
       │    │    ├─ UICorner + UIStroke_Outer(thick=2) + UIStroke_Inner(Color=red)
       │    │    ├─ ScrollingFrame (96% width, 85% height, pos=0.02,0.1)
       │    │    └─ ExitButton (red X, top-right corner, rot=-2)
       │    ├─ StoreIcon (ImageLabel, 80×80, icon)
       │    └─ TextLabel ("Store!", LuckiestGuy, 35, rot=2)
       ├─ IndexPanel (same structure, UIStroke_Inner=blue)
       ├─ InventoryPanel (same structure, UIStroke_Inner=gold)
       │    ├─ ScrollingFrame_2
       │    │    └─ UIGridLayout_2 (CellSize=80×80, Padding=15×5, Center)
       │    └─ InvSlot (template, Visible=false)
       │         ├─ UICorner(3) + UIStroke(Color=0.584)
       │         ├─ ItemIcon (ImageLabel, 70% size, offset 15%,11%)
       │         └─ ItemLabel (TextLabel, LuckiestGuy, 14, bottom, TextTruncate=AtEnd)
       └─ UpgradesPanel (same structure, UIStroke_Inner=green)
```

**Panel conventions:**
- All content panels: 639×354px, Position=0.274,0.314 (centered-ish)
- Container has double stroke: `UIStroke_Outer` (default color) + `UIStroke_Inner` (theme color)
- Each panel has an `ExitButton` (red X, top-right, rot=-2) wired to close
- Panels open/close via UIScale tween (0→1, Back easing, 0.35s)
- Button hover: UIScale 1→1.1 (Back, 0.3s) + icon rotation ±12°
- Button sounds: UIClickSound (rbxassetid://115942274494895), UIHoverSound (rbxassetid://119354387183704)
- **Theme colors per panel:** Store=red(1,0,0.016), Index=blue(0,0.733,1), Inventory=gold(0.714,0.463,0.11), Upgrades=green(0.392,0.835,0)

---

## ⚙️ Key Config Values (Config.lua)
| Key | Value | Notes |
|-----|-------|-------|
| TILE_SIZE | 8 studs | |
| TILE_HEIGHT | 0.5 studs | |
| GRID_WIDTH / HEIGHT | 128 × 128 | |
| MAP_NOISE_AMPLITUDE | 0.55 | Zone boundary organic wobble |
| MAP_NOISE_SEED | 42 | Change for different map shapes |
| TOWN_RADIUS | 10 tiles | Hard safe boundary — enemies blocked |
| MAX_CLICK_DISTANCE | 25 tiles | Client click-to-move range cap |
| MOVE_TWEEN_TIME | 0.35 s | player & enemy slide speed |
| AUTO_ATTACK_RANGE | 1 tile | Manhattan == 1 |
| AUTO_ATTACK_INTERVAL | 1.0 s | |
| ENEMY_ATTACK_INTERVAL | 1.5 s | |
| BASE_ATK | 15 | Player base weapon attack (scales with equipment later) |
| CAM_VERTICAL_ANGLE | 56 | Higher = more top-down, better click balance |
| ELITE_SPAWN_CHANCE | 5 % | |
| ELITE_STAR_MAX | 5 | |
| PREMIUM_NAME | "Crystals" | TBD |
| RESPAWN_DELAY | 5 s | seconds between death and respawn |
| INVINCIBILITY_DURATION | 3 s | seconds of post-respawn invincibility |

---

## 🏗️ Implemented Systems

### ✅ Tile Grid (TileGridService)
- 128×128 anchored Parts under `Workspace/Map/TileGrid/Tiles`
- Irregular boundary via fractal noise (deterministic, seed = 42)
- Voronoi + noise zone assignment: each tile assigned to nearest zone centre with organic wobble
- 5 zones with unique tile colours + materials
- Zone border blending: transition tiles at Voronoi boundaries blend toward neutral color
- Height variation: ±0.15 studs Y offset via fractal noise for bumpy terrain
- `TileToWorld`, `WorldToTile`, `IsWalkable`, `GetNeighbours`, `SetTileType`, `SetTileWalkable`
- `GetZone(tx, tz)` returns zone id string for a tile
- `SetTileType(tx, tz, "Water")` marks unwalkable + recolors (glass material, 30% transparency)
- **Decorations** (in `Workspace/Map/Decorations`):
  - Water pools: 2-4 per zone, 2-3 tile clusters, glass material
  - Rocks: 12-22 per zone, non-walkable slate tiles
  - Bushes: 15-30 per zone (not Volcano), green ball parts, no collision
  - Crystals: 4-10 per zone, neon cylinder parts, slight transparency
  - Ambient particles: 6 emitters per zone (petals/dust/mist/embers)

### ✅ Zone System (ZoneService + ZoneData)
- 5 zones: Town (safe), Grasslands (Tier 1), Desert (Tier 2), Swamp (Tier 3), Volcano (Tier 4)
- Zones are organic blobs — centre offset + radius + noise amplitude (not concentric rings)
- Town is a hard safe boundary (`TOWN_RADIUS = 10` tiles) — enemies cannot enter
- `ZoneService.GetZoneAt(tx, tz)` → zone table or nil (void tile)
- `ZoneService.IsSafeZone(tx, tz)` — true for Town only
- `ZoneService.GetRandomTileInZone(zoneId)` — random walkable tile in a zone
- `ZoneData.BuildSpawnPool(zone)` / `ZoneData.PickEnemy(zone, pool)` — weighted random enemy selection
- Each zone has `spawnDensity`, `leashRange`, and `spawnEnemies` weighted list

### ✅ Player Movement (MovementController + MovementService)
- WASD + click-to-move on `Tile_X_Z` parts
- Client tweens server-approved path; destination highlight until arrival
- Faces direction of travel; `CFrame.lookAt` tween
- Server validates, broadcasts `PlayerMoved`; other clients tween along path
- **Players can stack on the same tile** — pathfinding does NOT block on other players
- Blocks non-walkable terrain and enemy current/moving tiles
- Retargeting uses `requestId` to ignore stale approvals
- Single Heartbeat constant-speed mover (no stacked tweens)
- Blocked while Humanoid is dead; respawn-safe via `CharacterAdded`
- **Other-player tween cancellation**: per-user `otherPlayerTokens` table prevents overlapping tween coroutines when chase re-paths fire rapidly
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
- **4-state AI**: `wander` → A* to random tile in `wanderRange`, 2–4 s pause; `chase` → re-paths toward nearest player; `attack` → faces player, calls `queueDamage` every `ENEMY_ATTACK_INTERVAL`; `return` → walks back to spawn after leash break
- Occupied-tile set; `CurrentTileX/Z` + `MovingToTileX/Z` both player-blocking
- **Leash system**: enemy drops aggro and enters `return` state when > `leashRange` tiles from spawn
- **Town boundary**: enemies cannot path into Town zone tiles (`isPassableForEnemy` rejects safe-zone tiles)
- **Elite system**: 5 % chance, 1–5 stars, HP/DMG multiplied per Config tables
- **Overhead BillboardGui**: rarity-colored name with `[Lv.X]` prefix (computed as `max(1, floor(defense * 0.6))`) + green→red HP bar
- **Zone-based spawning**: enemies fill non-safe zones based on `spawnDensity`; weighted random picks from `ZoneData.spawnEnemies`
- **Respawn timer**: killed enemies queue respawn in their zone (8–15 s delay)
- **Combined damage per tick** (Rucoy-style): `queueDamage` adds to per-player accumulator; processor runs every 0.5s summing all damage, applying DEF once, granting DEF XP once
- `EnemyService.DamageEnemy(id, amount, player)`, `GetEnemy(id)`, `GetEnemyAtTile(tx, tz)`
- `_Kill` calls `KillTrackerService.RegisterKill(killer, enemyName)`, `LootService.Drop(model, killer)`, and `LeaderboardService.AddXP(killer, xp)`

### ✅ Kill Tracker (KillTrackerService)
- `KillTrackerService.RegisterKill(player, enemyName)` — called from `EnemyService._Kill`
- Tracks `_total` (global kills) + per-enemy counters keyed by enemy name string
- Persists to `"KillTracker_v1"` DataStore (saves on every kill + PlayerRemoving)
- On load: uses `player:WaitForChild("leaderstats")` then sets `Kills.Value = _total` — wins race vs Leaderboard
- `GetKills(player, enemyName)` and `GetTotalKills(player)` exposed
- **Leaderboard.lua** does NOT touch `Kills` in `refreshDisplay` or `PlayerRemoving` — KillTracker owns it entirely

### ✅ Combat (CombatService + CombatController)
- **Click-to-attack**: click enemy → `RequestAttack(enemyId)` → yellow SelectionBox → auto-attack loop
- Escape key → `StopAttack` → deselect; target dies / out of range → deselect
- Server: per-player auto-attack loop at `AUTO_ATTACK_INTERVAL`; single target only via `attackTarget[userId]`
- **Dynamic chase system**: when target moves out of range during attack, server starts a chase loop that re-paths every 0.2s using time-based client position estimation (`estimatePlayerTile`) to keep paths accurate. Uses `requestId == -1` for attack-move paths.
- **Damage formula** (IMPLEMENTED): `min_raw = (ATK_Level × BASE_ATK) / 20`, `max_raw = (ATK_Level × BASE_ATK) / 10`, accuracy check, roll `random(min_raw, max_raw) - enemy_DEF`
- **Defense formula** (IMPLEMENTED): `max(1, enemy_damage - DEF_Level)` — flat subtraction, no cap
- If accuracy = 0 (max_raw ≤ enemy_DEF): deal 0 — hard progression gate
- No damage split — Rucoy-style 1v1 targeting
- Grants ATK stat XP (1 tick per hit); DEF stat XP granted in EnemyService `processDamageAccumulator` (1 tick per combined tick, not per enemy)
- Equipment stat not yet factored in (pending inventory/equip system)
- Dead players blocked from movement and combat (client + server)
- **Forward declaration pattern**: `startChase` uses `local startChase` forward declaration to resolve circular runtime dependency with `doAttackTick`

### ✅ Skills (Skills.lua + SkillService.lua)
- Constants: `Skills.ATTACK`, `Skills.DEFENSE`, `Skills.MAX_LEVEL = 99`
- **Dual XP system** (two independent progression tracks):
  - Character Level XP: `xp_for_level(n) = floor(n ^ (n/1000 + 3))` — granted per enemy kill via `enemy.xp`
  - Stat XP (ATK/DEF): `stat_xp_for_level(n) = floor(n ^ (n/1000 + 2.373))` for 0-54, `floor(n ^ (n/1000 + 2.171))` for 55-99 — 1 tick per hit (ATK) or per damage taken (DEF)
- `GrantAttackXP(player, amount)` / `GrantDefenseXP(player, amount)` — no debounce, each enemy hit grants independently
- `GetAttackLevel(player)` → ATK stat level (used by CombatService damage formula)
- `GetDefenseLevel(player)` → DEF stat level (used by EnemyService defense formula: `max(1, raw - defLevel)`)
- Fires `SkillUpdated` after every grant with full payload for both skills
- Persisted to `"Skills_v1"` DataStore (saved on PlayerRemoving + BindToClose)

### ✅ Loot System (ItemData.lua + LootService.lua)
- 50+ item templates across 6 slots (weapon, offhand, helmet, chest, legs, boots), all 7 rarities
- Drop chain: `EnemyService._Kill` → `LootService.Drop` → world neon sphere in `Workspace/Map/Loot` → 0.3s pickup loop → `InventoryUpdated` remote
- Auto-pickup on exact tile (Manhattan == 0); **killer-locked** — only the player who killed the enemy can pick up the drop
- In-memory `inventories[userId]`; `GetInventory` RemoteFunction wired
- Elite star count bumps item rarity tier on drop
- `LootService.GiveItem(player, item)` public method for shop item delivery

### ✅ NPC Shop (ShopService.lua + ShopClient.lua)
- Global rotating stock of 12 items, refreshed every 5 minutes
- Items rolled from `ItemData._byRarity` weighted by rarity (500 Common → 1 Secret)
- Price formula: `floor(stat × PRICE_BASE(5) × rarityMultiplier)` — Common×1, Rare×2, VeryRare×4, Epic×8, Legendary×16, Mythic×32, Secret×64
- `GetShopList` RemoteFunction returns current stock; `BuyShopItem` RemoteEvent deducts coins via `Leaderboard.AddCoins(-price)` and gives item via `LootService.GiveItem`
- `ShopListUpdated` broadcasts to all players on buy or refresh
- Coin validation: `Leaderboard.GetCoins(player)` checked before purchase
- Lazy-loads Leaderboard and LootService dependencies to avoid circular requires
- **ShopClient.lua**: LocalScript in StarterPlayerScripts. Finds `ShopPanel` (ScreenGui) inside `MainGui`, clones `ShopSlot` template for each listing. Tooltip via dedicated `ShopTooltipGui` (DisplayOrder=100). UIScale open/close animation matching other panels. Keyboard shortcut: **B** to toggle. Exposes `openShop()`/`closeShop()`/`isOpen()` module.
- **LeftPanel wiring**: StoreButton click should call `require(player.PlayerScripts:WaitForChild("ShopClient")).openShop()`. The ShopPanel ScreenGui must exist in Studio as a child of MainGui with: `ShopContainer` Frame (639×354), `ShopSlot` template inside `ScrollingFrame`, `UIScale` child, `ExitButton` (red X).

### ✅ Inventory UI (InventoryController.client.lua)
- Listens to `InventoryUpdated` + `EquipmentUpdated` remotes; calls `GetInventory` + `GetEquipment` RemoteFunctions on spawn
- Clears and rebuilds `ScrollingFrame` inside `InventoryPanel > InventoryContainer` on every update
- Clones `InvSlot` template for each item; sets `ItemIcon` ImageLabel + `ItemLabel` TextLabel
- `UIStroke` colored by rarity; green + thicker stroke for equipped items
- Item data stored as Frame Attributes (`ItemId`, `ItemSlot`, `ItemEquipped`, `ItemRarity`, etc.) — click handler reads fresh attribute state at click time
- Sorted by rarity ascending, then name, then **item ID** as stable tiebreaker (prevents visual reorder when two items share name+rarity)
- Canvas height adjusted for UIGridLayout
- Placeholder icon: `rbxassetid://101140058690765`
- Template slot children expected: `ItemIcon` (ImageLabel), `ItemLabel` (TextLabel)
- **Tooltip**: dedicated `TooltipGui` ScreenGui (DisplayOrder=99) so tooltip renders above inventory regardless of parent GUI's ZIndexBehavior; positioned to right of hovered slot, clamped to screen edges; fade-in/out tweens with `tooltipVisible` flag to prevent race condition
- **Equip/Unequip**: click equipped item → `UnequipRequest:FireServer(slot)`; click unequipped item → `EquipRequest:FireServer(id)`. Brief white flash feedback on click; stroke restores from current attribute state (not stale closure capture)

### ✅ Floating Damage Numbers (DamageNumbers.client.lua)
- `DamageNumber` remote → server-broadcast to all clients; white number for own hits, gray for others
- `TakeDamage` → red number over own character (damage taken)
- Invisible anchor Part tweened upward 5 studs over 0.9s; label fades in second half

### ✅ HUD (HUDController.client.lua)
- Bottom-left panel: HP bar, Attack skill bar, Defense skill bar
- Reactive: `Humanoid.HealthChanged` for HP; `SkillUpdated` remote for skill bars
- Color-interpolated HP fill (green → red)

### ✅ Leaderboard (Leaderboard.lua)
- `leaderstats`: Level, Kills, Coins
- Level + Coins persisted in `"Stats"` DataStore; Kills excluded (owned by KillTrackerService)
- **XP-based level progression**: `rawStats` stores `totalXP` (cumulative character XP). `Level.Value` is the **computed level** via `Skills.LevelFromXP(totalXP)`, NOT raw XP.
- `refreshDisplay` computes level from `totalXP` and pushes to `Level.Value`
- `Leaderboard.AddXP(player, amount)` — called by `EnemyService._Kill` to add kill XP
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
| DamageNumber | S→C all | attackerUserId, damage, enemyId |
| EnemyDied | S→C all | enemyId, worldPosition |
| EnemyHPUpdate | S→C all | enemyId, currentHP, maxHP |
| PlayerDied | S→C | — |
| PlayerRespawn | S→C | — |
| SkillUpdated | S→C | { Attack={…}, Defense={…} } |
| ItemDropped | S→C | itemData, worldPosition |
| InventoryUpdated | S→C | serialisedInventory |
| EquipRequest | C→S | itemId |
| UnequipRequest | C→S | slot |
| EquipmentUpdated | S→C | equipmentTable |
| GetInventory | C→S fn | → inventory |
| GetEquipment | C→S fn | → equipment table |
| GetNearbyShops | C→S fn | → shop list |
| GetShopList | C→S fn | → NPC shop stock |
| BuyShopItem | C→S | listingIndex |
| ShopListUpdated | S→C | stockData |

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
- [x] Map expansion (128×128 Voronoi + noise blob zones)
- [x] Zone system (5 organic blobs: Town + 4 biome quadrants)
- [x] Zone-based enemy spawning with density + respawn timer
- [x] Safe zone (Brainrot Town — 12 tile radius, no enemies)
- [x] Enemy leash system (return-to-spawn after exceeding leash range)
- [x] Click-to-move distance cap (25 tiles)
- [x] Rucoy-style damage formula (multiplicative ATK × baseATK, flat DEF subtraction)
- [x] Click-to-attack enemy selection (RequestAttack/StopAttack flow)
- [x] Dual XP system (character level from kills + stat XP from using skills)
- [x] Enemy speed nerf (reduced by 2-3 across all tiers)
- [x] Enemy defense stat (all enemies now have defense values)
- [x] Dynamic chase system (re-paths every 0.2s with client position estimation)
- [x] Server-broadcast damage numbers (all players see all hits)
- [x] Killer-locked loot drops
- [x] Player stacking (pathfinding allows same-tile players)
- [x] Combined enemy damage per tick (Rucoy-style — summed into one hit, DEF applied once)
- [x] Enemy level display in overhead UI (computed from defense * 0.6)
- [x] Proper XP-based level progression (Leaderboard stores totalXP, computes level)
- [x] Item equip system + player stat scaling
- [x] NPC shop (coin-based rotating stock, 5-min refresh)
- [ ] Item reroll UI
- [ ] Full DataStore persistence (inventory, equipment)
- [ ] NPC shop (premium currency)
- [ ] Offline player shops
- [x] Full death/respawn flow polish
- [x] Loading screen with retry logic
- [ ] Game name

---

## 📝 Open Decisions
- [ ] Game name
- [ ] Item slots (sword, staff, shield, helmet, chest, legs, boots?)
- [x] Respawn mechanic — 5s timer, death screen, 3s invincibility after respawn
- [ ] Premium currency final name (currently "Crystals")
- [ ] Offline shop slot limit and duration tiers

---

## 🔑 Key Implementation Notes
- **Kill tracking ownership**: KillTrackerService is sole owner of kill counts. Leaderboard.lua does NOT write `Kills.Value` in `refreshDisplay` or save it in `PlayerRemoving`. KillTracker sets `leaderstats.Kills.Value` via `WaitForChild` after load to win the race condition.
- **DataStores in use**: `"Stats"` (Level, Coins via Leaderboard), `"KillTracker_v1"` (kills via KillTrackerService), `"Skills_v1"` (Attack/Defense XP via SkillService), `"Inventory_v1"` (inventory via LootService) — all saved on PlayerRemoving + BindToClose only (batched, no per-kill writes)
- Enemy defense reduction: flat subtraction — `max(1, enemy_damage - DEF_Level)`
- Attack bonus: `GetAttackLevel(player)` → ATK stat level; baseATK = `Config.BASE_ATK` (15)
- Damage: `(ATK_Level × BASE_ATK) / 20` to `/10`, accuracy check vs enemy defense, roll minus defense
- Attack XP: 1 per enemy hit (CombatService); Defense XP: 1 per combined tick taken (EnemyService `processDamageAccumulator`, not per enemy)
- `SkillUpdated` fires after every XP grant + on CharacterAdded (0.5s delay) for HUD init
- Loot drop chain: `EnemyService._Kill` → `KillTrackerService.RegisterKill` + `LootService.Drop` → world Part → pickup loop → `InventoryUpdated`
- `ItemData._byRarity[rarityName]` pre-built array for fast random picks
- Inventory slot template children must be named `ItemIcon` (ImageLabel) and `ItemLabel` (TextLabel)
- Main.server.lua boot order: TileGrid → Movement → Skills → Enemy → KillTracker → Loot → Combat → Leaderboard → Shop
- **Unified movement sequence**: All movement (click-to-move via `playerMoveSeq`, walk-to-enemy via `CancelMovement`, death, StopAttack) uses ONE counter in MovementService. `walkToEnemy` calls `CancelMovement` which increments `playerMoveSeq`, invalidating both click-to-move and previous walk-to-enemy delayed tasks. This prevents `playerTiles` corruption from concurrent movement systems.
- **Dynamic chase system**: `startChase` replaces static `walkToEnemy`. Uses time-based client position estimation (`estimatePlayerTile`) — tracks when the last path was sent and the player's speed, then calculates how many steps the client has completed via `floor(elapsed / speed)`. Range check and pathfinding both use the estimated position, not the stale server tile. Re-evaluates every 0.2s (`REVAL_INTERVAL`).
- **Forward declaration pattern**: `startChase` uses `local startChase` forward declaration to resolve circular runtime dependency with `doAttackTick` (which calls `startChase` inside `task.defer`). In Lua, upvalues capture the variable, not the value — so the deferred callback sees the assigned function by call time.
- **Combined enemy damage**: `queueDamage(player, amount)` adds to `pendingDamage[userId]`. Processor runs every 0.5s (`DAMAGE_TICK`), sums all raw damage per player, applies DEF once via `max(1, totalRaw - defLevel)`, and grants DEF XP once. This makes group fights much more dangerous — 4 enemies each doing 10 damage = combined hit of 40 minus DEF, not 4 separate hits of 10 minus DEF each.
- **Leaderboard.level → Leaderboard.totalXP**: `rawStats[userId]` now stores `totalXP` instead of `level`. On load, if old data contains `level` without `totalXP`, it migrates by deriving XP from the level table. `Leaderboard.AddXP(player, amount)` adds to `totalXP` and recomputes `Level.Value` via `Skills.LevelFromXP`. DataStore saves `{ totalXP, coins }`.
- **Enemy level display**: `getEnemyLevel(enemyName)` computes `max(1, floor(defense * 0.6))`. Displayed in overhead BillboardGui as `[Lv.X] EnemyName`. Also stored as model attribute `Level` for client-side use.
- **Inventory tooltip**: Uses a dedicated `TooltipGui` ScreenGui with `DisplayOrder = 99` (separate from `MainGui`) so the tooltip always renders above the inventory panel regardless of `ZIndexBehavior` mode (Sibling vs LayoutOrder). Position is calculated relative to `tooltipGui.AbsolutePosition`.
- **Inventory sort stability**: `refreshInventory` sorts by rarity → name → **item ID**. Without the ID tiebreaker, two items with identical name+rarity would swap positions on every rebuild, making equipped item strokes visually jump between identical items.
- **Equip click reads fresh attributes**: The click handler reads `ItemId`, `ItemEquipped`, `ItemSlot` from the slot Frame's Attributes (not closure-captured `item` table). Attributes are kept in sync by both `refreshInventory` (slot creation) and `refreshEquipment` (stroke updates), ensuring the correct action is taken even if UI is stale.
- **refreshEquipment brief visual feedback**: `refreshEquipment` fires first (server sends it before `InventoryUpdated`) and updates strokes on existing slot Frames for immediate visual feedback. `refreshInventory` then destroys all slots and recreates from serialized data, providing the authoritative final state.
- **Death/respawn flow**: `Players.CharacterAutoLoads = false` in Main.server.lua. On `Humanoid.Died`: server fires `PlayerDied`, waits `RESPAWN_DELAY` (5s), destroys old character, calls `player:LoadCharacter()`, fires `PlayerRespawn`, sets `InvincibleUntil` attribute. Client `DeathScreen.client.lua` shows black overlay + countdown on `PlayerDied`, hides on `PlayerRespawn`/`CharacterAdded`. `EnemyService.processDamageAccumulator` checks `InvincibleUntil` to skip damage during the 3s post-respawn window. Existing `CharacterAdded` handlers in MovementService/CombatService/HUDController/IsoCamera handle re-initialization naturally.
- **Loading screen**: `LoadingClient.client.lua` in `StarterGui/LoadingGui` runs before all other scripts. Shows a branded overlay with progress bar. Validates 6 steps: game engine loaded → core modules (Config, Pathfinder, etc.) → server remotes (RequestMove, PlayerDied, etc.) → world map (Map/TileGrid/Tiles) → enemy spawning → final config sanity check. Each step retries up to 3 times with 1.5s delay before moving on. On total failure (all retries exhausted for a step), restarts the entire sequence from step 1. Fades out on success.
- **Hold-to-target system**: `TargetingController.lua` provides a hold-E targeting mode. While E is held, a glowing cyan circle-on-chain follows the mouse cursor, connected to the player by a chain of beads + a 3D beam. Auto-snaps to the closest enemy within 60px screen distance with pop particles + sound. Releasing E fires `RequestAttack` to the server if snapped target is within 14 studs. CombatController and MovementController skip click input when targeting is active. Circle turns gold when snapped, pulses, and emits particle bursts on snap/unsnap.

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
baseATK = Config.BASE_ATK (15, scales with equipment later)
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
| 1 (Common) | 1-6 | Noobini: 1, Pipi Kiwi: 5 |
| 2 (Rare) | 8-18 | Trippi Troppi: 8, Frogo Elfo: 18 |
| 3 (Epic) | 25-43 | Cappuccino: 25, Penguino: 43 |
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
- All enemy damage per tick combined into one hit (not per-enemy calculation)
- DEF XP granted once per combined tick, not per enemy attack — slower DEF progression
- Leaderboard stores cumulative XP (`totalXP`), Level.Value is computed via `Skills.LevelFromXP`