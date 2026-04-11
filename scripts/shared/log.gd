extends Node
## Tiny structured logger used by client and server.
## Prefixes lines with role + monotonic ms so client/server logs interleave readably.

enum Level { DEBUG, INFO, WARN, ERROR }

var role: String = "?"
var min_level: int = Level.DEBUG

func _ready() -> void:
	# Detect role from cmdline (user args after `--`). Default to "client".
	role = "server" if "--server" in OS.get_cmdline_user_args() else "client"

func _fmt(level: String, msg: String) -> String:
	var t := Time.get_ticks_msec()
	return "[%s][%07d][%s] %s" % [role, t, level, msg]

func d(msg: String) -> void:
	if min_level <= Level.DEBUG: print(_fmt("DBG", msg))

func i(msg: String) -> void:
	if min_level <= Level.INFO: print(_fmt("INF", msg))

func w(msg: String) -> void:
	if min_level <= Level.WARN: print(_fmt("WRN", msg))

func e(msg: String) -> void:
	if min_level <= Level.ERROR: printerr(_fmt("ERR", msg))
