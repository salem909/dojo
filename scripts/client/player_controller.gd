extends Node
## Local-player controller. Reads WASD + Shift (sprint) + Space (jump),
## moves the local avatar with client-side prediction, drives animation
## state, and forwards position + yaw to the server.
## Follows terrain height via physics raycast when collision shapes exist.

@export var move_speed: float        = 1.8
@export var sprint_multiplier: float = 2.5
@export var jump_force: float        = 6.0
@export var gravity: float           = 20.0

var local_avatar: Node3D  = null
var network_client: Node  = null
var enabled: bool         = true

var _vertical_velocity: float = 0.0
var _is_grounded: bool        = true
var _ground_y: float          = 0.0

func _ready() -> void:
	set_physics_process(true)

func attach(avatar: Node3D, net: Node) -> void:
	local_avatar   = avatar
	network_client = net

func _physics_process(delta: float) -> void:
	if not enabled or local_avatar == null or network_client == null:
		return

	# ── sample ground height (raycast down from above the avatar) ────────
	_ground_y = _get_ground_height()

	# ── horizontal movement ──────────────────────────────────────────────
	var input_vec := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): input_vec.z -= 1.0
	if Input.is_action_pressed("move_back"):    input_vec.z += 1.0
	if Input.is_action_pressed("move_left"):    input_vec.x -= 1.0
	if Input.is_action_pressed("move_right"):   input_vec.x += 1.0

	var is_moving := input_vec.length() > 0.01
	var sprinting := is_moving and Input.is_action_pressed("sprint")
	var speed     := move_speed * (sprint_multiplier if sprinting else 1.0)

	if is_moving:
		input_vec = input_vec.normalized()
		local_avatar.position += input_vec * speed * delta
		var yaw := atan2(-input_vec.x, -input_vec.z)
		local_avatar.rotation.y = lerp_angle(local_avatar.rotation.y, yaw, 0.25)

	# ── vertical / jump ─────────────────────────────────────────────────
	if _is_grounded and Input.is_action_just_pressed("jump"):
		_vertical_velocity = jump_force
		_is_grounded       = false

	if not _is_grounded:
		_vertical_velocity      -= gravity * delta
		local_avatar.position.y += _vertical_velocity * delta
		if local_avatar.position.y <= _ground_y:
			local_avatar.position.y = _ground_y
			_vertical_velocity      = 0.0
			_is_grounded            = true
	else:
		# Snap to terrain surface while walking (smooth follow).
		local_avatar.position.y = lerpf(local_avatar.position.y, _ground_y, 0.35)

	# ── animation ────────────────────────────────────────────────────────
	if local_avatar.has_method("set_motion_state"):
		local_avatar.set_motion_state(is_moving, sprinting, not _is_grounded)

	# ── network ──────────────────────────────────────────────────────────
	network_client.send_move(local_avatar.position, local_avatar.rotation.y)

# ─── terrain height via raycast ──────────────────────────────────────────────

func _get_ground_height() -> float:
	## Cast a ray downward from above the avatar. If it hits a collision shape
	## (e.g. terrain trimesh), return the hit Y. Otherwise fall back to 0.0
	## (flat scenes like the ship deck that have no collision geometry).
	if local_avatar == null:
		return 0.0
	var space := local_avatar.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var origin := local_avatar.global_position + Vector3(0, 10, 0)
	var target := local_avatar.global_position - Vector3(0, 30, 0)
	var query  := PhysicsRayQueryParameters3D.create(origin, target)
	var result := space.intersect_ray(query)
	if result:
		return result.position.y
	return 0.0
