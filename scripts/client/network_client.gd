extends Node
## Thin client adapter. The actual RPCs live in the Game autoload — this node
## just registers the local world root with Game so client_player_spawned can
## attach visuals to the right parent, and re-emits Game's signals for the
## scene-local code that wants to listen.

@warning_ignore("unused_signal")
signal match3_started(board: Array, score: int)
@warning_ignore("unused_signal")
signal match3_updated(board: Array, score: int, last_matched: int)
@warning_ignore("unused_signal")
signal match3_finished(final_score: int)

var world_root: Node3D:
	set(value):
		world_root = value
		if Game != null:
			Game.client_set_world_root(value)

func _ready() -> void:
	Game.match3_started_sig.connect(func(b, s): match3_started.emit(b, s))
	Game.match3_updated_sig.connect(func(b, s, m): match3_updated.emit(b, s, m))
	Game.match3_finished_sig.connect(func(s): match3_finished.emit(s))

# Convenience pass-throughs used by world.gd / player_controller.gd / match3_view.gd

func send_move(target_pos: Vector3, yaw: float) -> void:
	Game.client_send_move(target_pos, yaw)

func request_match3_start() -> void:
	Game.client_request_match3_start()

func send_match3_swap(a: Vector2i, b: Vector2i) -> void:
	Game.client_send_match3_swap(a, b)

func request_match3_end() -> void:
	Game.client_request_match3_end()

# Expose Game's remote_players dict so world.gd's "find my own avatar" loop works.
var remote_players: Dictionary:
	get: return Game.remote_players if Game else {}
