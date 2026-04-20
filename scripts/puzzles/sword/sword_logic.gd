extends RefCounted
## Pure server-side logic for the Swordfighting puzzle.
##
## Rules sourced from three references:
##   - yppedia.puzzlepirates.com/Swordfight    (player-facing mechanics)
##   - FULL_ANALYSIS.md §4                      (high-level internal values)
##   - PP disassembled bytecode in              (deep mechanics; cited inline)
##     C:\Users\USER\Desktop\PP\yoclient\docs\dissasmble\com\threerings\
##     piracy\puzzle\sword\
##
## Bytecode-grounded facts wired into this file:
##   - Board dims 6×13 (SwordConfig.jbc:197-207)
##   - Spawn col 3 (DropBlockSprite.t = iconst_3, drop/client/i.jbc:91-93)
##   - 8 distinct color slots (Sword.jbc:34-42, NUM_SWORD_COLORS=8); standard
##     play uses 4, special game-modes (Atlantean/Cursed/Vampire) light up
##     the others. We expose NUM_COLORS_DEFAULT=4 and allow up to 8.
##   - Strike pieces are 3-stage decaying: each board lock ages a strike by 1
##     and unshattered strikes vanish at age 0 (SwordBoard.updateStrikePieces
##     362-438; piece type bits 256→384→512→0).
##   - Strike-size tier thresholds {24, 28, 34, 38} → 4 reward tiers
##     (sword/data/c.jbc:25-44, the `g` array — small/medium/big/huge).
##   - Sprinkle volume tier thresholds {0, 4, 12} → 3 reward tiers
##     (sword/data/c.jbc:8-24, the `f` array).
##   - Drop velocity 0.01F × (difficulty+1) (SwordObject.jbc:37-46).
##   - progressInterval 500ms default cadence (SwordObject.jbc:21-23). We
##     run our gravity at scaled drop_interval_ms instead of the original's
##     velocity model since Godot's tick is fixed.
##   - No hard-drop binding in PP — only Space-held soft-drop (puzzle/client/
##     v.jbc:301-307). We keep drop_pair() as a test API and a "panic"
##     keybind, but the standard play flow is set_soft_dropping(true/false).
##   - Two-direction rotation: VK_UP=CCW, VK_DOWN=CW (v.jbc:271-290).
##
## The puzzle runs on real-time gravity: the server calls tick(delta_ms) on
## its world tick and the pair falls one row per drop_interval_ms. When the
## pair cannot fall further, a lock_delay grace period lets the player still
## tuck it (move/rotate into a fitting position) before it locks.
## No engine dependencies — easy to unit test with deterministic ticks.
##
## Board is 6 wide × 13 tall, row 0 = top. Pieces fall in pairs from column 3
## (the "fourth column", which is the loss column — if a piece cannot enter
## here at spawn time, the player loses). Two piece kinds exist:
##   - SOLID   — remains on the board until shattered
##   - BREAKER — when locked, shatters all connected same-colored solids
## Any 2×2 or larger rectangle of same-color solids fuses into a STRIKE.
## Shattering a strike yields SWORDS (immovable damage blocks that decay to
## SPRINKLES after one resolve cycle). Chain multiplier = nth reaction × n.
##
## The puzzle runs on real-time gravity: the server calls tick(delta_ms) on
## its world tick and the pair falls one row per drop_interval_ms. Players
## also issue explicit moves / rotates / soft-drops / hard-drops. When the
## pair cannot fall further, a lock_delay grace period lets the player still
## tuck it (move/rotate into a fitting position) before it locks.
## No engine dependencies — easy to unit test with deterministic ticks.

const COLS: int = 6
const ROWS: int = 13
const NUM_COLORS_MAX: int = 8     # 1..8 (red, orange, yellow, green, blue, purple, white, black)
const NUM_COLORS_DEFAULT: int = 4 # standard ocean uses the first 4
const SPAWN_COL: int = 3          # the "fourth column" — losing column

# Strike scoring tiers (sword/data/c.jbc:25-44, the `g` int[] array). The
# size of a joined block at shatter time → tier index. Larger tiers carry
# stronger bonuses in _resolve_shatter_chain.
const STRIKE_TIER_THRESHOLDS: Array = [24, 28, 34, 38]  # small / med / big / huge

