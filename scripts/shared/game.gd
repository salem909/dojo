extends Node
## Single autoloaded RPC hub. Lives at `/root/Game` on both server and client,
## so Godot's RPC routing always finds a matching node on the remote peer.
##
## Server owns authoritative state: players[], match3_sessions[].
## Client owns view state: remote_players[], target_positions/yaws.
## Both declare identical RPC methods so the registry matches across peers.

const PlayerStateScript := preload("res://scripts/shared/player_state.gd")
const Match3Logic       := preload("res://scripts/puzzles/match3/match3_logic.gd")
const SwordLogic        := preload("res://scripts/puzzles/sword/sword_logic.gd")
const RemotePlayerScene := preload("res://scenes/world/remote_player.tscn")
const AuthDB            := preload("res://scripts/server/auth_db.gd")

# ─── server-only state ───────────────────────────────────────────────────────
var players: Dictionary          = {}  # peer_id → PlayerState (authenticated only)
var match3_sessions: Dictionary  = {}  # peer_id → Match3Logic
var sword_sessions: Dictionary   = {}  # peer_id → SwordLogic
var _tick_timer: Timer           = null
var _auth_db: Object             = null  # AuthDB; null on client
var _pending_auth: Dictionary    = {}    # peer_id → true (connected, not yet authed)
var _online_accounts: Dictionary = {}    # account_id → peer_id (prevent double-login)

# ─── client-only state ───────────────────────────────────────────────────────
var world_root: Node3D         = null
var remote_players: Dictionary = {}
var target_positions: Dictionary = {}
var target_yaws: Dictionary    = {}
var _pending_spawns: Array     = []   # buffered while world_root is null
var local_display_name: String = ""
var local_character_class: int = 0
var local_doubloons: int       = 0
var local_bank_doubloons: int  = 0
var local_crew_name: String    = ""

const INTERP_SPEED: float = 12.0

# ─── client-side signals ─────────────────────────────────────────────────────
signal auth_result_sig(ok: bool, error_code: int, display_name: String, doubloons: int)
signal match3_started_sig(board: Array, score: int)
signal match3_updated_sig(board: Array, score: int, last_matched: int)
signal match3_finished_sig(final_score: int, new_rank: int, planks_earned: int)
signal bank_updated_sig(doubloons: int, bank_doubloons: int)
signal zone_changed_sig(zone: int, spawn_pos: Vector3)
signal chat_received_sig(channel: int, from_name: String, message: String)
signal crew_result_sig(ok: bool, error_code: int, crew_name: String)
signal crew_invite_received_sig(from_name: String, crew_name: String)
signal player_info_received_sig(info: Dictionary)
signal sword_started_sig(state: Dictionary)
signal sword_updated_sig(state: Dictionary, summary: Dictionary)
signal sword_finished_sig(final_score: int, doubloons_earned: int)

func _ready() -> void:
	Net.peer_connected_to_us.connect(_on_peer_joined)
	Net.peer_disconnected_from_us.connect(_on_peer_left)

func become_server() -> void:
	_auth_db = AuthDB.new()
	_auth_db.load_db()
	_tick_timer = Timer.new()
	_tick_timer.wait_time = Protocol.TICK_DT
	_tick_timer.autostart = true
	_tick_timer.one_shot  = false
	_tick_timer.timeout.connect(_on_world_tick)
	add_child(_tick_timer)
	Log.i("game: server mode, tick %dHz" % Protocol.TICK_HZ)

func _process(delta: float) -> void:
	if Net.is_server: return
	# Smoothly interpolate every remote player except the local one.
	for peer_id in remote_players.keys():
		if peer_id == Net.local_peer_id: continue
		var node: Node3D = remote_players[peer_id]
		if not is_instance_valid(node): continue
		var target: Vector3 = target_positions.get(peer_id, node.position)
		var dist: float     = node.position.distance_to(target)
		var t: float        = clamp(delta * INTERP_SPEED, 0.0, 1.0)
		node.position       = node.position.lerp(target, t)
		var ty: float       = target_yaws.get(peer_id, node.rotation.y)
		node.rotation.y     = lerp_angle(node.rotation.y, ty, t)
		# Drive animation for remote players based on observable state.
		if node.has_method("set_motion_state"):
			var speed_est: float = dist / max(delta, 0.001)
			var in_air: bool     = node.position.y > 0.1
			node.set_motion_state(dist > 0.05, speed_est > 2.5, in_air)
		elif node.has_method("set_moving"):
			node.set_moving(dist > 0.05)

