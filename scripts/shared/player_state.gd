extends RefCounted
## Plain data container for one player on the server.

var peer_id: int = 0
var display_name: String = ""
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var doubloons: int = 0  # in-game currency awarded by puzzles
