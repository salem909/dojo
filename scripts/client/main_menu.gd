extends Control
## Title screen with two panels:
##   1. Login panel — username, password, Login / Create New Pirate / Quit
##   2. Pirate creation panel — pirate name, class selection, Create / Back
##
## Server address is fixed to Protocol.DEFAULT_HOST:DEFAULT_PORT.
## Dev cmdline flags still work:
##   --host [--username NAME --password PASS]   → fork server + auto auth
##   --connect HOST:PORT                        → override server address

# ─── panels ──────────────────────────────────────────────────────────────────
@onready var login_panel:    VBoxContainer = $Center/VBox/LoginPanel
@onready var creation_panel: VBoxContainer = $Center/VBox/CreationPanel

# ─── login panel nodes ───────────────────────────────────────────────────────
@onready var username_input: LineEdit = $Center/VBox/LoginPanel/UsernameInput
@onready var password_input: LineEdit = $Center/VBox/LoginPanel/PasswordInput
@onready var login_btn:      Button   = $Center/VBox/LoginPanel/LoginBtn
@onready var register_btn:   Button   = $Center/VBox/LoginPanel/RegisterBtn
@onready var quit_btn:       Button   = $Center/VBox/LoginPanel/QuitBtn

# ─── creation panel nodes ────────────────────────────────────────────────────
@onready var pirate_name_input: LineEdit = $Center/VBox/CreationPanel/PirateNameInput
@onready var create_btn: Button = $Center/VBox/CreationPanel/ButtonRow/CreateBtn
@onready var back_btn:   Button = $Center/VBox/CreationPanel/ButtonRow/BackBtn

@onready var status: Label = $Center/VBox/Status

var _selected_class: int  = 0
var _class_btns: Array     = []
var _server_host: String   = Protocol.DEFAULT_HOST
var _server_port: int      = Protocol.DEFAULT_PORT

func _ready() -> void:
	# Login panel wiring
	login_btn.pressed.connect(_on_login)
	register_btn.pressed.connect(_show_creation_panel)
	quit_btn.pressed.connect(func(): get_tree().quit())

	# Creation panel wiring
	create_btn.pressed.connect(_on_create_pirate)
	back_btn.pressed.connect(_show_login_panel)
	for i in range(4):
		var btn: Button = $Center/VBox/CreationPanel/ClassRow.get_child(i)
		_class_btns.append(btn)
		var idx := i
		btn.pressed.connect(func(): _select_class(idx))
	_select_class(0)

	_show_login_panel()

	# Pre-fill from cmdline (dev use)
	var user_arg := Boot.get_arg("--username", "")
	var pass_arg := Boot.get_arg("--password", "")
	if user_arg != "": username_input.text = user_arg
	if pass_arg != "": password_input.text = pass_arg
	var connect_arg := Boot.get_arg("--connect", "")
	if connect_arg != "":
		if ":" in connect_arg:
			var parts := connect_arg.split(":")
			_server_host = parts[0]
			_server_port = int(parts[1])
		else:
			_server_host = connect_arg

	# Cmdline auto-routes
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		call_deferred("_on_host_cmdline")
	elif connect_arg != "":
		call_deferred("_on_login")

# ─── panel switching ─────────────────────────────────────────────────────────

func _show_login_panel() -> void:
	login_panel.visible    = true
	creation_panel.visible = false
	status.text = ""

func _show_creation_panel() -> void:
	if not _validate_credentials():
		return
	login_panel.visible    = false
	creation_panel.visible = true
	status.text = ""

# ─── class selection ─────────────────────────────────────────────────────────

func _select_class(class_id: int) -> void:
	_selected_class = class_id
	for i in range(_class_btns.size()):
		_class_btns[i].modulate = Color(1.0, 0.85, 0.3, 1) if i == class_id \
								  else Color(0.55, 0.55, 0.55, 1)

# ─── actions ─────────────────────────────────────────────────────────────────