# ─── server: peer lifecycle ──────────────────────────────────────────────────

func _on_peer_joined(peer_id: int) -> void:
	if not Net.is_server: return
	_pending_auth[peer_id] = true
	Log.i("peer %d connected, awaiting auth" % peer_id)

func _on_peer_left(peer_id: int) -> void:
	if not Net.is_server: return
	if _pending_auth.has(peer_id):
		_pending_auth.erase(peer_id)
		Log.i("peer %d disconnected before auth" % peer_id)
		return
	if not players.has(peer_id): return
	var ps: Object      = players[peer_id]
	var zone: int       = ps.zone
	var acct_id: String = ps.account_id
	_save_player(ps)
	players.erase(peer_id)
	_online_accounts.erase(acct_id)
	if match3_sessions.has(peer_id):
		match3_sessions.erase(peer_id)
	if sword_sessions.has(peer_id):
		sword_sessions.erase(peer_id)
	Log.i("despawned player peer=%d account=%s" % [peer_id, acct_id])
	for other_id in players.keys():
		if players[other_id].zone == zone:
			rpc_id(other_id, "client_player_despawned", peer_id)

func _on_world_tick() -> void:
	if not Net.is_server: return
	# ── drive any active sword sessions with real-time gravity ───────────
	if not sword_sessions.is_empty():
		var dt_ms: int = int(Protocol.TICK_DT * 1000.0)
		# Snapshot keys; the dict can mutate while we iterate (game-over → erase).
		for peer_id in sword_sessions.keys():
			if not sword_sessions.has(peer_id): continue
			var session: Object = sword_sessions[peer_id]
			var summary: Dictionary = session.tick(dt_ms)
			if summary.get("changed", false):
				rpc_id(peer_id, "client_sword_update",
					session.export_state(), summary)
			if summary.get("game_over", false):
				_sword_finalize(peer_id)
	# ── world snapshot for player movement ───────────────────────────────
	if players.is_empty(): return
	var zone_snaps: Dictionary = {}
	for peer_id in players.keys():
		var p: Object = players[peer_id]
		if not zone_snaps.has(p.zone):
			zone_snaps[p.zone] = []
		zone_snaps[p.zone].append([peer_id, p.position.x, p.position.y, p.position.z, p.yaw])
	for peer_id in players.keys():
		var p: Object = players[peer_id]
		rpc_id(peer_id, "client_world_snapshot", zone_snaps.get(p.zone, []))

# ─── server: auth helpers ────────────────────────────────────────────────────

func _complete_auth(peer_id: int, account: Dictionary) -> void:
	var account_id: String = account.get("account_id", "")
	if _online_accounts.has(account_id):
		rpc_id(peer_id, "client_auth_result", false, Protocol.AuthError.ALREADY_ONLINE, "", 0, 0, 0)
		return
	_pending_auth.erase(peer_id)
	_online_accounts[account_id] = peer_id
	var ps := PlayerStateScript.new()
	ps.peer_id         = peer_id
	ps.account_id      = account_id
	ps.display_name    = account.get("display_name", "Player%d" % peer_id)
	ps.character_class = account.get("character_class", 0)
	ps.doubloons       = account.get("doubloons", 0)
	ps.bank_doubloons  = account.get("bank_doubloons", 0)
	ps.position        = Protocol.SPAWN_POSITION
	ps.zone            = Protocol.Zone.SHIP
	ps.crew_id         = account.get("crew_id", "")
	ps.crew_name       = account.get("crew_name", "")
	# JSON dict keys are strings — convert back to int
	for k in account.get("puzzle_wins", {}):
		ps.puzzle_wins[int(k)] = account["puzzle_wins"][k]
	for k in account.get("puzzle_losses", {}):
		ps.puzzle_losses[int(k)] = account["puzzle_losses"][k]
	for k in account.get("inventory", {}):
		ps.inventory[int(k)] = account["inventory"][k]
	players[peer_id] = ps
	Log.i("auth ok peer=%d account=%s class=%d doubloons=%d crew='%s'" \
		% [peer_id, account_id, ps.character_class, ps.doubloons, ps.crew_name])
	rpc_id(peer_id, "client_auth_result", true, Protocol.AuthError.OK,
		ps.display_name, ps.doubloons, ps.character_class, ps.bank_doubloons)
	rpc_id(peer_id, "client_crew_result", true, Protocol.CrewError.OK, ps.crew_name)
	_spawn_player_to_zone(peer_id)

