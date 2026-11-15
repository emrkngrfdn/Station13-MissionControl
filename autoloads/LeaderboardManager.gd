extends Node

const SAVE_PATH = "user://leaderboard.json"
var records: Array = []

const DEFAULT_RECORDS: Array = [
	{ "mission_id": "leo_climate_aqua", "team": "[1P] AstroBot#0001", "time_sec": 165.4, "score": 980 },
	{ "mission_id": "leo_climate_aqua", "team": "[2P] Goddard_Crew#2002", "time_sec": 192.0, "score": 1120 },
	{ "mission_id": "lunar_pole_lro", "team": "[2P] Artemis_Team#1099", "time_sec": 215.5, "score": 1280 },
	{ "mission_id": "lunar_pole_lro", "team": "[1P] LunarScout#4210", "time_sec": 248.0, "score": 1150 },
	{ "mission_id": "europa_juno", "team": "[4P] DeepSpace_4#8801", "time_sec": 274.2, "score": 1640 },
	{ "mission_id": "mars_perseverance", "team": "[3P] JPL_Crew#2020", "time_sec": 228.8, "score": 1520 },
	{ "mission_id": "mars_perseverance", "team": "[1P] RedPlanet#3055", "time_sec": 264.0, "score": 1390 }
]

func _ready() -> void:
	load_records()

func load_records() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if parsed is Array and not (parsed as Array).is_empty():
			records = parsed
			_ensure_valid_mission_records()
			return
	records = DEFAULT_RECORDS.duplicate(true)
	_sort_records()

func _ensure_valid_mission_records() -> void:
	var has_known: bool = false
	for r in records:
		var mid: String = String(r.get("mission_id", ""))
		if mid in ["leo_climate_aqua", "lunar_pole_lro", "europa_juno", "mars_perseverance"]:
			has_known = true
			break
	if not has_known:
		records.append_array(DEFAULT_RECORDS.duplicate(true))
	_sort_records()

func _sort_records() -> void:
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = float(a.get("time_sec", 999999.0))
		var tb: float = float(b.get("time_sec", 999999.0))
		if is_equal_approx(ta, tb):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return ta < tb
	)

func get_records_for_mission(mission_id: String) -> Array:
	_sort_records()
	var filtered: Array = []
	for rec in records:
		if mission_id == "" or String(rec.get("mission_id", "")) == mission_id:
			filtered.append(rec)
	return filtered

func add_record(mission_id: String, time_sec: float, score: int) -> void:
	var player_count: int = max(1, GameState.lobby_players.size())
	var mode_tag: String = "[1P]" if GameState.is_solo else "[%dP]" % player_count
	var host_tag: String = String(GameState.lobby_players[0].get("tag", PlayerProfile.full_tag)) if not GameState.lobby_players.is_empty() else PlayerProfile.full_tag
	var team_name: String = "%s %s" % [mode_tag, host_tag]
	records.append({
		"mission_id": mission_id,
		"team": team_name,
		"time_sec": snapped(time_sec, 0.1),
		"score": score
	})
	_sort_records()
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(records))

func format_duration(time_sec: float) -> String:
	var total_tenths: int = int(round(time_sec * 10.0))
	var mins: int = (total_tenths / 10) / 60
	var secs: int = (total_tenths / 10) % 60
	var tenths: int = total_tenths % 10
	return "%02d:%02d.%d" % [mins, secs, tenths]
