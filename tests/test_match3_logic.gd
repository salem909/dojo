extends SceneTree
## Headless unit tests for the match-3 puzzle logic.
## Run with:  godot --headless --script res://tests/test_match3_logic.gd

const Match3 := preload("res://scripts/puzzles/match3/match3_logic.gd")

var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	test_seed_board_no_initial_matches()
	test_invalid_swap_returns_zero()
	test_in_bounds_and_adjacent()
	test_swap_creates_match_clears_and_scores()
	test_export_board_shape()

	print("\n[match3] %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  ok   %s" % name)
	else:
		failed += 1
		print("  FAIL %s  %s" % [name, detail])

func test_seed_board_no_initial_matches() -> void:
	var m: Object = Match3.new()
	m.seed_board(12345)
	# After seed_board, _resolve_matches has run until clean.
	# Calling _find_matches should return all-false.
	var marks: Array = m._find_matches()
	var any_marked := false
	for row in marks:
		for v in row:
			if v: any_marked = true
	_check("seed_board leaves no immediate matches", not any_marked)

func test_invalid_swap_returns_zero() -> void:
	var m: Object = Match3.new()
	m.seed_board(7)
	# Swap two non-adjacent cells.
	var n: int = m.try_swap(Vector2i(0, 0), Vector2i(3, 3))
	_check("non-adjacent swap returns 0", n == 0)
	# Out-of-bounds swap.
	var n2: int = m.try_swap(Vector2i(-1, 0), Vector2i(0, 0))
	_check("out-of-bounds swap returns 0", n2 == 0)

func test_in_bounds_and_adjacent() -> void:
	var m: Object = Match3.new()
	m.seed_board(1)
	_check("in_bounds(0,0)", m.in_bounds(Vector2i(0, 0)))
	_check("not in_bounds(6,0)", not m.in_bounds(Vector2i(6, 0)))
	_check("adjacent (0,0)-(1,0)", m.is_adjacent(Vector2i(0, 0), Vector2i(1, 0)))
	_check("not adjacent (0,0)-(2,0)", not m.is_adjacent(Vector2i(0, 0), Vector2i(2, 0)))

func test_swap_creates_match_clears_and_scores() -> void:
	# Hand-craft a board where swapping two cells creates a clear horizontal 3-match.
	var m: Object = Match3.new()
	m.rng.seed = 42
	m.board = []
	for _y in Match3.ROWS:
		var row: Array = []
		for _x in Match3.COLS:
			row.append(1)  # all red, then we'll punch holes
		m.board.append(row)
	# Make a board with no matches: alternate colors row-by-row.
	for y in Match3.ROWS:
		for x in Match3.COLS:
			m.board[y][x] = 1 + ((x + y) % 4)  # never 3 in a row of same color
	# Sanity: starting board should have zero matches.
	var pre_marks: Array = m._find_matches()
	var any_pre := false
	for row in pre_marks:
		for v in row:
			if v: any_pre = true
	_check("hand-crafted board starts clean", not any_pre)
	# Set up: row 4 -> [2, 2, X, 2, 3, 4]  with X=3.
	# Swapping (2,4) X=3 with (3,4)=2 yields [2,2,2,3,3,4] — a 3-match of color 2.
	m.board[4][0] = 2
	m.board[4][1] = 2
	m.board[4][2] = 3
	m.board[4][3] = 2
	m.board[4][4] = 3
	m.board[4][5] = 4
	# Make sure no vertical 3 in adjacent columns (force differs above/below).
	m.board[3][0] = 5; m.board[3][1] = 5; m.board[3][2] = 5  # this would be a row 3 match - undo
	m.board[3][0] = 4; m.board[3][1] = 5; m.board[3][2] = 4
	m.board[5][0] = 5; m.board[5][1] = 4; m.board[5][2] = 5
	var n: int = m.try_swap(Vector2i(2, 4), Vector2i(3, 4))
	_check("valid match swap clears >= 3 tiles", n >= 3, "got %d cleared" % n)

func test_export_board_shape() -> void:
	var m: Object = Match3.new()
	m.seed_board(99)
	var b: Array = m.export_board()
	_check("export_board has ROWS rows", b.size() == Match3.ROWS)
	if b.size() > 0:
		_check("export_board row has COLS cols", b[0].size() == Match3.COLS)