func _spawn_player_to_zone(peer_id: int) -> void:
	var ps: Object = players[peer_id]
	for existing_id in players.keys():
		var p: Object = players[existing_id]
		if p.zone == ps.zone:
			rpc_id(peer_id, "client_player_spawned",
				existing_id, p.display_name, p.position, p.character_class)
	for other_id in players.keys():
		if other_id == peer_id: continue
		if players[other_id].zone == ps.zone:
			rpc_id(other_id, "client_player_spawned",
				peer_id, ps.display_name, ps.position, ps.character_class)

func _save_player(ps: Object) -> void:
	if _auth_db == null or ps.account_id == "": return
	_auth_db.save_player_data(ps.account_id, {
		"doubloons":     ps.doubloons,
		"bank_doubloons": ps.bank_doubloons,
		"puzzle_wins":   ps.puzzle_wins,
		"puzzle_losses": ps.puzzle_losses,
		"inventory":     ps.inventory,
		"crew_id":       ps.crew_id,
		"crew_name":     ps.crew_name,
	})

func _calc_rank(wins: int) -> int:
	var rank := 0
	for i in range(Protocol.RANK_WIN_THRESHOLDS.size()):
		if wins >= Protocol.RANK_WIN_THRESHOLDS[i]:
			rank = i
	return rank

# ─── client-side helpers ─────────────────────────────────────────────────────

func client_login(username: String, password_hash: String) -> void:
	rpc_id(1, "server_authenticate", username, password_hash)

func client_register(username: String, password_hash: String,
		char_class: int, display_name: String) -> void:
	rpc_id(1, "server_register", username, password_hash, char_class, display_name)

func client_set_world_root(root: Node3D) -> void:
	world_root = root
	for args in _pending_spawns:
		_do_spawn_player(args[0], args[1], args[2], args[3])
	_pending_spawns.clear()

func client_clear_zone() -> void:
	for peer_id in remote_players.keys():
		var node = remote_players[peer_id]
		if is_instance_valid(node):
			node.queue_free()
	remote_players.clear()
	target_positions.clear()
	target_yaws.clear()
	_pending_spawns.clear()
	world_root = null

func client_send_move(target_pos: Vector3, yaw: float) -> void:
	if multiplayer.multiplayer_peer == null: return
	rpc_id(1, "server_move_input", target_pos, yaw)

func client_request_match3_start() -> void:
	rpc_id(1, "server_start_match3")

func client_send_match3_swap(a: Vector2i, b: Vector2i) -> void:
	rpc_id(1, "server_match3_swap", a.x, a.y, b.x, b.y)

func client_request_match3_end() -> void:
	rpc_id(1, "server_match3_end")

func client_request_zone_change(target_zone: int) -> void:
	rpc_id(1, "server_request_zone_change", target_zone)

func client_request_deposit_doubloons() -> void:
	rpc_id(1, "server_deposit_doubloons")

# ─── RPCs: client → server ───────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func server_authenticate(username: String, password_hash: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not _pending_auth.has(sender): return
	var result: Array = _auth_db.authenticate(username, password_hash)
	if result[0] == null:
		rpc_id(sender, "client_auth_result", false, result[1], "", 0, 0, 0)
		Log.w("auth failed peer=%d user='%s' err=%d" % [sender, username, result[1]])
		return
	_complete_auth(sender, result[0])

