# Ocean Water System

## Overview

The ocean water in AtlariousPuzzles uses a **Gerstner wave shader** with vertex displacement, depth-based coloring, fresnel reflection, screen-space refraction, and procedural foam. No external textures are required — all effects are computed in the shader.

## Architecture

```
assets/shaders/ocean_water.gdshader   ← shared shader (vertex + fragment)
scenes/client/world.tscn              ← ship scene: ShaderMaterial on Water mesh
scenes/client/island.tscn             ← island scene: ShaderMaterial on Water mesh
```

Both scenes use a `PlaneMesh` (300x300 units, 128x128 subdivisions) with a `ShaderMaterial` that references the shared `.gdshader` file. Each scene has its own shader parameter overrides for slightly different wave behavior (the island has gentler, longer-wavelength swells).

## How Gerstner Waves Work

Unlike simple sine waves, **Gerstner waves** displace vertices both horizontally and vertically, producing the characteristic peaked crests and flat troughs of real ocean waves. Each wave is defined by 4 parameters packed into a `vec4`:

| Component | Meaning |
|-----------|---------|
| `x, y`    | Wave direction (normalized internally) |
| `z`       | Steepness (0.0–1.0). Higher = sharper peaks. Above ~0.5 causes looping artifacts. |
| `w`       | Wavelength in meters. Longer = larger, slower waves. |

The shader sums 4 independent Gerstner waves (`wave_a` through `wave_d`) to produce complex, natural-looking motion. Each wave also contributes to the surface tangent and binormal vectors, giving correct normal mapping for lighting.

**Physics:** Wave phase speed follows the deep-water dispersion relation `c = sqrt(g / k)` where `k = 2π / wavelength` and `g = 9.8 m/s²`. This means longer waves travel faster — matching real ocean behavior.

## Shader Parameters Reference

### Colors

| Parameter | Default | Description |
|-----------|---------|-------------|
| `shallow_color` | `(0.22, 0.66, 0.84, 0.85)` | Water color where geometry is just below the surface |
| `deep_color` | `(0.04, 0.12, 0.35, 0.95)` | Water color in deep areas |
| `fresnel_color` | `(0.70, 0.90, 1.00)` | Color at grazing angles (edges of view, where sky reflects) |
| `foam_color` | `(0.95, 0.98, 1.00)` | White foam on wave peaks and shorelines |

### Depth

| Parameter | Default | Description |
|-----------|---------|-------------|
| `beers_law` | `2.0` | Absorption rate. Higher = faster falloff from shallow to deep color. |
| `depth_offset` | `-0.75` | Shifts the depth sampling. Tweak if colors look wrong near surfaces. |
| `fresnel_power` | `5.0` | Higher = fresnel only at extreme angles. Lower = more reflection everywhere. |

### Waves

| Parameter | Default (Ship) | Description |
|-----------|----------------|-------------|
| `wave_a` | `(1.0, 1.0, 0.22, 4.0)` | Primary swell |
| `wave_b` | `(1.0, 0.6, 0.18, 2.5)` | Secondary wave |
| `wave_c` | `(0.8, 1.3, 0.12, 1.2)` | Small detail wave |
| `wave_d` | `(-0.6, 0.9, 0.08, 0.8)` | Cross-wave for complexity |
| `wave_speed` | `0.4` | Global time multiplier. Lower = calmer. |

### Foam

| Parameter | Default | Description |
|-----------|---------|-------------|
| `foam_threshold` | `0.55` | Wave height above which peak foam appears |
| `foam_intensity` | `0.6` | Opacity of wave-peak foam |
| `edge_foam_width` | `0.8` | How far from shore edges the foam band extends |

## Mesh Setup

The water plane requires **subdivisions** for vertex displacement to work:

```
PlaneMesh:
  size = (300, 300)         # covers the visible ocean
  subdivide_width = 128     # 128×128 = 16K vertices
  subdivide_depth = 128
  position.y = -0.3         # slightly below the ground plane
```

Higher subdivisions (256+) give smoother waves but cost more draw calls. 128 is a good balance for the current game scale.

## Per-Scene Tuning

**Ship scene** (`world.tscn`): Slightly choppier waves with more foam (harbor with wind).

**Island scene** (`island.tscn`): Gentler, longer-wavelength swells with wider edge foam (tropical lagoon feel). Wave speed is slightly lower.

To tune a scene: select the Water `MeshInstance3D`, expand the `ShaderMaterial`, and adjust parameters in the inspector. Changes are immediate.

## Performance Notes

- **128×128 PlaneMesh**: ~16K vertices. Negligible impact on modern GPUs.
- **Screen texture sampling** (`SCREEN_TEXTURE`, `DEPTH_TEXTURE`): Requires one extra render pass. This is standard for any transparent/refractive material in Godot 4.
- **4 Gerstner waves in vertex shader**: Very cheap — just trig functions per vertex.
- **Procedural foam (FBM noise)**: 3 octaves of hash noise in the fragment shader. Cheaper than sampling a texture.
- **No shadow casting**: The water mesh should have `cast_shadow = Off` (it's a flat plane, shadows would be wrong).

## Extending the Shader

### Adding normal maps
For more surface detail between vertices, add two scrolling normal maps:
```glsl
uniform sampler2D normal_a : hint_normal;
uniform sampler2D normal_b : hint_normal;
// Sample at different scales/speeds, blend, and use for NORMAL
```

### Adding caustics
Use a `sampler2DArray` with 16 pre-rendered caustic frames. Sample based on `floor(mod(TIME * 26.0, 16.0))` for animated underwater light patterns.

### Infinite ocean
For open-ocean scenes, attach the water plane to the camera's XZ position (snap to grid to avoid vertex swimming). The shader uses world-space UVs so waves tile seamlessly.

## References

- [Gerstner Waves — GPU Gems Ch. 1](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models)
- [Water Shader 3D (Godot 4.3) — GodotShaders](https://godotshaders.com/shader/water-shader-3d-godot-4-3/)
- [Gerstner Wave Ocean Shader — GodotShaders](https://godotshaders.com/shader/gerstner-wave-ocean-shader/)
- [Gerstner Waves with Buoyancy in Godot 4 — SeaCreatureGame](https://www.seacreaturegame.com/blog/gerstner-waves-with-buoyancy-godot)
- [Realistic Water Shader — GodotShaders](https://godotshaders.com/shader/realistic-water/)
