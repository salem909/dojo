extends RefCounted
## Plain data container for one player on the server.

var peer_id: int = 0
var account_id: String = ""        # persistent identifier; lowercase username
var display_name: String = ""
var character_class: int = 0       # Protocol.CharacterClass
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var doubloons: int = 0             # pocket doubloons; persisted to DB
var bank_doubloons: int = 0        # safely deposited; persisted to DB
var zone: int = 0                  # Protocol.Zone value; 0 = ship (default spawn)
var puzzle_wins: Dictionary = {}   # puzzle_id (int) → win count
var puzzle_losses: Dictionary = {} # puzzle_id (int) → loss count
var inventory: Dictionary = {}     # item_id (int) → quantity
var crew_id: String = ""           # crew key (lowercase name); "" = no crew
var crew_name: String = ""         # display name of the crew
var pending_crew_invites: Array = [] # array of {from_peer, from_name, crew_id, crew_name}