@rpc("any_peer", "call_remote", "reliable")
func server_register(username: String, password_hash: String,
		char_class: int, display_name: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not _pending_auth.has(sender): return
	var clamped_class := clampi(char_class, 0, Protocol.CHARACTER_MODELS.size() - 1)
	var err: int = _auth_db.register_account(
		username, password_hash, clamped_class, display_name)
	if err != Protocol.AuthError.OK:
		rpc_id(sender, "client_auth_result", false, err, "", 0, 0, 0)
		Log.w("register failed peer=%d user='%s' err=%d" % [sender, username, err])
		return
	var result: Array = _auth_db.authenticate(username, password_hash)
	_complete_auth(sender, result[0])

@rpc("any_peer", "call_remote", "unreliable_ordered")
func server_move_input(target_pos: Vector3, yaw: float) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var p: Object      = players[sender]
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
		session.score += matched * Protocol.REWARD_MATCH3_PER_MATCH
	rpc_id(sender, "client_match3_update", session.export_board(), session.score, matched)

@rpc("any_peer", "call_remote", "reliable")
func server_match3_end() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not match3_sessions.has(sender): return
	var final_score: int = match3_sessions[sender].score
	match3_sessions.erase(sender)
	var new_rank: int   = 0
	var planks: int     = 0
	if players.has(sender):
		var ps: Object   = players[sender]
		var pid: int     = Protocol.PuzzleId.MATCH3_BILGE
		ps.doubloons    += final_score
		# Track win/loss
		if final_score > 0:
			ps.puzzle_wins[pid] = ps.puzzle_wins.get(pid, 0) + 1
		else:
			ps.puzzle_losses[pid] = ps.puzzle_losses.get(pid, 0) + 1
		# Award planks
		planks = final_score / Protocol.BILGE_PLANKS_PER_SCORE
		if planks > 0:
			ps.inventory[Protocol.ItemId.PLANK] = \
				ps.inventory.get(Protocol.ItemId.PLANK, 0) + planks
		new_rank = _calc_rank(ps.puzzle_wins.get(pid, 0))
		_save_player(ps)
		Log.i("match3 ended peer=%d score=%d doubloons=%d rank=%d planks=%d" \
			% [sender, final_score, ps.doubloons, new_rank, planks])
	rpc_id(sender, "client_match3_finished", final_score, new_rank, planks)

@rpc("any_peer", "call_remote", "reliable")
func server_deposit_doubloons() -> void:
	## Moves all pocket doubloons into the bank.
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var ps: Object = players[sender]
	if ps.doubloons <= 0: return
	ps.bank_doubloons += ps.doubloons
	ps.doubloons = 0
	_save_player(ps)
	Log.i("deposit peer=%d bank=%d" % [sender, ps.bank_doubloons])
	rpc_id(sender, "client_bank_updated", ps.doubloons, ps.bank_doubloons)

@rpc("any_peer", "call_remote", "reliable")
func server_request_zone_change(target_zone: int) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var p: Object = players[sender]
	if p.zone == target_zone: return
	if target_zone < 0 or target_zone >= Protocol.ZONE_SCENES.size(): return
	var old_zone: int = p.zone
	if match3_sessions.has(sender):
		match3_sessions.erase(sender)
	if sword_sessions.has(sender):
		sword_sessions.erase(sender)
	for other_id in players.keys():
		if other_id == sender: continue
		if players[other_id].zone == old_zone:
			rpc_id(other_id, "client_player_despawned", sender)
	p.zone     = target_zone
	p.position = Protocol.PORTAL_EXIT[target_zone]
	rpc_id(sender, "client_zone_changed", target_zone, p.position)
	rpc_id(sender, "client_player_spawned",
		sender, p.display_name, p.position, p.character_class)
	for other_id in players.keys():
		if other_id == sender: continue
		if players[other_id].zone == target_zone:
			var op: Object = players[other_id]
			rpc_id(sender,   "client_player_spawned",
				other_id, op.display_name, op.position, op.character_class)
			rpc_id(other_id, "client_player_spawned",
				sender, p.display_name, p.position, p.character_class)
	Log.i("peer=%d zone %d→%d pos=%s" % [sender, old_zone, target_zone, p.position])

# ─── RPCs: server → client ───────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func client_auth_result(ok: bool, error_code: int, display_name: String,
		doubloons: int, char_class: int, bank_doubloons: int) -> void:
	if Net.is_server: return
	if ok:
		local_display_name    = display_name
		local_doubloons       = doubloons
		local_character_class = char_class
		local_bank_doubloons  = bank_doubloons
	auth_result_sig.emit(ok, error_code, display_name, doubloons)

