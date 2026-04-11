# Dojo MMO

A 3D MMO puzzle game inspired by **Puzzle Pirates**, built with **Godot 4.3**.
Players sail a shared world and play minigames at stations to earn rewards.
This repo is the **vertical slice**: client + authoritative server, networked
3D player movement, and one playable puzzle (the bilging match‑3).

## Quick start

You need [Godot 4.3+](https://godotengine.org/download) on your `PATH`.

```bash
# One command — starts a headless server and opens a windowed client.
./tools/host_and_play.sh

# Or run them separately:
./tools/run_server.sh        # terminal 1
./tools/run_client.sh        # terminal 2 (and 3, 4, ... for more players)
```

You should see a 3D world with a green ground and an orange "Bilging Pump"
station. **WASD** to move, **E** near the station to start the puzzle, **ESC**
to exit it.

## Project layout

```
.
├── project.godot                  Godot project file
├── icon.svg
├── assets/                        Drop Blender exports here (see assets/README.md)
│   ├── source/                    .blend originals
│   ├── models/                    .glb / .gltf — auto-imported by Godot
│   ├── textures/  materials/  audio/
├── scenes/
│   ├── boot/boot.tscn             Entry point — routes to client or server
│   ├── client/main_menu.tscn      Title screen
│   ├── client/world.tscn          The 3D world the player joins
│   ├── server/server.tscn         Headless server scene
│   ├── puzzles/match3/match3_ui.tscn
│   └── world/remote_player.tscn   Capsule placeholder for any player
├── scripts/
│   ├── boot.gd
│   ├── shared/                    Code used by client AND server
│   │   ├── log.gd                 Tiny structured logger (autoloaded)
│   │   ├── net.gd                 ENet host/join helpers (autoloaded)
│   │   ├── protocol.gd            Constants, enums, message shapes (autoloaded)
│   │   └── player_state.gd
│   ├── server/
│   │   └── network_server.gd      Authoritative server, RPCs, world tick
│   ├── client/
│   │   ├── network_client.gd      Receives snapshots, drives interp
│   │   ├── player_controller.gd   Local input → predicted move + RPC
│   │   ├── camera_rig.gd          Third-person follow camera
│   │   ├── world.gd               World scene controller
│   │   └── main_menu.gd
│   └── puzzles/match3/
│       ├── match3_logic.gd        Pure server-side game logic (testable)
│       └── match3_view.gd         Client-side grid renderer
├── tools/
│   ├── host_and_play.sh
│   ├── run_server.sh
│   ├── run_client.sh
│   └── export_blender.sh          Batch .blend → .glb if you have Blender
├── docs/
│   ├── ARCHITECTURE.md
│   ├── ASSET_PIPELINE.md
│   ├── ROADMAP.md
│   └── DEVLOG.md
└── .github/workflows/ci.yml       Headless project import + parse check
```

## Architecture in one paragraph

The **server** is authoritative. Clients send their intended position via
`server_move_input` RPC; the server clamps for sanity and broadcasts a
30 Hz world snapshot back to every client. Puzzle minigame state lives entirely
on the server (`scripts/puzzles/match3/match3_logic.gd` is pure data — no
engine references — so it's easy to unit-test). Clients only render the
results. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details.

## Adding your Blender assets

See [assets/README.md](assets/README.md). TL;DR: export `.glb`, drop into
`assets/models/`, re-open the project. Replace the placeholder capsule in
`scenes/world/remote_player.tscn` with your model.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md). The slice that exists today is the
foundation; the next milestones add ship vessels, multi-player ship crews,
more puzzle minigames (sailing, gunning, sword‑fighting), persistence, and
account auth.
