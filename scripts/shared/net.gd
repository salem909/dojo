extends Node
## Tiny shared networking helpers used by both client and server.
## Knows whether we're host/client and exposes a few signals.

signal peer_connected_to_us(peer_id: int)
signal peer_disconnected_from_us(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()

var is_server: bool = false
var local_peer_id: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = Protocol.DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Protocol.MAX_CLIENTS)
	if err != OK:
		Log.e("host: failed to create server on port %d (err=%d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	local_peer_id = 1
	Log.i("hosting on port %d" % port)
	return OK

func join(host_addr: String = Protocol.DEFAULT_HOST, port: int = Protocol.DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_addr, port)
	if err != OK:
		Log.e("join: failed to connect to %s:%d (err=%d)" % [host_addr, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	Log.i("connecting to %s:%d" % [host_addr, port])
	return OK

func disconnect_from_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	is_server = false
	local_peer_id = 0

func _on_peer_connected(id: int) -> void:
	Log.i("peer connected id=%d" % id)
	peer_connected_to_us.emit(id)

func _on_peer_disconnected(id: int) -> void:
	Log.i("peer disconnected id=%d" % id)
	peer_disconnected_from_us.emit(id)

func _on_connected_ok() -> void:
	local_peer_id = multiplayer.get_unique_id()
	Log.i("connected to server, local id=%d" % local_peer_id)
	connected_to_server.emit()

func _on_connection_failed() -> void:
	Log.e("connection to server failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	Log.w("server disconnected us")
	server_disconnected.emit()