@rpc("authority", "call_remote", "reliable")
func client_player_spawned(peer_id: int, display_name: String,
		pos: Vector3, char_class: int) -> void:
	if Net.is_server: return
	if remote_players.has(peer_id): return
	if world_root == null:
		_pending_spawns.append([peer_id, display_name, pos, char_class])
		return
	_do_spawn_player(peer_id, display_name, pos, char_class)

func _do_spawn_player(peer_id: int, display_name: String,
		pos: Vector3, char_class: int) -> void:
	if remote_players.has(peer_id): return
	var node: Node3D = RemotePlayerScene.instantiate()
	node.name     = "Player_%d" % peer_id
	node.position = pos
	node.set_meta("peer_id",      peer_id)
	node.set_meta("display_name", display_name)
	world_root.add_child(node)
	# Set character model and name label via script method.
	if node.has_method("setup"):
		node.setup(char_class, display_name)
	remote_players[peer_id]   = node
	target_positions[peer_id] = pos
	target_yaws[peer_id]      = 0.0
	Log.i("spawn peer=%d name=%s class=%d" % [peer_id, display_name, char_class])

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
		var yaw: float   = entry[4]
		if peer_id == Net.local_peer_id: continue
		target_positions[peer_id] = pos
		target_yaws[peer_id]      = yaw

@rpc("authority", "call_remote", "reliable")
func client_match3_started(board: Array, score: int) -> void:
	if Net.is_server: return
	match3_started_sig.emit(board, score)

@rpc("authority", "call_remote", "reliable")
func client_match3_update(board: Array, score: int, matched: int) -> void:
	if Net.is_server: return
	match3_updated_sig.emit(board, score, matched)

@rpc("authority", "call_remote", "reliable")
func client_match3_finished(final_score: int, new_rank: int, planks_earned: int) -> void:
	if Net.is_server: return
	local_doubloons += final_score
	match3_finished_sig.emit(final_score, new_rank, planks_earned)

@rpc("authority", "call_remote", "reliable")
func client_bank_updated(doubloons: int, bank_doubloons: int) -> void:
	if Net.is_server: return
	local_doubloons      = doubloons
	local_bank_doubloons = bank_doubloons
	bank_updated_sig.emit(doubloons, bank_doubloons)

@rpc("authority", "call_remote", "reliable")
func client_zone_changed(zone: int, spawn_pos: Vector3) -> void:
	if Net.is_server: return
	zone_changed_sig.emit(zone, spawn_pos)

# ─── Chat ────────────────────────────────────────────────────────────────────

func client_send_chat(channel: int, message: String) -> void:
	rpc_id(1, "server_chat", channel, message)

@rpc("any_peer", "call_remote", "reliable")
func server_chat(channel: int, message: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var clean := message.strip_edges()
	if clean.is_empty(): return
	if clean.length() > Protocol.MAX_CHAT_LENGTH:
		clean = clean.substr(0, Protocol.MAX_CHAT_LENGTH)
	var sender_ps: Object = players[sender]
	match channel:
		Protocol.ChatChannel.SAY:
			# Broadcast to everyone in the same zone (including sender for echo).
			for other_id in players.keys():
				if players[other_id].zone == sender_ps.zone:
					rpc_id(other_id, "client_chat", Protocol.ChatChannel.SAY,
						sender_ps.display_name, clean)
			Log.i("chat SAY peer=%d zone=%d: %s" \
				% [sender, sender_ps.zone, clean])
		Protocol.ChatChannel.CREW:
			if sender_ps.crew_id == "":
				rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
					"", "You are not in a crew.")
				return
			# Broadcast to all online crew members.
			for other_id in players.keys():
				if players[other_id].crew_id == sender_ps.crew_id:
					rpc_id(other_id, "client_chat", Protocol.ChatChannel.CREW,
						sender_ps.display_name, clean)
			Log.i("chat CREW peer=%d crew=%s: %s" \
				% [sender, sender_ps.crew_id, clean])
		_:
			pass

@rpc("authority", "call_remote", "reliable")
func client_chat(channel: int, from_name: String, message: String) -> void:
	if Net.is_server: return
	chat_received_sig.emit(channel, from_name, message)

# ─── Crew ────────────────────────────────────────────────────────────────────

func client_request_create_crew(crew_name: String) -> void:
	rpc_id(1, "server_create_crew", crew_name)

