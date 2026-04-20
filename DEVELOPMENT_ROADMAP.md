# AtlariousPuzzles — Development Roadmap
## 3D Multiplayer MMO Puzzle Game (Godot 4.3)

**Generated**: 2026-04-15  
**Based on**: Reverse engineering of Yohoho! Puzzle Pirates architecture  
**Total Scope**: 16 weeks (4 phases)  
**Target**: Minimum Viable MMO with core gameplay loop

---

## ✅ PHASE 1 COMPLETE (2026-04-15)

**Status**: All Phase 1 success criteria met — players can log in, see each other, **chat**, navigate zones, form crews, and look each other up.

**Phase 1 deliverables (actual):**
- ✅ Network layer: ENet, server-authoritative, 60Hz tick
- ✅ Authentication: SHA256 x2 hashed passwords, JSON DB, anti-double-login
- ✅ Character system: 4 classes (Warrior/Rogue/Mage/Minion) w/ Kaykit models, full animation states
- ✅ World: 2 zones (Ship/Island), portal traversal, occupant tracking, ocean + terrain + vegetation
- ✅ Movement: WASD + sprint + jump, terrain raycast, client prediction + server auth
- ✅ **Chat system**: scene-local SAY + crew-wide CREW channels, slash commands (/c /who /help /crew ...)
- ✅ **Crew system**: create / leave / invite / accept-or-decline via in-chat popup, persisted in `user://db/crews.json`
- ✅ **Player info lookup**: `/who <name>` returns name/class/crew/online-status/ratings, works for both online and offline pirates
- ✅ Bonus from Phase 2: Match3 Bilging puzzle with banking + rank progression

**Next**: Move into Phase 2 (Puzzle Engine) — implement Sword and Boxing puzzles.

---

## 🟡 PHASE 2 IN PROGRESS (2026-04-15)

**Phase 2.1 — Swordfighting MVP: ✅ COMPLETE**

Implementation grounded in two references (both quoted in `sword_logic.gd` header):
- yppedia.puzzlepirates.com/Swordfight — player-facing mechanics
- `C:\Users\USER\Desktop\PP\yoclient\FULL_ANALYSIS.md` §4 — internal block values & rating ID

Delivered:
- ✅ Pure logic `scripts/puzzles/sword/sword_logic.gd` (6×13 board, 4 colors, solid/breaker/strike/sword/sprinkle cell encoding, flood-fill shatter, 2×2 rectangle fuse, chain multiplier, spawn-at-column-3 game-over)
- ✅ Client view `scripts/puzzles/sword/sword_view.gd` + scene `scenes/puzzles/sword/sword_ui.tscn` (A/D move, W rotate, Space drop)
- ✅ Server RPCs in `game.gd` (start / move / rotate / drop / end / finalize, with per-peer `sword_sessions`)
- ✅ Sword dueling station added to `scenes/client/world.tscn` (red box south-east of the bilging pump)
- ✅ Protocol extended: `PuzzleId.SWORD = 2`, `SWORD_SCORE_TO_DOUBLOONS_DIVISOR = 10`
- ✅ Sword results persisted as a separate puzzle (own W/L record, separate rank progression)
- ✅ 26 unit tests in `tests/test_sword_logic.gd`, all passing
- ✅ Match3 tests still green; integration smoke test confirms server + client start cleanly

Turn-based MVP intentionally defers real-time gravity (the server does not tick the pair down on a clock; the player hard-drops via Space). This isolates every bit of game logic under unit tests. Real-time gravity is a trivial addition: a `Timer` per session that calls `session.drop_pair()` at a difficulty-scaled interval.

**Phase 2.x.2 — Bytecode-grounded fidelity pass: ✅ COMPLETE (2026-04-16)**

