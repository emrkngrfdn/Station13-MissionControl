extends Node

const SAVE_PATH = "user://leaderboard.json"
const LEGACY_FAKE_TEAMS: Array[String] = [
	"[1P] AstroBot#0001",
	"[2P] Goddard_Crew#2002",
	"[2P] Artemis_Team#1099",
	"[1P] LunarScout#4210",
	"[4P] DeepSpace_4#8801",
	"[3P] JPL_Crew#2020",
	"[1P] RedPlanet#3055"
]

var records: Array = []
var _fetch_http: HTTPRequest = null
var _submit_http: HTTPRequest = null

func _ready() -> void:
	_fetch_http = HTTPRequest.new()
	_fetch_http.timeout = 20.0
	add_child(_fetch_http)
	_fetch_http.request_completed.connect(_on_fetch_completed)

	_submit_http = HTTPRequest.new()
	_submit_http.timeout = 20.0
	add_child(_submit_http)
	_submit_http.request_completed.connect(_on_submit_completed)

	load_records()
	fetch_from_server()

func load_records() -> void:
	records.clear()
	if FileAccess.file_exists(SAVE_PATH):
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if parsed is Array:
			var cleaned: Array = []
			for item in parsed:
				if not (item is Dictionary):
					continue
				var rec: Dictionary = item
				if String(rec.get("team", "")) in LEGACY_FAKE_TEAMS:
					continue
				cleaned.append(rec)
			records = cleaned
	_sort_records()
	_save_local()

func _save_local() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records))

func _sort_records() -> void:
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = float(a.get("time_sec", 999999.0))
		var tb: float = float(b.get("time_sec", 999999.0))
		if is_equal_approx(ta, tb):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return ta < tb
	)

func _record_key(rec: Dictionary) -> String:
	return "%s|%s|%.1f|%d" % [
		String(rec.get("mission_id", "")),
		String(rec.get("team", "")),
		float(rec.get("time_sec", 0.0)),
		int(rec.get("score", 0))
	]

func _has_record(rec: Dictionary) -> bool:
	var key: String = _record_key(rec)
	for existing in records:
		if existing is Dictionary and _record_key(existing) == key:
			return true
	return false

func _get_room_host_tag() -> String:
	for p in GameState.lobby_players:
		if p is Dictionary and bool(p.get("is_host", false)):
			var tag: String = String(p.get("tag", "")).strip_edges()
			if tag != "":
				return tag
	if not GameState.lobby_players.is_empty() and GameState.lobby_players[0] is Dictionary:
		var fallback: String = String(GameState.lobby_players[0].get("tag", "")).strip_edges()
		if fallback != "":
			return fallback
	return PlayerProfile.full_tag

func get_records_for_mission(mission_id: String) -> Array:
	_sort_records()
	var filtered: Array = []
	for rec in records:
		if not (rec is Dictionary):
			continue
		if mission_id == "" or String(rec.get("mission_id", "")) == mission_id:
			filtered.append(rec)
	return filtered

func add_record(mission_id: String, time_sec: float, score: int) -> void:
	var player_count: int = 1 if GameState.is_solo else max(1, GameState.lobby_players.size())
	var mode_tag: String = "[1P]" if player_count <= 1 else "[%dP]" % player_count
	var host_tag: String = _get_room_host_tag()
	var team_name: String = "%s %s" % [mode_tag, host_tag]
	var rec: Dictionary = {
		"mission_id": mission_id,
		"team": team_name,
		"host_tag": host_tag,
		"player_count": player_count,
		"time_sec": snapped(maxf(0.1, time_sec), 0.1),
		"score": max(0, score)
	}
	if not _has_record(rec):
		records.append(rec)
		_sort_records()
		_save_local()
		EventBus.leaderboard_updated.emit()

	var should_submit_to_server: bool = (not GameState.is_network_active) or GameState.is_room_host
	if should_submit_to_server and NetworkClient.is_server_configured():
		_submit_to_server(rec)
	elif GameState.is_network_active and not GameState.is_room_host and NetworkClient.is_server_configured():
		fetch_from_server()

func fetch_from_server() -> void:
	if not NetworkClient.is_server_configured() or _fetch_http == null:
		return
	if _fetch_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_fetch_http.cancel_request()
	var url: String = "%s/api/leaderboard" % NetworkClient.get_http_base_url()
	_fetch_http.request(url)

func _submit_to_server(rec: Dictionary) -> void:
	if _submit_http == null or not NetworkClient.is_server_configured():
		return
	if _submit_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_submit_http.cancel_request()
	var url: String = "%s/api/leaderboard" % NetworkClient.get_http_base_url()
	var headers: PackedStringArray = ["Content-Type: application/json"]
	_submit_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(rec))

func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var server_records: Variant = (parsed as Dictionary).get("records", null)
	if not (server_records is Array):
		return
	_merge_server_records(server_records as Array)

func _on_submit_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 201):
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var server_records: Variant = (parsed as Dictionary).get("records", null)
	if server_records is Array:
		_merge_server_records(server_records as Array)

func _merge_server_records(server_records: Array) -> void:
	var changed: bool = false
	for item in server_records:
		if not (item is Dictionary):
			continue
		var rec: Dictionary = item
		if String(rec.get("team", "")) in LEGACY_FAKE_TEAMS:
			continue
		if not _has_record(rec):
			records.append({
				"mission_id": String(rec.get("mission_id", "")),
				"team": String(rec.get("team", "")),
				"host_tag": String(rec.get("host_tag", "")),
				"player_count": int(rec.get("player_count", 1)),
				"time_sec": snapped(float(rec.get("time_sec", 0.0)), 0.1),
				"score": int(rec.get("score", 0))
			})
			changed = true
	if changed:
		_sort_records()
		_save_local()
		EventBus.leaderboard_updated.emit()

func format_duration(time_sec: float) -> String:
	var total_tenths: int = int(round(time_sec * 10.0))
	var mins: int = (total_tenths / 10) / 60
	var secs: int = (total_tenths / 10) % 60
	var tenths: int = total_tenths % 10
	return "%02d:%02d.%d" % [mins, secs, tenths]