# Sprinkle volley tiers (sword/data/c.jbc:8-24, the `f` int[] array). Number
# of solid blocks shattered in a single chain link → tier index → number of
# sprinkles dropped on the player (or in PvP, the opponent).
const SPRINKLE_TIER_THRESHOLDS: Array = [0, 4, 12]      # small / med / large
const SPRINKLE_TIER_COUNTS: Array     = [1, 3, 6]       # how many sprinkles per tier

# Strike lifetime in board-locks. Each pair lock ages every strike by 1; a
# strike that reaches age 0 simply vanishes (SwordBoard.updateStrikePieces
# 362-438; original encoding had 3 stages 256→384→512→0). Players must use
# breakers promptly to capitalize on strikes.
const STRIKE_MAX_AGE: int = 3

# Backward-compat alias for tests that referenced NUM_COLORS.
const NUM_COLORS: int = NUM_COLORS_DEFAULT

# Difficulty → drop interval. Original: velocity = 0.01F * (difficulty+1)
# (SwordObject.jbc:37-46). We translate to ms-per-row at our 60Hz tick:
# higher difficulty = faster fall. base 800ms at diff=0, 100ms at diff=10.
const DROP_INTERVAL_BASE_MS: int = 800
const DROP_INTERVAL_MIN_MS:  int = 100
# Soft-drop multiplier — while the player holds Space, drop interval is
# divided by this. ~7-8x feels right vs PP's velocity model.
const SOFT_DROP_MULTIPLIER: int = 8

# Cell value encoding. Simple ints so it serializes cleanly over RPC.
#   0        = empty
#   1..4     = SOLID of color c
#   11..14   = BREAKER of color c  (10 + color)
#   21..24   = STRIKE of color c   (20 + color, fused 2x2+ solid)
#   30       = SPRINKLE (gray, non-fusing, decays next tick)
#   40       = SWORD  (damage block, decays to SPRINKLE next tick)
const KIND_EMPTY:    int = 0
const KIND_SOLID:    int = 1   # base offset
const KIND_BREAKER:  int = 10  # base offset (breaker = 10 + color)
const KIND_STRIKE:   int = 20  # base offset (strike  = 20 + color)
const KIND_SPRINKLE: int = 30
const KIND_SWORD:    int = 40

# Pair orientations. The anchor is piece_a; piece_b is placed relative to it.
#   0 = b above a    (vertical,   b on top)
#   1 = b right of a (horizontal, b on right)
#   2 = b below a    (vertical,   b on bottom)
#   3 = b left of a  (horizontal, b on left)
const ORIENT_COUNT: int = 4

var board: Array = []               # board[y][x]
# Parallel array tracking strike-piece age per cell. 0 for non-strike cells;
# 1..STRIKE_MAX_AGE for strikes (newest = STRIKE_MAX_AGE, oldest = 1).
# Decrements on each pair lock; reaches 0 → strike vanishes.
var strike_age: Array = []          # strike_age[y][x]
var score: int = 0
var chain_multiplier: int = 0       # highest chain length observed this session
var game_over: bool = false

# Difficulty selector (0..10). Sets active drop_interval_ms — see _apply_difficulty.
var difficulty: int = 3
# Number of distinct colors in this game (4 standard, up to 8 in special modes).
var num_colors: int = NUM_COLORS_DEFAULT
# Damage level (0..1) — fraction of the bottom rows pre-seeded with sprinkles
# at game start. See populate_with_damage. Mirrors _damageLevel from
# SwordBoard.populate (SwordBoard.jbc:139-205).
var damage_level: float = 0.0

# Active falling pair.
var active_a_col: int = SPAWN_COL
var active_a_row: int = 0
var active_orient: int = 0
var active_a_piece: int = 0         # encoded cell value
var active_b_piece: int = 0

# Next pair preview (so client can show it).
var next_a_piece: int = 0
var next_b_piece: int = 0

# ─── gravity state ───────────────────────────────────────────────────────────
# Base fall rate: one row per drop_interval_ms. Scales with difficulty.
var drop_interval_ms: int  = DROP_INTERVAL_BASE_MS
var lock_delay_ms:   int   = 500
var _time_since_drop_ms: int = 0
var _time_since_stuck_ms: int = 0
# When true, the active pair can't fall further this frame; we're running
# out the lock-delay grace window until we commit the lock.
var _is_stuck: bool = false
# Soft-drop hold flag — while true, drop_interval is divided by SOFT_DROP_MULTIPLIER.
var _soft_dropping: bool = false

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ─── setup ───────────────────────────────────────────────────────────────────

