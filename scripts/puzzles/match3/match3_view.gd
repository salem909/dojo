extends Control
## Renders the Match-3 board as a grid of colored buttons.
## Click two adjacent tiles to swap them.

const COLS: int = 6
const ROWS: int = 8
const TILE_SIZE: int = 64

const COLOR_TABLE: Array = [
	Color(0.1, 0.1, 0.15),    # 0 = empty (shouldn't be visible)
	Color(0.95, 0.30, 0.30),  # 1 red
	Color(0.30, 0.85, 0.30),  # 2 green
	Color(0.30, 0.55, 0.95),  # 3 blue
	Color(0.95, 0.85, 0.30),  # 4 yellow
	Color(0.80, 0.40, 0.95),  # 5 purple
]

@onready var grid: GridContainer = $Panel/VBox/Grid
@onready var score_label: Label = $Panel/VBox/ScoreLabel
@onready var hint_label: Label = $Panel/VBox/HintLabel

var current_board: Array = []
var selected: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	visible = false
	grid.columns = COLS
	# Pre-create COLS*ROWS buttons.
	for y in ROWS:
		for x in COLS:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			btn.focus_mode = Control.FOCUS_NONE
			btn.set_meta("cell", Vector2i(x, y))
			btn.pressed.connect(_on_tile_pressed.bind(Vector2i(x, y)))
			grid.add_child(btn)

func set_board(board: Array, score: int) -> void:
	current_board = board
	score_label.text = "Doubloons: %d" % score
	for y in ROWS:
		for x in COLS:
			var idx := y * COLS + x
			var btn: Button = grid.get_child(idx)
			var color_idx: int = board[y][x]
			var sb := StyleBoxFlat.new()
			sb.bg_color = COLOR_TABLE[color_idx]
			sb.corner_radius_top_left = 8
			sb.corner_radius_top_right = 8
			sb.corner_radius_bottom_left = 8
			sb.corner_radius_bottom_right = 8
			if Vector2i(x, y) == selected:
				sb.border_color = Color(1, 1, 1, 1)
				sb.border_width_left = 4
				sb.border_width_right = 4
				sb.border_width_top = 4
				sb.border_width_bottom = 4
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)

func _on_tile_pressed(cell: Vector2i) -> void:
	if selected == Vector2i(-1, -1):
		selected = cell
		set_board(current_board, _current_score())
		hint_label.text = "Pick an adjacent tile to swap."
		return
	if selected == cell:
		selected = Vector2i(-1, -1)
		set_board(current_board, _current_score())
		return
	var dx: int = abs(cell.x - selected.x)
	var dy: int = abs(cell.y - selected.y)
	if dx + dy == 1:
		# Send swap to network client via Game autoload (avoids hardcoded scene path).
		Game.client_send_match3_swap(selected, cell)
		selected = Vector2i(-1, -1)
		hint_label.text = ""
	else:
		selected = cell
		set_board(current_board, _current_score())
		hint_label.text = "Tiles must be adjacent."

func _current_score() -> int:
	# Cheap parse: scrape last score we displayed.
	var s := score_label.text
	var num := s.replace("Doubloons: ", "")
	return int(num) if num.is_valid_int() else 0
