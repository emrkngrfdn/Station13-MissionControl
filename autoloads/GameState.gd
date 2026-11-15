extends Node

const MissionValidator = preload("res://scripts/MissionValidator.gd")

var missions_data: Dictionary = {}
var parts_data: Dictionary = {}
var quests_data: Dictionary = {}

# Lobi & Oyuncular (Max 4)
var lobby_players: Array = [] # [{ "tag": "Commander#1042", "color": Color.CORAL, "is_host": true }]
var is_solo: bool = true

# Aktif Görev & Dinamik Ekonomi
var current_mission: Dictionary = {}
var current_modifier: Dictionary = {}
var budget_m: float = 0.0
var elapsed_time_sec: float = 0.0
var is_mission_active: bool = false

# Araç Telemetrisi
var total_mass_kg: float = 0.0
var net_power_w: float = 0.0
var data_gen_mbps: float = 0.0
var downlink_mbps: float = 0.0
var science_score: int = 0
var landing_success_chance: int = 40
var downloaded_data_gb: float = 0.0

var installed_parts: Array = []
var selected_rocket: Dictionary = {}
var selected_launch_site: Dictionary = {}
var decision_logs: Array[String] = []

# Yan görevlerden gelen kalıcı delta değerleri (recalculate'te kaybolmaz)
var _quest_mass_delta: float = 0.0
var _quest_power_delta: float = 0.0
var _quest_landing_delta: int = 0

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
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func reset_lobby() -> void:
	lobby_players = [{ "tag": PlayerProfile.full_tag, "color": Color.CORAL, "is_host": true }]
	is_solo = true
	if missions_data.has("missions") and missions_data["missions"].size() > 0:
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
	var missions: Array = missions_data.get("missions", [])
	var modifiers: Array = missions_data.get("budget_modifiers", [])
	if missions.is_empty() or modifiers.is_empty():
		return

	current_mission = missions[clamp(mission_idx, 0, missions.size() - 1)]
	current_modifier = modifiers[clamp(modifier_idx, 0, modifiers.size() - 1)]

	# Dinamik Bütçe Hesabı: Temel Bütçe * Zorluk Çarpanı
	budget_m = round(float(current_mission.get("base_budget_m", 160)) * float(current_modifier.get("budget_mult", 1.0)))

	var rec_rocket_id: String = current_mission.get("recommended_rocket_id", "")
	selected_rocket = _find_by_id(parts_data.get("rockets", []), rec_rocket_id, 0)

	var rec_site_id: String = current_mission.get("recommended_launch_site_id", "")
	selected_launch_site = _find_by_id(missions_data.get("launch_sites", []), rec_site_id, 0)

	installed_parts.clear()
	decision_logs.clear()
	_quest_mass_delta = 0.0
	_quest_power_delta = 0.0
	_quest_landing_delta = 0
	recalculate()

func _find_by_id(items: Array, target_id: String, fallback_idx: int = 0) -> Dictionary:
	for item in items:
		if item.get("id", "") == target_id:
			return item
	return items[fallback_idx] if items.size() > fallback_idx else {}

func select_rocket(rocket_id: String) -> void:
	selected_rocket = _find_by_id(parts_data.get("rockets", []), rocket_id, 0)
	EventBus.rocket_changed.emit(selected_rocket)
	recalculate()

func select_launch_site(site_id: String) -> void:
	selected_launch_site = _find_by_id(missions_data.get("launch_sites", []), site_id, 0)
	EventBus.launch_site_changed.emit(selected_launch_site)
	recalculate()

func get_available_parts_for_mission() -> Array:
	var mission_id: String = current_mission.get("id", "")
	var result: Array = []
	for p in parts_data.get("parts", []):
		var m_ids: Array = p.get("mission_ids", ["all"])
		if m_ids.has("all") or m_ids.has(mission_id):
			result.append(p)
	return result

func get_available_side_quests_for_mission() -> Array:
	var mission_id: String = current_mission.get("id", "")
	var result: Array = []
	for q in quests_data.get("side_quests", []):
		var m_ids: Array = q.get("mission_ids", ["all"])
		if m_ids.has("all") or m_ids.has(mission_id):
			result.append(q)
	return result

func start_mission() -> void:
	is_solo = lobby_players.size() == 1
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	is_mission_active = true
	EventBus.mission_started.emit()

func buy_part(part: Dictionary) -> bool:
	var cost: float = float(part.get("cost_m", 0))
	if budget_m < cost:
		return false
	budget_m -= cost
	EventBus.cargo_spawned.emit(part)
	EventBus.telemetry_changed.emit()
	return true

func install_part(part: Dictionary) -> void:
	installed_parts.append(part)
	recalculate()

func uninstall_part(index: int) -> void:
	if index >= 0 and index < installed_parts.size():
		var removed: Dictionary = installed_parts[index]
		budget_m += float(removed.get("cost_m", 0))
		installed_parts.remove_at(index)
		recalculate()

func apply_side_quest_option(opt: Dictionary) -> void:
	budget_m += float(opt.get("budget_delta", 0))
	_quest_mass_delta += float(opt.get("mass_delta", 0))
	_quest_power_delta += float(opt.get("power_delta", 0))
	_quest_landing_delta += int(opt.get("landing_chance_delta", 0))

	if opt.has("set_launch_site"):
		select_launch_site(opt["set_launch_site"])

	var note: String = opt.get("result_note", "")
	if note != "":
		decision_logs.append(note)

	EventBus.side_quest_resolved.emit(opt)
	recalculate()

func recalculate() -> void:
	total_mass_kg = float(current_mission.get("bus_dry_mass_kg", 50.0)) + _quest_mass_delta
	net_power_w = float(current_mission.get("nominal_power_w", 0.0)) + _quest_power_delta
	data_gen_mbps = 0.0
	downlink_mbps = 0.0
	science_score = 0
	landing_success_chance = 40 + _quest_landing_delta

	var solar_eff: float = float(current_mission.get("solar_efficiency", 1.0))

	for p in installed_parts:
		total_mass_kg += float(p.get("mass_kg", 0.0))
		science_score += int(p.get("science", 0))
		landing_success_chance += int(p.get("landing_bonus", 0))

		var p_power: float = float(p.get("power_w", 0.0))
		if p.get("type", "") == "power" and not p.get("nuclear", false):
			net_power_w += p_power * solar_eff
		else:
			net_power_w += p_power

		var d_rate: float = float(p.get("data_mbps", 0.0))
		if d_rate > 0.0:
			data_gen_mbps += d_rate
		elif d_rate < 0.0:
			downlink_mbps += abs(d_rate)

	landing_success_chance = clamp(landing_success_chance, 0, 100)
	EventBus.telemetry_changed.emit()

func validate_launch() -> Dictionary:
	return MissionValidator.validate_build(
		current_mission,
		selected_rocket,
		selected_launch_site,
		installed_parts,
		total_mass_kg,
		net_power_w
	)

func complete_mission() -> Dictionary:
	is_mission_active = false
	var score_mult: float = float(current_modifier.get("score_mult", 1.0))
	var report: Dictionary = MissionValidator.evaluate_mission_outcome(
		current_mission,
		selected_rocket,
		selected_launch_site,
		installed_parts,
		total_mass_kg,
		net_power_w,
		science_score,
		downloaded_data_gb,
		landing_success_chance,
		score_mult
	)
	if report["success"]:
		LeaderboardManager.add_record(
			current_mission.get("id", "unknown"),
			elapsed_time_sec,
			int(report["score"])
		)
	EventBus.mission_completed.emit(report["success"], report)
	return report
