extends Node3D
## Scatters palm trees and bushes on the island terrain using MultiMeshInstance3D.
## Must be a sibling of IslandTerrain (listed AFTER it in the scene tree so
## terrain _ready runs first).

@export var palm_count: int     = 25
@export var bush_count: int     = 50
@export var min_height: float   = 1.2   # above this = valid spawn
@export var max_height: float   = 5.5   # below this = valid spawn
@export var scatter_radius: float = 18.0

var _terrain: Node = null

func _ready() -> void:
	_terrain = get_parent().get_node_or_null("IslandTerrain")
	if _terrain == null or not _terrain.has_method("get_height_at"):
		push_warning("VegetationScatter: no IslandTerrain sibling found")
		return
	_scatter_palms()
	_scatter_bushes()

# ─── palms ───────────────────────────────────────────────────────────────────

func _scatter_palms() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius    = 0.06
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height        = 4.5
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.40, 0.26, 0.12)
	trunk_mat.roughness    = 0.90
	trunk_mesh.material    = trunk_mat

	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radius = 1.3
	leaf_mesh.height = 1.8
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.16, 0.52, 0.14)
	leaf_mat.roughness    = 0.80
	leaf_mesh.material    = leaf_mat

	var positions := _find_valid_positions(palm_count, 42)

	var mm_trunk := MultiMesh.new()
	mm_trunk.transform_format = MultiMesh.TRANSFORM_3D
	mm_trunk.mesh             = trunk_mesh
	mm_trunk.instance_count   = positions.size()

	var mm_leaf := MultiMesh.new()
	mm_leaf.transform_format = MultiMesh.TRANSFORM_3D
	mm_leaf.mesh             = leaf_mesh
	mm_leaf.instance_count   = positions.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var s := rng.randf_range(0.75, 1.25)
		var rot := rng.randf_range(0.0, TAU)
		var basis := Basis.IDENTITY.rotated(Vector3.UP, rot).scaled(Vector3(s, s, s))
		var trunk_y := pos.y + trunk_mesh.height * 0.5 * s
		mm_trunk.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, trunk_y, pos.z)))
		var leaf_y := pos.y + trunk_mesh.height * s + 0.4
		mm_leaf.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, leaf_y, pos.z)))

	var mmi_t := MultiMeshInstance3D.new()
	mmi_t.multimesh = mm_trunk
	mmi_t.name = "PalmTrunks"
	add_child(mmi_t)

	var mmi_l := MultiMeshInstance3D.new()
	mmi_l.multimesh = mm_leaf
	mmi_l.name = "PalmLeaves"
	add_child(mmi_l)

# ─── bushes ──────────────────────────────────────────────────────────────────

func _scatter_bushes() -> void:
	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 0.55
	bush_mesh.height = 0.75
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.20, 0.46, 0.16)
	bush_mat.roughness    = 0.85
	bush_mesh.material    = bush_mat

	var positions := _find_valid_positions(bush_count, 123)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh             = bush_mesh
	mm.instance_count   = positions.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var s := rng.randf_range(0.45, 1.4)
		var basis := Basis.IDENTITY.scaled(Vector3(s, s * 0.7, s))
		mm.set_instance_transform(i, Transform3D(basis, pos + Vector3(0, 0.25 * s, 0)))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Bushes"
	add_child(mmi)

# ─── helpers ─────────────────────────────────────────────────────────────────

func _find_valid_positions(count: int, seed_val: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var attempts := 0
	while result.size() < count and attempts < count * 15:
		attempts += 1
		var x := rng.randf_range(-scatter_radius, scatter_radius)
		var z := rng.randf_range(-scatter_radius, scatter_radius)
		if Vector2(x, z).length() > scatter_radius * 0.92:
			continue
		var y: float = _terrain.get_height_at(x, z)
		if y < min_height or y > max_height:
			continue
		# Minimum spacing from existing positions
		var too_close := false
		for p in result:
			if Vector2(x - p.x, z - p.z).length() < 2.5:
				too_close = true
				break
		if too_close:
			continue
		result.append(Vector3(x, y, z))
	return result
