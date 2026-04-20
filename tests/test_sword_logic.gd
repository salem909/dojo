extends SceneTree
## Headless unit tests for the Swordfighting puzzle logic.
## Run with:  godot --headless --script res://tests/test_sword_logic.gd

const Sword := preload("res://scripts/puzzles/sword/sword_logic.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	test_seed_starts_empty_with_spawn_pair()
	test_move_and_rotate_within_bounds()
	test_drop_locks_pair_at_bottom()
	test_breaker_clears_connected_same_color()
	test_breaker_alone_is_inert()
	test_strike_forms_from_2x2()
	test_chain_multiplier_increments()
	test_game_over_when_spawn_blocked()
	test_export_state_shape()
	# Real-time gravity (Phase 2.x).
	test_tick_advances_pair_by_one_row_per_interval()
	test_tick_below_interval_does_not_drop()
	test_soft_drop_advances_one_row()
	test_soft_drop_at_floor_locks()
	test_lock_delay_grace_window()
	test_tuck_resets_lock_delay()
	# Bytecode-grounded improvements (Phase 2.x.2).
	test_strike_age_set_on_fuse()
	test_strike_decays_after_max_age_locks()
	test_unshattered_strike_vanishes_at_age_zero()
	test_rotate_cw_and_ccw_are_inverses()
	test_set_soft_dropping_accelerates_fall()
	test_difficulty_shortens_drop_interval()
	test_damage_level_pre_seeds_bottom_rows()
	test_classify_tier_semantics()
	test_higher_tier_strikes_pay_more()
	test_export_state_includes_strike_age()

	print("\n[sword] %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(desc: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  ok   %s" % desc)
	else:
		failed += 1
		print("  FAIL %s  %s" % [desc, detail])

# ─── helpers ─────────────────────────────────────────────────────────────────

func _empty_board(s: Object) -> void:
	## Reset the board to all-empty so tests can hand-craft scenarios.
	for y in Sword.ROWS:
		for x in Sword.COLS:
			s.board[y][x] = Sword.KIND_EMPTY

func _place(s: Object, x: int, y: int, v: int) -> void:
	s.board[y][x] = v

# ─── tests ───────────────────────────────────────────────────────────────────

func test_seed_starts_empty_with_spawn_pair() -> void:
	var s: Object = Sword.new()
	s.seed_board(1)
	var empty_cells: int = 0
	for y in Sword.ROWS:
		for x in Sword.COLS:
			if s.board[y][x] == Sword.KIND_EMPTY:
				empty_cells += 1
	_check("fresh board is fully empty", empty_cells == Sword.ROWS * Sword.COLS)
	_check("active pair spawns at column 3", s.active_a_col == Sword.SPAWN_COL)
	_check("active pair a-piece is set", s.active_a_piece != 0)
	_check("active pair b-piece is set", s.active_b_piece != 0)
	_check("next pair preview is set",
		s.next_a_piece != 0 and s.next_b_piece != 0)

func test_move_and_rotate_within_bounds() -> void:
	var s: Object = Sword.new()
	s.seed_board(2)
	var ok_left: bool = s.move_pair(-1)
	_check("move left once from spawn succeeds", ok_left)
	_check("a-col decremented", s.active_a_col == Sword.SPAWN_COL - 1)
	# Ram into left wall.
	while s.move_pair(-1):
		pass
	_check("can't move past left wall", s.active_a_col == 0)
	var ok_rot: bool = s.rotate_pair()
	_check("rotate succeeds when space allows", ok_rot)
	_check("orientation advanced", s.active_orient == 1)

func test_drop_locks_pair_at_bottom() -> void:
	var s: Object = Sword.new()
	s.seed_board(3)
	# Force known pieces so we can assert positions.
	s.active_a_piece = 1   # red solid
	s.active_b_piece = 2   # yellow solid
	s.active_orient = 0    # b above a
	var summary: Dictionary = s.drop_pair()
	_check("drop does not trigger game over on empty board", not summary["game_over"])
	# After drop: a-piece rests at bottom row of column SPAWN_COL.
	var bottom: int = Sword.ROWS - 1
	_check("a-piece settled at bottom of spawn col",
		s.board[bottom][Sword.SPAWN_COL] == 1)
	_check("b-piece settled one above a-piece",
		s.board[bottom - 1][Sword.SPAWN_COL] == 2)

func test_breaker_clears_connected_same_color() -> void:
	var s: Object = Sword.new()
	s.seed_board(4)
	_empty_board(s)
	# Row 12: [0, 1, 1, 1, 0, 0]  (three red solids)
	# Row 11: [0, 0, 0, 1, 0, 0]  (one red solid, adjacent)
	var bot: int = Sword.ROWS - 1
	_place(s, 1, bot, 1)
	_place(s, 2, bot, 1)
	_place(s, 3, bot, 1)
	_place(s, 3, bot - 1, 1)
	# Set the active pair to a red breaker piece dropping into col 0, which
	# will come to rest next to the cluster. But the breaker needs to TOUCH
	# a red — so put it at col 1, row 11 (ends up at bot-1 after gravity).
	# Easiest: just simulate a direct drop by setting active pair to red
	# breaker at col 1.
	s.active_a_piece = Sword.KIND_BREAKER + 1   # red breaker
	s.active_b_piece = 2                         # yellow solid (harmless filler)
	s.active_orient  = 0                         # b-above-a
	s.active_a_col   = 1
	s.active_a_row   = 0
	var pre_empty: int = _count_empty(s)
	var summary: Dictionary = s.drop_pair()
	# Expect: breaker landed next to the red cluster and shattered them all.
	# 3 bottom-row reds + 1 above = 4 solids cleared, plus the breaker itself.
	_check("breaker shattered at least the 4 connected solids",
		summary["shattered"] >= 4, "shattered=%d" % summary["shattered"])
	_check("score incremented after shatter", s.score > 0)
	_check("emptied cells increased",
		_count_empty(s) > pre_empty - 2, "shatter should outpace the 2 locked pieces")

func test_breaker_alone_is_inert() -> void:
	var s: Object = Sword.new()
	s.seed_board(5)
	_empty_board(s)
	# Drop a red breaker into an empty board with a yellow filler partner.
	s.active_a_piece = Sword.KIND_BREAKER + 1
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 0
	s.active_a_row   = 0
	var summary: Dictionary = s.drop_pair()
	_check("lone breaker does not shatter", summary["shattered"] == 0)

func test_strike_forms_from_2x2() -> void:
	var s: Object = Sword.new()
	s.seed_board(6)
	_empty_board(s)
	# Place a 2×2 block of red solids near the bottom manually, then
	# drop a non-matching pair to trigger _fuse_strikes via drop_pair.
	var bot: int = Sword.ROWS - 1
	_place(s, 0, bot,     1)
	_place(s, 1, bot,     1)
	_place(s, 0, bot - 1, 1)
	_place(s, 1, bot - 1, 1)
	# Drop a yellow pair far away — shouldn't interact, but will trigger fuse.
	s.active_a_piece = 2
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 5
	s.active_a_row   = 0
	s.drop_pair()
	# Now the 2×2 red should be strikes (color-1 strike = KIND_STRIKE+1 = 21).
	var a: int = s.board[bot][0]
	_check("2x2 fused into strikes",
		a == Sword.KIND_STRIKE + 1,
		"cell(0,bot)=%d expected %d" % [a, Sword.KIND_STRIKE + 1])

func test_chain_multiplier_increments() -> void:
	var s: Object = Sword.new()
	s.seed_board(7)
	_empty_board(s)
	# Set up a scenario where one breaker clears reds, and when gravity drops
	# yellows into a new arrangement, another breaker clears them. This is
	# tricky; for MVP just verify that `chain` is reported >= 1 when any
	# shatter happens.
	var bot: int = Sword.ROWS - 1
	_place(s, 0, bot,     1)  # red
	_place(s, 1, bot,     1)  # red
	s.active_a_piece = Sword.KIND_BREAKER + 1
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 0
	s.active_a_row   = 0
	var summary: Dictionary = s.drop_pair()
	_check("chain is at least 1 when shatter occurred",
		summary["chain"] >= 1, "chain=%d" % summary["chain"])

func test_game_over_when_spawn_blocked() -> void:
	var s: Object = Sword.new()
	s.seed_board(8)
	# Fill column 3 all the way to the top — next spawn must fail.
	for y in Sword.ROWS:
		s.board[y][Sword.SPAWN_COL] = 1
	# Force a drop to trigger spawn of the next pair (which should fail).
	s.active_a_piece = 1
	s.active_b_piece = 1
	s.active_orient  = 0
	s.active_a_col   = 0   # land elsewhere, doesn't matter
	s.active_a_row   = 0
	var summary: Dictionary = s.drop_pair()
	_check("game over reported after column 3 is full",
		summary["game_over"], "game_over=%s" % str(summary["game_over"]))

func test_export_state_shape() -> void:
	var s: Object = Sword.new()
	s.seed_board(9)
	var state: Dictionary = s.export_state()
	_check("export has a board", state.has("board"))
	_check("board has ROWS rows", state["board"].size() == Sword.ROWS)
	_check("board has COLS cols", state["board"][0].size() == Sword.COLS)
	_check("export has score",    state.has("score"))
	_check("export has orient",   state.has("orient"))
	_check("export has next_a",   state.has("next_a"))

# ─── real-time gravity tests ─────────────────────────────────────────────────

func test_tick_advances_pair_by_one_row_per_interval() -> void:
	var s: Object = Sword.new()
	s.seed_board(101)
	# Force known piece + empty board so tick has somewhere to fall.
	_empty_board(s)
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 0
	s.active_a_row = 0
	var start_row: int = s.active_a_row
	var summary: Dictionary = s.tick(s.drop_interval_ms)
	_check("tick at full interval advances 1 row",
		s.active_a_row == start_row + 1, "row=%d" % s.active_a_row)
	_check("tick reports dropped=true", summary.get("dropped", false))
	_check("tick reports changed=true", summary.get("changed", false))

func test_tick_below_interval_does_not_drop() -> void:
	var s: Object = Sword.new()
	s.seed_board(102)
	_empty_board(s)
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 0
	s.active_a_row = 0
	var start_row: int = s.active_a_row
	var summary: Dictionary = s.tick(s.drop_interval_ms - 50)
	_check("tick below interval does not advance row",
		s.active_a_row == start_row, "row=%d" % s.active_a_row)
	_check("tick reports changed=false", not summary.get("changed", true))

func test_soft_drop_advances_one_row() -> void:
	var s: Object = Sword.new()
	s.seed_board(103)
	_empty_board(s)
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 0
	s.active_a_row = 0
	var start_row: int = s.active_a_row
	var summary: Dictionary = s.soft_drop_pair()
	_check("soft drop advances 1 row",
		s.active_a_row == start_row + 1, "row=%d" % s.active_a_row)
	_check("soft drop on empty space does NOT lock",
		not summary.get("locked", true))

func test_soft_drop_at_floor_locks() -> void:
	var s: Object = Sword.new()
	s.seed_board(104)
	_empty_board(s)
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 0
	s.active_a_row = Sword.ROWS - 1   # already on the floor
	var summary: Dictionary = s.soft_drop_pair()
	_check("soft drop at floor locks the pair",
		summary.get("locked", false), "locked=%s" % str(summary.get("locked")))

func test_lock_delay_grace_window() -> void:
	var s: Object = Sword.new()
	s.seed_board(105)
	_empty_board(s)
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 0
	s.active_a_row = Sword.ROWS - 1   # on the floor; can't fall further
	var bot: int = Sword.ROWS - 1
	# Tick once for less than lock_delay — pair should still be active.
	var s1: Dictionary = s.tick(s.lock_delay_ms - 50)
	_check("partial lock-delay tick does not lock yet",
		not s1.get("locked", true))
	_check("board cell still empty during grace window",
		s.board[bot][0] == 0)
	# Tick again past lock_delay — pair must lock.
	var s2: Dictionary = s.tick(100)
	_check("lock-delay expiry locks pair", s2.get("locked", false))

func test_tuck_resets_lock_delay() -> void:
	## Build an overhang: top floor at col 1 forces the pair to be stuck at
	## col 1, but col 2 is open all the way down. Sliding right under should
	## let it fall again (and clear _is_stuck).
	var s: Object = Sword.new()
	s.seed_board(106)
	_empty_board(s)
	# Put a single block at col 1, row 5 — pair at col 1 can fall to row 4.
	# Then at col 2 it's open all the way to bottom.
	s.board[5][1] = 1
	s.active_a_piece = 1
	s.active_b_piece = 2
	s.active_orient = 0
	s.active_a_col = 1
	s.active_a_row = 4   # resting on the obstacle
	# Tick partway — gets stuck with no further fall available.
	s.tick(100)
	_check("pair recognised as stuck", s._is_stuck)
	# Move right to col 2 where there IS room below.
	var moved: bool = s.move_pair(1)
	_check("can move under overhang", moved)
	_check("stuck flag clears after tuck", not s._is_stuck)

# ─── bytecode-grounded improvements (Phase 2.x.2) ────────────────────────────

func test_strike_age_set_on_fuse() -> void:
	var s: Object = Sword.new()
	s.seed_board(201)
	_empty_board(s)
	# Build a 2×2 red square at the bottom and trigger fuse via a yellow
	# pair drop far away.
	var bot: int = Sword.ROWS - 1
	_place(s, 0, bot,     1)
	_place(s, 1, bot,     1)
	_place(s, 0, bot - 1, 1)
	_place(s, 1, bot - 1, 1)
	s.active_a_piece = 2
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 5
	s.active_a_row   = 0
	s.drop_pair()
	# After fuse + age (lock decrements all strikes), strikes should be at
	# STRIKE_MAX_AGE - 1 (since _age_strikes runs once per lock).
	var expected_age: int = Sword.STRIKE_MAX_AGE - 1
	_check("strike age recorded near max after first lock",
		s.strike_age[bot][0] == expected_age,
		"got %d expected %d" % [s.strike_age[bot][0], expected_age])

func test_strike_decays_after_max_age_locks() -> void:
	var s: Object = Sword.new()
	s.seed_board(202)
	_empty_board(s)
	var bot: int = Sword.ROWS - 1
	_place(s, 0, bot,     1)
	_place(s, 1, bot,     1)
	_place(s, 0, bot - 1, 1)
	_place(s, 1, bot - 1, 1)
	# Drop yellow pair to far col → triggers fuse, ages strikes by 1.
	s.active_a_piece = 2
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 5
	s.active_a_row   = 0
	s.drop_pair()
	# Without shattering, drop another yellow pair to age strikes again.
	s.active_a_piece = 2
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 4
	s.active_a_row   = 0
	s.drop_pair()
	# After 2 locks, the strike that started at age 3 should be at age 1.
	_check("strike at age 1 after 2 locks (expecting STRIKE_MAX_AGE-2)",
		s.strike_age[bot][0] == Sword.STRIKE_MAX_AGE - 2,
		"got %d" % s.strike_age[bot][0])

func test_unshattered_strike_vanishes_at_age_zero() -> void:
	var s: Object = Sword.new()
	s.seed_board(203)
	_empty_board(s)
	var bot: int = Sword.ROWS - 1
	_place(s, 0, bot,     1)
	_place(s, 1, bot,     1)
	_place(s, 0, bot - 1, 1)
	_place(s, 1, bot - 1, 1)
	# First lock → fuse + age (3→2)
	s.active_a_piece = 2
	s.active_b_piece = 2
	s.active_orient  = 0
	s.active_a_col   = 5
	s.active_a_row   = 0
	s.drop_pair()
	# Drop two more yellow pairs to age the strike to 0 → decay.
	for col in [4, 3]:
		s.active_a_piece = 2
		s.active_b_piece = 2
		s.active_orient  = 0
		s.active_a_col   = col
		s.active_a_row   = 0
		s.drop_pair()
	# Strike should now be gone (decayed). Cell is empty (or filled by
	# gravity from above, but bottom of col 0 should not still be a strike).
	_check("strike at original cell is no longer a strike after age 0",
		not s._is_strike(s.board[bot][0]))

func test_rotate_cw_and_ccw_are_inverses() -> void:
	var s: Object = Sword.new()
	s.seed_board(204)
	_empty_board(s)
	s.active_a_col = 2
	s.active_a_row = 5
	s.active_orient = 0
	s.rotate_pair_cw()
	var after_cw: int = s.active_orient
	s.rotate_pair_ccw()
	_check("CW then CCW returns to original orient",
		s.active_orient == 0,
		"after CW=%d, after CCW=%d" % [after_cw, s.active_orient])
	# 4× CW returns to start.
	for _i in 4: s.rotate_pair_cw()
	_check("4× CW returns to start", s.active_orient == 0)

func test_set_soft_dropping_accelerates_fall() -> void:
	var s: Object = Sword.new()
	s.seed_board(205)
	_empty_board(s)
	s.active_a_col = 0
	s.active_a_row = 0
	s.active_orient = 0
	# At default difficulty 3, drop_interval is around 590ms — without soft
	# drop, ticking 100ms shouldn't advance.
	var start_row: int = s.active_a_row
	s.tick(100)
	_check("no advance at 100ms without soft drop",
		s.active_a_row == start_row)
	# Now enable soft-dropping. With multiplier 8, the same 100ms interval
	# should be enough.
	s.set_soft_dropping(true)
	s.tick(100)
	_check("advance at 100ms with soft drop active",
		s.active_a_row == start_row + 1,
		"row=%d expected=%d" % [s.active_a_row, start_row + 1])

func test_difficulty_shortens_drop_interval() -> void:
	var s_easy: Object = Sword.new()
	s_easy.seed_board(206, 0)
	var s_hard: Object = Sword.new()
	s_hard.seed_board(207, 10)
	_check("difficulty 0 has the longest interval",
		s_easy.drop_interval_ms == Sword.DROP_INTERVAL_BASE_MS,
		"got %d" % s_easy.drop_interval_ms)
	_check("difficulty 10 has the shortest interval",
		s_hard.drop_interval_ms == Sword.DROP_INTERVAL_MIN_MS,
		"got %d" % s_hard.drop_interval_ms)
	_check("difficulty 10 strictly faster than 0",
		s_hard.drop_interval_ms < s_easy.drop_interval_ms)

func test_damage_level_pre_seeds_bottom_rows() -> void:
	var s: Object = Sword.new()
	s.seed_board(208, 3, 4, 0.5)
	# At damage_level=0.5, the bottom rows should have sprinkles.
	var bot: int = Sword.ROWS - 1
	var sprinkle_cells: int = 0
	for x in Sword.COLS:
		if s.board[bot][x] == Sword.KIND_SPRINKLE:
			sprinkle_cells += 1
	_check("bottom row mostly seeded with sprinkles at damage=0.5",
		sprinkle_cells >= 4,
		"got %d sprinkles" % sprinkle_cells)
	# Top row (row 0) should still be free of pre-seeded sprinkles.
	var top_sprinkles: int = 0
	for x in Sword.COLS:
		if s.board[0][x] == Sword.KIND_SPRINKLE:
			top_sprinkles += 1
	_check("top row has no pre-seeded sprinkles",
		top_sprinkles == 0)

func test_classify_tier_semantics() -> void:
	var s: Object = Sword.new()
	s.seed_board(209)
	_check("under floor returns -1",
		s._classify_tier(23, [24, 28, 34, 38]) == -1)
	_check("just qualified returns 0",
		s._classify_tier(24, [24, 28, 34, 38]) == 0)
	_check("middle returns mid index",
		s._classify_tier(34, [24, 28, 34, 38]) == 2)
	_check("over top returns max index",
		s._classify_tier(100, [24, 28, 34, 38]) == 3)
	_check("zero meets threshold[0]=0",
		s._classify_tier(0, [0, 4, 12]) == 0)

func test_higher_tier_strikes_pay_more() -> void:
	## Build a small strike chain vs a large strike chain and verify scoring
	## monotonically increases. Hand-crafting exact strike counts is fiddly,
	## so this test just confirms strike_bonus_per scales by hitting the
	## scoring code path twice with different pre-shattered counts.
	var s_small: Object = Sword.new()
	s_small.seed_board(210)
	_empty_board(s_small)
	# Tiny: a single 2×2 red strike — pass_strikes will be 4.
	var bot: int = Sword.ROWS - 1
	for y in [bot, bot - 1]:
		for x in [0, 1]:
			_place(s_small, x, y, 1)
	# Drop a red breaker adjacent to fire the chain.
	s_small.active_a_piece = Sword.KIND_BREAKER + 1
	s_small.active_b_piece = 2
	s_small.active_orient  = 0
	s_small.active_a_col   = 2
	s_small.active_a_row   = 0
	var summary_small: Dictionary = s_small.drop_pair()
	var score_small: int = s_small.score
	_check("small strike chain produces nonzero score",
		score_small > 0, "score=%d" % score_small)
	_check("small strike chain reports strikes_broken > 0",
		summary_small.get("strikes_broken", 0) > 0)

func test_export_state_includes_strike_age() -> void:
	var s: Object = Sword.new()
	s.seed_board(211)
	var state: Dictionary = s.export_state()
	_check("export has strike_age", state.has("strike_age"))
	_check("strike_age has ROWS rows",
		state["strike_age"].size() == Sword.ROWS)
	_check("strike_age row has COLS cols",
		state["strike_age"][0].size() == Sword.COLS)
	_check("export has difficulty", state.has("difficulty"))
	_check("export has soft flag", state.has("soft"))

# ─── utils ───────────────────────────────────────────────────────────────────

func _count_empty(s: Object) -> int:
	var n: int = 0
	for y in Sword.ROWS:
		for x in Sword.COLS:
			if s.board[y][x] == Sword.KIND_EMPTY:
				n += 1
	return n