func client_request_leave_crew() -> void:
	rpc_id(1, "server_leave_crew")

func client_request_invite_to_crew(target_name: String) -> void:
	rpc_id(1, "server_invite_to_crew", target_name)

func client_respond_crew_invite(accept: bool, crew_id: String) -> void:
	rpc_id(1, "server_respond_crew_invite", accept, crew_id)

@rpc("any_peer", "call_remote", "reliable")
func server_create_crew(crew_name: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var ps: Object = players[sender]
	if ps.crew_id != "":
		rpc_id(sender, "client_crew_result", false,
			Protocol.CrewError.ALREADY_IN_CREW, "")
		return
	var err: int = _auth_db.create_crew(crew_name, ps.account_id, ps.display_name)
	if err != Protocol.CrewError.OK:
		rpc_id(sender, "client_crew_result", false, err, "")
		return
	ps.crew_id   = crew_name.to_lower()
	ps.crew_name = crew_name.strip_edges()
	rpc_id(sender, "client_crew_result", true, Protocol.CrewError.OK, ps.crew_name)
	Log.i("crew created by peer=%d name='%s'" % [sender, ps.crew_name])

@rpc("any_peer", "call_remote", "reliable")
func server_leave_crew() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var ps: Object = players[sender]
	if ps.crew_id == "":
		rpc_id(sender, "client_crew_result", false,
			Protocol.CrewError.NOT_IN_CREW, "")
		return
	var old_crew: String = ps.crew_id
	_auth_db.leave_crew(ps.account_id)
	ps.crew_id   = ""
	ps.crew_name = ""
	rpc_id(sender, "client_crew_result", true, Protocol.CrewError.OK, "")
	# Notify remaining online crewmates so their rosters refresh.
	for other_id in players.keys():
		if players[other_id].crew_id == old_crew:
			rpc_id(other_id, "client_chat", Protocol.ChatChannel.SYSTEM,
				"", "%s has left the crew." % ps.display_name)
	Log.i("crew left by peer=%d" % sender)

@rpc("any_peer", "call_remote", "reliable")
func server_invite_to_crew(target_name: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var ps: Object = players[sender]
	if ps.crew_id == "":
		rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
			"", "You must be in a crew to invite players.")
		return
	var needle := target_name.strip_edges().to_lower()
	if needle == ps.display_name.to_lower():
		rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
			"", "You cannot invite yourself.")
		return
	# Find online target.
	var target_peer: int = 0
	for pid in players.keys():
		if players[pid].display_name.to_lower() == needle:
			target_peer = pid
			break
	if target_peer == 0:
		rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
			"", "No online pirate named '%s'." % target_name)
		return
	var target_ps: Object = players[target_peer]
	if target_ps.crew_id != "":
		rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
			"", "%s is already in a crew." % target_ps.display_name)
		return
	target_ps.pending_crew_invites.append({
		"from_peer": sender,
		"from_name": ps.display_name,
		"crew_id":   ps.crew_id,
		"crew_name": ps.crew_name,
	})
	rpc_id(target_peer, "client_crew_invite", ps.display_name, ps.crew_name, ps.crew_id)
	rpc_id(sender, "client_chat", Protocol.ChatChannel.SYSTEM,
		"", "Invited %s to %s." % [target_ps.display_name, ps.crew_name])
	Log.i("crew invite: %d → %d (%s)" % [sender, target_peer, ps.crew_name])