A subagent did a deep read of `C:\Users\USER\Desktop\PP\yoclient\docs\dissasmble\com\threerings\piracy\puzzle\sword\` and the parent drop-puzzle framework. Concrete findings, citations, and fixes:

| Bytecode finding | Citation | Fix in our code |
|---|---|---|
| Strikes are 3-stage decaying (256→384→512→0), aged per board lock | SwordBoard.updateStrikePieces:362-438 | Added `strike_age[][]` parallel array, `STRIKE_MAX_AGE=3`, `_age_strikes()` runs after every lock; expired strikes vanish |
| Strike-size tier thresholds `{24, 28, 34, 38}` → 4 reward tiers | sword/data/c.jbc:25-44 | `STRIKE_TIER_THRESHOLDS` + tiered bonus per strike `[5,10,18,30,50]` |
| Sprinkle volley tiers `{0, 4, 12}` → small/med/large volleys | sword/data/c.jbc:8-24 | `SPRINKLE_TIER_THRESHOLDS` + `SPRINKLE_TIER_COUNTS=[1,3,6]` |
| 8 distinct color slots, standard play uses 4 | Sword.jbc:34-42 | `NUM_COLORS_DEFAULT=4`, `NUM_COLORS_MAX=8`; client palette extended to 8 |
| Drop velocity = 0.01 × (difficulty+1) | SwordObject.jbc:37-46 | `seed_board(seed, difficulty, colors, dmg_level)`; interval lerps 800ms→100ms |
| Two-direction rotate: VK_UP=CCW, VK_DOWN=CW | puzzle/client/v.jbc:271-290 | Added `rotate_pair_cw()` + `rotate_pair_ccw()`; client view: W/↑=CCW, S/↓=CW |
| **No hard-drop in PP** — only Space-held soft-drop | puzzle/client/v.jbc:301-307 | Removed Space=hard-drop binding; Space now toggles `set_soft_dropping(true/false)`; soft-drop divides interval by `SOFT_DROP_MULTIPLIER=8` |
| Damage-level pre-seeding for resumed/harder games | SwordBoard.populate:139-205 | `populate_with_damage(level)` fills bottom rows with sprinkles |

Also added: strike_age in `export_state` → client renders strikes with freshness tint (bright/amber/red as they age toward decay), so the player sees the urgency. Hint text updated to "A/D move • W↺ S↻ • Hold Space to fall faster".

24 new unit tests cover all the above mechanics. **64 sword tests passing**, 11 match3 tests passing, integration smoke test green.

`drop_pair()` (hard drop) kept as test API and an emergency keybind we can re-enable later — never wired to user input.

**Phase 2.x.1 — Real-time gravity (earlier today)**: `sword_logic.gd` exposes `tick(delta_ms)` driven by the 60Hz `_on_world_tick`; lock-delay grace window with tuck support; soft-drop + hard-drop primitives. Was superseded UX-wise by 2.x.2 (Space is no longer hard-drop in PP), but the underlying tick infrastructure carried forward unchanged.

**Phase 2.2 — Next up**: Boxing (10×21 hex grid, angle-based shooting). Same architectural pattern: pure logic + view + server RPCs + tests.

**Phase 2.3 — After that**: AI opponent, PvP synchronization, rating-based matchmaking.

---

## 📋 PROJECT OVERVIEW

### Objective
Build a modern 3D multiplayer MMO puzzle game in Godot 4.3, inspired by the architecture and mechanics of Yohoho! Puzzle Pirates.

### What You've Reverse-Engineered
- ✅ Complete client architecture (6,179 JBC files)
- ✅ All 60+ service protocols and marshallers
- ✅ Full game systems (sea, islands, puzzles, economy, crew, combat)
- ✅ Rendering pipeline (LWJGL/OpenGL)
- ✅ Authentication and networking (Narya distributed objects)
- ✅ 9 puzzle game mechanics with board generation

### Current State (Godot 4.3)
- ✅ Project structure initialized
- ✅ Island terrain system started
- ✅ Ocean water system started
- ✅ Character model assets
- ✅ Settings menu UI
- ✅ Camera rig & player controller scripts

---

## 🎯 STRATEGIC DECISIONS (MAKE NOW)

### Decision 1: Network Architecture (Week 1 - CRITICAL)

**Option A: Godot MultiplayerAPI (Native)**
- ✅ Built-in, easy synchronization
- ✅ Less boilerplate
- ❌ Less control over network behavior
- ❌ Harder to replicate legacy system

**Option B: Custom TCP/WebSocket (Flexible)**
- ✅ Full control over protocol
- ✅ Can replicate legacy Narya
- ✅ Better for server scalability
- ❌ More development work
- ❌ Requires custom serialization

**RECOMMENDATION: Option B**
- You've reverse-engineered the complete protocol
- Gives you architectural parity with legacy
- Scales better for production MMO
- Better for debugging/testing

### Decision 2: 3D vs 2D Puzzles (Week 2 - CRITICAL)

**Legacy**: 2D drop-puzzle (Java Swing panels)

**Option A: Keep 2D (Godot Control)**
- ✅ Exact gameplay parity
- ✅ Easier to implement
- ✅ Faster performance
- ✅ Use your existing match3_view.gd as base

**Option B: Make 3D (Godot 3D world)**
- ✅ More immersive
- ✅ Better MMO feel
- ❌ Harder puzzle UI/interaction
- ❌ Performance cost
- ❌ More animation work

**RECOMMENDATION: Hybrid Approach**
- Puzzle UI: 2D Control overlay (match3_view.gd exists)
- Match effects: 3D particles in background
- Character idle: 3D avatar visible behind puzzle

### Decision 3: Database Strategy (Week 1 - CRITICAL)

**Legacy**: SQLite (single-server)

**Options:**
- A) SQLite (development/small scale) ← START HERE
- B) PostgreSQL (scalable production)
- C) MySQL (middle ground)

**RECOMMENDATION: Start SQLite**
- Fast iteration
- Easy local testing
- Migrate to PostgreSQL later
- Keep schema from legacy analysis

### Decision 4: Physics/Movement (Week 2)

**Legacy**: Swing-based, no physics

**RECOMMENDATIONS for Godot:**
- Player movement: CharacterBody3D (not physics-based)
- Puzzle physics: None (logic-based matching)
- Object interaction: Area3D triggers
- Water/environment: Physics-based if needed
- Ships/boats: RigidBody3D for naval

**ACTION**: Review existing player_controller.gd, decide on approach

---

## 📅 DETAILED PHASE BREAKDOWN

## PHASE 1: FOUNDATION (Weeks 1-4) — MVP Network Core

**Objective**: Establish working client-server with core gameplay loop  
**Success Criteria**: "Players can log in, see each other, chat, and navigate zones"

### Week 1: Network Architecture + Authentication

**Deliverables:**
- [ ] Client-server TCP connection established
- [ ] Session creation and validation
- [ ] Basic RPC framework for service calls
- [ ] User authentication (AES+RSA or TLS)

**Files to Create/Modify:**
```
scripts/network/
├─ connection.gd           # Network transport layer
├─ rpc_framework.gd        # RPC call serialization
├─ message_queue.gd        # Async message handling
└─ auth_handler.gd         # Authentication flow

