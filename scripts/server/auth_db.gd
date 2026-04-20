extends RefCounted
## Server-only flat-file persistence layer (JSON).
## Stores accounts at user://db/accounts.json.
## Production: replace with SQLite or PostgreSQL.
##
## Account record shape:
##   { account_id, display_name, password_hash, character_class,
##     doubloons, bank_doubloons, puzzle_wins, puzzle_losses, inventory }

const DB_PATH  := "user://db/accounts.json"
const CREW_DB_PATH := "user://db/crews.json"

var _accounts: Dictionary = {}  # account_id (lowercase) → account dict
var _crews: Dictionary    = {}  # crew_id (lowercase name) → { crew_id, name, captain, members[] }

func load_db() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://db"))
	_accounts = _load_json(DB_PATH)
	_crews    = _load_json(CREW_DB_PATH)
	Log.i("auth_db: loaded %d account(s), %d crew(s)" \
		% [_accounts.size(), _crews.size()])

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.e("auth_db: cannot open %s (err=%d)" % [path, FileAccess.get_open_error()])
		return {}
	var json := JSON.new()
	var parse_err := json.parse(f.get_as_text())
	f.close()
	if parse_err != OK:
		Log.e("auth_db: JSON parse error in %s at line %d: %s" \
			% [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}

func register_account(username: String, password_hash: String,
		char_class: int = 0, display_name: String = "") -> int:
	## Returns a Protocol.AuthError code; 0 = OK.
	if not _is_valid_username(username):
		return Protocol.AuthError.BAD_USERNAME
	var key := username.to_lower()
	if _accounts.has(key):
		return Protocol.AuthError.USERNAME_TAKEN
	var pirate_name := display_name.strip_edges()
	if pirate_name.is_empty():
		pirate_name = username
	_accounts[key] = {
		"account_id":      key,
		"display_name":    pirate_name,
		"password_hash":   _server_hash(password_hash),
		"character_class": char_class,
		"doubloons":       0,
		"bank_doubloons":  0,
		"puzzle_wins":     {},
		"puzzle_losses":   {},
		"inventory":       {},
		"crew_id":         "",
		"crew_name":       "",
	}
	_write_db()
	Log.i("auth_db: registered '%s' class=%d" % [username, char_class])
	return Protocol.AuthError.OK

func authenticate(username: String, password_hash: String) -> Array:
	## Returns [account_dict_or_null, error_code].
	var key := username.to_lower()
	if not _accounts.has(key):
		return [null, Protocol.AuthError.BAD_CREDENTIALS]
	var acct: Dictionary = _accounts[key]
	if acct.get("password_hash", "") != _server_hash(password_hash):
		return [null, Protocol.AuthError.BAD_CREDENTIALS]
	return [acct, Protocol.AuthError.OK]

func save_player_data(account_id: String, data: Dictionary) -> void:
	## Merges data into the account record and writes to disk.
	## data keys: doubloons, bank_doubloons, puzzle_wins, puzzle_losses,
	##            inventory, crew_id, crew_name
	if not _accounts.has(account_id):
		return
	for key in data:
		_accounts[account_id][key] = data[key]
	_write_db()

# ─── crews ───────────────────────────────────────────────────────────────────

func create_crew(name: String, captain_account_id: String, captain_display_name: String) -> int:
	## Returns Protocol.CrewError code; OK on success.
	if not _is_valid_crew_name(name):
		return Protocol.CrewError.BAD_NAME
	var key := name.to_lower()
	if _crews.has(key):
		return Protocol.CrewError.NAME_TAKEN
	if not _accounts.has(captain_account_id):
		return Protocol.CrewError.NO_SUCH_PLAYER
	if _accounts[captain_account_id].get("crew_id", "") != "":
		return Protocol.CrewError.ALREADY_IN_CREW
	_crews[key] = {
		"crew_id":   key,
		"name":      name,
		"captain":   captain_account_id,
		"members":   [captain_account_id],
	}
	_accounts[captain_account_id]["crew_id"]   = key
	_accounts[captain_account_id]["crew_name"] = name
	_write_db()
	_write_crew_db()
	Log.i("auth_db: created crew '%s' captain='%s'" % [name, captain_account_id])
	return Protocol.CrewError.OK

func join_crew(crew_id: String, account_id: String) -> int:
	if not _crews.has(crew_id):
		return Protocol.CrewError.BAD_NAME
	if not _accounts.has(account_id):
		return Protocol.CrewError.NO_SUCH_PLAYER
	if _accounts[account_id].get("crew_id", "") != "":
		return Protocol.CrewError.ALREADY_IN_CREW
	var crew: Dictionary = _crews[crew_id]
	if not crew["members"].has(account_id):
		crew["members"].append(account_id)
	_accounts[account_id]["crew_id"]   = crew_id
	_accounts[account_id]["crew_name"] = crew["name"]
	_write_db()
	_write_crew_db()
	Log.i("auth_db: '%s' joined crew '%s'" % [account_id, crew["name"]])
	return Protocol.CrewError.OK

func leave_crew(account_id: String) -> int:
	if not _accounts.has(account_id):
		return Protocol.CrewError.NO_SUCH_PLAYER
	var crew_id: String = _accounts[account_id].get("crew_id", "")
	if crew_id == "":
		return Protocol.CrewError.NOT_IN_CREW
	if _crews.has(crew_id):
		var crew: Dictionary = _crews[crew_id]
		crew["members"].erase(account_id)
		# If captain leaves and there are other members, promote the next one.
		# If empty, disband.
		if crew["members"].is_empty():
			_crews.erase(crew_id)
			Log.i("auth_db: disbanded empty crew '%s'" % crew["name"])
		elif crew["captain"] == account_id:
			crew["captain"] = crew["members"][0]
			Log.i("auth_db: promoted '%s' to captain of '%s'" \
				% [crew["captain"], crew["name"]])
	_accounts[account_id]["crew_id"]   = ""
	_accounts[account_id]["crew_name"] = ""
	_write_db()
	_write_crew_db()
	return Protocol.CrewError.OK

func get_crew(crew_id: String) -> Dictionary:
	return _crews.get(crew_id, {})

func find_account_by_display_name(pirate_name: String) -> Dictionary:
	## Case-insensitive lookup by pirate display name. Returns {} if not found.
	var needle := pirate_name.strip_edges().to_lower()
	for acct_id in _accounts:
		var acct: Dictionary = _accounts[acct_id]
		if acct.get("display_name", "").to_lower() == needle:
			return acct
	return {}

# ─── internal ────────────────────────────────────────────────────────────────

func _is_valid_username(username: String) -> bool:
	if username.length() < 3 or username.length() > 20:
		return false
	for i in range(username.length()):
		var c := username.unicode_at(i)
		# Allow A-Z (65-90), a-z (97-122), 0-9 (48-57), _ (95)
		if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
				or (c >= 48 and c <= 57) or c == 95):
			return false
	return true

func _server_hash(client_hash: String) -> String:
	## client sends SHA256(password). We store SHA256(that) so the DB value
	## differs from what travels over the wire.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(client_hash.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _is_valid_crew_name(name: String) -> bool:
	var trimmed := name.strip_edges()
	if trimmed.length() < Protocol.MIN_CREW_NAME_LEN \
			or trimmed.length() > Protocol.MAX_CREW_NAME_LEN:
		return false
	# Allow letters, digits, spaces, apostrophes, dashes.
	for i in range(trimmed.length()):
		var c := trimmed.unicode_at(i)
		var ok := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
				or (c >= 48 and c <= 57) or c == 32 or c == 39 or c == 45
		if not ok:
			return false
	return true

func _write_db() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://db"))
	var f := FileAccess.open(DB_PATH, FileAccess.WRITE)
	if f == null:
		Log.e("auth_db: cannot write %s (err=%d)" % [DB_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(_accounts, "\t"))
	f.close()

func _write_crew_db() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://db"))
	var f := FileAccess.open(CREW_DB_PATH, FileAccess.WRITE)
	if f == null:
		Log.e("auth_db: cannot write %s (err=%d)" \
			% [CREW_DB_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(_crews, "\t"))
	f.close()