func seed_board(seed_val: int, difficulty_level: int = 3,
		colors: int = NUM_COLORS_DEFAULT, dmg_level: float = 0.0) -> void:
	rng.seed = seed_val
	difficulty   = clampi(difficulty_level, 0, 10)
	num_colors   = clampi(colors, 2, NUM_COLORS_MAX)
	damage_level = clampf(dmg_level, 0.0, 1.0)
	board = []
	strike_age = []
	for _y in ROWS:
		var row: Array = []
		var ages: Array = []
		for _x in COLS:
			row.append(KIND_EMPTY)
			ages.append(0)
		board.append(row)
		strike_age.append(ages)
	score = 0
	chain_multiplier = 0
	game_over = false
	_apply_difficulty()
	# Pre-seed bottom rows with sprinkles if damage_level > 0. Mirrors
	# SwordBoard.populate(). Useful for "join in progress" or harder starts.
	if damage_level > 0.0:
		populate_with_damage(damage_level)
	# Pre-generate the first pair for the queue…
	next_a_piece = _random_piece()
	next_b_piece = _random_piece()
	# …then spawn it as the active pair and roll a new "next".
	_spawn_pair_from_queue()

func _apply_difficulty() -> void:
	## Linearly scale drop interval with difficulty: diff 0 = 800ms/row,
	## diff 10 = 100ms/row. Mirrors PP's velocity = 0.01 * (difficulty+1).
	var t: float = float(difficulty) / 10.0
	drop_interval_ms = int(lerp(float(DROP_INTERVAL_BASE_MS),
								float(DROP_INTERVAL_MIN_MS), t))

func populate_with_damage(level: float) -> void:
	## Pre-seed bottom rows with sprinkles. Mirrors SwordBoard.populate
	## (SwordBoard.jbc:139-205): pieces = COLS * (ROWS - 4 + 1) * level.
	## Sprinkles fill bottom-up, full rows then a random partial top row.
	var capacity: int = COLS * (ROWS - 4 + 1)
	var to_drop: int = int(capacity * clampf(level, 0.0, 1.0))
	var full_rows: int = to_drop / COLS
	var leftover: int = to_drop - full_rows * COLS
	for r in full_rows:
		var y: int = ROWS - 1 - r
		for x in COLS:
			_set_cell(x, y, KIND_SPRINKLE)
	if leftover > 0:
		var y: int = ROWS - 1 - full_rows
		# Shuffle column order so the partial row is randomized.
		var cols: Array = []
		for c in COLS: cols.append(c)
		cols.shuffle()
		for i in leftover:
			_set_cell(cols[i], y, KIND_SPRINKLE)

func _random_piece() -> int:
	var color: int = rng.randi_range(1, num_colors)
	# ~1 in 4 pieces is a breaker so strikes can actually be shattered.
	var is_breaker: bool = rng.randf() < 0.25
	# SOLID cell value is just the color (1..N); BREAKER is 10+color.
	return (KIND_BREAKER + color) if is_breaker else color

func _spawn_pair_from_queue() -> void:
	active_a_piece = next_a_piece
	active_b_piece = next_b_piece
	next_a_piece = _random_piece()
	next_b_piece = _random_piece()
	active_a_col = SPAWN_COL
	active_a_row = 0
	active_orient = 0  # b-on-top
	_time_since_drop_ms  = 0
	_time_since_stuck_ms = 0
	_is_stuck            = false
	# Game-over check: if the spawn position or the orient-0 b position is
	# already occupied, the player can't place and loses.
	if _cell(active_a_col, active_a_row) != KIND_EMPTY:
		game_over = true

# ─── board inspection helpers ────────────────────────────────────────────────

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < COLS and y >= 0 and y < ROWS

func _cell(x: int, y: int) -> int:
	if not _in_bounds(x, y): return -1
	return board[y][x]

func _set_cell(x: int, y: int, v: int) -> void:
	board[y][x] = v

func _color_of(cell: int) -> int:
	## Returns 1..4 for any colored piece (solid/breaker/strike), 0 otherwise.
	if cell >= KIND_STRIKE and cell < KIND_STRIKE + 10:
		return cell - KIND_STRIKE
	if cell >= KIND_BREAKER and cell < KIND_BREAKER + 10:
		return cell - KIND_BREAKER
	if cell >= KIND_SOLID and cell <= 4:
		return cell
	return 0

