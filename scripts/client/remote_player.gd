extends Node3D
## Visual representation of any player (local or remote).
## Loads the correct KayKit skeleton model and exposes set_motion_state()
## so callers drive animations directly (idle / walk / run / jump).

enum { IDLE, WALKING, RUNNING, JUMPING }

var _anim_player: AnimationPlayer = null
var _motion: int                  = IDLE

func setup(char_class: int, display_name: String) -> void:
	var model_path: String = Protocol.CHARACTER_MODELS[
		clampi(char_class, 0, Protocol.CHARACTER_MODELS.size() - 1)]
	var packed: PackedScene = load(model_path)
	if packed == null:
		_add_fallback_capsule()
	else:
		var model := packed.instantiate()
		model.scale = Vector3(0.62, 0.62, 0.62)
		model.rotation_degrees.y = 180.0
		add_child(model)
		_anim_player = _find_anim_player(model)
		_force_loop(["Idle", "Idle_B", "Unarmed_Idle",
					 "Walking_A", "Walking_B", "Walking_C",
					 "Running_A", "Running_B", "Running_C",
					 "Jump_Idle"])
		_play_one_of(["Idle", "Idle_B", "Unarmed_Idle"])
	var lbl := $NameLabel as Label3D
	if lbl:
		lbl.text = display_name

func set_motion_state(moving: bool, sprinting: bool, in_air: bool) -> void:
	var next: int
	if in_air:
		next = JUMPING
	elif sprinting:
		next = RUNNING
	elif moving:
		next = WALKING
	else:
		next = IDLE
	if next == _motion:
		return
	_motion = next
	match _motion:
		IDLE:    _play_one_of(["Idle", "Idle_B", "Unarmed_Idle"])
		WALKING: _play_one_of(["Walking_A", "Walking_B", "Walking_C"])
		RUNNING: _play_one_of(["Running_A", "Running_B", "Running_C"])
		JUMPING: _play_one_of(["Jump_Full_Short", "Jump_Full_Long"])

## Backward-compat wrapper used by game.gd for remote players.
func set_moving(moving: bool) -> void:
	set_motion_state(moving, false, false)

# ─── helpers ─────────────────────────────────────────────────────────────────

func _force_loop(names: Array) -> void:
	if _anim_player == null: return
	for anim_name in names:
		if _anim_player.has_animation(anim_name):
			_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result: return result
	return null

func _play_one_of(names: Array) -> void:
	if _anim_player == null: return
	for anim_name in names:
		if _anim_player.has_animation(anim_name):
			if _anim_player.current_animation != anim_name:
				_anim_player.play(anim_name)
			return

func _add_fallback_capsule() -> void:
	var mi  := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	mi.mesh       = cap
	mi.position.y = 0.85
	var mat       := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.65, 0.95)
	mi.set_surface_override_material(0, mat)
	add_child(mi)
