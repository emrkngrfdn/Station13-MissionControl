extends Node

const SAVE_PATH = "user://leaderboard.json"
var records: Array = []

func _ready() -> void:
	load_records()

func load_records() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		records = JSON.parse_string(file.get_as_text())
	else:
		# Örnek başlangıç kayıtları
		records = [
			{ "mission_id": "lunar_south_pole", "team": "[1P] AstroBot#0001", "time_sec": 245.0, "score": 1250 },
			{ "mission_id": "mars_jezero", "team": "[2P] JPL_Crew", "time_sec": 310.5, "score": 1800 }
		]

func add_record(mission_id: String, time_sec: float, score: int) -> void:
	var mode_tag = "[1P]" if GameState.is_solo else "[%dP]" % GameState.lobby_players.size()
	var team_name = "%s %s" % [mode_tag, GameState.lobby_players[0]["tag"]]
	records.append({
		"mission_id": mission_id,
		"team": team_name,
		"time_sec": snapped(time_sec, 0.1),
		"score": score
	})
	records.sort_custom(func(a, b): return a["time_sec"] < b["time_sec"])
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(records))