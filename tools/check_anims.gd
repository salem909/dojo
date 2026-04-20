extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://assets/models/characters/Skeleton_Warrior.glb")
	var inst := packed.instantiate()
	var ap := _find_ap(inst)
	var names := ["Jump_Full_Short", "Jump_Full_Long", "Jump_Start", "Jump_Land",
				  "Jump_Idle", "Running_A", "Running_B", "Running_C",
				  "Walking_A"]
	for n in names:
		if ap.has_animation(n):
			var a := ap.get_animation(n)
			print("%-20s  loop=%d  dur=%.2fs" % [n, a.loop_mode, a.length])
	inst.free()
	quit()

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node as AnimationPlayer
	for c in node.get_children():
		var r := _find_ap(c)
		if r: return r
	return null
