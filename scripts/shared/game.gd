extends Node
## Single autoloaded RPC hub. Lives at `/root/Game` on both server and client,
## so Godot's RPC routing always finds a matching node on the remote peer.
##
## On the server (Net.is_server == true), it owns authoritative state:
##   - players[peer_id] -> PlayerState
##   - match3_sessions[peer_id] -> Match3Logic
## On the client, it owns view state:
##   - remote_players[peer_id] -> Node3D
##   - target_positions, target_yaws (for interp)
## Both roles register the same RPC methods so the registry matches.

const PlayerStateScript := preload("res://scripts/shared/player_state.gd")
const Match3Logic := preload("res://scripts/puzzles/match3/match3_logic.gd")
const RemotePlayerScene := preload("res://scenes/world/remote_player.tscn")

# ────────────────── server-only state ──────────────────
var players: Dictionary = {}
var match3_sessions: Dictionary = {}
var _tick_timer: Timer = null

# ────────────────── client-only state ──────────────────
var world_root: Node3D = null
var remote_players: Dictionary = {}
var target_positions: Dictionary = {}
var target_yaws: Dictionary = {}

const INTERP_SPEED: float = 12.0

# ────────────────── client-side signals ──────────────────
signal match3_started_sig(board: Array, score: int)
signal match3_updated_sig(board: Array, score: int, last_matched: int)
signal match3_finished_sig(final_score: int)

func _ready() -> void:
	# Wire to Net so we hear about peer events as soon as we host or join.
	Net.peer_connected_to_us.connect(_on_peer_joined)
	Net.peer_disconnected_from_us.connect(_on_peer_left)

func become_server() -> void:
	# Called by the server scene after Net.host() succeeded.
	_tick_timer = Timer.new()
	_tick_timer.wait_time = Protocol.TICK_DT
	_tick_timer.autostart = true
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_world_tick)
	add_child(_tick_timer)
	Log.i("game: server mode, tick %dHz" % Protocol.TICK_HZ)

func _process(delta: float) -> void:
	if Net.is_server:
		return
	# Client-side: smoothly interpolate every remote player toward target.
	for peer_id in remote_players.keys():
		var node: Node3D = remote_players[peer_id]
		if not is_instance_valid(node): continue
		var target: Vector3 = target_positions.get(peer_id, node.position)
		var t: float = clamp(delta * INTERP_SPEED, 0.0, 1.0)
		node.position = node.position.lerp(target, t)
		var ty: float = target_yaws.get(peer_id, node.rotation.y)
		node.rotation.y = lerp_angle(node.rotation.y, ty, t)

# ────────────────── server-side handlers ──────────────────

func _on_peer_joined(peer_id: int) -> void:
	if not Net.is_server: return
	var ps := PlayerStateScript.new()
	ps.peer_id = peer_id
	ps.position = Protocol.SPAWN_POSITION
	ps.display_name = "Player%d" % peer_id
	players[peer_id] = ps
	Log.i("spawned player peer=%d at %s" % [peer_id, ps.position])

	# Tell new client about every existing player.
	for existing_id in players.keys():
		var p: Object = players[existing_id]
		rpc_id(peer_id, "client_player_spawned", existing_id, p.display_name, p.position)

	# Tell everyone else about the new player.
	for other_id in players.keys():
		if other_id == peer_id: continue
		rpc_id(other_id, "client_player_spawned", peer_id, ps.display_name, ps.position)

func _on_peer_left(peer_id: int) -> void:
	if not Net.is_server: return
	if not players.has(peer_id): return
	players.erase(peer_id)
	if match3_sessions.has(peer_id):
		match3_sessions.erase(peer_id)
	Log.i("despawned player peer=%d" % peer_id)
	for other_id in players.keys():
		rpc_id(other_id, "client_player_despawned", peer_id)

func _on_world_tick() -> void:
	if not Net.is_server: return
	if players.is_empty(): return
	var snap: Array = []
	for peer_id in players.keys():
		var p: Object = players[peer_id]
		snap.append([peer_id, p.position.x, p.position.y, p.position.z, p.yaw])
	for peer_id in players.keys():
		rpc_id(peer_id, "client_world_snapshot", snap)

# ────────────────── client-side helpers ──────────────────

func client_set_world_root(root: Node3D) -> void:
	world_root = root

func client_send_move(target_pos: Vector3, yaw: float) -> void:
	if multiplayer.multiplayer_peer == null: return
	rpc_id(1, "server_move_input", target_pos, yaw)

