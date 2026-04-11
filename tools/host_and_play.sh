#!/usr/bin/env bash
# One-command "host and play": start the server in the background, then open
# a windowed client that connects to it. Server logs go to logs/server.log.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
PORT="${1:-24565}"
echo "[host_and_play] starting server on port $PORT"
godot --headless --path . -- --server --port "$PORT" > logs/server.log 2>&1 &
SERVER_PID=$!
trap "echo '[host_and_play] killing server pid=$SERVER_PID'; kill $SERVER_PID 2>/dev/null || true" EXIT
sleep 0.7
echo "[host_and_play] launching client"
godot --path . -- --connect "127.0.0.1:$PORT"