scripts/data/
├─ network_message.gd      # Message structure
└─ serialization.gd        # JSON/binary serialization
```

**Server Requirements:**
- Accept TCP connections on port 47624
- Validate credentials against accounts table
- Return session token + bootstrap data
- Implement heartbeat/keepalive mechanism

**Testing:**
- [ ] Client connects without error
- [ ] Multiple clients can connect simultaneously
- [ ] Session tokens issued and validated
- [ ] Network timeout handling works

---

### Week 1-2: Character System

**Deliverables:**
- [ ] Character creation with appearance (charPrint system)
- [ ] Pirate selection screen
- [ ] 3D character spawning in world
- [ ] Equipment visualization (sword/mug/glove/trinket/pet)

**Data Model (YoUserObject → Godot):**
```gdscript
class_name CharacterData extends Resource

@export var user_id: int
@export var account_id: int
@export var pirate_name: String
@export var character_print: PackedInt32Array  # [13] components
@export var species: int
@export var faction: int
@export var equipment: Dictionary = {
    "sword": -1,
    "mug": -1,
    "glove": -1,
    "trinket": -1,
    "pet": -1
}
@export var inventory: Array[Item] = []
@export var crew_id: int = -1
@export var crew_name: String = ""
@export var ratings: Dictionary = {}  # puzzle_type -> rating
```

**Files to Create:**
```
scripts/data/
├─ character_data.gd       # Character resource
├─ appearance_generator.gd # charPrint → visual mapping
└─ item_definitions.gd     # Item types/properties

scenes/ui/
├─ character_creation.tscn # Creation UI
└─ character_creation.gd   # Logic

scenes/character/
├─ character_3d.tscn       # 3D model with attachment points
└─ character_animator.gd    # Animation state machine
```

**Server Requirements:**
- Store pirates in database
- Validate names (no duplicates, content filter)
- Generate charPrint (appearance encoding)
- Return available pirates on login

**Testing:**
- [ ] Create character with appearance
- [ ] Select from multiple pirates
- [ ] Character spawns in world with correct look
- [ ] Equipment slots visible

---

### Week 2-3: World Foundation

**Deliverables:**
- [ ] Multiple islands load properly
- [ ] Player can traverse between zones
- [ ] Portal system works
- [ ] Other players visible in zones

**Zone/Island System (Whirled → Godot):**
```gdscript
class_name ZoneData extends Resource

@export var zone_id: int
@export var zone_name: String
@export var scenes: Array[SceneInfo] = []

class SceneInfo:
    var scene_id: int
    var scene_name: String
    var scene_model: String  # Path to .tscn
    var portals: Array[Portal] = []

class Portal:
    var portal_id: int
    var source_pos: Vector3
    var dest_zone: int
    var dest_scene: int
    var dest_pos: Vector3
```

**Files to Create:**
```
scripts/world/
├─ zone_manager.gd         # Zone loading/tracking
├─ scene_manager.gd        # Scene lifecycle
├─ portal_system.gd        # Portal traversal
├─ occupant_tracker.gd     # Who's where
└─ scene_loader.gd         # Load .tscn dynamically

scenes/world/
├─ island_docks.tscn       # 3D scene for docks
├─ island_town.tscn        # Town area
├─ island_interior.tscn    # Shop interior (example)
└─ templates/
   └─ portal.tscn          # Portal prefab

scripts/data/
└─ world_layout.gd         # Island positions, connections
```

**Server Requirements:**
- Store zone/scene definitions
- Load scene models from disk (cached)
- Track player locations
- Send scene data + occupant list on zone enter
- Handle portal traversal requests

**Testing:**
- [ ] Island loads when entered
- [ ] Other players visible in zone
- [ ] Can walk through portal
- [ ] Arrive at correct destination

---

### Week 3-4: Basic Gameplay Loop

**Deliverables:**
- [ ] Players can move and see each other
- [ ] Chat works locally in scenes
- [ ] Crew system functional
- [ ] Basic player info visible

**Movement & Interaction:**
```gdscript
# Expand scripts/client/player_controller.gd
- WASD movement
- Mouse look
- Portal detection/activation
- Interaction radius
- Animation state
```

**Social Systems:**
```
scripts/social/
├─ chat_manager.gd         # Message routing
├─ chat_ui.gd              # Chat panel
├─ player_info.gd          # Profile lookup
├─ crew_manager.gd         # Crew operations
└─ friends_list.gd         # Friends tracking

scenes/ui/
├─ chat_panel.tscn
├─ player_profile.tscn
└─ crew_panel.tscn
```

**Files to Create:**
```
scripts/services/
├─ chat_service.gd         # Chat RPC wrapper
├─ crew_service.gd         # Crew RPC wrapper
├─ info_service.gd         # Player info RPC wrapper
└─ location_service.gd     # Movement RPC wrapper
```

**Server Requirements:**
- Implement SpeakService (scene-wide chat)
- Implement CrewService (create, join, leave)
- Implement InfoService (player lookup)
- Implement LocationService (movement tracking)
- Broadcast occupant updates

**Testing:**
- [ ] Type chat, see other players receive it
- [ ] Create crew, invite player, accept
- [ ] Look up player info
- [ ] Movement visible in real-time

---

## PHASE 2: PUZZLE ENGINE (Weeks 5-8) — Core Gameplay

**Objective**: Implement 2-3 core puzzle games (Sword, Boxing, Bilging)  
**Success Criteria**: "Players can play puzzles against AI and each other, scores save"

### Week 5: Puzzle Framework

**Deliverables:**
- [ ] Match-3 mechanics working
- [ ] Board generation deterministic
- [ ] Drop/match physics functional

**Puzzle Architecture:**
```gdscript
class_name PuzzleGame extends Node