@rpc("any_peer", "call_remote", "reliable")
func server_respond_crew_invite(accept: bool, crew_id: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var ps: Object = players[sender]
	# Find and remove the matching invite.
	var found_invite: Dictionary = {}
	for inv in ps.pending_crew_invites:
		if inv.get("crew_id", "") == crew_id:
			found_invite = inv
			break
	if found_invite.is_empty(): return
	ps.pending_crew_invites.erase(found_invite)
	if not accept: return
	if ps.crew_id != "":
		rpc_id(sender, "client_crew_result", false,
			Protocol.CrewError.ALREADY_IN_CREW, "")
		return
	var err: int = _auth_db.join_crew(crew_id, ps.account_id)
	if err != Protocol.CrewError.OK:
		rpc_id(sender, "client_crew_result", false, err, "")
		return
	var crew: Dictionary = _auth_db.get_crew(crew_id)
	ps.crew_id   = crew_id
	ps.crew_name = crew.get("name", "")
	rpc_id(sender, "client_crew_result", true, Protocol.CrewError.OK, ps.crew_name)
	# Announce to online crewmates.
	for other_id in players.keys():
		if players[other_id].crew_id == crew_id:
			rpc_id(other_id, "client_chat", Protocol.ChatChannel.SYSTEM,
				"", "%s has joined the crew." % ps.display_name)
	Log.i("crew join: peer=%d → %s" % [sender, ps.crew_name])

@rpc("authority", "call_remote", "reliable")
func client_crew_result(ok: bool, error_code: int, crew_name: String) -> void:
	if Net.is_server: return
	if ok:
		local_crew_name = crew_name
	crew_result_sig.emit(ok, error_code, crew_name)

@rpc("authority", "call_remote", "reliable")
func client_crew_invite(from_name: String, crew_name: String, _crew_id: String) -> void:
	if Net.is_server: return
	crew_invite_received_sig.emit(from_name, crew_name)

# ─── Player Info Lookup (/who <name>) ────────────────────────────────────────

func client_request_player_info(pirate_name: String) -> void:
	rpc_id(1, "server_request_player_info", pirate_name)

@rpc("any_peer", "call_remote", "reliable")
func server_request_player_info(pirate_name: String) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var needle := pirate_name.strip_edges().to_lower()
	# Try online players first (richer info), then fall back to DB.
	for pid in players.keys():
		var p: Object = players[pid]
		if p.display_name.to_lower() == needle:
			var wins: int = p.puzzle_wins.get(Protocol.PuzzleId.MATCH3_BILGE, 0)
			var rank: int = _calc_rank(wins)
			rpc_id(sender, "client_player_info", {
				"name":         p.display_name,
				"class":        p.character_class,
				"crew":         p.crew_name,
				"online":       true,
				"bilge_wins":   wins,
				"bilge_losses": p.puzzle_losses.get(Protocol.PuzzleId.MATCH3_BILGE, 0),
				"bilge_rank":   rank,
			})
			return
	var acct: Dictionary = _auth_db.find_account_by_display_name(pirate_name)
	if acct.is_empty():
		rpc_id(sender, "client_player_info", {
			"name":   pirate_name,
			"found":  false,
		})
		return
	var wins: int = int(acct.get("puzzle_wins", {}).get(
		str(Protocol.PuzzleId.MATCH3_BILGE), 0))
	var losses: int = int(acct.get("puzzle_losses", {}).get(
		str(Protocol.PuzzleId.MATCH3_BILGE), 0))
	rpc_id(sender, "client_player_info", {
		"name":         acct.get("display_name", pirate_name),
		"class":        int(acct.get("character_class", 0)),
		"crew":         acct.get("crew_name", ""),
		"online":       false,
		"bilge_wins":   wins,
		"bilge_losses": losses,
		"bilge_rank":   _calc_rank(wins),
	})

@rpc("authority", "call_remote", "reliable")
func client_player_info(info: Dictionary) -> void:
	if Net.is_server: return
	player_info_received_sig.emit(info)

# ─── Sword puzzle ────────────────────────────────────────────────────────────

func client_request_sword_start() -> void:
	rpc_id(1, "server_start_sword")

func client_sword_move(delta_col: int) -> void:
	rpc_id(1, "server_sword_move", delta_col)

func client_sword_rotate() -> void:
	rpc_id(1, "server_sword_rotate")

func client_sword_drop() -> void:
	rpc_id(1, "server_sword_drop")

func client_sword_soft_drop() -> void:
	rpc_id(1, "server_sword_soft_drop")

func client_sword_rotate_cw() -> void:
	rpc_id(1, "server_sword_rotate_cw")

func client_sword_rotate_ccw() -> void:
	rpc_id(1, "server_sword_rotate_ccw")

func client_sword_set_soft(active: bool) -> void:
	rpc_id(1, "server_sword_set_soft", active)

func client_request_sword_end() -> void:
	rpc_id(1, "server_sword_end")

@rpc("any_peer", "call_remote", "reliable")
func server_start_sword() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender): return
	var session := SwordLogic.new()
	session.seed_board(randi())
	sword_sessions[sender] = session
	rpc_id(sender, "client_sword_started", session.export_state())
	Log.i("sword started for peer=%d" % sender)

