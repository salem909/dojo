extends Control
## In-scene chat overlay. Displays a rolling history of incoming messages
## and exposes an input line toggled with the Enter key.
##
## Commands supported while typed in the input:
##   /c  <message>        → crew chat
##   /who <pirate name>   → request player info (opens info panel)
##   /crew create <name>  → found a new crew (must not be in one)
##   /crew leave          → leave current crew
##   /crew invite <name>  → invite a pirate to your crew
##
## Bare text (no leading "/") is sent on the SAY channel to everyone in the
## current zone.

signal input_captured(has_focus: bool)
signal lookup_requested(pirate_name: String)

@onready var history_label: RichTextLabel = $VBox/HistoryBox/History
@onready var input_line:    LineEdit      = $VBox/InputLine
@onready var invite_popup:  ColorRect     = $InvitePopup
@onready var invite_label:  Label         = $InvitePopup/VBox/Label
@onready var invite_accept: Button        = $InvitePopup/VBox/HBox/Accept
@onready var invite_reject: Button        = $InvitePopup/VBox/HBox/Reject

var _history: Array = []          # array of BBCode-formatted strings
var _pending_invite_crew_id: String = ""

func _ready() -> void:
	input_line.visible = false
	input_line.text_submitted.connect(_on_submit)
	invite_popup.visible = false
	invite_accept.pressed.connect(_on_invite_accept)
	invite_reject.pressed.connect(_on_invite_reject)

	Game.chat_received_sig.connect(_on_chat_received)
	Game.crew_result_sig.connect(_on_crew_result)
	Game.crew_invite_received_sig.connect(_on_crew_invite)
	# Seed with a friendly tip.
	_append_system("Welcome! Press [b]Enter[/b] to chat. Type [b]/help[/b] for commands.")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo: return
	if input_line.visible:
		# Allow ESC to cancel chat input without submitting.
		if key_event.physical_keycode == KEY_ESCAPE:
			_close_input()
			get_viewport().set_input_as_handled()
		return
	# Pressing Enter or T opens the input line if nothing else owns focus.
	if key_event.physical_keycode == KEY_ENTER \
			or key_event.physical_keycode == KEY_KP_ENTER \
			or key_event.physical_keycode == KEY_T:
		_open_input()
		get_viewport().set_input_as_handled()

func _open_input() -> void:
	input_line.visible = true
	input_line.text    = ""
	input_line.grab_focus()
	input_captured.emit(true)

func _close_input() -> void:
	input_line.visible = false
	input_line.release_focus()
	input_captured.emit(false)

func _on_submit(text: String) -> void:
	var msg := text.strip_edges()
	_close_input()
	if msg.is_empty(): return
	if msg.begins_with("/"):
		_handle_command(msg)
	else:
		Game.client_send_chat(Protocol.ChatChannel.SAY, msg)

func _handle_command(cmd: String) -> void:
	var parts: PackedStringArray = cmd.split(" ", false)
	var head: String = parts[0].to_lower()
	match head:
		"/help":
			_append_system(
				"Commands:\n" +
				"  /c <msg>              — crew chat\n" +
				"  /who <name>           — look up a pirate\n" +
				"  /crew create <name>   — found a crew\n" +
				"  /crew leave           — leave your crew\n" +
				"  /crew invite <name>   — invite to your crew")
		"/c":
			if parts.size() < 2:
				_append_system("Usage: /c <message>")
				return
			var msg := cmd.substr(3).strip_edges()
			if msg.is_empty(): return
			Game.client_send_chat(Protocol.ChatChannel.CREW, msg)
		"/who":
			if parts.size() < 2:
				_append_system("Usage: /who <pirate name>")
				return
			var target := cmd.substr(5).strip_edges()
			lookup_requested.emit(target)
			Game.client_request_player_info(target)
		"/crew":
			if parts.size() < 2:
				_append_system("Usage: /crew <create|leave|invite> ...")
				return
			var sub: String = parts[1].to_lower()
			match sub:
				"create":
					if parts.size() < 3:
						_append_system("Usage: /crew create <name>")
						return
					var name := cmd.substr(13).strip_edges()
					Game.client_request_create_crew(name)
				"leave":
					Game.client_request_leave_crew()
				"invite":
					if parts.size() < 3:
						_append_system("Usage: /crew invite <pirate name>")
						return
					var target := cmd.substr(13).strip_edges()
					Game.client_request_invite_to_crew(target)
				_:
					_append_system("Unknown crew command: %s" % sub)
		_:
			_append_system("Unknown command: %s" % head)