@export var puzzle_type: int  # 0=sword, 27=boxing, 2=bilging
@export var difficulty: int   # 0-10
@export var seed: int         # For deterministic boards
@export var board: Array[Array] = []

var piece_types: int
var board_width: int
var board_height: int
var score: int = 0
var chains: int = 0

# Core mechanics
func drop_piece() -> void: pass
func match_check() -> Array: pass
func cascade() -> void: pass
func calculate_damage() -> int: pass
```

**Files to Create:**
```
scripts/puzzles/
├─ puzzle_game.gd           # Base puzzle class
├─ puzzle_board.gd          # Board state + logic
├─ match3_engine.gd         # Match detection
├─ piece_physics.gd         # Drop/animate pieces
├─ difficulty_scaler.gd     # Difficulty mechanics
└─ scoring.gd               # Score calculation

scenes/puzzles/
├─ puzzle_game.tscn         # Main puzzle scene
├─ game_board.tscn          # Grid display
└─ piece.tscn               # Individual piece
```

**Board Specification (from legacy):**

**SWORD:**
- 6x13 grid
- 5-6 colors
- Strike pieces in 3 stages (256→384→512)
- Damage rows fill from bottom
- Rating Type: 0

**BOXING:**
- 10x21 hexagonal grid
- 5 colors + 10% black pieces
- Angle-based shooting
- Rating Type: 27

**BILGING:**
- 6x12 swap puzzle
- 5-7 colors by difficulty
- Special pieces: Pufferfish, Crab, Jellyfish
- 20% bonus token probability
- Rating Type: 2

**Testing:**
- [ ] Board generates from seed reproducibly
- [ ] Pieces drop and match correctly
- [ ] Cascades work
- [ ] Score calculation accurate

---

### Week 6-7: Implement 3 Puzzles

**Deliverables:**
- [ ] Sword puzzle fully playable
- [ ] Boxing puzzle fully playable
- [ ] Bilging puzzle fully playable

**Sword Implementation (Priority 1):**
```
Week 6 Day 1-2
├─ Board state + rendering
├─ Piece dropping + animation
├─ Match detection (horizontal/vertical)
├─ Row damage calculation
├─ Score display

Week 6 Day 3-5
├─ Piece removal + cascade
├─ Combo multiplier
├─ Game end condition
├─ UI (score, health, timer)
```

**Boxing Implementation (Priority 2):**
```
Week 7 Day 1-2
├─ Hexagonal grid rendering
├─ Shooting mechanic (angle + power)
├─ Piece collision detection
├─ Damage calculation

Week 7 Day 3-5
├─ Combo system
├─ Time limit per turn
├─ Game flow (turn-based)
├─ Result screen
```

**Bilging Implementation (Priority 3):**
```
Week 7 Day 5+
├─ Swap mechanic (click pieces to swap)
├─ Board generation (different layouts)
├─ Special piece logic
├─ Bonus token probability
```

**Files Expand:**
```
scripts/puzzles/
├─ sword_game.gd
├─ boxing_game.gd
├─ bilging_game.gd
├─ sword_ai.gd              # AI for sword
├─ boxing_ai.gd             # AI for boxing
└─ bilging_ai.gd            # AI for bilging
```

**Server Requirements:**
- PuzzleGameProvider service
- updateProgress RPC (streaming score updates)
- calculateDamage RPC (for PvP)
- endGame RPC (save results)

**Testing:**
- [ ] Play solo against AI
- [ ] AI makes reasonable moves
- [ ] Game ends correctly
- [ ] Scores display properly

---

### Week 7-8: AI + Networking + Ratings

**Deliverables:**
- [ ] AI plays at multiple difficulties
- [ ] PvP puzzle game with sync
- [ ] Ratings persist on server
- [ ] Leaderboards functional

**AI Difficulty Levels (11 from legacy):**
```gdscript
# Difficulty 0-10, with baseDestroy parameter
var difficulty_table = {
    0:  {base_destroy: 0.07, think_time: 5000},
    1:  {base_destroy: 0.10, think_time: 4500},
    2:  {base_destroy: 0.12, think_time: 4000},
    5:  {base_destroy: 0.25, think_time: 2000},
    7:  {base_destroy: 0.35, think_time: 1500},
    10: {base_destroy: 0.60, think_time: 800},
}
```

**AI Move Generation:**
```gdscript
class_name PuzzleAI extends Node

func get_best_move(board: Array[Array], difficulty: int) -> Vector2:
    # 1. Generate all possible moves
    # 2. Score each move (damage potential)
    # 3. Weight by difficulty
    # 4. Return best (with randomness)
    pass
```

**Files to Create:**
```
scripts/puzzles/
├─ puzzle_ai.gd             # Base AI
├─ sword_ai.gd              # Sword-specific AI
├─ boxing_ai.gd             # Boxing-specific AI
├─ bilging_ai.gd            # Bilging-specific AI
└─ ai_move_scorer.gd        # Move evaluation

scripts/ratings/
├─ rating_calculator.gd     # Rating from score
├─ leaderboard_manager.gd   # Leaderboard display
└─ rating_service.gd        # RPC wrapper
```

**PvP Synchronization:**
```gdscript
# Synchronized fields
var opponent_board: Array[Array]
var opponent_score: int
var opponent_health: int
var opponent_combo: int

