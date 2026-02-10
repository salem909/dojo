#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR"

docker build -t ctf-challenge-base:latest ./base

for dir in challenge01 challenge02 challenge03 challenge04 challenge05 challenge06 challenge07 challenge08 challenge09 challenge10; do
  docker build -t "ctf/${dir}:latest" "./${dir}"
done

echo "Challenge images built."
