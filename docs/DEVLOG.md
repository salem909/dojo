# Devlog

Append-only notes. Newest at top. Each entry: what changed, why, what's next.

---

## 2026-04-11 — M0: vertical slice landed

**What:**
- Wiped the previous CTF platform content. Bootstrapped a Godot 4.3 project.
- Authoritative server (`network_server.gd`) over ENet, 30 Hz tick.
- Client with prediction + remote player interpolation.
- One puzzle: bilging match-3, with pure server-side logic
  (`match3_logic.gd`) and a client `Control` view.
- Asset pipeline directories + Blender batch-export script.
- Helper scripts: `tools/host_and_play.sh`, `run_server.sh`, `run_client.sh`.
- CI workflow that headlessly imports the project as a smoke test.

**Why:**
The "MMO from scratch" framing is a trap; you sink months into infra and
ship nothing. The bilging puzzle is the smallest thing that already feels
like Puzzle Pirates, so we lead with that and a real network spine instead.

**Next:**
- M1 — replace capsule with Blender rig + animations.
- Smoke test the puzzle by playing it for 30 seconds and seeing if scoring
  feels right.
- Decide on character art direction before committing further geometry.
