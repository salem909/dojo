extends Control
## In-game settings overlay. Opened with ESC from world/island scenes.
## Shows rebindable keybindings and a Quit button.
## Keybindings are persisted to user://settings.cfg.

signal closed

const SETTINGS_PATH := "user://settings.cfg"

const ACTIONS: Array = [
	["move_forward", "Move Forward"],
	["move_back",    "Move Back"],
	["move_left",    "Move Left"],
	["move_right",   "Move Right"],
	["sprint",       "Sprint"],
	["jump",         "Jump"],
	["interact",     "Interact"],
]

## Original default physical keycodes (for reset).
const DEFAULTS: Dictionary = {
	"move_forward": KEY_W,
	"move_back":    KEY_S,
	"move_left":    KEY_A,
	"move_right":   KEY_D,
	"sprint":       KEY_SHIFT,
	"jump":         KEY_SPACE,
	"interact":     KEY_E,
}

var _key_buttons: Dictionary  = {}  # action_name → Button
var _rebinding_action: String = ""  # non-empty while waiting for a keypress

@onready var _grid:      GridContainer = $Center/Panel/Margin/VBox/BindingsGrid
@onready var _reset_btn: Button        = $Center/Panel/Margin/VBox/ResetBtn
@onready var _quit_btn:  Button        = $Center/Panel/Margin/VBox/QuitBtn
@onready var _close_btn: Button        = $Center/Panel/Margin/VBox/CloseBtn

func _ready() -> void:
	_close_btn.pressed.connect(func(): closed.emit())
	_quit_btn.pressed.connect(func(): get_tree().quit())
	_reset_btn.pressed.connect(_reset_to_defaults)
	_build_bindings_grid()
	_load_bindings()

# ─── input (handles rebinding + ESC to close) ────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _rebinding_action != "":
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
		else:
			_apply_rebind(event)
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()

# ─── grid building ───────────────────────────────────────────────────────────

func _build_bindings_grid() -> void:
	for entry in ACTIONS:
		var action_name: String = entry[0]
		var label_text: String  = entry[1]
		var lbl := Label.new()
		lbl.text = label_text
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size.x = 160
		btn.text = _key_name_for(action_name)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var act := action_name  # capture for lambda
		btn.pressed.connect(func(): _start_rebind(act))
		_grid.add_child(btn)
		_key_buttons[action_name] = btn

func _refresh_all_buttons() -> void:
	for action_name in _key_buttons:
		_key_buttons[action_name].text = _key_name_for(action_name)

# ─── rebinding ───────────────────────────────────────────────────────────────

func _start_rebind(action_name: String) -> void:
	_rebinding_action = action_name
	_key_buttons[action_name].text = "[ press a key ]"

func _cancel_rebind() -> void:
	_key_buttons[_rebinding_action].text = _key_name_for(_rebinding_action)
	_rebinding_action = ""

func _apply_rebind(event: InputEventKey) -> void:
	var action_name := _rebinding_action
	_rebinding_action = ""
	InputMap.action_erase_events(action_name)
	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputMap.action_add_event(action_name, new_event)
	_key_buttons[action_name].text = _key_name_for(action_name)
	_save_bindings()

func _reset_to_defaults() -> void:
	_rebinding_action = ""
	for action_name in DEFAULTS:
		InputMap.action_erase_events(action_name)
		var ev := InputEventKey.new()
		ev.physical_keycode = DEFAULTS[action_name]
		InputMap.action_add_event(action_name, ev)
	_refresh_all_buttons()
	_save_bindings()

func is_rebinding() -> bool:
	return _rebinding_action != ""

# ─── persistence ─────────────────────────────────────────────────────────────

func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	for entry in ACTIONS:
		var action_name: String = entry[0]
		var events := InputMap.action_get_events(action_name)
		if events.size() > 0 and events[0] is InputEventKey:
			cfg.set_value("keybindings", action_name, (events[0] as InputEventKey).physical_keycode)
	cfg.save(SETTINGS_PATH)

func _load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for entry in ACTIONS:
		var action_name: String = entry[0]
		if cfg.has_section_key("keybindings", action_name):
			var keycode: int = cfg.get_value("keybindings", action_name)
			InputMap.action_erase_events(action_name)
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action_name, ev)
	_refresh_all_buttons()

# ─── helpers ─────────────────────────────────────────────────────────────────

func _key_name_for(action_name: String) -> String:
	var events := InputMap.action_get_events(action_name)
	if events.size() > 0 and events[0] is InputEventKey:
		return OS.get_keycode_string((events[0] as InputEventKey).physical_keycode)
	return "???"