# Send update every 500ms
func _on_progress_tick():
    rpc("update_progress", score, health, combo, board_state)
```

**Rating System (from legacy):**
```
Puzzle Types:
├─ 0: Sword
├─ 2: Bilging
├─ 3: Sailing
├─ 4: Navigation
├─ 5: Gunnery
├─ 6: Carpentry
├─ 27: Boxing
├─ 31: Rigging
└─ 32: Patching

For each type:
├─ Calculate rating from score
├─ Min/max rating limits
├─ Leaderboard ranking
└─ Achievement unlocks
```

**Server Requirements:**
- Rating calculation from scores
- Leaderboard queries
- Achievement system
- PvP match pairing (difficulty-based)
- Rematch requests

**Testing:**
- [ ] AI plays at correct difficulty
- [ ] PvP boards stay synchronized
- [ ] Ratings calculated correctly
- [ ] Leaderboards display top 100

---

## PHASE 3: ECONOMY & PROGRESSION (Weeks 9-12) — Systems Depth

**Objective**: Add item/economy systems that give progression meaning  
**Success Criteria**: "Gameplay loop feels rewarding with clear progression"

### Week 9-10: Item System

**Deliverables:**
- [ ] Items load from database
- [ ] Equipment affects character appearance
- [ ] Inventory UI fully functional
- [ ] Item persistence working

**Item Hierarchy (from legacy):**
```gdscript
class_name Item extends Resource

@export var item_id: int
@export var bag_id: int
@export var property_id: int  # PERMANENT=1, UNTRADEABLE=2
@export var age: int

# Subclasses
class Sword extends Item:
    @export var type: int      # 0-25
    @export var variation: int # Color encoding

class Bauble extends Item:
    @export var type: int
    @export var color_print: int

class Stackable extends Bauble:
    @export var count: int

class Trinket extends Bauble:
    @export var text: String

class Pet extends Item:
    @export var species: int
    @export var char_print: PackedInt32Array
    @export var name: String
    @export var loyalty: int
    @export var curiosity: int
```

**BagSet Serialization:**
```gdscript
class_name BagSet extends Node

var bags: Dictionary = {}  # bag_id -> Array[Item]
var equipped: Dictionary = {
    "sword": -1,
    "mug": -1,
    "glove": -1,
    "trinket": -1,
    "pet": -1,
}

func serialize() -> PackedByteArray:
    # Serialize all bags + equipped items
    pass

func deserialize(data: PackedByteArray) -> void:
    # Load from network
    pass
```

**Files to Create:**
```
scripts/inventory/
├─ item.gd                  # Base item class
├─ item_definitions.gd      # Item types registry
├─ bag_set.gd               # Inventory container
├─ inventory_manager.gd     # Load/save logic
└─ item_service.gd          # RPC wrapper

scenes/ui/
├─ inventory_panel.tscn
├─ item_slot.tscn
├─ equipment_panel.tscn
└─ item_tooltip.tscn
```

**Inventory UI:**
- Bag grid display (click items to select)
- Equipment slots (5 active items)
- Item tooltips (type, properties, bonuses)
- Drag-drop management
- Trash/drop button
- Trading placeholder

**Server Requirements:**
- ItemProvider service (putItem, takeItem, equipItem)
- Item persistence in database
- Equipment slot validation
- Item durability/decay (optional for Phase 1)

**Testing:**
- [ ] Load inventory from server
- [ ] Equip item, see character appearance change
- [ ] Drop item from inventory
- [ ] Pick up item
- [ ] Equipment persists on logout/login

---

### Week 11: Currency & Shops

**Deliverables:**
- [ ] Currency system working
- [ ] Shops functional on each island
- [ ] Buy/sell mechanics working
- [ ] Currency displayed on UI

**Currency System:**
```gdscript
class_name Purse extends Node

var pieces_of_eight: int = 0    # Main currency
var doubloons: int = 0          # Premium (optional)
var puzzle_points: int = 0      # For progression

func add_currency(type: String, amount: int) -> void:
    match type:
        "poe": pieces_of_eight += amount
        "doubloons": doubloons += amount
        "points": puzzle_points += amount
```

**Shop System:**
```gdscript
class_name BuildingShop extends Node

@export var shop_type: String  # "sword_shop", "tavern", etc.
@export var island_id: int
@export var owner: String

var inventory: Array[ShopItem] = []

class ShopItem:
    var item: Item
    var price: int
    var stock: int
    var respawn_time: int
```

**Files to Create:**
```
scripts/economy/
├─ purse.gd                 # Currency management
├─ shop.gd                  # Shop data
├─ shop_manager.gd          # Shop lifecycle
├─ price_calculator.gd      # Dynamic pricing
└─ store_service.gd         # RPC wrapper

scenes/ui/
├─ shop_panel.tscn
├─ shop_item_slot.tscn
├─ buy_sell_dialog.tscn
└─ currency_display.tscn

scenes/world/
├─ shop_npc.tscn            # Shop vendor
└─ shop_interior.tscn
```

**Shop Mechanics:**
- Buy items with currency
- Sell items for currency
- Shop inventory respawns over time
- Price variations by shop
- Reputation discounts (optional)

**Server Requirements:**
- StoreProvider service (getShops, buyItem, sellItem)
- Price list per shop
- Currency transactions logged
- Fraud detection (anti-cheat)

**Testing:**
- [ ] Buy item from shop
- [ ] See currency decrease
- [ ] Sell item to shop
- [ ] See currency increase
- [ ] Purchased item in inventory

---

### Week 12: Progression Systems

**Deliverables:**
- [ ] Ratings leaderboards displaying
- [ ] Achievements system working
- [ ] Titles/badges earned and visible
- [ ] Progression feels rewarding

**Rating System (Extended):**
```gdscript
class_name DisplayRatingDetail extends Resource

