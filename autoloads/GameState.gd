extends Node

var missions_data: Dictionary = {}
var parts_data: Dictionary = {}
var quests_data: Dictionary = {}

# Lobi & Oyuncular (Max 4)
var lobby_players: Array = [] # [{ "tag": "Commander#1042", "color": Color.RED, "is_host": true }]
var is_solo: bool = true

# Aktif Görev & Dinamik Ekonomi
var current_mission: Dictionary = {}
var current_modifier: Dictionary = {}
var budget_m: float = 0.0
var elapsed_time_sec: float = 0.0
var is_mission_active: bool = false

# Araç Telemetrisi
var total_mass_kg: float = 50.0
var net_power_w: float = 0.0
var data_gen_mbps: float = 0.0
var downlink_mbps: float = 0.0
var science_score: int = 0
var landing_success_chance: int = 40 # Temel iniş şansı %40
var downloaded_data_gb: float = 0.0

var installed_parts: Array = []
var selected_rocket: Dictionary = {}
var decision_logs: Array[String] = []

func _ready() -> void:
	missions_data = _load_json("res://data/missions.json")
	parts_data = _load_json("res://data/parts_catalog.json")
	quests_data = _load_json("res://data/side_quests.json")
	reset_lobby()

func _process(delta: float) -> void:
	if is_mission_active:
		elapsed_time_sec += delta

func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file else {}

func reset_lobby() -> void:
	lobby_players = [{ "tag": PlayerProfile.full_tag, "color": Color.CORAL, "is_host": true }]
	is_solo = true
	if missions_data.has("missions"):
		setup_mission(0, 0)

func add_player_to_lobby(player_tag: String) -> bool:
	if lobby_players.size() >= 4 or player_tag.strip_edges() == "":
		return false
	var colors = [Color.CORAL, Color.DODGER_BLUE, Color.GOLD, Color.MEDIUM_SEA_GREEN]
	lobby_players.append({
		"tag": player_tag.strip_edges(),
		"color": colors[lobby_players.size()],
		"is_host": false
	})
	is_solo = lobby_players.size() == 1
	EventBus.lobby_updated.emit(lobby_players)
	return true

func setup_mission(mission_idx: int, modifier_idx: int) -> void:
	current_mission = missions_data["missions"][mission_idx]
	current_modifier = missions_data["budget_modifiers"][modifier_idx]
	# Dinamik Bütçe Hesabı: Temel Bütçe * Zorluk Çarpanı
	budget_m = round(current_mission["base_budget_m"] * current_modifier["budget_mult"])
	selected_rocket = parts_data["rockets"][0]
	installed_parts.clear()
	decision_logs.clear()
	recalculate()

func start_mission() -> void:
	is_solo = lobby_players.size() == 1
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	is_mission_active = true
	EventBus.mission_started.emit()

func buy_part(part: Dictionary) -> bool:
	if budget_m < part["cost_m"]:
		return false
	budget_m -= part["cost_m"]
	EventBus.cargo_spawned.emit(part)
	EventBus.telemetry_changed.emit()
	return true

func install_part(part: Dictionary) -> void:
	installed_parts.append(part)
	recalculate()

func apply_side_quest_option(opt: Dictionary) -> void:
	budget_m += opt.get("budget_delta", 0)
	total_mass_kg += opt.get("mass_delta", 0)
	net_power_w += opt.get("power_delta", 0)
	landing_success_chance = clamp(landing_success_chance + opt.get("landing_chance_delta", 0), 0, 100)
	decision_logs.append(opt.get("result_note", ""))
	EventBus.side_quest_resolved.emit(opt)
	EventBus.telemetry_changed.emit()

func recalculate() -> void:
	total_mass_kg = 50.0
	net_power_w = 0.0
	data_gen_mbps = 0.0
	downlink_mbps = 0.0
	science_score = 0
	landing_success_chance = 40
	var solar_eff = current_mission.get("solar_efficiency", 1.0)
	
	for p in installed_parts:
		total_mass_kg += p["mass_kg"]
		science_score += p["science"]
		landing_success_chance += p.get("landing_bonus", 0)
		if p["type"] == "power" and not p.get("nuclear", false):
			net_power_w += p["power_w"] * solar_eff
		else:
			net_power_w += p["power_w"]
		if p["data_mbps"] > 0:
			data_gen_mbps += p["data_mbps"]
		elif p["data_mbps"] < 0:
			downlink_mbps += abs(p["data_mbps"])
	landing_success_chance = clamp(landing_success_chance, 0, 100)
	EventBus.telemetry_changed.emit()