func _is_breaker(cell: int) -> bool:
	return cell >= KIND_BREAKER and cell < KIND_BREAKER + 10

func _is_strike(cell: int) -> bool:
	return cell >= KIND_STRIKE and cell < KIND_STRIKE + 10

func _is_solid_like(cell: int) -> bool:
	## Any colored piece that can participate in flood-fill matching.
	return _color_of(cell) > 0

# ─── active pair position math ───────────────────────────────────────────────

func _b_offset(orient: int) -> Vector2i:
	match orient:
		0: return Vector2i(0, -1)   # above
		1: return Vector2i(1, 0)    # right
		2: return Vector2i(0, 1)    # below
		3: return Vector2i(-1, 0)   # left
		_: return Vector2i(0, -1)

func _b_col() -> int: return active_a_col + _b_offset(active_orient).x
func _b_row() -> int: return active_a_row + _b_offset(active_orient).y

func _pair_fits(a_col: int, a_row: int, orient: int) -> bool:
	var b_off := _b_offset(orient)
	var b_col: int = a_col + b_off.x
	var b_row: int = a_row + b_off.y
	# Allow the b-piece to be above the top edge when orient=0 at spawn.
	# We treat rows < 0 as "empty sky" so the pair can start at row 0.
	var a_ok: bool = _in_bounds(a_col, a_row) and board[a_row][a_col] == KIND_EMPTY
	var b_ok: bool
	if b_row < 0:
		b_ok = b_col >= 0 and b_col < COLS
	else:
		b_ok = _in_bounds(b_col, b_row) and board[b_row][b_col] == KIND_EMPTY
	return a_ok and b_ok

# ─── player actions ──────────────────────────────────────────────────────────

func move_pair(delta_col: int) -> bool:
	if game_over: return false
	var new_col: int = active_a_col + delta_col
	if _pair_fits(new_col, active_a_row, active_orient):
		active_a_col = new_col
		_refresh_stuck()
		return true
	return false

func rotate_pair() -> bool:
	## Backward-compat single-direction rotate (CW). Existing tests use this.
	return rotate_pair_cw()

func rotate_pair_cw() -> bool:
	## CW from PP's perspective: VK_DOWN in puzzle/client/v.jbc:271-275.
	return _rotate_pair(1)

func rotate_pair_ccw() -> bool:
	## CCW: VK_UP in puzzle/client/v.jbc:286-290.
	return _rotate_pair(-1)

func _rotate_pair(dir: int) -> bool:
	if game_over: return false
	var new_orient: int = (active_orient + dir + ORIENT_COUNT) % ORIENT_COUNT
	# Try rotation in place; if blocked, try simple wall-kick (shift 1 col).
	if _pair_fits(active_a_col, active_a_row, new_orient):
		active_orient = new_orient
		_refresh_stuck()
		return true
	for kick in [-1, 1]:
		if _pair_fits(active_a_col + kick, active_a_row, new_orient):
			active_a_col += kick
			active_orient = new_orient
			_refresh_stuck()
			return true
	return false

func set_soft_dropping(active: bool) -> void:
	## Toggle the soft-drop hold. While true, the next tick will use the
	## reduced interval (drop_interval / SOFT_DROP_MULTIPLIER).
	_soft_dropping = active

func _refresh_stuck() -> void:
	## Called after a successful move/rotate. If the new position can fall
	## again, clear the stuck flag so lock-delay resets — this is the classic
	## "tuck" maneuver (slide under an overhang at the last second).
	if _pair_fits(active_a_col, active_a_row + 1, active_orient):
		_is_stuck = false
		_time_since_stuck_ms = 0

func drop_pair() -> Dictionary:
	## Hard-drop: slam the pair to its final resting position and lock it.
	## Returns a summary { shattered, strikes_broken, swords_made, chain,
	##                     delta_score, game_over, locked }.
	if game_over:
		return _empty_summary(true)
	# Find the deepest row where both pieces still fit.
	var final_row: int = active_a_row
	while _pair_fits(active_a_col, final_row + 1, active_orient):
		final_row += 1
	active_a_row = final_row
	return _lock_and_resolve()

