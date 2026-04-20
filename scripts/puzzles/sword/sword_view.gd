extends Control
## Client-side view for the Swordfighting puzzle. Renders a 6×13 grid, the
## active falling pair (which falls automatically under server gravity), a
## "next" preview, a score line, and a chain multiplier badge.
##
## Keyboard — matches PP's key map (puzzle/client/v.jbc:239-307):
##   A / ←        move pair left
##   D / →        move pair right
##   W / ↑        rotate pair CCW
##   S / ↓        rotate pair CW
##   Space        HOLD for soft drop (release to return to normal speed)
##                — there is no hard drop in PP
##   Escape       exit the puzzle (handled by world.gd)
##
## Strike pieces decay over 3 board-locks; we render them with a freshness
## tint (bright = new, dim/red = about to vanish) using the strike_age
## parallel array from the server-exported state.
##
## This scene reads the server-exported state Dictionary and re-renders on
## every update — it's intentionally stateless so server ticks win any races.

const COLS: int = 6
const ROWS: int = 13
const TILE_SIZE: int = 34

# Cell kinds mirror sword_logic.gd constants.
const KIND_EMPTY:    int = 0
const KIND_BREAKER:  int = 10
const KIND_STRIKE:   int = 20
const KIND_SPRINKLE: int = 30
const KIND_SWORD:    int = 40

# Color palette. Index = color id (1..8).
#
# We keep the *standard ocean* set (red, yellow, green, blue per yppedia) at
# contiguous indices 1..4 so the default num_colors=4 picks them naturally.
# Special-ocean colors (orange/purple/white/black per Sword.jbc:34-42) live
# at 5..8 and only show up when special game-modes set num_colors higher.
const COLOR_TABLE: Array = [
	Color(0.08, 0.08, 0.12, 0),   # 0 = empty
	Color(0.92, 0.28, 0.28, 1),   # 1 red
	Color(0.95, 0.85, 0.25, 1),   # 2 yellow
	Color(0.30, 0.78, 0.30, 1),   # 3 green
	Color(0.25, 0.55, 0.95, 1),   # 4 blue
	Color(0.97, 0.55, 0.20, 1),   # 5 orange  (special)
	Color(0.65, 0.35, 0.85, 1),   # 6 purple  (special)
	Color(0.95, 0.95, 0.95, 1),   # 7 white   (special)
	Color(0.20, 0.18, 0.22, 1),   # 8 black   (special)
]
const SPRINKLE_COLOR: Color = Color(0.55, 0.55, 0.55, 1)
const SWORD_COLOR:    Color = Color(0.80, 0.80, 0.85, 1)

@onready var grid:       GridContainer = $Panel/HBox/Left/Grid
@onready var score_lbl:  Label         = $Panel/HBox/Right/ScoreLabel
@onready var chain_lbl:  Label         = $Panel/HBox/Right/ChainLabel
@onready var next_grid:  GridContainer = $Panel/HBox/Right/NextGrid
@onready var hint_lbl:   Label         = $Panel/HBox/Right/HintLabel
@onready var gameover_lbl: Label       = $Panel/HBox/Right/GameOverLabel

var _cells: Array = []        # 2D array of ColorRect (display tiles)
var _next_cells: Array = []   # 2 ColorRect for the next-pair preview
var _last_state: Dictionary = {}
var _active: bool = false

func _ready() -> void:
	visible = false
	grid.columns = COLS
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var c := ColorRect.new()
			c.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			c.color = Color(0.08, 0.08, 0.12, 0.85)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(c)
			row.append(c)
		_cells.append(row)
	# Next pair preview: a tiny 1x2 grid (b above a).
	next_grid.columns = 1
	for _i in 2:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
		c.color = Color(0.08, 0.08, 0.12, 0.85)
		next_grid.add_child(c)
		_next_cells.append(c)

func _input(event: InputEvent) -> void:
	if not _active: return
	if not event is InputEventKey: return
	var key_event := event as InputEventKey
	if key_event.echo: return
	# ── Space: toggle soft-drop hold on press AND release ────────────────
	if key_event.physical_keycode == KEY_SPACE:
		Game.client_sword_set_soft(key_event.pressed)
		get_viewport().set_input_as_handled()
		return
	# Other keys are press-only.
	if not key_event.pressed: return
	match key_event.physical_keycode:
		KEY_A, KEY_LEFT:
			Game.client_sword_move(-1)
			get_viewport().set_input_as_handled()
		KEY_D, KEY_RIGHT:
			Game.client_sword_move(1)
			get_viewport().set_input_as_handled()
		KEY_W, KEY_UP:
			Game.client_sword_rotate_ccw()
			get_viewport().set_input_as_handled()
		KEY_S, KEY_DOWN:
			Game.client_sword_rotate_cw()
			get_viewport().set_input_as_handled()

