# Island Terrain System

## Overview

The island uses a **procedurally generated terrain mesh** with height/slope-based shader splatting and MultiMesh vegetation scatter. No external models or textures are imported — everything is computed at runtime.

## Architecture

```
scripts/client/island_terrain.gd      ← SurfaceTool mesh generator
scripts/client/vegetation_scatter.gd  ← MultiMeshInstance3D palm/bush spawner
assets/shaders/terrain_island.gdshader ← height+slope color blending
scenes/client/island.tscn              ← scene wiring
```

## Terrain Generation (`island_terrain.gd`)

### Algorithm

1. Create a grid of `(grid_resolution+1)^2` vertices spanning `island_radius * 2` units
2. For each vertex, compute height as: `noise(x, z) * terrain_height * radial_falloff - offset`
3. **Radial falloff** = `1.0 - pow(distance_from_center / radius, steepness)` — creates circular island shape
4. Connect vertices into triangles, generate normals and tangents
5. Call `create_trimesh_collision()` for physics/raycasting

### Parameters

| Export | Default | Description |
|--------|---------|-------------|
| `island_radius` | 22.0 | Half-width of the terrain grid |
| `grid_resolution` | 100 | Vertices per axis (100 = 10K total) |
| `terrain_height` | 7.0 | Maximum peak height in units |
| `noise_frequency` | 0.025 | FastNoiseLite frequency. Lower = broader hills |
| `noise_octaves` | 4 | Fractal detail layers |
| `falloff_steepness` | 2.8 | How sharply the island edge drops off (higher = steeper coast) |
| `noise_seed` | 42 | Deterministic seed for consistent island shape |

### Public API

```gdscript
func get_height_at(wx: float, wz: float) -> float
```

Returns the terrain height at any world XZ position. Used by vegetation scatter, portal/NPC placement, and can be used for buoyancy or AI pathfinding.

## Terrain Shader (`terrain_island.gdshader`)

Blends three biomes based on vertex height and surface slope:

| Biome | Height Range | Slope | Color |
|-------|-------------|-------|-------|
| **Sand** | Below `beach_height` | Any | Warm tan |
| **Grass + dirt** | Mid heights | Flat | Green with dirt patches |
| **Rock** | Above `grass_height` OR steep slopes | > cliff threshold | Gray stone |

All colors use procedural FBM noise for micro-variation — no texture imports needed.

## Vegetation Scatter (`vegetation_scatter.gd`)

Uses `MultiMeshInstance3D` for efficient instanced rendering:

- **Palm trees**: trunk (CylinderMesh) + canopy (SphereMesh), random scale (0.75–1.25x) and rotation
- **Bushes**: flattened SphereMesh, random scale (0.45–1.4x)
- Both respect terrain height bounds (`min_height` to `max_height`)
- Minimum spacing of 2.5 units between vegetation items
- Deterministic seeds for consistent placement across sessions

### Performance

| Feature | Cost |
|---------|------|
| 100×100 terrain mesh | ~10K vertices, trivial |
| `create_trimesh_collision()` | One-time at scene load |
| 25 palm instances | 2 MultiMesh draw calls (trunks + leaves) |
| 50 bush instances | 1 MultiMesh draw call |
| **Total scene draw calls** | ~4 for all vegetation |

## Player Terrain Following

`player_controller.gd` uses a **downward physics raycast** each physics tick to find the ground surface:

```
Ray: avatar.position + (0, 10, 0) → avatar.position - (0, 30, 0)
```

- **Island scene**: hits terrain trimesh collision → follows surface
- **Ship scene**: no collision geometry → falls back to y=0 (flat deck)
- **Jumping**: when airborne, gravity applies normally; landing detected when `position.y <= ground_y`
- **Walking**: smooth lerp toward ground_y for gentle slope transitions

## References

- [Godot SurfaceTool Docs](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/surfacetool.html)
- [FastNoiseLite Docs](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html)
- [MultiMeshInstance3D Docs](https://docs.godotengine.org/en/stable/classes/class_multimeshinstance3d.html)
- [Procedural Terrain Generator (GitHub)](https://github.com/EmberNoGlow/Procedural-Terrain-Generator-for-Godot)
- [Godot Terrain Shader (victorkarp.com)](https://victorkarp.com/godot-terrain-shader/)
