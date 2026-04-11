#!/usr/bin/env bash
# Batch-export every .blend file in assets/source to assets/models as .glb.
# Requires `blender` on PATH. No-op if blender is not installed.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v blender >/dev/null 2>&1; then
  echo "[export_blender] blender not found on PATH, skipping."
  exit 0
fi

mkdir -p assets/models
shopt -s nullglob
for blend in assets/source/*.blend; do
  base=$(basename "$blend" .blend)
  out="assets/models/${base}.glb"
  echo "[export_blender] $blend -> $out"
  blender --background "$blend" --python-expr "
import bpy
bpy.ops.export_scene.gltf(
    filepath='${out}',
    export_format='GLB',
    export_apply=True,
    export_yup=True,
    export_animations=True,
    export_skins=True,
)
" >/dev/null
done
echo "[export_blender] done."