func _on_chat_received(channel: int, from_name: String, message: String) -> void:
	var color: Color = Protocol.CHAT_CHANNEL_COLORS[channel]
	var prefix: String = Protocol.CHAT_CHANNEL_PREFIXES[channel]
	var line: String
	if channel == Protocol.ChatChannel.SYSTEM:
		line = "[color=#%s]%s%s[/color]" \
				% [color.to_html(false), prefix, message]
	else:
		line = "[color=#%s]%s%s: %s[/color]" \
				% [color.to_html(false), prefix, from_name, message]
	_append_line(line)

func _on_crew_result(ok: bool, error_code: int, crew_name: String) -> void:
	if ok:
		if crew_name == "":
			_append_system("You have left your crew.")
		else:
			_append_system("Crew: you are now a member of [b]%s[/b]." % crew_name)
		return
	match error_code:
		Protocol.CrewError.BAD_NAME:
			_append_system("Invalid crew name. Use 3-24 letters, digits, spaces, apostrophes, or dashes.")
		Protocol.CrewError.NAME_TAKEN:
			_append_system("That crew name is already taken.")
		Protocol.CrewError.ALREADY_IN_CREW:
			_append_system("You are already in a crew. Leave first with /crew leave.")
		Protocol.CrewError.NOT_IN_CREW:
			_append_system("You are not in a crew.")
		Protocol.CrewError.TARGET_OFFLINE:
			_append_system("Target pirate is offline.")
		Protocol.CrewError.NO_SUCH_PLAYER:
			_append_system("No such pirate.")
		Protocol.CrewError.SELF_TARGET:
			_append_system("You cannot invite yourself.")
		_:
			_append_system("Crew action failed (code %d)." % error_code)

func _on_crew_invite(from_name: String, crew_name: String) -> void:
	# Store the crew_id for accept/reject. We'll need to pass it to game,
	# so we'll just use crew_name.to_lower() since that's our crew_id scheme.
	_pending_invite_crew_id = crew_name.to_lower()
	invite_label.text = "%s invites you to join\n[b]%s[/b]" % [from_name, crew_name]
	invite_popup.visible = true
	_append_system("Crew invite from [b]%s[/b] → %s" % [from_name, crew_name])

func _on_invite_accept() -> void:
	Game.client_respond_crew_invite(true, _pending_invite_crew_id)
	invite_popup.visible = false
	_pending_invite_crew_id = ""

func _on_invite_reject() -> void:
	Game.client_respond_crew_invite(false, _pending_invite_crew_id)
	invite_popup.visible = false
	_pending_invite_crew_id = ""
	_append_system("Declined crew invite.")

func _append_system(text: String) -> void:
	var color: Color = Protocol.CHAT_CHANNEL_COLORS[Protocol.ChatChannel.SYSTEM]
	_append_line("[color=#%s][System] %s[/color]" \
			% [color.to_html(false), text])

func _append_line(bbcode_line: String) -> void:
	_history.append(bbcode_line)
	while _history.size() > Protocol.MAX_CHAT_HISTORY:
		_history.pop_front()
	history_label.text = "\n".join(_history)
	# Scroll to bottom on next frame so the RichTextLabel has its layout.
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	var vbar := history_label.get_v_scroll_bar()
	if vbar:
		vbar.value = vbar.max_value

# Public: used by the world/island scene to show a player-info result.
func show_player_info(info: Dictionary) -> void:
	if not info.get("found", true):
		_append_system("No pirate named '%s'." % info.get("name", "?"))
		return
	var klass: int = info.get("class", 0)
	var class_name_str: String = Protocol.CHARACTER_NAMES[
		clampi(klass, 0, Protocol.CHARACTER_NAMES.size() - 1)]
	var crew_name: String = info.get("crew", "")
	var crew_line: String = crew_name if crew_name != "" else "(no crew)"
	var status: String = "online" if info.get("online", false) else "offline"
	var wins: int = info.get("bilge_wins", 0)
	var losses: int = info.get("bilge_losses", 0)
	var rank: int = info.get("bilge_rank", 0)
	var rank_name_str: String = Protocol.RANK_NAMES[
		clampi(rank, 0, Protocol.RANK_NAMES.size() - 1)]
	_append_system(
		"[b]%s[/b] (%s, %s)\n" % [info.get("name", "?"), class_name_str, status] +
		"  Crew: %s\n"        % crew_line +
		"  Bilging: %s — %d wins, %d losses" % [rank_name_str, wins, losses])