func _on_login() -> void:
	if not _validate_credentials():
		return
	status.text = "Connecting..."
	_connect_to_server(func():
		status.text = "Logging in..."
		Game.auth_result_sig.connect(_on_auth_result, CONNECT_ONE_SHOT)
		Game.client_login(
			username_input.text.strip_edges(),
			_hash_password(password_input.text)))

func _on_create_pirate() -> void:
	if not _validate_credentials():
		return
	var pirate_name := pirate_name_input.text.strip_edges()
	if pirate_name.is_empty():
		status.text = "Enter a pirate name."
		return
	status.text = "Connecting..."
	_connect_to_server(func():
		status.text = "Creating pirate..."
		Game.auth_result_sig.connect(_on_auth_result, CONNECT_ONE_SHOT)
		Game.client_register(
			username_input.text.strip_edges(),
			_hash_password(password_input.text),
			_selected_class,
			pirate_name))

func _on_host_cmdline() -> void:
	## Dev-only: --host flag forks a server and auto-auths.
	if not _validate_credentials():
		return
	status.text = "Starting local server..."
	var godot_path := OS.get_executable_path()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				 "--", "--server", "--port", str(_server_port)]
	var pid := OS.create_process(godot_path, args)
	if pid <= 0:
		status.text = "Failed to spawn server (pid=%d)" % pid
		return
	Log.i("forked server pid=%d" % pid)
	_server_host = "127.0.0.1"
	await get_tree().create_timer(0.7).timeout
	# Try register first; fall back to login if account exists.
	_connect_to_server(func():
		Game.auth_result_sig.connect(_on_host_auth_result, CONNECT_ONE_SHOT)
		var uname := username_input.text.strip_edges()
		Game.client_register(uname, _hash_password(password_input.text), 0, uname))

func _on_host_auth_result(ok: bool, error_code: int, _dn: String, _db: int) -> void:
	if ok:
		get_tree().change_scene_to_file("res://scenes/client/world.tscn")
		return
	if error_code == Protocol.AuthError.USERNAME_TAKEN:
		# Account exists — retry as login.
		Game.auth_result_sig.connect(_on_auth_result, CONNECT_ONE_SHOT)
		Game.client_login(
			username_input.text.strip_edges(),
			_hash_password(password_input.text))
		return
	_show_auth_error(error_code)

# ─── network ─────────────────────────────────────────────────────────────────

func _connect_to_server(after: Callable) -> void:
	var err := Net.join(_server_host, _server_port)
	if err != OK:
		status.text = "Failed to connect (err=%d)" % err
		return
	Net.connected_to_server.connect(func(): after.call(), CONNECT_ONE_SHOT)
	Net.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)

func _on_auth_result(ok: bool, error_code: int, _dn: String, _db: int) -> void:
	if ok:
		get_tree().change_scene_to_file("res://scenes/client/world.tscn")
		return
	_show_auth_error(error_code)

func _on_failed() -> void:
	status.text = "Connection failed."

func _show_auth_error(error_code: int) -> void:
	match error_code:
		Protocol.AuthError.BAD_CREDENTIALS:
			status.text = "Wrong username or password."
		Protocol.AuthError.USERNAME_TAKEN:
			status.text = "Username already taken."
		Protocol.AuthError.BAD_USERNAME:
			status.text = "Invalid username. Use 3-20 chars: letters, digits, underscores."
		Protocol.AuthError.ALREADY_ONLINE:
			status.text = "Account is already logged in."
		_:
			status.text = "Authentication failed (code %d)." % error_code
	Net.disconnect_from_peer()

# ─── helpers ─────────────────────────────────────────────────────────────────

func _validate_credentials() -> bool:
	if username_input.text.strip_edges().is_empty():
		status.text = "Enter a username."
		return false
	if password_input.text.is_empty():
		status.text = "Enter a password."
		return false
	return true

func _hash_password(password: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(password.to_utf8_buffer())
	return ctx.finish().hex_encode()