func client_request_match3_start() -> void:
	rpc_id(1, "server_start_match3")

func client_send_match3_swap(a: Vector2i, b: Vector2i) -> void:
	rpc_id(1, "server_match3_swap", a.x, a.y, b.x, b.y)

func client_request_match3_end() -> void:
	rpc_id(1, "server_match3_end")

# ────────────────── RPCs: client -> server ──────────────────

@rpc("any_peer", "call_remote", "unreliable_ordered")
func server_move_input(target_pos: Vector3, yaw: float) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var p: Object = players[sender]
	var delta: Vector3 = target_pos - p.position
	if delta.length() > Protocol.MAX_POS_DELTA:
		delta = delta.normalized() * Protocol.MAX_POS_DELTA
	p.position += delta
	p.yaw = yaw

@rpc("any_peer", "call_remote", "reliable")
func server_start_match3() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var session := Match3Logic.new()
	session.seed_board(randi())
	match3_sessions[sender] = session
	rpc_id(sender, "client_match3_started", session.export_board(), session.score)
	Log.i("match3 started for peer=%d" % sender)

@rpc("any_peer", "call_remote", "reliable")
func server_match3_swap(a_x: int, a_y: int, b_x: int, b_y: int) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not match3_sessions.has(sender): return
	var session: Object = match3_sessions[sender]
	var matched: int = session.try_swap(Vector2i(a_x, a_y), Vector2i(b_x, b_y))
	if matched > 0:
		var reward := matched * Protocol.REWARD_MATCH3_PER_MATCH
		session.score += reward
	rpc_id(sender, "client_match3_update", session.export_board(), session.score, matched)

@rpc("any_peer", "call_remote", "reliable")
func server_match3_end() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not match3_sessions.has(sender): return
	var session: Object = match3_sessions[sender]
	var final_score: int = session.score
	match3_sessions.erase(sender)
	rpc_id(sender, "client_match3_finished", final_score)
	Log.i("match3 ended for peer=%d score=%d" % [sender, final_score])

# ────────────────── RPCs: server -> client ──────────────────

@rpc("authority", "call_remote", "reliable")
func client_player_spawned(peer_id: int, display_name: String, pos: Vector3) -> void:
	if Net.is_server: return
	if remote_players.has(peer_id): return
	if world_root == null:
		Log.w("client_player_spawned but world_root not set yet")
		return
	var node: Node3D = RemotePlayerScene.instantiate()
	node.name = "Player_%d" % peer_id
	node.position = pos
	node.set_meta("peer_id", peer_id)
	node.set_meta("display_name", display_name)
	world_root.add_child(node)
	# Set the name label if present.
	var lbl: Node = node.find_child("NameLabel", true, false)
	if lbl != null and lbl is Label3D:
		(lbl as Label3D).text = display_name
	remote_players[peer_id] = node
	target_positions[peer_id] = pos
	target_yaws[peer_id] = 0.0
	Log.i("spawn peer=%d name=%s" % [peer_id, display_name])

@rpc("authority", "call_remote", "reliable")
func client_player_despawned(peer_id: int) -> void:
	if Net.is_server: return
	if remote_players.has(peer_id):
		var node: Node = remote_players[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		remote_players.erase(peer_id)
		target_positions.erase(peer_id)
		target_yaws.erase(peer_id)

@rpc("authority", "call_remote", "unreliable_ordered")
func client_world_snapshot(snap: Array) -> void:
	if Net.is_server: return
	for entry in snap:
		if entry.size() < 5: continue
		var peer_id: int = entry[0]
		var pos := Vector3(entry[1], entry[2], entry[3])
		var yaw: float = entry[4]
		if peer_id == Net.local_peer_id:
			continue
		target_positions[peer_id] = pos
		target_yaws[peer_id] = yaw

@rpc("authority", "call_remote", "reliable")
func client_match3_started(board: Array, score: int) -> void:
	if Net.is_server: return
	match3_started_sig.emit(board, score)

@rpc("authority", "call_remote", "reliable")
func client_match3_update(board: Array, score: int, matched: int) -> void:
	if Net.is_server: return
	match3_updated_sig.emit(board, score, matched)

@rpc("authority", "call_remote", "reliable")
func client_match3_finished(final_score: int) -> void:
	if Net.is_server: return
	match3_finished_sig.emit(final_score)