@export var puzzle_type: int
@export var rating: int
@export var standing: int      # Rank in leaderboard
@export var points: int
@export var rank_name: String  # "Novice", "Journeyman", etc.
```

**Achievements:**
```gdscript
class_name Achievement extends Resource

@export var id: int
@export var name: String
@export var description: String
@export var icon: Texture2D
@export var unlock_condition: String
@export var reward_points: int
```

**Titles:**
```gdscript
class_name Title extends Resource

@export var id: int
@export var name: String
@export var description: String
@export var unlock_achievement: int
@export var display_priority: int
```

**Files to Create:**
```
scripts/progression/
├─ rating_system.gd         # Rating calculations
├─ achievement_manager.gd    # Achievement tracking
├─ title_manager.gd          # Title unlocking
├─ leaderboard_manager.gd    # Leaderboard display
└─ progression_service.gd    # RPC wrapper

scenes/ui/
├─ leaderboard_panel.tscn
├─ achievements_panel.tscn
├─ titles_panel.tscn
└─ stats_display.tscn
```

**Leaderboards:**
- Global (all players)
- Puzzle-specific (per game type)
- Crew leaderboards
- Time-based (weekly, monthly, all-time)
- Top 100 + player's rank

**Server Requirements:**
- Rating calculation algorithm
- Achievement unlock detection
- Leaderboard rankings (cached, updated periodically)
- Title assignment
- Seasonal resets

**Testing:**
- [ ] Play puzzle, rating calculated
- [ ] Appear on leaderboard
- [ ] Achievement unlocks
- [ ] Title displays on profile
- [ ] Leaderboard rankings correct

---

## PHASE 4: ADVANCED FEATURES (Weeks 13-16) — Full MMO

**Objective**: Add depth with crew/vessel/housing systems  
**Success Criteria**: "Full MMO with diverse content"

### Week 13-14: Crew/Alliance Features

**Files to Create:**
```
scripts/crew/
├─ crew.gd                  # Crew data
├─ crew_manager.gd          # Crew operations
├─ crew_roster.gd           # Member management
├─ crew_chat.gd             # Crew chat channel
└─ crew_service.gd          # RPC wrapper

scripts/alliance/
├─ flag.gd                  # Alliance data
├─ flag_manager.gd          # Alliance operations
├─ blockade.gd              # War system
└─ flag_service.gd          # RPC wrapper

scenes/ui/
├─ crew_panel.tscn
├─ crew_roster.tscn
├─ flag_panel.tscn
└─ blockade_map.tscn
```

**Features:**
- Crew creation (captain pays fee)
- Member roles (captain, officer, crew)
- Crew chat channel
- Crew house/hall
- Alliance/flag creation
- Flag colors customization
- Alliance war (blockade system)

---

### Week 14-15: Vessel/Naval System

**Files to Create:**
```
scripts/vessel/
├─ vessel.gd                # Ship data
├─ vessel_manager.gd        # Ship ownership
├─ naval_combat.gd          # Ship battles
├─ sea_navigation.gd        # Ocean traversal
└─ vessel_service.gd        # RPC wrapper

scripts/sea/
├─ ocean_map.gd             # World map
├─ port.gd                  # Island docks
├─ trading_route.gd         # Merchant routes
└─ sea_service.gd           # RPC wrapper

scenes/world/
├─ ocean.tscn               # Ocean environment
├─ ship_deck.tscn           # Ship interior
├─ port.tscn                # Docking area
└─ sea_chart.tscn           # Map UI
```

**Features:**
- Ship purchase from shipyard
- Ship customization (colors, name)
- Crew assignment to ship
- Ocean navigation (island to island)
- Merchant trading routes
- Naval combat (puzzle-based battles)
- Piracy/looting mechanics
- Port services (repair, cargo)

---

### Week 15-16: Housing & Events

**Files to Create:**
```
scripts/housing/
├─ house.gd                 # House data
├─ house_manager.gd         # House ownership
├─ furniture.gd             # Furniture items
├─ interior_design.gd       # Decoration system
└─ house_service.gd         # RPC wrapper

scripts/events/
├─ mission.gd               # Quest data
├─ mission_manager.gd       # Quest system
├─ tournament.gd            # Tournament events
├─ tournament_manager.gd    # Tournament lifecycle
└─ event_calendar.gd        # Event schedule

