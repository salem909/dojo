extends Node
## Protocol constants and message shapes.
## Single source of truth for client and server.

const PROTOCOL_VERSION: int = 1

# Network defaults
const DEFAULT_PORT: int = 24565
const DEFAULT_HOST: String = "127.0.0.1"
const MAX_CLIENTS: int = 32

# Game tick rate (server authoritative)
const TICK_HZ: int = 60
const TICK_DT: float = 1.0 / 60.0

# Player movement bounds (sanity-check on server)
const MAX_MOVE_SPEED: float = 3.0
const MAX_POS_DELTA: float = 4.0  # per tick, anti-teleport

# Spawn point on the ship deck
const SPAWN_POSITION: Vector3 = Vector3(0.0, 0.0, 0.0)

# Puzzle minigame ids
enum PuzzleId { NONE = 0, MATCH3_BILGE = 1, SWORD = 2 }

# Puzzle result rewards (server-validated)
const REWARD_MATCH3_PER_MATCH: int = 5
# Sword: doubloons awarded per 10 puzzle-score points at game end.
# The puzzle's internal score already folds in per-piece values and chain
# multipliers (see sword_logic.gd), so we simply divide at payout.
const SWORD_SCORE_TO_DOUBLOONS_DIVISOR: int = 10

# Zone / scene routing
enum Zone { SHIP = 0, ISLAND = 1 }
const ZONE_SCENES: Array = [
	"res://scenes/client/world.tscn",
	"res://scenes/client/island.tscn",
]
# Where a player appears when arriving through a portal into each zone.
const PORTAL_EXIT: Array = [
	Vector3(-8.0, 0.0,   0.0),   # arrive on ship (flat deck at y=0)
	Vector3( 0.0, 10.0, -10.0),  # arrive on island (above terrain; ground-follow snaps down)
]

# Player character classes
enum CharacterClass { WARRIOR = 0, ROGUE = 1, MAGE = 2, MINION = 3 }
const CHARACTER_MODELS: Array = [
	"res://assets/models/characters/Skeleton_Warrior.glb",
	"res://assets/models/characters/Skeleton_Rogue.glb",
	"res://assets/models/characters/Skeleton_Mage.glb",
	"res://assets/models/characters/Skeleton_Minion.glb",
]
const CHARACTER_NAMES: Array = ["Warrior", "Rogue", "Mage", "Minion"]

# Puzzle skill ranking
enum PuzzleRank { ABLE = 0, DISTINGUISHED = 1, RESPECTED = 2, MASTER = 3, RENOWNED = 4 }
const RANK_NAMES: Array = ["Able", "Distinguished", "Respected", "Master", "Renowned"]
const RANK_WIN_THRESHOLDS: Array = [0, 5, 15, 30, 50]  # wins to reach each tier

# Inventory item ids
enum ItemId { PLANK = 0, RUM = 1 }
const ITEM_NAMES: Array = ["Plank", "Rum"]
const BILGE_PLANKS_PER_SCORE: int = 10  # 1 plank per 10 bilge-score earned

# Authentication error codes (returned by server_authenticate / server_register)
enum AuthError {
	OK              = 0,
	BAD_USERNAME    = 1,  # too short, too long, or invalid characters
	USERNAME_TAKEN  = 2,  # registration: username already exists
	BAD_CREDENTIALS = 3,  # login: username not found or wrong password
	ALREADY_ONLINE  = 4,  # account already has an active session
}

# ─── Chat ────────────────────────────────────────────────────────────────────
const MAX_CHAT_LENGTH: int = 200       # max characters in a single message
const MAX_CHAT_HISTORY: int = 50       # messages kept in client-side history

enum ChatChannel {
	SAY    = 0,  # scene-local speak (visible in same zone)
	CREW   = 1,  # crew-wide chat
	SYSTEM = 2,  # server announcement
}
const CHAT_CHANNEL_COLORS: Array = [
	Color(1.00, 1.00, 1.00, 1),  # SAY — white
	Color(0.50, 0.85, 1.00, 1),  # CREW — light blue
	Color(1.00, 0.75, 0.25, 1),  # SYSTEM — amber
]
const CHAT_CHANNEL_PREFIXES: Array = ["", "[Crew] ", "[System] "]

# ─── Crew ────────────────────────────────────────────────────────────────────
const MIN_CREW_NAME_LEN: int = 3
const MAX_CREW_NAME_LEN: int = 24

enum CrewError {
	OK              = 0,
	BAD_NAME        = 1,  # name too short/long or bad chars
	NAME_TAKEN      = 2,  # crew name already exists
	ALREADY_IN_CREW = 3,  # player is already in a crew
	NOT_IN_CREW     = 4,  # leave-when-no-crew
	TARGET_OFFLINE  = 5,  # invite target not online
	NO_SUCH_PLAYER  = 6,  # target pirate name not found
	SELF_TARGET     = 7,  # can't invite yourself
}