func soft_drop_pair() -> Dictionary:
	## Drop the pair down by exactly one row. If it can't fall (already
	## resting on something), lock it immediately. Returns the same summary
	## shape as drop_pair; `locked` indicates whether this call ended the
	## active pair.
	if game_over:
		return _empty_summary(true)
	if _pair_fits(active_a_col, active_a_row + 1, active_orient):
		active_a_row += 1
		# Reset the gravity tick clock so the next auto-drop happens a full
		# interval from now — feels right when the player is hammering S.
		_time_since_drop_ms = 0
		var s := _empty_summary(false)
		s["dropped"] = true
		return s
	# Can't fall: commit the lock now (no waiting for lock-delay).
	return _lock_and_resolve()

func tick(delta_ms: int) -> Dictionary:
	## Server-side gravity tick. Call this every frame on the server with the
	## elapsed milliseconds since the last call. Returns a summary;
	## summary.changed is true whenever the visible state moved (pair fell,
	## locked, or game ended), so callers can throttle their network sends.
	var summary: Dictionary = _empty_summary(false)
	summary["changed"] = false
	if game_over:
		return summary
	# Decide whether the pair can still fall.
	if _pair_fits(active_a_col, active_a_row + 1, active_orient):
		_is_stuck = false
		_time_since_stuck_ms = 0
		_time_since_drop_ms += delta_ms
		var effective_interval: int = drop_interval_ms
		if _soft_dropping:
			effective_interval = max(1, drop_interval_ms / SOFT_DROP_MULTIPLIER)
		if _time_since_drop_ms >= effective_interval:
			active_a_row += 1
			_time_since_drop_ms = 0
			summary["dropped"] = true
			summary["changed"] = true
		return summary
	# Pair is stuck — run out the lock-delay grace window.
	_is_stuck = true
	_time_since_stuck_ms += delta_ms
	if _time_since_stuck_ms >= lock_delay_ms:
		var lock_summary: Dictionary = _lock_and_resolve()
		lock_summary["changed"] = true
		return lock_summary
	return summary

func _empty_summary(go: bool) -> Dictionary:
	return {
		"shattered":      0,
		"strikes_broken": 0,
		"swords_made":    0,
		"chain":          0,
		"delta_score":    0,
		"game_over":      go,
		"locked":         false,
		"dropped":        false,
		"changed":        false,
	}

func _lock_and_resolve() -> Dictionary:
	## Place the active pair at its current position, run gravity / fusion /
	## shatter chain, then age strikes (decaying expired ones) and spawn the
	## next pair (or game-over).
	var summary: Dictionary = _empty_summary(false)
	# Place both pieces. b might still be above the top edge if a is at row 0
	# — that's a near-death scenario; still lock a.
	var b_off := _b_offset(active_orient)
	var b_col: int = active_a_col + b_off.x
	var b_row: int = active_a_row + b_off.y
	if _in_bounds(active_a_col, active_a_row):
		_set_cell(active_a_col, active_a_row, active_a_piece)
	if _in_bounds(b_col, b_row):
		_set_cell(b_col, b_row, active_b_piece)
	_apply_gravity_all()
	_fuse_strikes()
	var pre_score: int = score
	var chain_stats: Dictionary = _resolve_shatter_chain()
	summary["shattered"]      = chain_stats["shattered"]
	summary["strikes_broken"] = chain_stats["strikes_broken"]
	summary["swords_made"]    = chain_stats["swords_made"]
	summary["chain"]          = chain_stats["chain"]
	summary["delta_score"]    = score - pre_score
	# Age strikes (one tick of life consumed per pair lock). Strikes at age 1
	# decay to empty; strikes at age 0 are non-strike cells and are skipped.
	# This is the bytecode 256→384→512→0 progression.
	_age_strikes()
	_decay_blocks()
	_spawn_pair_from_queue()
	summary["game_over"] = game_over
	summary["locked"]    = true
	summary["changed"]   = true
	return summary

func _age_strikes() -> void:
	for y in ROWS:
		for x in COLS:
			if not _is_strike(board[y][x]): continue
			strike_age[y][x] -= 1
			if strike_age[y][x] <= 0:
				_set_cell(x, y, KIND_EMPTY)
				strike_age[y][x] = 0
	# Decayed strikes leave holes — let things above them fall in.
	_apply_gravity_all()

# ─── resolution: strikes → shatter → chain → decay ───────────────────────────

