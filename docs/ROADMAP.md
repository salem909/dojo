# Roadmap

The point of this list is to keep the project from drowning in scope. Each
milestone is a thing you can actually play. Don't start the next one until
the previous one is fun for at least five minutes.

## ✅ M0 — Vertical slice (this commit)

- Headless authoritative server + windowed client, both from one Godot project.
- ENet networking. Multiple clients can join, see each other, walk around.
- One 3D scene (flat ground, sun, sky).
- Capsule placeholder character — drop-in replacement for Blender models.
- One puzzle minigame: **Bilging** (match-3, server-validated).
- Asset pipeline scaffolding: `assets/{source,models,textures,materials,audio}`,
  Blender batch-export script.
- CI smoke test that imports the project headlessly.

## M1 — A real 3D player

- Replace the capsule with a Blender-rigged character.
- Idle / walk / run animation states driven by movement speed.
- Mouse-look third-person camera, jump, basic collisions.
- A second player visible at the same time, smoothly interpolated.

## M2 — A boat

- A ship `Node3D` with a deck the player can walk on (KinematicBody parented
  to a moving platform).
- One ship hosts up to 4 player crew members.
- Wheel station: standing on it lets you steer.
- Bilging station spawns the existing match-3 puzzle.

## M3 — Persistence + accounts

- SQLite on the server for: accounts (login + bcrypt), per-character
  doubloons, last login.
- A simple `--auth-token` for the client.
- Doubloons earned by puzzles persist between sessions.

## M4 — Two more puzzles

- **Sailing puzzle:** rhythm-based tile placement (puzzle pirates' "wind").
- **Gunning puzzle:** spatial Tetris-ish loading minigame.
- Each one earns its respective ship-task contribution.

## M5 — A second ship and PvP

- Two ships in the same world.
- "Battle mode" when ships collide: gunning puzzle determines damage, sailing
  puzzle determines positioning.

## M6 — World map + multiple islands

- Switch the single flat scene for a small archipelago. Each island is its
  own scene loaded from a portal.

## M7 — Cosmetics + economy

- Buy hats / outfits with doubloons. Server-tracked inventory.
- This is the first thing you can show friends and have them care.

---

**Out of scope until much later:** PvE NPCs, guilds, mass PvP, voice chat,
mobile build, anti-cheat beyond server validation, web client.
