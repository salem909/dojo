# Assets

Drop your Blender exports here. Godot will auto-import everything on next launch.

## Folder layout

```
assets/
├── source/      # .blend files (the editable originals)
├── models/      # .glb / .gltf exports — game-ready geometry + materials
├── textures/    # .png / .webp / .jpg
├── materials/   # .tres material resources made inside Godot
└── audio/       # .ogg / .wav music + sfx
```

## How to add a player model

1. Open your character in Blender.
2. Make sure the armature is named `Skeleton`, the mesh is parented to it, and
   the rest pose faces **−Z** (Godot's "forward").
3. `File → Export → glTF 2.0 (.glb/.gltf)`:
   - Format: **glTF Binary (.glb)**
   - Include: ✅ Selected Objects, ✅ Custom Properties, ✅ Cameras (off),
     ✅ Punctual Lights (off)
   - Transform: +Y Up
   - Geometry: ✅ Apply Modifiers, ✅ UVs, ✅ Normals, ✅ Tangents
   - Animation: ✅ Use Current Frame, ✅ Animation, ✅ Skinning
4. Save as `assets/models/player.glb`
5. Re-open the Godot project. Godot will create `player.glb.import` next to it
   automatically.
6. To use it in-game, open `scenes/world/remote_player.tscn` and replace the
   placeholder `Body` MeshInstance3D with an instance of `assets/models/player.glb`.
   Or just drop the `.glb` straight in — it will become a child Node3D.

A helper script `tools/export_blender.sh` will batch-export all `.blend` files
in `assets/source/` to `assets/models/` if you have Blender installed.

## Asset naming convention

- All lowercase, snake_case: `player_pirate.glb`, `crate_wood.glb`
- Group related assets by prefix: `ship_hull.glb`, `ship_sail.glb`, `ship_mast.glb`
- Animations baked into the same `.glb` as the rig: don't ship separate `.glb` per anim.

## What NOT to commit

- `.blend1` autosaves (already in `.gitignore`)
- Multi-GB sculpt files — keep heavy sources in cloud storage and only commit
  the optimized export.
