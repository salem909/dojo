extends Node
## Local-player controller. Reads WASD/space, moves the local avatar locally
## with simple prediction, and forwards target position + yaw to the server.

@export var move_speed: float = 5.0

var local_avatar: Node3D = null
var network_client: Node = null

func _ready() -> void:
	set_physics_process(true)

func attach(avatar: Node3D, net: Node) -> void:
	local_avatar = avatar
	network_client = net

func _physics_process(delta: float) -> void:
	if local_avatar == null or network_client == null:
		return
	var input_vec := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): input_vec.z -= 1.0
	if Input.is_action_pressed("move_back"):    input_vec.z += 1.0
	if Input.is_action_pressed("move_left"):    input_vec.x -= 1.0
	if Input.is_action_pressed("move_right"):   input_vec.x += 1.0
	if input_vec.length() > 0.01:
		input_vec = input_vec.normalized()
		local_avatar.position += input_vec * move_speed * delta
		var yaw := atan2(-input_vec.x, -input_vec.z)
		local_avatar.rotation.y = lerp_angle(local_avatar.rotation.y, yaw, 0.25)
	# Push to server every physics tick (server runs at 30Hz, matches us).
	network_client.send_move(local_avatar.position, local_avatar.rotation.y)
