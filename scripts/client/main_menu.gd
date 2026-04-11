extends Control
## Title screen. Lets the player Host (forks a headless server subprocess and
## then joins it) or Join (connects to an existing server).
##
## Cmdline auto-routes:
##   --host                 → host + join immediately
##   --connect HOST:PORT    → join immediately

@onready var host_btn: Button = $Center/VBox/HostBtn
@onready var join_btn: Button = $Center/VBox/JoinBtn
@onready var quit_btn: Button = $Center/VBox/QuitBtn
@onready var addr_input: LineEdit = $Center/VBox/AddrInput
@onready var status: Label = $Center/VBox/Status

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	quit_btn.pressed.connect(func(): get_tree().quit())
	addr_input.text = "127.0.0.1:%d" % Protocol.DEFAULT_PORT
	status.text = ""

	# Cmdline auto-routes
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		call_deferred("_on_host")
	else:
		var ca := Boot.get_arg("--connect", "")
		if ca != "":
			addr_input.text = ca
			call_deferred("_on_join")

func _on_host() -> void:
	# Fork a headless Godot subprocess running the server scene, then join it.
	status.text = "Starting local server..."
	var godot_path := OS.get_executable_path()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port", str(Protocol.DEFAULT_PORT)]
	var pid := OS.create_process(godot_path, args)
	if pid <= 0:
		status.text = "Failed to spawn server (pid=%d)" % pid
		return
	Log.i("forked server pid=%d" % pid)
	# Give the server a moment to bind the port before we try to connect.
	await get_tree().create_timer(0.7).timeout
	addr_input.text = "127.0.0.1:%d" % Protocol.DEFAULT_PORT
	_on_join()

func _on_join() -> void:
	var addr := addr_input.text.strip_edges()
	var host := Protocol.DEFAULT_HOST
	var port := Protocol.DEFAULT_PORT
	if ":" in addr:
		var parts := addr.split(":")
		host = parts[0]
		port = int(parts[1])
	else:
		host = addr
	status.text = "Connecting to %s:%d..." % [host, port]
	var err := Net.join(host, port)
	if err != OK:
		status.text = "Failed to start client (err=%d)" % err
		return
	# Wait for confirmation, then change scene.
	Net.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/client/world.tscn")

func _on_failed() -> void:
	status.text = "Connection failed."
