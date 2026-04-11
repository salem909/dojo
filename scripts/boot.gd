extends Node
class_name Boot
## Entry point. Inspects cmdline and routes to either the server scene or
## the client main menu. This is what `--main-scene` points at in project.godot.
##
## Server:    godot --headless -- --server [--port 24565]
## Client:    godot           [--connect 127.0.0.1] [--port 24565]
## Hostclient: godot          --host        (run server + client in one process)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var is_server: bool = "--server" in args
	var is_host: bool = "--host" in args
	var target: String
	if is_server:
		Log.i("boot -> server")
		target = "res://scenes/server/server.tscn"
	elif is_host:
		Log.i("boot -> hostclient (server + local client)")
		target = "res://scenes/client/main_menu.tscn"
	else:
		Log.i("boot -> client")
		target = "res://scenes/client/main_menu.tscn"
	# Must defer: we are inside the SceneTree's add-children pass.
	get_tree().call_deferred("change_scene_to_file", target)

static func get_arg(arg_name: String, default_value: String = "") -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == arg_name and i + 1 < args.size():
			return args[i + 1]
		if a.begins_with(arg_name + "="):
			return a.substr(arg_name.length() + 1)
	return default_value
