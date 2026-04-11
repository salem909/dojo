# Architecture

## High-level

```
   ┌──────────────────────┐         ENet over UDP         ┌──────────────────────┐
   │   Godot CLIENT       │  ◀──────────────────────▶     │   Godot SERVER       │
   │   (windowed)         │                                │   (--headless)       │
   │                      │                                │                      │
   │  main_menu.tscn      │                                │  server.tscn         │
   │  world.tscn          │                                │  network_server.gd   │
   │  network_client.gd   │                                │  match3_logic.gd     │
   │  player_controller   │                                │  (pure data)         │
   │  camera_rig          │                                │                      │
   └──────────────────────┘                                └──────────────────────┘
            │                                                          │
            └────────── shared autoloads (Net, Protocol, Log) ─────────┘
```

The same Godot project produces both client and server. The `boot.gd` script
inspects `OS.get_cmdline_args()` and routes to either `scenes/server/server.tscn`
or `scenes/client/main_menu.tscn`. This means **one project, one codebase, no
duplication** — the price is that the server still drags in some Godot bits
it doesn't need (acceptable for now; we can split into a dedicated headless
target later if memory becomes a concern).

## Authority model

The server is the single source of truth. Clients are dumb terminals:

- **Client → Server (input):** the local player runs prediction (it moves its
  own avatar instantly so the player doesn't feel input lag), then sends its
  new position to the server every physics tick via the `server_move_input`
  RPC.
- **Server validates:** it clamps the position delta against
  `Protocol.MAX_POS_DELTA` (anti‑teleport) and stores the result in
  `players[peer_id]`.
- **Server → Client (snapshot):** every server tick (30 Hz), the server
  broadcasts a flat array of `[peer_id, x, y, z, yaw]` to every connected
  client.
- **Client interpolates:** `network_client.gd` lerps remote players toward
  the latest snapshot position. The local player's snapshot is **ignored**
  (we trust our own prediction) — server reconciliation will be added in
  the next milestone.

## RPC catalogue

| Direction | Name | Reliability | Purpose |
|---|---|---|---|
| C→S | `server_move_input(target_pos, yaw)` | unreliable_ordered | Player tick input |
| C→S | `server_start_match3()` | reliable | Begin a puzzle session |
| C→S | `server_match3_swap(ax, ay, bx, by)` | reliable | Try to swap two tiles |
| C→S | `server_match3_end()` | reliable | Cancel/finish puzzle |
| S→C | `client_player_spawned(peer, name, pos)` | reliable | A player joined |
| S→C | `client_player_despawned(peer)` | reliable | A player left |
| S→C | `client_world_snapshot(snap)` | unreliable_ordered | 30 Hz position broadcast |
| S→C | `client_match3_started(board, score)` | reliable | Initial puzzle board |
| S→C | `client_match3_update(board, score, last_matched)` | reliable | Post-swap board |
| S→C | `client_match3_finished(final_score)` | reliable | Reward payout |

Both server and client `.gd` files declare every RPC method (server RPCs as
no-op stubs on the client and vice versa) so Godot's RPC registration matches
on both ends.

## Puzzle subsystem

Each puzzle minigame is a directory under `scripts/puzzles/<id>/` containing:

- `<id>_logic.gd` — a `RefCounted` class with **no engine dependencies**.
  Easy to unit-test; can be moved to a dedicated server binary later.
- `<id>_view.gd` — a `Control` (or `Node3D`) that renders the board and
  forwards input to the network client.

The server holds one logic instance **per active session** in
`network_server.gd::match3_sessions`. The client never owns logic state — it
only displays whatever the server says.

## Why server-authoritative for a puzzle minigame?

Because the puzzles award in-game currency (`doubloons`), they're the obvious
cheat target. Doing the match-finding on the server means a modified client
can't fake matches.

## Asset pipeline

Blender `.blend` files live in `assets/source/`. They are exported to
`assets/models/*.glb` either by hand (Blender → Export → glTF Binary) or by
running `tools/export_blender.sh`. Godot picks up the `.glb` files
automatically on next launch and creates `.import` files next to them. See
[ASSET_PIPELINE.md](ASSET_PIPELINE.md).

## Future work (in priority order)

See [ROADMAP.md](ROADMAP.md).