@rpc("any_peer", "call_remote", "reliable")
func server_sword_move(delta_col: int) -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	# Clamp to -1/0/+1 — any other value is a protocol violation; drop.
	if delta_col != -1 and delta_col != 1: return
	session.move_pair(delta_col)
	rpc_id(sender, "client_sword_update", session.export_state(), {})

@rpc("any_peer", "call_remote", "reliable")
func server_sword_rotate() -> void:
	## Backward-compat: existing client code calls this; new code should
	## prefer server_sword_rotate_cw / server_sword_rotate_ccw.
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	session.rotate_pair_cw()
	rpc_id(sender, "client_sword_update", session.export_state(), {})

@rpc("any_peer", "call_remote", "reliable")
func server_sword_rotate_cw() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	session.rotate_pair_cw()
	rpc_id(sender, "client_sword_update", session.export_state(), {})

@rpc("any_peer", "call_remote", "reliable")
func server_sword_rotate_ccw() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	session.rotate_pair_ccw()
	rpc_id(sender, "client_sword_update", session.export_state(), {})

@rpc("any_peer", "call_remote", "reliable")
func server_sword_set_soft(active: bool) -> void:
	## Soft-drop hold: while true, the session's gravity tick uses a faster
	## interval (drop_interval / SOFT_DROP_MULTIPLIER). Idempotent — safe
	## to call repeatedly.
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	session.set_soft_dropping(active)
	# No state RPC here — the next tick or input will sync. Avoids spam if
	# the client repeatedly sends set_soft on key auto-repeat.

@rpc("any_peer", "call_remote", "reliable")
func server_sword_drop() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	var summary: Dictionary = session.drop_pair()
	rpc_id(sender, "client_sword_update", session.export_state(), summary)
	if summary.get("game_over", false):
		_sword_finalize(sender)

@rpc("any_peer", "call_remote", "reliable")
func server_sword_soft_drop() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	var session: Object = sword_sessions[sender]
	var summary: Dictionary = session.soft_drop_pair()
	rpc_id(sender, "client_sword_update", session.export_state(), summary)
	if summary.get("game_over", false):
		_sword_finalize(sender)

@rpc("any_peer", "call_remote", "reliable")
func server_sword_end() -> void:
	if not Net.is_server: return
	var sender := multiplayer.get_remote_sender_id()
	if not sword_sessions.has(sender): return
	_sword_finalize(sender)

func _sword_finalize(peer_id: int) -> void:
	## Pay out, update W/L, persist, and notify the client. Sword uses its own
	## puzzle id so its rating is tracked separately from bilging.
	if not sword_sessions.has(peer_id): return
	var session: Object = sword_sessions[peer_id]
	var final_score: int = session.score
	var doubloons: int = final_score / Protocol.SWORD_SCORE_TO_DOUBLOONS_DIVISOR
	sword_sessions.erase(peer_id)
	if not players.has(peer_id):
		return
	var ps: Object = players[peer_id]
	var pid: int = Protocol.PuzzleId.SWORD
	ps.doubloons += doubloons
	if final_score > 0:
		ps.puzzle_wins[pid] = ps.puzzle_wins.get(pid, 0) + 1
	else:
		ps.puzzle_losses[pid] = ps.puzzle_losses.get(pid, 0) + 1
	_save_player(ps)
	Log.i("sword ended peer=%d score=%d doubloons+=%d total=%d" \
		% [peer_id, final_score, doubloons, ps.doubloons])
	rpc_id(peer_id, "client_sword_finished", final_score, doubloons)

@rpc("authority", "call_remote", "reliable")
func client_sword_started(state: Dictionary) -> void:
	if Net.is_server: return
	sword_started_sig.emit(state)

@rpc("authority", "call_remote", "reliable")
func client_sword_update(state: Dictionary, summary: Dictionary) -> void:
	if Net.is_server: return
	sword_updated_sig.emit(state, summary)

@rpc("authority", "call_remote", "reliable")
func client_sword_finished(final_score: int, doubloons_earned: int) -> void:
	if Net.is_server: return
	local_doubloons += doubloons_earned
	sword_finished_sig.emit(final_score, doubloons_earned)