func _fuse_strikes() -> void:
	## Any rectangle of same-color SOLIDs that is at least 2×2 becomes STRIKEs.
	## We mark a boolean grid of "in a strike rect", then convert in-place.
	var mark: Array = []
	for _y in ROWS:
		var row: Array = []
		for _x in COLS:
			row.append(false)
		mark.append(row)
	for y in range(ROWS - 1):
		for x in range(COLS - 1):
			var c: int = _color_of(board[y][x])
			if c == 0: continue
			# STRIKE pieces are already fused; don't re-fuse them.
			if _is_strike(board[y][x]) or _is_breaker(board[y][x]): continue
			# Find the largest rectangle extending right+down with the same color
			# and no breakers/strikes inside.
			var max_r: int = x
			while max_r + 1 < COLS and _color_of(board[y][max_r + 1]) == c \
					and not _is_breaker(board[y][max_r + 1]) \
					and not _is_strike(board[y][max_r + 1]):
				max_r += 1
			var max_b: int = y
			var keep_going: bool = true
			while keep_going and max_b + 1 < ROWS:
				for col in range(x, max_r + 1):
					var cell: int = board[max_b + 1][col]
					if _color_of(cell) != c or _is_breaker(cell) or _is_strike(cell):
						keep_going = false
						break
				if keep_going:
					max_b += 1
			if max_r - x >= 1 and max_b - y >= 1:
				for yy in range(y, max_b + 1):
					for xx in range(x, max_r + 1):
						mark[yy][xx] = true
	for y in ROWS:
		for x in COLS:
			if mark[y][x] and not _is_strike(board[y][x]):
				var c: int = _color_of(board[y][x])
				_set_cell(x, y, KIND_STRIKE + c)
				strike_age[y][x] = STRIKE_MAX_AGE

func _resolve_shatter_chain() -> Dictionary:
	## Keep resolving until no breaker has a same-color neighbor to clear.
	## Each pass counts as one chain link; chain multiplier = nth link × n.
	var total_shattered: int = 0
	var total_strikes: int   = 0
	var total_swords: int    = 0
	var chain: int = 0
	while true:
		var targets: Array = []    # array of Vector2i cells to clear this pass
		var breakers_visited: Dictionary = {}
		for y in ROWS:
			for x in COLS:
				var cell: int = board[y][x]
				if not _is_breaker(cell): continue
				var c: int = _color_of(cell)
				# Flood-fill from this breaker across same-color pieces.
				var to_visit: Array = [Vector2i(x, y)]
				var visited: Dictionary = {}
				var any_neighbor: bool = false
				while not to_visit.is_empty():
					var p: Vector2i = to_visit.pop_back()
					var key := "%d,%d" % [p.x, p.y]
					if visited.has(key): continue
					visited[key] = true
					for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
						var n: Vector2i = p + (d as Vector2i)
						if not _in_bounds(n.x, n.y): continue
						var nc: int = board[n.y][n.x]
						if _color_of(nc) != c: continue
						any_neighbor = true
						if not visited.has("%d,%d" % [n.x, n.y]):
							to_visit.push_back(n)
				if any_neighbor:
					for key in visited:
						var parts: PackedStringArray = key.split(",")
						var px: int = int(parts[0])
						var py: int = int(parts[1])
						targets.append(Vector2i(px, py))
						if _is_breaker(board[py][px]):
							breakers_visited[key] = true
		# De-duplicate targets.
		var uniq: Dictionary = {}
		for t in targets:
			uniq["%d,%d" % [t.x, t.y]] = t
		if uniq.is_empty():
			break
		chain += 1
		var pass_shattered: int = 0
		var pass_strikes: int   = 0
		var pass_swords: int    = 0
		for key in uniq:
			var p: Vector2i = uniq[key]
			var cell: int = board[p.y][p.x]
			if _is_strike(cell):
				pass_strikes += 1
				pass_swords  += 1  # broken strike => 1 sword
				# yppedia: swords replace the cleared strike position with
				# an immovable sword. Clear strike_age — it's no longer a strike.
				_set_cell(p.x, p.y, KIND_SWORD)
				strike_age[p.y][p.x] = 0
			else:
				pass_shattered += 1
				_set_cell(p.x, p.y, KIND_EMPTY)
		# Sprinkle volley: tiered by total shattered this chain link.
		# (sword/data/c.jbc:8-24 — `f` array)
		var sprinkles: int = 0
		var sprinkle_tier: int = _classify_tier(pass_shattered, SPRINKLE_TIER_THRESHOLDS)
		if sprinkle_tier >= 0:
			sprinkles = SPRINKLE_TIER_COUNTS[sprinkle_tier]
		_drop_sprinkles(sprinkles)
		# Strike size bonus: bigger strikes pay more.
		# (sword/data/c.jbc:25-44 — `g` array, 4 thresholds → 4 bonus tiers)
		var strike_bonus_per: int = 5  # base for any strike, no-tier qualifying
		var strike_tier: int = _classify_tier(pass_strikes, STRIKE_TIER_THRESHOLDS)
		if strike_tier >= 0:
			strike_bonus_per = [10, 18, 30, 50][strike_tier]
		# Scoring: per-piece points × chain multiplier.
		var delta: int = (pass_shattered * 1
				+ pass_strikes * strike_bonus_per
				+ pass_swords  * 20) * chain
		score += delta
		total_shattered += pass_shattered
		total_strikes   += pass_strikes
		total_swords    += pass_swords
		# Apply gravity before scanning the next chain link.
		_apply_gravity_all()
		# Re-fuse strikes that may have formed after gravity.
		_fuse_strikes()
	if chain > chain_multiplier:
		chain_multiplier = chain
	return {
		"shattered":      total_shattered,
		"strikes_broken": total_strikes,
		"swords_made":    total_swords,
		"chain":          chain,
	}

