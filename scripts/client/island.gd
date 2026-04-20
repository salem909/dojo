extends Node3D
## Island world. Manages the network client, player controller, camera,
## the portal back to the ship, the Bank NPC, and the settings menu.

const NetworkClientScript    := preload("res://scripts/client/network_client.gd")
const PlayerControllerScript := preload("res://scripts/client/player_controller.gd")
const SettingsMenuScene      := preload("res://scenes/client/settings_menu.tscn")
const ChatPanelScene         := preload("res://scenes/client/chat_panel.tscn")

@onready var camera: Camera3D    = $CameraRig
@onready var portal: Node3D      = $Portal
@onready var bank_npc: Node3D    = $BankNPC
@onready var player_root: Node3D = $PlayerRoot
@onready var prompt_label: Label = $UI/PromptLabel
@onready var hud_label: Label    = $UI/HudLabel

var network_client: Node    = null
var player_controller: Node = null
var local_avatar: Node3D    = null
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

	_settings_menu = SettingsMenuScene.instantiate()
	_settings_menu.visible = false
	_settings_menu.closed.connect(func(): _toggle_settings(false))

	# Position portal and bank on the terrain surface.
	var terrain := get_node_or_null("IslandTerrain")
	if terrain and terrain.has_method("get_height_at"):
		_place_on_terrain(terrain, portal, 1.2)
		_place_on_terrain(terrain, bank_npc, 0.7)
	$UI.add_child(_settings_menu)

	# Chat panel — same instance pattern as world.gd.
	_chat_panel = ChatPanelScene.instantiate()
	_chat_panel.input_captured.connect(_on_chat_focus_changed)
	$UI.add_child(_chat_panel)
	Game.player_info_received_sig.connect(_on_player_info)

	network_client.zone_changed.connect(_on_zone_changed)
	network_client.bank_updated.connect(_on_bank_updated)
	Game.crew_result_sig.connect(func(_ok, _err, _crew): _refresh_hud())

	set_process(true)
	hud_label.text    = "Connecting..."
	prompt_label.text = ""

func _process(_delta: float) -> void:
	if _settings_open or _chat_has_focus:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_settings(true)
		return

	if local_avatar == null:
		var pid := Net.local_peer_id
		if pid != 0 and network_client.remote_players.has(pid):
			local_avatar = network_client.remote_players[pid]
			player_controller.attach(local_avatar, network_client)
			camera.set_target(local_avatar)
			_refresh_hud()
		else:
			return

	var portal_dist := local_avatar.global_position.distance_to(portal.global_position)
	var bank_dist   := local_avatar.global_position.distance_to(bank_npc.global_position)

	if bank_dist < 3.0:
		if Game.local_doubloons > 0:
			prompt_label.text = "[E] Deposit %d doubloons to bank" % Game.local_doubloons
			if Input.is_action_just_pressed("interact"):
				network_client.request_deposit_doubloons()
		else:
			prompt_label.text = "Bank balance: %d doubloons" % Game.local_bank_doubloons
	elif portal_dist < 2.5:
		prompt_label.text = "[E] Enter Portal  →  Ship"
		if Input.is_action_just_pressed("interact"):
			network_client.request_zone_change(Protocol.Zone.SHIP)
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

func _on_bank_updated(doubloons: int, bank_doubloons: int) -> void:
	Game.local_doubloons      = doubloons
	Game.local_bank_doubloons = bank_doubloons
	_refresh_hud()

func _refresh_hud() -> void:
	var crew_suffix := ""
	if Game.local_crew_name != "":
		crew_suffix = "  •  Crew: %s" % Game.local_crew_name
	hud_label.text = "Island  •  %s  •  %d doubloons  (bank: %d)%s  |  Enter to chat." \
			% [Game.local_display_name, Game.local_doubloons,
			   Game.local_bank_doubloons, crew_suffix]

func _place_on_terrain(terrain: Node, node: Node3D, y_offset: float) -> void:
	var pos := node.position
	pos.y = terrain.get_height_at(pos.x, pos.z) + y_offset
	node.position = pos

func _on_zone_changed(zone: int, _spawn_pos: Vector3) -> void:
	set_process(false)
	local_avatar = null
	Game.client_clear_zone()
	get_tree().change_scene_to_file(Protocol.ZONE_SCENES[zone])
