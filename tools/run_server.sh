#!/usr/bin/env bash
# Launch the headless authoritative server.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-24565}"
exec godot --headless --path . -- --server --port "$PORT"
