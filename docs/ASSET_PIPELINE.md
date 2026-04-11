# Asset pipeline

## Goal

Drop a `.blend` file in one place, run one command, and have it usable
in‑game next time you open the project.

## Conventions

| Where | What | Tracked in git? |
|---|---|---|
| `assets/source/*.blend` | The editable Blender file | Yes (small files only) |
| `assets/models/*.glb`   | The exported game-ready binary | Yes |
| `assets/textures/`      | Standalone textures (PBR maps, sprites) | Yes |
| `assets/audio/`         | OGG / WAV music & sfx | Yes |
| `assets/source/*.blend1`| Blender autosaves | **No** (`.gitignore`) |

## Pipeline

```
   Blender (.blend)            tools/export_blender.sh           Godot import
        │                              │                                │
        ▼                              ▼                                ▼
 assets/source/foo.blend  ───►  assets/models/foo.glb  ───►  assets/models/foo.glb.import
                                                                       │
                                                                       ▼
                                                              usable in Godot scenes
```

### Manual export from Blender

1. Select your model + armature in the 3D viewport.
2. **File → Export → glTF 2.0 (.glb/.gltf)**
3. Format: **glTF Binary (.glb)**
4. Transform: **+Y Up**
5. Geometry: ✅ Apply Modifiers, ✅ UVs, ✅ Normals, ✅ Tangents
6. Animation: ✅ Animation, ✅ Skinning
7. Save as `assets/models/<name>.glb`
8. Re-open the Godot project → done.

### Batch export

```bash
./tools/export_blender.sh
```

Walks `assets/source/*.blend` and writes a `.glb` for each into
`assets/models/`. Requires `blender` on `PATH`. No-op if Blender isn't
installed (so CI doesn't break).

## Using a model in a scene

1. Open Godot.
2. In the FileSystem dock, drag `assets/models/player.glb` into the scene.
3. Re-parent / position as needed.
4. To replace the placeholder capsule character:
   - Open `scenes/world/remote_player.tscn`
   - Delete the `Body` MeshInstance3D
   - Drag `assets/models/player.glb` in as a child of the root
   - Save. Every player now uses your model.

## Material conventions

- Use Godot's **StandardMaterial3D** for prototyping.
- For final art, prefer baking a single PBR material in Blender (Principled
  BSDF) and exporting it embedded in the `.glb`. Godot reads the embedded
  material correctly.
- Texture atlasing is preferred for the world props (one texture per ship,
  per puzzle station, etc.) to keep draw calls down.

## Animation conventions

- Bake all animations into the same `.glb` as the rig.
- Naming: `idle`, `walk`, `run`, `sit`, `pump_lever`, `cheer`, etc.
- Length is whatever you want — Godot will play the named animations from
  the AnimationPlayer that the import auto-creates.
