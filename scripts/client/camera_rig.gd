extends Camera3D
## Simple third-person follow camera. Smooths to a position behind the target.

@export var target_path: NodePath
@export var distance: float = 6.0
@export var height: float = 4.0
@export var smooth: float = 6.0

var target: Node3D = null

func _ready() -> void:
	if target_path != NodePath(""):
		target = get_node_or_null(target_path) as Node3D

func set_target(node: Node3D) -> void:
	target = node

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var desired_pos: Vector3 = target.global_position + Vector3(0, height, distance)
	position = position.lerp(desired_pos, clamp(delta * smooth, 0.0, 1.0))
	look_at(target.global_position + Vector3(0, 1.0, 0), Vector3.UP)
