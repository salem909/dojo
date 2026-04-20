extends Node3D
## Ship-deck world. Manages the network client, player controller, camera,
## the bilge-pump puzzle station, the portal to the island, and the settings menu.

const NetworkClientScript    := preload("res://scripts/client/network_client.gd")
const PlayerControllerScript := preload("res://scripts/client/player_controller.gd")
const SettingsMenuScene      := preload("res://scenes/client/settings_menu.tscn")
const ChatPanelScene         := preload("res://scenes/client/chat_panel.tscn")

@onready var camera: Camera3D       = $CameraRig
@onready var puzzle_station: Node3D = $PuzzleStation
@onready var sword_station: Node3D  = $SwordStation
@onready var portal: Node3D         = $Portal
@onready var player_root: Node3D    = $PlayerRoot
@onready var prompt_label: Label    = $UI/PromptLabel
@onready var hud_label: Label       = $UI/HudLabel
@onready var puzzle_ui: Control     = $UI/PuzzleUI
@onready var sword_ui: Control      = $UI/SwordUI

var network_client: Node    = null
var player_controller: Node = null
var local_avatar: Node3D    = null
var match3_active: bool     = false
var sword_active: bool      = false
var _settings_open: bool    = false
var _settings_menu: Control = null
var _chat_panel: Control    = null
var _chat_has_focus: bool   = false

func _ready() -> void:
	network_client = NetworkClientScript.new()
	network_client.name       = "NetworkClient"
	network_client.world_root = player_root
	add_child(network_client)

	player_controller = PlayerControllerScript.new()
	player_controller.name = "PlayerController"
	add_child(player_controller)

	# Settings menu (hidden by default, toggled with ESC).
	_settings_menu = SettingsMenuScene.instantiate()
	_settings_menu.visible = false
	_settings_menu.closed.connect(func(): _toggle_settings(false))
	$UI.add_child(_settings_menu)

	# Chat panel — always-on overlay, captures Enter.
	_chat_panel = ChatPanelScene.instantiate()
	_chat_panel.input_captured.connect(_on_chat_focus_changed)
	$UI.add_child(_chat_panel)
	Game.player_info_received_sig.connect(_on_player_info)

	network_client.match3_started.connect(_on_match3_started)
	network_client.match3_updated.connect(_on_match3_updated)
	network_client.match3_finished.connect(_on_match3_finished)
	network_client.zone_changed.connect(_on_zone_changed)
	Game.crew_result_sig.connect(func(_ok, _err, _crew): _refresh_hud())
	Game.sword_started_sig.connect(_on_sword_started)
	Game.sword_updated_sig.connect(_on_sword_updated)
	Game.sword_finished_sig.connect(_on_sword_finished)

	set_process(true)
	hud_label.text    = "Connecting..."
	prompt_label.text = ""

func _process(_delta: float) -> void:
	# ── settings overlay or chat input suppresses all world input ────────
	if _settings_open or _chat_has_focus:
		return

	# ── ESC handling ─────────────────────────────────────────────────────
	if Input.is_action_just_pressed("ui_cancel"):
		if match3_active:
			network_client.request_match3_end()
		elif sword_active:
			# Release soft-drop hold before ending so the server doesn't
			# leave a dangling soft-drop flag on a future session.
			Game.client_sword_set_soft(false)
			Game.client_request_sword_end()
		else:
			_toggle_settings(true)
		return

	# ── wait for local avatar ────────────────────────────────────────────
	if local_avatar == null:
		var pid := Net.local_peer_id
		if pid != 0 and network_client.remote_players.has(pid):
			local_avatar = network_client.remote_players[pid]
			player_controller.attach(local_avatar, network_client)
			camera.set_target(local_avatar)
			_refresh_hud()
		else:
			return

	# ── active puzzle ────────────────────────────────────────────────────
	if match3_active or sword_active:
		prompt_label.text = ""
		return

	# ── proximity prompts ────────────────────────────────────────────────
	var puzzle_dist := local_avatar.global_position.distance_to(puzzle_station.global_position)
	var sword_dist  := local_avatar.global_position.distance_to(sword_station.global_position)
	var portal_dist := local_avatar.global_position.distance_to(portal.global_position)

	if puzzle_dist < 3.5:
		prompt_label.text = "[E] Start Bilging Puzzle"
		if Input.is_action_just_pressed("interact"):
			network_client.request_match3_start()
	elif sword_dist < 3.5:
		prompt_label.text = "[E] Start Swordfighting"
		if Input.is_action_just_pressed("interact"):
			Game.client_request_sword_start()
	elif portal_dist < 2.5:
		prompt_label.text = "[E] Enter Portal  →  Island"
		if Input.is_action_just_pressed("interact"):
			network_client.request_zone_change(Protocol.Zone.ISLAND)
	else:
		prompt_label.text = ""

