extends Node3D
## Top-level client world. Hosts the network client, the player controller,
## the camera rig, and a single interactable puzzle station.

const NetworkClientScript := preload("res://scripts/client/network_client.gd")
const PlayerControllerScript := preload("res://scripts/client/player_controller.gd")

@onready var camera: Camera3D = $CameraRig
@onready var puzzle_station: Node3D = $PuzzleStation
@onready var player_root: Node3D = $PlayerRoot
@onready var prompt_label: Label = $UI/PromptLabel
@onready var hud_label: Label = $UI/HudLabel
@onready var puzzle_ui: Control = $UI/PuzzleUI

var network_client: Node = null
var player_controller: Node = null
var local_avatar: Node3D = null
var match3_active: bool = false

func _ready() -> void:
	network_client = NetworkClientScript.new()
	network_client.name = "NetworkClient"
	network_client.world_root = player_root
	add_child(network_client)

	player_controller = PlayerControllerScript.new()
	player_controller.name = "PlayerController"
	add_child(player_controller)

	# Wait for our spawn confirmation from the server before binding camera.
	network_client.match3_started.connect(_on_match3_started)
	network_client.match3_updated.connect(_on_match3_updated)
	network_client.match3_finished.connect(_on_match3_finished)

	# Poll until our local player exists in the remote_players dict.
	set_process(true)
	hud_label.text = "Connecting..."
	prompt_label.text = ""

func _process(_delta: float) -> void:
	if local_avatar == null:
		var pid := Net.local_peer_id
		if pid != 0 and network_client.remote_players.has(pid):
			local_avatar = network_client.remote_players[pid]
			player_controller.attach(local_avatar, network_client)
			camera.set_target(local_avatar)
			hud_label.text = "Connected as peer %d. WASD to move." % pid
		else:
			return

	# Show interaction prompt when near the puzzle station.
	var dist := local_avatar.position.distance_to(puzzle_station.position)
	if dist < 2.5 and not match3_active:
		prompt_label.text = "[E] Start Bilging Puzzle"
		if Input.is_action_just_pressed("interact"):
			network_client.request_match3_start()
	elif match3_active:
		prompt_label.text = ""
	else:
		prompt_label.text = ""

	# ESC ends an active puzzle early.
	if match3_active and Input.is_action_just_pressed("ui_cancel"):
		network_client.request_match3_end()

func _on_match3_started(board: Array, score: int) -> void:
	match3_active = true
	puzzle_ui.visible = true
	puzzle_ui.set_board(board, score)

func _on_match3_updated(board: Array, score: int, matched: int) -> void:
	puzzle_ui.set_board(board, score)
	if matched > 0:
		hud_label.text = "Cleared %d tiles!  +%d doubloons" % [matched, matched * Protocol.REWARD_MATCH3_PER_MATCH]

func _on_match3_finished(final_score: int) -> void:
	match3_active = false
	puzzle_ui.visible = false
	hud_label.text = "Bilging finished. Score: %d doubloons" % final_score