scenes/world/
├─ house_interior.tscn
├─ house_exterior.tscn
├─ mission_board.tscn
└─ tournament_arena.tscn
```

**Features:**
- House ownership on islands
- Furniture placement and decoration
- House touring (visit other players)
- NPC quest givers
- Mission system with objectives
- Reward structure (items, currency, titles)
- Tournaments (time-limited events)
- Seasonal events
- Leaderboards for events

---

## 📊 CRITICAL PATH CHECKLIST

### Phase 1 (Weeks 1-4)
- [ ] **Week 1**: Network + Auth working
  - [ ] TCP connection established
  - [ ] Session creation working
  - [ ] RPC framework functional
  
- [ ] **Week 1-2**: Character creation
  - [ ] UI for character creation
  - [ ] Appearance generation (charPrint)
  - [ ] 3D model spawning
  
- [ ] **Week 2-3**: World foundation
  - [ ] Island/zone loading
  - [ ] Scene traversal
  - [ ] Portal system
  
- [ ] **Week 3-4**: Gameplay loop
  - [ ] Movement working
  - [ ] Chat functional
  - [ ] Crew system basic
  
**GATE**: Can players login, see each other, and chat?

---

### Phase 2 (Weeks 5-8)
- [ ] **Week 5**: Puzzle framework
  - [ ] Board generation
  - [ ] Match detection
  - [ ] Scoring system
  
- [ ] **Week 6-7**: Implement puzzles
  - [ ] Sword (vs AI)
  - [ ] Boxing (vs AI)
  - [ ] Bilging (vs AI)
  
- [ ] **Week 7-8**: AI + Networking
  - [ ] AI at multiple difficulties
  - [ ] PvP synchronization
  - [ ] Ratings persistence
  
**GATE**: Can players play puzzles and get rated?

---

### Phase 3 (Weeks 9-12)
- [ ] **Week 9-10**: Items
  - [ ] Item loading from DB
  - [ ] Inventory UI
  - [ ] Equipment display
  
- [ ] **Week 11**: Economy
  - [ ] Shops functional
  - [ ] Buy/sell mechanics
  - [ ] Currency persistence
  
- [ ] **Week 12**: Progression
  - [ ] Ratings leaderboards
  - [ ] Achievements
  - [ ] Titles/badges
  
**GATE**: Does progression feel rewarding?

---

### Phase 4 (Weeks 13-16)
- [ ] **Week 13-14**: Crew/Alliance
  - [ ] Crew management
  - [ ] Alliance system
  - [ ] Wars (blockade)
  
- [ ] **Week 14-15**: Vessels
  - [ ] Ship ownership
  - [ ] Ocean navigation
  - [ ] Naval combat
  
- [ ] **Week 15-16**: Housing/Events
  - [ ] House system
  - [ ] Missions/quests
  - [ ] Tournaments
  
**GATE**: Full MMO feature set complete?

---

## 🔧 PROJECT STRUCTURE

```
C:\Users\USER\Desktop\threerings\dojo\
├─ project.godot
├─ DEVELOPMENT_ROADMAP.md          # This file
├─
├─ client/
│  ├─ scenes/
│  │  ├─ ui/
│  │  │  ├─ main_menu.tscn
│  │  │  ├─ settings_menu.tscn
│  │  │  ├─ character_creation.tscn    # NEW
│  │  │  ├─ chat_panel.tscn            # NEW
│  │  │  ├─ inventory_panel.tscn       # NEW
│  │  │  ├─ shop_panel.tscn            # NEW
│  │  │  └─ leaderboard_panel.tscn     # NEW
│  │  │
│  │  ├─ world/
│  │  │  ├─ island.tscn
│  │  │  ├─ island_terrain.tscn
│  │  │  ├─ ocean_water.tscn
│  │  │  ├─ island_docks.tscn          # NEW
│  │  │  ├─ island_town.tscn           # NEW
│  │  │  ├─ shop_interior.tscn         # NEW
│  │  │  └─ ocean.tscn                 # NEW
│  │  │
│  │  ├─ character/
│  │  │  ├─ character_3d.tscn          # NEW
│  │  │  ├─ remote_player.tscn
│  │  │  └─ npc.tscn                   # NEW
│  │  │
│  │  └─ puzzles/
│  │     ├─ puzzle_game.tscn           # NEW
│  │     ├─ sword_game.tscn            # NEW
│  │     ├─ boxing_game.tscn           # NEW
│  │     └─ bilging_game.tscn          # NEW
│  │
│  ├─ scripts/
│  │  ├─ network/                      # NEW
│  │  │  ├─ connection.gd
│  │  │  ├─ rpc_framework.gd
│  │  │  └─ message_queue.gd
│  │  │
│  │  ├─ data/                         # NEW
│  │  │  ├─ character_data.gd
│  │  │  ├─ network_message.gd
│  │  │  ├─ item.gd
│  │  │  └─ serialization.gd
│  │  │
│  │  ├─ services/                     # NEW
│  │  │  ├─ chat_service.gd
│  │  │  ├─ crew_service.gd
│  │  │  ├─ puzzle_service.gd
│  │  │  ├─ item_service.gd
│  │  │  ├─ store_service.gd
│  │  │  └─ rating_service.gd
│  │  │
│  │  ├─ world/                        # NEW
│  │  │  ├─ zone_manager.gd
│  │  │  ├─ scene_manager.gd
│  │  │  ├─ portal_system.gd
│  │  │  └─ occupant_tracker.gd
│  │  │
│  │  ├─ puzzles/                      # NEW
│  │  │  ├─ puzzle_game.gd
│  │  │  ├─ puzzle_board.gd
│  │  │  ├─ match3_engine.gd
│  │  │  ├─ sword_game.gd
│  │  │  ├─ sword_ai.gd
│  │  │  ├─ boxing_game.gd
│  │  │  ├─ boxing_ai.gd
│  │  │  └─ puzzle_ai.gd
│  │  │
│  │  ├─ inventory/                    # NEW
│  │  │  ├─ item_definitions.gd
│  │  │  ├─ bag_set.gd
│  │  │  └─ inventory_manager.gd
│  │  │
│  │  ├─ social/                       # NEW
│  │  │  ├─ chat_manager.gd
│  │  │  ├─ crew_manager.gd
│  │  │  └─ player_info.gd
│  │  │
│  │  ├─ progression/                  # NEW
│  │  │  ├─ rating_system.gd
│  │  │  ├─ achievement_manager.gd
│  │  │  ├─ leaderboard_manager.gd
│  │  │  └─ title_manager.gd
│  │  │
│  │  ├─ client/
│  │  │  ├─ player_controller.gd
│  │  │  ├─ camera_rig.gd
│  │  │  ├─ main_menu.gd
│  │  │  └─ network_client.gd
│  │  │
│  │  └─ shared/
│  │     ├─ protocol.gd                # Keep synchronized with server
│  │     └─ game.gd
│  │
│  ├─ assets/
│  │  ├─ models/characters/
│  │  ├─ shaders/
│  │  └─ sounds/                       # NEW (music, SFX)
│  │
│  └─ export/
│     └─ index.html                    # HTML5 export
│
├─ server/
│  ├─ src/main/java/
│  │  └─ com/threerings/yohoho/
│  │     ├─ YoPirateServer.java
│  │     ├─ YoSession.java
│  │     ├─ YoPirateModule.java
│  │     ├─ auth/
│  │     ├─ data/
│  │     ├─ db/
│  │     ├─ services/
│  │     └─ handlers/
│  │
│  ├─ data/
│  │  ├─ scenes/                       # Scene models (loaded from disk)
│  │  │  ├─ island_docks.json
│  │  │  ├─ island_town.json
│  │  │  └─ ...
│  │  └─ items.json                    # Item definitions
│  │
│  ├─ db/
│  │  └─ yopirates.db                  # SQLite database
│  │
│  └─ lib/
│     └─ (dependencies)
│
└─ docs/
   ├─ PROTOCOL.md                      # Network protocol spec
   ├─ SCHEMA.sql                       # Database schema
   ├─ PUZZLE_MECHANICS.md              # Puzzle details
   └─ API.md                           # Service API
