extends MeshInstance3D
## Procedural island terrain generator. Uses SurfaceTool + FastNoiseLite
## with a radial falloff to create an island shape rising from the ocean.
## Exposes get_height_at() so other systems can query terrain height.

@export var island_radius: float    = 22.0
@export var grid_resolution: int    = 100
@export var terrain_height: float   = 7.0
@export var noise_frequency: float  = 0.025
@export var noise_octaves: int      = 4
@export var falloff_steepness: float = 2.8
@export var noise_seed: int         = 42

var _noise: FastNoiseLite

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed              = noise_seed
	_noise.noise_type        = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency         = noise_frequency
	_noise.fractal_octaves   = noise_octaves
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain      = 0.5
	_generate()
	_apply_material()

func _generate() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := grid_resolution / 2.0
	var cell := (island_radius * 2.0) / float(grid_resolution)

	# ── vertices ─────────────────────────────────────────────────────────
	for z in range(grid_resolution + 1):
		for x in range(grid_resolution + 1):
			var wx := (float(x) - half) * cell
			var wz := (float(z) - half) * cell
			var y  := _height(wx, wz)
			st.set_uv(Vector2(
				float(x) / float(grid_resolution),
				float(z) / float(grid_resolution)))
			st.add_vertex(Vector3(wx, y, wz))

	# ── triangle indices (CCW winding for upward-facing normals) ─────────
	var w := grid_resolution + 1
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var i := x + z * w
			# Triangle 1: top-left, top-right, bottom-left
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + w)
			# Triangle 2: top-right, bottom-right, bottom-left
			st.add_index(i + 1)
			st.add_index(i + w + 1)
			st.add_index(i + w)

	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()
	# Walkable collision for raycasting / player ground-follow.
	create_trimesh_collision()

func _apply_material() -> void:
	var shader: Shader = load("res://assets/shaders/terrain_island.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material_override = mat

## Public: query terrain height at any world XZ position.
func get_height_at(wx: float, wz: float) -> float:
	return _height(wx, wz)

## Internal height function — matches the vertex generation exactly.
func _height(wx: float, wz: float) -> float:
	var dist := Vector2(wx, wz).length() / island_radius
	dist = clampf(dist, 0.0, 1.0)
	var falloff := 1.0 - pow(dist, falloff_steepness)
	falloff = maxf(falloff, 0.0)
	var n := (_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	return n * terrain_height * falloff - 0.8