func _classify_tier(value: int, thresholds: Array) -> int:
	## Returns the highest index i where value >= thresholds[i].
	## Returns -1 if value is below thresholds[0]. Caller handles the
	## "no qualifying tier" case explicitly. Examples:
	##   value=23, thresholds=[24,28,34,38] → -1 (under floor)
	##   value=24, same                       → 0 (just qualified)
	##   value=38, same                       → 3 (top tier)
	##   value=0,  thresholds=[0,4,12]        → 0
	##   value=12, same                       → 2
	var tier: int = -1
	for i in range(thresholds.size()):
		if value >= thresholds[i]:
			tier = i
	return tier

func _drop_sprinkles(count: int) -> void:
	## Drop `count` gray sprinkles at the top of random columns.
	## They fall to rest with gravity (called by caller).
	for _i in count:
		var tries: int = 0
		while tries < 8:
			var col: int = rng.randi_range(0, COLS - 1)
			if board[0][col] == KIND_EMPTY:
				_set_cell(col, 0, KIND_SPRINKLE)
				break
			tries += 1
	_apply_gravity_all()

func _decay_blocks() -> void:
	## Swords placed this turn persist to the next; sprinkles from a PRIOR
	## resolution are eligible to decay now. Since we lump them together
	## simply: swords → sprinkles each turn. Sprinkles stay (they're the
	## yppedia "permanent" gray blocks).
	for y in ROWS:
		for x in COLS:
			if board[y][x] == KIND_SWORD:
				_set_cell(x, y, KIND_SPRINKLE)

func _apply_gravity_all() -> void:
	for x in COLS:
		var write_y: int = ROWS - 1
		for y in range(ROWS - 1, -1, -1):
			if board[y][x] != KIND_EMPTY:
				var v: int = board[y][x]
				board[y][x] = KIND_EMPTY
				board[write_y][x] = v
				write_y -= 1

# ─── serialization ───────────────────────────────────────────────────────────

func export_state() -> Dictionary:
	var out_board: Array = []
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			row.append(board[y][x])
		out_board.append(row)
	# Pack strike_age into a parallel 2D array so the client can render the
	# decay state visually (newer strikes brighter, age-1 strikes dim/red).
	var out_ages: Array = []
	for y in ROWS:
		var ages: Array = []
		for x in COLS:
			ages.append(strike_age[y][x])
		out_ages.append(ages)
	return {
		"board":       out_board,
		"strike_age":  out_ages,
		"score":       score,
		"chain":       chain_multiplier,
		"game_over":   game_over,
		"active_col":  active_a_col,
		"active_row":  active_a_row,
		"orient":      active_orient,
		"active_a":    active_a_piece,
		"active_b":    active_b_piece,
		"next_a":      next_a_piece,
		"next_b":      next_b_piece,
		"stuck":       _is_stuck,
		"drop_ms":     drop_interval_ms,
		"difficulty":  difficulty,
		"num_colors":  num_colors,
		"soft":        _soft_dropping,
	}