func _toggle_settings(open: bool) -> void:
	_settings_open         = open
	_settings_menu.visible = open
	if player_controller:
		player_controller.enabled = not open

func _on_chat_focus_changed(has_focus: bool) -> void:
	_chat_has_focus = has_focus
	if player_controller:
		player_controller.enabled = not (has_focus or _settings_open)

func _on_player_info(info: Dictionary) -> void:
	if _chat_panel and _chat_panel.has_method("show_player_info"):
		_chat_panel.show_player_info(info)

func _on_match3_started(board: Array, score: int) -> void:
	match3_active     = true
	puzzle_ui.visible = true
	puzzle_ui.set_board(board, score)

func _on_match3_updated(board: Array, score: int, matched: int) -> void:
	puzzle_ui.set_board(board, score)
	if matched > 0:
		hud_label.text = "Cleared %d tiles!  +%d doubloons" \
				% [matched, matched * Protocol.REWARD_MATCH3_PER_MATCH]

func _on_match3_finished(final_score: int, new_rank: int, planks_earned: int) -> void:
	match3_active     = false
	puzzle_ui.visible = false
	var rank_name: String = Protocol.RANK_NAMES[new_rank]
	var plank_str := "  +%d planks" % planks_earned if planks_earned > 0 else ""
	hud_label.text = "Bilging done.  +%d → %d doubloons  |  Rank: %s%s" \
			% [final_score, Game.local_doubloons, rank_name, plank_str]

func _on_sword_started(state: Dictionary) -> void:
	sword_active = true
	if sword_ui and sword_ui.has_method("show_state"):
		sword_ui.show_state(state)

func _on_sword_updated(state: Dictionary, summary: Dictionary) -> void:
	if sword_ui and sword_ui.has_method("show_state"):
		sword_ui.show_state(state)
	var delta: int = int(summary.get("delta_score", 0))
	var chain: int = int(summary.get("chain", 0))
	if delta > 0:
		hud_label.text = "Shattered for +%d%s" % [delta,
				(" (chain %dx)" % chain) if chain > 1 else ""]

func _on_sword_finished(final_score: int, doubloons_earned: int) -> void:
	sword_active = false
	if sword_ui and sword_ui.has_method("hide_puzzle"):
		sword_ui.hide_puzzle()
	hud_label.text = "Swordfight done. Final: %d → +%d doubloons (%d total)" \
			% [final_score, doubloons_earned, Game.local_doubloons]

func _on_zone_changed(zone: int, _spawn_pos: Vector3) -> void:
	set_process(false)
	local_avatar = null
	Game.client_clear_zone()
	get_tree().change_scene_to_file(Protocol.ZONE_SCENES[zone])

func _refresh_hud() -> void:
	var crew_suffix := ""
	if Game.local_crew_name != "":
		crew_suffix = "  •  Crew: %s" % Game.local_crew_name
	hud_label.text = "%s  •  %d doubloons%s  |  WASD to move, Enter to chat." \
			% [Game.local_display_name, Game.local_doubloons, crew_suffix]
