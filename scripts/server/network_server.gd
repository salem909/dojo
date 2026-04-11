extends Node
## Server scene root. Calls Net.host() and tells the Game autoload to switch
## into server mode. All RPC handling lives in scripts/shared/game.gd so the
## node path matches between server and client.

func _ready() -> void:
	var port_str := Boot.get_arg("--port", str(Protocol.DEFAULT_PORT))
	var port: int = int(port_str)
	var err := Net.host(port)
	if err != OK:
		Log.e("server failed to start, exiting")
		get_tree().quit(1)
		return
	Game.become_server()
	Log.i("network_server: ready")