```

---

## 🎯 IMMEDIATE NEXT STEPS (This Week)

### Decision Phase (2 hours)
- [ ] Decide on network architecture (Option A vs B)
- [ ] Decide on puzzle representation (2D vs Hybrid 3D)
- [ ] Choose database (SQLite vs PostgreSQL)
- [ ] Review existing code quality

### Planning Phase (4 hours)
- [ ] Create network protocol specification
- [ ] Design database schema (from legacy analysis)
- [ ] Map YoUserObject → Godot data structures
- [ ] Create project structure

### Prototyping Phase (4+ hours)
- [ ] Network bootstrap code
  ```gdscript
  # scripts/network/connection.gd template
  extends Node
  
  const SERVER_HOST = "localhost"
  const SERVER_PORT = 47624
  
  signal connected
  signal disconnected
  signal error(reason)
  
  var socket: StreamPeer
  var is_connected: bool = false
  
  func connect_to_server() -> bool:
      # TODO: Implement
      pass
  ```

- [ ] Character data resource
  ```gdscript
  # scripts/data/character_data.gd template
  class_name CharacterData extends Resource
  
  @export var user_id: int
  @export var pirate_name: String
  @export var character_print: PackedInt32Array
  @export var equipment: Dictionary
  @export var crew_id: int
  ```

- [ ] Test TCP connection
- [ ] Test character data serialization

---

## 📈 RISK ASSESSMENT & MITIGATION

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **Scope creep** | HIGH | HIGH | Strict phase gates; cut Phase 4 if needed |
| **Networking bugs** | HIGH | MEDIUM | Extensive testing early; replay system |
| **Performance (puzzles)** | MEDIUM | MEDIUM | Profile early; optimize match-3 physics |
| **Asset pipeline** | MEDIUM | MEDIUM | Use Godot imports; batch processing |
| **Server scalability** | MEDIUM | HIGH | Stateless services; design for 100→1000 players |
| **Puzzle balance** | MEDIUM | MEDIUM | Play test AI extensively |
| **Data sync bugs** | HIGH | HIGH | Integration tests; versioning |
| **Art/animation gaps** | MEDIUM | LOW | Use simple placeholders; iterate later |
| **Player retention** | MEDIUM | MEDIUM | Content variety (Phase 2+); events |
| **Security issues** | LOW | HIGH | Input validation; server-side checks |

---

## 💡 STRATEGIC RECOMMENDATIONS

### Do This:
✅ **Leverage reverse engineering** — You have the entire protocol documented  
✅ **Network early** — Build networked, not single-player  
✅ **Ship fast** — 2-week iteration cycles with playable demos  
✅ **Test multiplayer** — Use 50-100 concurrent player tests by Phase 2  
✅ **Keep design docs** — Update protocol.md, schema.sql regularly  

### Don't Do This:
❌ **Don't replicate legacy UI exactly** — Godot's native UI is better  
❌ **Don't over-engineer puzzles** — Match-3 is simple; don't over-complicate  
❌ **Don't build everything before testing** — MVP-first; add complexity later  
❌ **Don't skip database design** — Schema mistakes require costly migrations  
❌ **Don't ignore performance** — Profile puzzles in Week 5, not Week 15  

---

## 📞 SUCCESS CRITERIA BY PHASE

**Phase 1 ✓**: Players log in, see each other, chat, navigate zones  
**Phase 2 ✓**: Players play puzzles, get rated, see leaderboards  
**Phase 3 ✓**: Players buy items, use currency, earn achievements  
**Phase 4 ✓**: Full MMO with crew wars, ships, housing, events  

---

**Generated**: 2026-04-15  
**Author**: AI Development Planner  
**Next Review**: Weekly (Sunday evening)  
**Last Updated**: [Will be updated as phases complete]