func show_state(state: Dictionary) -> void:
	_last_state = state
	_active     = not state.get("game_over", false)
	visible     = true
	gameover_lbl.visible = state.get("game_over", false)
	_render_board(state)
	_render_next(state)
	score_lbl.text = "Score: %d" % int(state.get("score", 0))
	var chain: int = int(state.get("chain", 0))
	chain_lbl.text = "Best chain: %dx" % chain if chain > 0 else "Best chain: —"
	if state.get("game_over", false):
		hint_lbl.text = "Game over! Press ESC to finish."
	elif state.get("stuck", false):
		hint_lbl.text = "Locking! Move or rotate to tuck under."
	elif state.get("soft", false):
		hint_lbl.text = "Soft-dropping… (release Space to slow)"
	else:
		hint_lbl.text = "A/D move  •  W↺  S↻  •  Hold Space to fall faster"

func hide_puzzle() -> void:
	visible = false
	_active = false

func _render_board(state: Dictionary) -> void:
	var board: Array = state.get("board", [])
	var ages:  Array = state.get("strike_age", [])
	const STRIKE_AGE_TINT: Array = [
		Color(1.0, 1.0, 1.0, 1),    # age 0 — not a strike
		Color(1.4, 0.55, 0.55, 1),  # age 1 — about to vanish (warning red)
		Color(1.0, 0.85, 0.5, 1),   # age 2 — getting old (amber)
		Color(1.2, 1.2, 1.2, 1),    # age 3 — fresh (bright)
	]
	for y in ROWS:
		for x in COLS:
			var v: int = 0
			if y < board.size() and x < board[y].size():
				v = board[y][x]
			_cells[y][x].color = _color_for(v)
			# Tint by strike age if this cell is a strike.
			var tint: Color = Color(1, 1, 1, 1)
			if y < ages.size() and x < ages[y].size():
				var age: int = int(ages[y][x])
				if age > 0 and age < STRIKE_AGE_TINT.size():
					tint = STRIKE_AGE_TINT[age]
			_cells[y][x].modulate = tint
	# Overlay the active pair. The a-piece is at (active_col, active_row);
	# the b-piece is offset by orient. Show the pair pieces at half-brightness
	# plus an outline — the easiest way in a ColorRect grid is to write their
	# colors on top.
	var a_col: int = int(state.get("active_col", -1))
	var a_row: int = int(state.get("active_row", -1))
	var orient: int = int(state.get("orient", 0))
	var a_piece: int = int(state.get("active_a", 0))
	var b_piece: int = int(state.get("active_b", 0))
	# When stuck, flash the active pair toward red so the player notices the
	# lock-delay countdown before the piece commits.
	var stuck: bool = bool(state.get("stuck", false))
	var active_tint: Color = Color(1.4, 0.55, 0.55, 1) if stuck else Color(1.1, 1.1, 1.1, 1)
	if a_piece != 0 and a_col >= 0 and a_row >= 0 and a_row < ROWS:
		_cells[a_row][a_col].color = _color_for(a_piece)
		_cells[a_row][a_col].modulate = active_tint
	var b_off := _b_offset(orient)
	var b_col: int = a_col + b_off.x
	var b_row: int = a_row + b_off.y
	if b_piece != 0 and b_row >= 0 and b_row < ROWS and b_col >= 0 and b_col < COLS:
		_cells[b_row][b_col].color = _color_for(b_piece)
		_cells[b_row][b_col].modulate = active_tint

func _render_next(state: Dictionary) -> void:
	var a: int = int(state.get("next_a", 0))
	var b: int = int(state.get("next_b", 0))
	# next_cells[0] is top (b), [1] is bottom (a)
	_next_cells[0].color = _color_for(b)
	_next_cells[1].color = _color_for(a)

func _color_for(cell_value: int) -> Color:
	if cell_value == KIND_EMPTY:
		return Color(0.08, 0.08, 0.12, 0.85)
	if cell_value == KIND_SPRINKLE:
		return SPRINKLE_COLOR
	if cell_value == KIND_SWORD:
		return SWORD_COLOR
	var color_id: int = 0
	var tint_mul: float = 1.0
	if cell_value >= KIND_STRIKE and cell_value < KIND_STRIKE + 10:
		color_id = cell_value - KIND_STRIKE
		tint_mul = 1.25   # strikes appear brighter
	elif cell_value >= KIND_BREAKER and cell_value < KIND_BREAKER + 10:
		color_id = cell_value - KIND_BREAKER
		tint_mul = 0.65   # breakers darker / cutout feel
	else:
		color_id = cell_value
	if color_id < 1 or color_id >= COLOR_TABLE.size():
		return Color(0.08, 0.08, 0.12, 0.85)
	var base: Color = COLOR_TABLE[color_id]
	return Color(
		clampf(base.r * tint_mul, 0, 1),
		clampf(base.g * tint_mul, 0, 1),
		clampf(base.b * tint_mul, 0, 1),
		1)

func _b_offset(orient: int) -> Vector2i:
	match orient:
		0: return Vector2i(0, -1)
		1: return Vector2i(1, 0)
		2: return Vector2i(0, 1)
		3: return Vector2i(-1, 0)
		_: return Vector2i(0, -1)
