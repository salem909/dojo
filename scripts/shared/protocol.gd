extends Node
## Protocol constants and message shapes.
## Single source of truth for client and server.

const PROTOCOL_VERSION: int = 1

# Network defaults
const DEFAULT_PORT: int = 24565
const DEFAULT_HOST: String = "127.0.0.1"
const MAX_CLIENTS: int = 32

# Game tick rate (server authoritative)
const TICK_HZ: int = 30
const TICK_DT: float = 1.0 / 30.0

# Player movement bounds (sanity-check on server)
const MAX_MOVE_SPEED: float = 8.0
const MAX_POS_DELTA: float = 12.0  # per tick, anti-teleport

# Spawn point on the ship deck
const SPAWN_POSITION: Vector3 = Vector3(0.0, 1.0, 0.0)

# Puzzle minigame ids
enum PuzzleId { NONE = 0, MATCH3_BILGE = 1 }

# Puzzle result rewards (server-validated)
const REWARD_MATCH3_PER_MATCH: int = 5
