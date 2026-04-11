#!/usr/bin/env bash
# Launch a windowed client and auto-connect to a server.
set -euo pipefail
cd "$(dirname "$0")/.."
ADDR="${1:-127.0.0.1:24565}"
exec godot --path . -- --connect "$ADDR"
