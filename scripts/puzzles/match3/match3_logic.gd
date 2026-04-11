extends RefCounted
## Pure server-side logic for the Match-3 "Bilging" puzzle.
## Inspired by Puzzle Pirates' bilging minigame: swap adjacent tiles, clear
## groups of 3+ same color, gravity drops tiles, refill from the top.
## No engine dependencies — easy to unit test.

const COLS: int = 6
const ROWS: int = 8
const NUM_COLORS: int = 5  # 1..5 (0 = empty)

# board[y][x], y=0 is top
var board: Array = []
var score: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func seed_board(seed_val: int) -> void:
	rng.seed = seed_val
	board = []
	for _y in ROWS:
		var row: Array = []
		for _x in COLS:
			row.append(_random_color())
		board.append(row)
	# Resolve any starting matches so the player begins with a clean board.
	while _resolve_matches() > 0:
		pass

func _random_color() -> int:
	return rng.randi_range(1, NUM_COLORS)

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < COLS and p.y >= 0 and p.y < ROWS

func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return (abs(a.x - b.x) + abs(a.y - b.y)) == 1

func get_cell(p: Vector2i) -> int:
	return board[p.y][p.x]

func set_cell(p: Vector2i, v: int) -> void:
	board[p.y][p.x] = v

## Attempt to swap two adjacent tiles. Returns total tiles cleared (0 = invalid).
func try_swap(a: Vector2i, b: Vector2i) -> int:
	if not in_bounds(a) or not in_bounds(b): return 0
	if not is_adjacent(a, b): return 0
	var av := get_cell(a)
	var bv := get_cell(b)
	set_cell(a, bv)
	set_cell(b, av)
	var cleared := _resolve_matches()
	if cleared == 0:
		# Revert: invalid move per Puzzle Pirates rules.
		set_cell(a, av)
		set_cell(b, bv)
	return cleared

## Find all 3+ matches, clear them, drop, refill, cascade. Returns total cleared.
func _resolve_matches() -> int:
	var total := 0
	while true:
		var marks := _find_matches()
		var cleared := 0
		for y in ROWS:
			for x in COLS:
				if marks[y][x]:
					board[y][x] = 0
					cleared += 1
		if cleared == 0:
			break
		total += cleared
		_apply_gravity()
		_refill()
	return total

func _find_matches() -> Array:
	var marks: Array = []
	for _y in ROWS:
		var row: Array = []
		for _x in COLS:
			row.append(false)
		marks.append(row)
	# Horizontal runs
	for y in ROWS:
		var run_start: int = 0
		while run_start < COLS:
			var c: int = board[y][run_start]
			var run_end: int = run_start
			while run_end < COLS and int(board[y][run_end]) == c and c != 0:
				run_end += 1
			if run_end - run_start >= 3:
				for x in range(run_start, run_end):
					marks[y][x] = true
			run_start = max(run_end, run_start + 1)
	# Vertical runs
	for x in COLS:
		var run_start: int = 0
		while run_start < ROWS:
			var c: int = board[run_start][x]
			var run_end: int = run_start
			while run_end < ROWS and int(board[run_end][x]) == c and c != 0:
				run_end += 1
			if run_end - run_start >= 3:
				for y in range(run_start, run_end):
					marks[y][x] = true
			run_start = max(run_end, run_start + 1)
	return marks

func _apply_gravity() -> void:
	for x in COLS:
		var write_y: int = ROWS - 1
		for y in range(ROWS - 1, -1, -1):
			if int(board[y][x]) != 0:
				var v: int = board[y][x]
				board[y][x] = 0
				board[write_y][x] = v
				write_y -= 1

func _refill() -> void:
	for y in ROWS:
		for x in COLS:
			if board[y][x] == 0:
				board[y][x] = _random_color()

## Export as plain Array of Arrays for sending over RPC.
func export_board() -> Array:
	var out: Array = []
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			row.append(board[y][x])
		out.append(row)
	return out
