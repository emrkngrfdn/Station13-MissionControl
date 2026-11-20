extends Node

const MissionValidator = preload("res://scripts/MissionValidator.gd")

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const CRISIS_MIN_INTERVAL_SEC: float = 95.0
const CRISIS_MAX_INTERVAL_SEC: float = 135.0
const MAX_RANDOM_CRISES_PER_MISSION: int = 2
const DSN_EXTRA_STEP_GB: float = 30.0
const DSN_EXTRA_SCIENCE_PER_STEP: int = 40
const DSN_MAX_EXTRA_STEPS: int = 4
const SLOT_COLORS: Array[Color] = [
	Color.CORAL,
	Color.DODGER_BLUE,
	Color.GOLD,
	Color.MEDIUM_SEA_GREEN
]

var missions_data: Dictionary = {}
var parts_data: Dictionary = {}
var quests_data: Dictionary = {}

# Lobi & Oyuncular (Max 4) + Ağ Durumu
var room_code: String = ""
var is_room_open: bool = false
var is_room_host: bool = false
var is_room_public: bool = false
var last_join_error: String = ""
var lobby_players: Array = [] # [{ "tag": "Commander#1042", "color": Color.CORAL, "is_host": true, "peer_id": 1 }]
var is_solo: bool = true
var is_network_active: bool = false
var my_peer_id: int = 1
var _cargo_seq: int = 0

# Aktif Görev & Dinamik Ekonomi
var current_mission: Dictionary = {}
var current_modifier: Dictionary = {}
var current_mission_idx: int = 0
var current_modifier_idx: int = 0
var budget_m: float = 0.0
var elapsed_time_sec: float = 0.0
var is_mission_active: bool = false

# Araç Telemetrisi
var total_mass_kg: float = 0.0
var net_power_w: float = 0.0
var data_gen_mbps: float = 0.0
var downlink_mbps: float = 0.0
var science_score: int = 0
var landing_success_chance: int = 15
var downloaded_data_gb: float = 0.0
var dsn_freq_value: float = 50.0
var dsn_target_center: float = 24.0
var dsn_station_idx: int = 0
var dsn_station_timer: float = 0.0
var active_crisis_id: String = ""
var crisis_votes: Dictionary = {}
var last_crisis_vote_result: Dictionary = {}
var last_quest_landing_delta: int = 0
var last_quest_is_negative: bool = false

# Özel Mekanikler (Mars Power Cycling / MOXIE 300W, JunoCam Radyasyon, DSN SSD)
var power_cycling_enabled: bool = false
var battery_charge_pct: float = 100.0
var junocam_degraded: bool = false
var ssd_used_gb: float = 0.0
var ssd_capacity_gb: float = 64.0
var dsn_locked: bool = false
var briefing_completed: bool = false
var power_wiring_broken: bool = false

var purchased_parts: Array = []
var installed_parts: Array = []
var selected_rocket: Dictionary = {}
var _paid_rocket_cost: float = 0.0
var selected_launch_site: Dictionary = {}
var decision_logs: Array[String] = []
var resolved_quest_ids: Array[String] = []

# Yan görevlerden gelen kalıcı delta değerleri (recalculate'te kaybolmaz)
var _quest_mass_delta: float = 0.0
var _quest_power_delta: float = 0.0
var _quest_landing_delta: int = 0
var _quest_science_delta: int = 0
var _quest_downlink_mult: float = 1.0
var _crisis_timer: float = 0.0
var _next_crisis_interval: float = 105.0
var _triggered_crisis_ids: Array[String] = []

func _ready() -> void:
	missions_data = _load_json("res://data/missions.json")
	parts_data = _load_json("res://data/parts_catalog.json")
	quests_data = _load_json("res://data/side_quests.json")
	_setup_multiplayer_signals()
	reset_lobby()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		leave_room()

func _process(delta: float) -> void:
	if not is_mission_active:
		return
	elapsed_time_sec += delta

	# Uydu SSD belleği doluluk simülasyonu (sensörler veri ürettikçe SSD dolar)
	if data_gen_mbps > 0.0:
		var generated_gb: float = (data_gen_mbps * delta) / 120.0
		ssd_used_gb = clamp(ssd_used_gb + generated_gb, 0.0, ssd_capacity_gb)

	# Mars Power Cycling / MOXIE 300W batarya döngüsü simülasyonu
	if bool(current_mission.get("requires_power_cycling", false)):
		if power_cycling_enabled:
			battery_charge_pct = clamp(battery_charge_pct + delta * 4.0, 25.0, 100.0)
		elif has_installed_tag("peak_power_trap"):
			battery_charge_pct = max(0.0, battery_charge_pct - delta * 12.0)

	# Rastgele Acil Kriz zamanlayıcısı (daha seyrek, görev başına en fazla 2 farklı kriz)
	if _triggered_crisis_ids.size() < MAX_RANDOM_CRISES_PER_MISSION:
		_crisis_timer += delta
		if _crisis_timer >= _next_crisis_interval:
			_crisis_timer = 0.0
			_next_crisis_interval = randf_range(CRISIS_MIN_INTERVAL_SEC, CRISIS_MAX_INTERVAL_SEC)
			_check_and_trigger_random_crisis()

func _load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _normalize_tag(raw_tag: String) -> String:
	var cleaned: String = raw_tag.strip_edges()
	if cleaned == "":
		return ""
	if cleaned.contains("#"):
		var parts: PackedStringArray = cleaned.split("#", false, 1)
		var name_part: String = parts[0].strip_edges()
		var id_part: String = parts[1].strip_edges() if parts.size() > 1 else ""
		if name_part == "":
			return ""
		if id_part == "":
			id_part = str(randi_range(1000, 9999))
		return "%s#%s" % [name_part, id_part]
	return "%s#%d" % [cleaned, randi_range(1000, 9999)]

# ============================================================================
# 4 KİŞİLİK LOBİ & MULTIPLAYER ODA / SENKRONİZASYON ALTYAPISI (WebSocket)
# ============================================================================

func _setup_multiplayer_signals() -> void:
	NetworkClient.lobby_state_received.connect(_on_net_lobby_state)
	NetworkClient.mission_started_received.connect(_on_net_mission_started)
	NetworkClient.return_to_lobby_received.connect(_on_net_return_to_lobby)
	NetworkClient.room_closed_received.connect(_on_net_room_closed)
	NetworkClient.peer_left_received.connect(_on_net_peer_left)
	NetworkClient.relay_received.connect(_on_net_relay)

func _deserialize_players(raw_players: Array) -> Array:
	var out: Array = []
	for i in range(raw_players.size()):
		var p: Dictionary = raw_players[i]
		var c_idx: int = clampi(int(p.get("color_idx", i)), 0, SLOT_COLORS.size() - 1)
		out.append({
			"tag": String(p.get("tag", "")),
			"color": SLOT_COLORS[c_idx],
			"color_idx": c_idx,
			"is_host": bool(p.get("is_host", i == 0)),
			"role": String(p.get("role", "Mürettebat")),
			"peer_id": int(p.get("peer_id", 0))
		})
	return out

func _generate_random_room_code() -> String:
	var letters: String = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	var p1: String = ""
	for _i in range(3):
		p1 += letters[randi() % letters.length()]
	var num: int = randi_range(10, 99)
	return "%s-%02d" % [p1, num]

func apply_network_room_state(peer_id: int, new_code: String, net_state: Dictionary, as_host: bool) -> void:
	my_peer_id = peer_id
	room_code = new_code
	is_room_open = true
	is_room_host = as_host
	is_network_active = true
	is_room_public = bool(net_state.get("is_public", false))
	last_join_error = ""
	_apply_lobby_state_dict(net_state)
	EventBus.network_status_changed.emit(
		"Çevrimiçi Oda: %s (%s)" % [room_code, "Host" if as_host else "Mürettebat"],
		true
	)

func _apply_lobby_state_dict(net_state: Dictionary) -> void:
	is_room_public = bool(net_state.get("is_public", is_room_public))
	var synced_players: Array = _deserialize_players(net_state.get("players", []))
	if not synced_players.is_empty():
		lobby_players = synced_players
		is_solo = lobby_players.size() == 1
	var m_idx: int = int(net_state.get("mission_idx", current_mission_idx))
	var mod_idx: int = int(net_state.get("modifier_idx", current_modifier_idx))
	var r_id: String = String(net_state.get("rocket_id", ""))
	var s_id: String = String(net_state.get("site_id", ""))
	if not is_mission_active and (m_idx != current_mission_idx or mod_idx != current_modifier_idx):
		setup_mission(m_idx, mod_idx, false)
	if not is_mission_active and r_id != "" and r_id != String(selected_rocket.get("id", "")):
		select_rocket(r_id, false)
	if not is_mission_active and s_id != "" and s_id != String(selected_launch_site.get("id", "")):
		select_launch_site(s_id, false)
	EventBus.lobby_updated.emit(lobby_players)
	EventBus.telemetry_changed.emit()

func create_offline_solo_room() -> String:
	leave_room()
	reset_lobby()
	randomize()
	room_code = "SOLO"
	is_room_open = true
	is_room_host = true
	is_room_public = false
	is_network_active = false
	my_peer_id = 1
	EventBus.network_status_changed.emit("Çevrimdışı Solo Mod", false)
	EventBus.lobby_updated.emit(lobby_players)
	return room_code

func create_room(public_room: bool = false) -> String:
	return create_offline_solo_room() if not NetworkClient.is_server_configured() else ""

func set_room_public(public_room: bool) -> void:
	if is_room_open and not is_room_host:
		return
	is_room_public = public_room
	if is_network_active and is_room_host:
		_broadcast_lobby_state()
	EventBus.telemetry_changed.emit()

func set_host_color(new_color: Color) -> void:
	set_my_color(new_color)

func _color_to_slot_idx(c: Color) -> int:
	for i in range(SLOT_COLORS.size()):
		if SLOT_COLORS[i].is_equal_approx(c):
			return i
	if c.b > 0.7 and c.r < 0.5:
		return 1
	if c.r > 0.8 and c.g > 0.7:
		return 2
	if c.g > 0.7 and c.r < 0.5:
		return 3
	return 0

func set_my_color(new_color: Color) -> void:
	var target_idx: int = _color_to_slot_idx(new_color)
	if is_network_active:
		for p in lobby_players:
			if int(p.get("peer_id", -1)) == my_peer_id:
				continue
			var other_c: Color = p.get("color", Color.BLACK)
			if other_c.is_equal_approx(SLOT_COLORS[target_idx]):
				return
		NetworkClient.send_set_color(target_idx)
		return

	var my_idx: int = 0
	for i in range(lobby_players.size()):
		if i == my_idx:
			continue
		var other_c: Color = lobby_players[i].get("color", Color.BLACK)
		if other_c.is_equal_approx(new_color):
			return
	if my_idx >= 0 and my_idx < lobby_players.size():
		lobby_players[my_idx]["color"] = new_color
		lobby_players[my_idx]["color_idx"] = target_idx
		EventBus.lobby_updated.emit(lobby_players)

func _pick_distinct_color(ignore_idx: int = -1) -> Color:
	for candidate in SLOT_COLORS:
		var used: bool = false
		for i in range(lobby_players.size()):
			if i == ignore_idx:
				continue
			var c: Color = lobby_players[i].get("color", Color.WHITE)
			if c.is_equal_approx(candidate):
				used = true
				break
		if not used:
			return candidate
	return SLOT_COLORS[lobby_players.size() % SLOT_COLORS.size()]

func get_local_player_color() -> Color:
	if is_network_active:
		for p in lobby_players:
			if int(p.get("peer_id", -1)) == my_peer_id:
				return p.get("color", Color.CORAL)
	for p in lobby_players:
		if String(p.get("tag", "")) == PlayerProfile.full_tag:
			return p.get("color", Color.CORAL)
	if lobby_players.size() > 0:
		return lobby_players[0].get("color", Color.CORAL)
	return Color.CORAL

func get_player_color_by_peer(peer_id: int) -> Color:
	for p in lobby_players:
		if int(p.get("peer_id", -1)) == peer_id:
			return p.get("color", Color.CORAL)
	return Color.CORAL

func get_player_tag_by_peer(peer_id: int) -> String:
	for p in lobby_players:
		if int(p.get("peer_id", -1)) == peer_id:
			return String(p.get("tag", "Mürettebat"))
	return "Mürettebat#%d" % peer_id

func leave_room() -> void:
	if is_network_active or NetworkClient.is_connected_online:
		NetworkClient.disconnect_from_room()
	is_network_active = false
	is_room_open = false
	is_room_host = false
	is_room_public = false
	is_mission_active = false
	room_code = ""
	my_peer_id = 1
	EventBus.network_status_changed.emit("Çevrimdışı / Yerel Lobi Modu", false)

func _on_net_lobby_state(net_state: Dictionary) -> void:
	_apply_lobby_state_dict(net_state)

func _on_net_mission_started(net_state: Dictionary) -> void:
	_apply_lobby_state_dict(net_state)
	is_solo = lobby_players.size() == 1
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	ssd_used_gb = 12.0
	briefing_completed = false
	power_wiring_broken = false
	_crisis_timer = 0.0
	_triggered_crisis_ids.clear()
	_next_crisis_interval = randf_range(CRISIS_MIN_INTERVAL_SEC, CRISIS_MAX_INTERVAL_SEC)
	is_mission_active = true
	EventBus.mission_started.emit()
	if ResourceLoader.exists("res://scenes/world/station.tscn"):
		get_tree().change_scene_to_file("res://scenes/world/station.tscn")

func _on_net_return_to_lobby(net_state: Dictionary) -> void:
	is_mission_active = false
	_apply_lobby_state_dict(net_state)
	setup_mission(current_mission_idx, current_modifier_idx, false)
	EventBus.room_returned_to_lobby.emit()
	if is_inside_tree() and ResourceLoader.exists("res://scenes/world/waiting_room.tscn"):
		get_tree().call_deferred("change_scene_to_file", "res://scenes/world/waiting_room.tscn")

func abort_mission_to_lobby() -> void:
	is_mission_active = false
	if is_network_active:
		if is_room_host:
			setup_mission(current_mission_idx, current_modifier_idx, false)
			NetworkClient.send_return_to_lobby()
			_broadcast_lobby_state()
			EventBus.room_returned_to_lobby.emit()
			if is_inside_tree() and ResourceLoader.exists("res://scenes/world/waiting_room.tscn"):
				get_tree().call_deferred("change_scene_to_file", "res://scenes/world/waiting_room.tscn")
		else:
			leave_room()
			reset_lobby()
			if is_inside_tree():
				get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/main_menu.tscn")
		return
	setup_mission(current_mission_idx, current_modifier_idx, false)
	if is_inside_tree() and ResourceLoader.exists("res://scenes/world/waiting_room.tscn"):
		get_tree().call_deferred("change_scene_to_file", "res://scenes/world/waiting_room.tscn")

func _on_net_room_closed(reason: String) -> void:
	last_join_error = reason
	is_network_active = false
	is_room_open = false
	is_room_host = false
	is_room_public = false
	is_mission_active = false
	room_code = ""
	my_peer_id = 1
	reset_lobby()
	EventBus.network_status_changed.emit(reason, false)
	EventBus.status_message.emit(reason, true)
	if is_inside_tree() and get_tree().current_scene != null:
		var scene_path: String = get_tree().current_scene.scene_file_path
		if scene_path != "res://scenes/ui/main_menu.tscn":
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_net_peer_left(peer_id: int) -> void:
	EventBus.remote_player_left.emit(peer_id)

func _broadcast_lobby_state() -> void:
	EventBus.lobby_updated.emit(lobby_players)
	if is_network_active and is_room_host:
		NetworkClient.send_update_lobby(
			is_room_public,
			current_mission_idx,
			current_modifier_idx,
			String(current_mission.get("name", "")),
			String(selected_rocket.get("id", "")),
			String(selected_launch_site.get("id", "")),
			PlayerProfile.full_tag
		)

func reset_lobby() -> void:
	lobby_players = [{
		"tag": PlayerProfile.full_tag,
		"color": SLOT_COLORS[0],
		"color_idx": 0,
		"is_host": true,
		"role": "Komutan",
		"peer_id": 1
	}]
	is_solo = true
	if missions_data.has("missions") and missions_data["missions"].size() > 0:
		setup_mission(0, 0, false)
	EventBus.lobby_updated.emit(lobby_players)

func update_host_nickname(new_name: String) -> void:
	PlayerProfile.set_nickname(new_name)
	if lobby_players.size() > 0:
		lobby_players[0]["tag"] = PlayerProfile.full_tag
		_broadcast_lobby_state()

func add_player_to_lobby(player_tag: String) -> bool:
	var normalized: String = _normalize_tag(player_tag)
	if lobby_players.size() >= MAX_PLAYERS or normalized == "":
		return false
	for p in lobby_players:
		if String(p.get("tag", "")).to_lower() == normalized.to_lower():
			return false
	var roles: Array[String] = ["Komutan", "Sistem Müh.", "Yük Uzmanı", "Uçuş Müh."]
	var idx: int = lobby_players.size()
	var c: Color = _pick_distinct_color()
	lobby_players.append({
		"tag": normalized,
		"color": c,
		"color_idx": _color_to_slot_idx(c),
		"is_host": false,
		"role": roles[idx],
		"peer_id": 0
	})
	is_solo = lobby_players.size() == 1
	_broadcast_lobby_state()
	return true

func remove_player_from_lobby(slot_idx: int) -> bool:
	if slot_idx <= 0 or slot_idx >= lobby_players.size():
		return false
	lobby_players.remove_at(slot_idx)
	_reindex_lobby_slots()
	_broadcast_lobby_state()
	return true

func _reindex_lobby_slots() -> void:
	var roles: Array[String] = ["Komutan", "Sistem Müh.", "Yük Uzmanı", "Uçuş Müh."]
	for i in range(lobby_players.size()):
		lobby_players[i]["color"] = SLOT_COLORS[i]
		lobby_players[i]["color_idx"] = i
		lobby_players[i]["role"] = roles[i]
	is_solo = lobby_players.size() == 1

# ============================================================================
# GÖREV KURULUMU, PARÇA MAĞAZASI & KRİZ MEKANİKLERİ
# ============================================================================

func setup_mission(mission_idx: int, modifier_idx: int, broadcast: bool = true) -> void:
	var missions: Array = missions_data.get("missions", [])
	var modifiers: Array = missions_data.get("budget_modifiers", [])
	if missions.is_empty() or modifiers.is_empty():
		return

	current_mission_idx = clamp(mission_idx, 0, missions.size() - 1)
	current_modifier_idx = clamp(modifier_idx, 0, modifiers.size() - 1)
	current_mission = missions[current_mission_idx]
	current_modifier = modifiers[current_modifier_idx]

	# Dinamik Bütçe Hesabı: Temel Bütçe * Zorluk Çarpanı
	budget_m = round(float(current_mission.get("base_budget_m", 160)) * float(current_modifier.get("budget_mult", 1.0)))

	var rec_rocket_id: String = String(current_mission.get("recommended_rocket_id", ""))
	selected_rocket = _find_by_id(parts_data.get("rockets", []), rec_rocket_id, 0)
	_paid_rocket_cost = float(selected_rocket.get("cost_m", 0.0))

	var rec_site_id: String = String(current_mission.get("recommended_launch_site_id", ""))
	selected_launch_site = _find_by_id(missions_data.get("launch_sites", []), rec_site_id, 0)

	purchased_parts.clear()
	installed_parts.clear()
	decision_logs.clear()
	resolved_quest_ids.clear()
	_triggered_crisis_ids.clear()
	_quest_mass_delta = 0.0
	_quest_power_delta = 0.0
	_quest_landing_delta = 0
	_quest_science_delta = 0
	_quest_downlink_mult = 1.0
	_crisis_timer = 0.0
	_next_crisis_interval = randf_range(CRISIS_MIN_INTERVAL_SEC, CRISIS_MAX_INTERVAL_SEC)
	power_cycling_enabled = false
	battery_charge_pct = 100.0
	junocam_degraded = false
	ssd_used_gb = 0.0
	dsn_locked = false
	briefing_completed = false
	power_wiring_broken = false
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	active_crisis_id = ""
	crisis_votes.clear()
	last_crisis_vote_result.clear()
	last_quest_landing_delta = 0
	last_quest_is_negative = false
	recalculate()
	if broadcast and is_network_active and is_room_host:
		_broadcast_lobby_state()

func _find_by_id(items: Array, target_id: String, fallback_idx: int = 0) -> Dictionary:
	for item in items:
		if String(item.get("id", "")) == target_id:
			return item
	if fallback_idx >= 0 and items.size() > fallback_idx:
		return items[fallback_idx]
	return {}

func get_rocket_upgrade_cost(new_rocket: Dictionary) -> float:
	var new_cost: float = float(new_rocket.get("cost_m", 0.0))
	return max(0.0, new_cost - _paid_rocket_cost)

func select_rocket(rocket_id: String, broadcast: bool = true) -> bool:
	var new_rocket: Dictionary = _find_by_id(parts_data.get("rockets", []), rocket_id, 0)
	if broadcast:
		var upgrade_cost: float = get_rocket_upgrade_cost(new_rocket)
		if upgrade_cost > budget_m:
			EventBus.status_message.emit(
				"BÜTÇE YETERSİZ! Roket yükseltmesi için $%.0fM gerekiyor (Mevcut: $%.0fM)." % [upgrade_cost, budget_m],
				true
			)
			return false
		if upgrade_cost > 0.0:
			budget_m -= upgrade_cost
			_paid_rocket_cost += upgrade_cost
			decision_logs.append("Roket yükseltildi: %s (-$%.0fM)." % [String(new_rocket.get("name", "")), upgrade_cost])
	else:
		_paid_rocket_cost = max(_paid_rocket_cost, float(new_rocket.get("cost_m", 0.0)))
	selected_rocket = new_rocket
	EventBus.rocket_changed.emit(selected_rocket)
	recalculate()
	if broadcast and is_network_active:
		if is_mission_active:
			NetworkClient.send_relay("select_rocket", {
				"rocket_id": rocket_id,
				"paid_cost": _paid_rocket_cost,
				"budget_m": budget_m,
				"log_line": decision_logs[-1] if not decision_logs.is_empty() else ""
			})
		elif is_room_host:
			_broadcast_lobby_state()
	return true

func select_launch_site(site_id: String, broadcast: bool = true) -> void:
	selected_launch_site = _find_by_id(missions_data.get("launch_sites", []), site_id, 0)
	EventBus.launch_site_changed.emit(selected_launch_site)
	recalculate()
	if broadcast and is_network_active and is_room_host:
		_broadcast_lobby_state()

func get_available_parts_for_mission() -> Array:
	var mission_id: String = String(current_mission.get("id", ""))
	var result: Array = []
	for p in parts_data.get("parts", []):
		var m_ids: Array = p.get("mission_ids", ["all"])
		if m_ids.has("all") or m_ids.has(mission_id):
			result.append(p)
	return result

func get_available_side_quests_for_mission() -> Array:
	var mission_id: String = String(current_mission.get("id", ""))
	var result: Array = []
	for q in quests_data.get("side_quests", []):
		var m_ids: Array = q.get("mission_ids", ["all"])
		if m_ids.has("all") or m_ids.has(mission_id):
			result.append(q)
	return result

func get_side_quest_for_room(room_name: String) -> Dictionary:
	var quests: Array = get_available_side_quests_for_mission()
	for q in quests:
		if String(q.get("room", "")) == room_name and not resolved_quest_ids.has(String(q.get("id", ""))):
			return q
	for q in quests:
		if String(q.get("room", "")) == room_name:
			return q
	return quests[0] if not quests.is_empty() else {}

func _check_and_trigger_random_crisis() -> void:
	if is_network_active and not is_room_host:
		return
	var available: Array = get_available_side_quests_for_mission()
	var candidates: Array = []
	for q in available:
		var q_id: String = String(q.get("id", ""))
		if bool(q.get("is_random_crisis", false)) and not _triggered_crisis_ids.has(q_id) and not resolved_quest_ids.has(q_id):
			candidates.append(q)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var chosen: Dictionary = candidates[0]
	var chosen_id: String = String(chosen.get("id", ""))
	_triggered_crisis_ids.append(chosen_id)
	EventBus.crisis_alert.emit(chosen_id.to_upper())
	EventBus.side_quest_triggered.emit(chosen)
	if is_network_active:
		NetworkClient.send_relay("crisis_trigger", { "quest_id": chosen_id })

func has_installed_tag(tag_name: String) -> bool:
	var tags: Dictionary = MissionValidator.collect_installed_tags(installed_parts)
	return tags.has(tag_name)

func has_installed_type(part_type: String) -> bool:
	for p in installed_parts:
		if String(p.get("type", "")) == part_type:
			return true
	return false

func start_mission() -> void:
	is_solo = lobby_players.size() == 1
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	ssd_used_gb = 12.0
	briefing_completed = false
	power_wiring_broken = false
	_crisis_timer = 0.0
	_triggered_crisis_ids.clear()
	_next_crisis_interval = randf_range(CRISIS_MIN_INTERVAL_SEC, CRISIS_MAX_INTERVAL_SEC)
	is_mission_active = true
	EventBus.mission_started.emit()
	if is_network_active and is_room_host:
		NetworkClient.send_start_mission(
			current_mission_idx,
			current_modifier_idx,
			String(current_mission.get("name", "")),
			String(selected_rocket.get("id", "")),
			String(selected_launch_site.get("id", ""))
		)

func buy_part(part: Dictionary) -> bool:
	var cost: float = float(part.get("cost_m", 0))
	if budget_m < cost:
		return false
	budget_m -= cost
	purchased_parts.append(part)
	_cargo_seq += 1
	var box_id: String = "%d_%d" % [my_peer_id, _cargo_seq]
	var jx: float = randf_range(-10.0, 10.0)
	var jy: float = randf_range(-10.0, 10.0)
	var spawn_payload: Dictionary = part.duplicate(true)
	spawn_payload["_box_id"] = box_id
	spawn_payload["_jx"] = jx
	spawn_payload["_jy"] = jy
	EventBus.cargo_spawned.emit(spawn_payload)
	EventBus.telemetry_changed.emit()
	if is_network_active:
		NetworkClient.send_relay("buy_part", {
			"part_id": String(part.get("id", "")),
			"box_id": box_id,
			"jx": jx,
			"jy": jy
		})
	return true

func is_part_installed(part_id: String) -> bool:
	if part_id == "":
		return false
	for p in installed_parts:
		if String(p.get("id", "")) == part_id:
			return true
	return false

func get_purchased_summary() -> Array:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for p in purchased_parts:
		var pid: String = String(p.get("id", ""))
		if pid == "":
			continue
		if not counts.has(pid):
			counts[pid] = {
				"id": pid,
				"name": String(p.get("name", pid)),
				"count": 0,
				"installed": is_part_installed(pid)
			}
			order.append(pid)
		counts[pid]["count"] = int(counts[pid]["count"]) + 1
	var summary: Array = []
	for pid in order:
		summary.append(counts[pid])
	return summary

func install_part(part: Dictionary, box_id: String = "") -> bool:
	var pid: String = String(part.get("id", ""))
	if is_part_installed(pid):
		EventBus.status_message.emit("ZATEN MONTE EDİLDİ: %s roket üzerinde zaten takılı!" % String(part.get("name", "Ekipman")), true)
		return false
	installed_parts.append(part)
	var tags: Array = part.get("tags", [])
	if tags.has("radiation_degrading_camera") and String(current_mission.get("id", "")) == "europa_juno":
		junocam_degraded = true
	recalculate()
	EventBus.status_message.emit("MONTE EDİLDİ: %s başarıyla takıldı!" % String(part.get("name", "Ekipman")), false)
	if is_network_active:
		NetworkClient.send_relay("install_part", {
			"part_id": pid,
			"box_id": box_id
		})
	return true

func _apply_remote_install_part(part_id: String, box_id: String) -> void:
	var part: Dictionary = _find_by_id(parts_data.get("parts", []), part_id, -1)
	if not part.is_empty() and not is_part_installed(part_id):
		installed_parts.append(part)
		var tags: Array = part.get("tags", [])
		if tags.has("radiation_degrading_camera") and String(current_mission.get("id", "")) == "europa_juno":
			junocam_degraded = true
		recalculate()
		EventBus.status_message.emit("EKİP MONTE ETTİ: %s roket üzerine takıldı!" % String(part.get("name", "Ekipman")), false)
	if box_id != "":
		EventBus.box_installed.emit(box_id)

func uninstall_part(index: int) -> void:
	if index >= 0 and index < installed_parts.size():
		var removed: Dictionary = installed_parts[index]
		budget_m += float(removed.get("cost_m", 0))
		installed_parts.remove_at(index)
		if not has_installed_tag("radiation_degrading_camera"):
			junocam_degraded = false
		recalculate()

func apply_side_quest_option(opt: Dictionary, quest_id: String = "", broadcast: bool = true) -> void:
	if quest_id != "" and not resolved_quest_ids.has(quest_id):
		resolved_quest_ids.append(quest_id)

	var resolved_opt: Dictionary = opt.duplicate(true)
	var b_delta: float = float(resolved_opt.get("budget_delta", 0.0))
	var m_delta: float = float(resolved_opt.get("mass_delta", 0.0))
	var p_delta: float = float(resolved_opt.get("power_delta", 0.0))
	var l_delta: int = int(resolved_opt.get("landing_chance_delta", 0))
	var s_delta: int = int(resolved_opt.get("science_delta", 0))
	var note: String = String(resolved_opt.get("result_note", ""))

	var mechanic: String = String(resolved_opt.get("crisis_mechanic", ""))
	match mechanic:
		"SOLAR_FLARE_GAMBLE":
			var has_shield_or_av: bool = has_installed_tag("radiation_shield") or has_installed_tag("thermal_survival") or has_installed_type("survival") or has_installed_type("avionics")
			if has_shield_or_av and net_power_w >= 30.0:
				s_delta += 240
				l_delta += 10
				note = "KORUMALI GÖZLEM BAŞARILI: Kalkan/aviyonik donanımı ve yeterli güç (+30W) sayesinde CME patlaması hasarsız kaydedildi (+240 Bilim, +%10 İniş)!"
			else:
				s_delta -= 120
				p_delta -= 40.0
				l_delta -= 20
				note = "İŞLEMCİ HASARI: Koruma/aviyonik modülü veya +30W güç rezervi eksik olduğu için protonlar sisteme hasar verdi (-40W, -120 Bilim, -%20 İniş)!"
		"MICROMETEOROID_BURN":
			var has_nav: bool = has_installed_tag("laser_altimeter") or has_installed_tag("rover_navigation") or has_installed_type("avionics")
			var has_mass_margin: bool = get_effective_mass_kg() + 40.0 <= get_effective_mass_limit_kg()
			if has_nav and has_mass_margin:
				l_delta += 15
				s_delta += 50
				note = "ACİL MANEVRA BAŞARILI: Aviyonik yönelim ve yeterli kütle/yakıt marjı sayesinde araç hedef yörüngeye oturttu (+%15 İniş, +50 Bilim)!"
			else:
				m_delta += 85.0
				l_delta -= 20
				note = "DELTA-V SAPMASI: Aviyonik eksikliği veya kütle marjı yetersizliği nedeniyle manevra fazladan yakıt tüketti (+85 kg Kütle Cezası, -%20 İniş)!"
		"DUST_STORM_HIBERNATE":
			var has_nuclear_or_heater: bool = has_installed_tag("nuclear_power") or has_installed_tag("thermal_survival") or String(current_mission.get("power_source_type", "")) == "mmrtg"
			if has_nuclear_or_heater:
				l_delta += 15
				note = "KIŞ UYKUSU BAŞARILI: MMRTG / Termal Isıtıcı sayesinde toz fırtınası donma riski olmadan güvenle atlatıldı (+%15 İniş)!"
			elif net_power_w >= 40.0:
				p_delta -= 15.0
				l_delta += 5
				note = "SINIRDA UYANIŞ: Isıtıcı yoktu ancak +40W üzeri güç rezervi sayesinde bataryalar donmadan atlatıldı (-15W Güç, +%5 İniş)."
			else:
				p_delta -= 60.0
				l_delta -= 25
				note = "DONMA HASARI: MMRTG/Isıtıcı ve +40W güç rezervi olmadığı için bataryalar soğuktan ağır güç kaybetti (-60W, -%25 İniş)!"
		"DUST_STORM_SHAKE":
			if net_power_w >= 50.0 and (has_installed_type("avionics") or has_installed_type("power")):
				p_delta += 25.0
				l_delta += 10
				note = "PANELLER TEMİZLENDİ: +50W güç rezervi ve kontrol sistemi sayesinde toz tabakası temizlendi (+25W, +%10 İniş)!"
			else:
				p_delta -= 75.0
				l_delta -= 30
				note = "BATARYA REZERVİ TÜKENDİ: +50W güç rezervi veya kontrol modülü olmadığı için sarsıntı kritik bataryayı tüketti (-75W, -%30 İniş)!"
		"HGA_LOW_GAIN_FALLBACK":
			_quest_downlink_mult = 0.25
		"HGA_THERMAL_SHOCK":
			if net_power_w >= 35.0 and (has_installed_type("comms") or has_installed_type("survival")):
				s_delta += 160
				l_delta += 15
				note = "ANTEN KURTULDU: +35W güç rezervi ve iletişim/termal donanımıyla sıkışan anten açıldı (+160 Bilim, +%15 İniş)!"
			else:
				m_delta += 65.0
				p_delta -= 25.0
				l_delta -= 20
				note = "YÖNELİM BOZULDU: +35W güç rezervi veya iletişim/termal modül eksikliğinden manevra yakıt harcadı (+65 kg, -25W, -%20 İniş)!"
		"SEU_HARD_REBOOT":
			if has_installed_type("avionics") and net_power_w >= 25.0:
				p_delta -= 10.0
				l_delta += 5
				note = "HARD REBOOT BAŞARILI: Kurulu aviyonik ve +25W güç rezervi sayesinde bilgisayar güvenle yeniden başlatıldı (-10W, +%5 İniş)."
			else:
				p_delta -= 35.0
				s_delta -= 70
				l_delta -= 25
				note = "TAKLA (TUMBLE) KRİZİ: Aviyonik veya +25W güç rezervi olmadığı için reboot sonrası yönelim kaybedildi (-35W, -70 Bilim, -%25 İniş)!"
		"SEU_COLD_BACKUP":
			if has_installed_type("avionics"):
				l_delta += 20
				s_delta += 50
				note = "COLD-BACKUP DEVREDE: Kurulu aviyonik/yedek bilgisayar modülü devreye girdi; 1202 Alarmı hasarsız çözüldü (+%20 İniş, +50 Bilim)!"
			elif budget_m >= 20.0 and net_power_w >= 20.0:
				b_delta -= 20.0
				m_delta += 10.0
				l_delta += 5
				note = "COLD-BACKUP ACİL KURTARMA: Aviyonik modül yoktu ancak $20M bütçe ve +20W güç rezerviyle yedek sistem devreye alındı (-$20M, +10kg, +%5 İniş)."
			else:
				p_delta -= 60.0
				l_delta -= 35
				note = "SİSTEM ÇÖKTÜ: Aviyonik modül veya $20M bütçe / +20W güç rezervi olmadığı için Cold-Backup devreye giremedi (-60W, -%35 İniş)!"

	if not is_random_quest_budget_valid(opt):
		EventBus.status_message.emit("BÜTÇE YETERSİZ! Bu işlem için yeterli bütçeniz yok (Mevcut: $%.0fM)." % budget_m, true)
		return

	budget_m = max(0.0, budget_m + b_delta)
	_quest_mass_delta += m_delta
	_quest_power_delta += p_delta
	_quest_landing_delta += l_delta
	_quest_science_delta += s_delta
	last_quest_landing_delta = l_delta
	last_quest_is_negative = l_delta < 0 or (l_delta == 0 and (p_delta < 0.0 or s_delta < 0 or m_delta > 0.0))

	if resolved_opt.has("set_launch_site"):
		select_launch_site(String(resolved_opt["set_launch_site"]), false)

	# Mars Power Cycling mekaniği kontrolü
	if quest_id == "mars_power_cycling" and l_delta > 0:
		power_cycling_enabled = true
		battery_charge_pct = 100.0
	elif String(resolved_opt.get("triggers_crisis", "")) == "POWER_BROWNOUT":
		power_cycling_enabled = false
		battery_charge_pct = 15.0

	# JunoCam Radyasyon onarımı kontrolü
	if bool(resolved_opt.get("clears_junocam_degradation", false)):
		junocam_degraded = false

	resolved_opt["result_note"] = note
	if note != "":
		decision_logs.append(note)

	if resolved_opt.has("triggers_crisis"):
		EventBus.crisis_alert.emit(String(resolved_opt["triggers_crisis"]))

	EventBus.side_quest_resolved.emit(resolved_opt)
	recalculate()
	if broadcast and is_network_active:
		NetworkClient.send_relay("side_quest_option", {
			"quest_id": quest_id,
			"opt": opt
		})

func recalculate() -> void:
	total_mass_kg = float(current_mission.get("bus_dry_mass_kg", 50.0)) + _quest_mass_delta
	net_power_w = float(current_mission.get("nominal_power_w", 0.0)) + _quest_power_delta
	data_gen_mbps = 0.0
	downlink_mbps = 0.0
	science_score = _quest_science_delta
	landing_success_chance = 15 + _quest_landing_delta

	var solar_eff: float = float(current_mission.get("solar_efficiency", 1.0))

	for p in installed_parts:
		total_mass_kg += float(p.get("mass_kg", 0.0))
		var part_science: int = int(p.get("science", 0))
		var p_tags: Array = p.get("tags", [])
		# JunoCam radyasyon bozulması aktifse kameranın bilim katkısı %35 düşer
		if junocam_degraded and p_tags.has("radiation_degrading_camera"):
			part_science = int(round(part_science * 0.65))
		science_score += part_science
		landing_success_chance += int(p.get("landing_bonus", 0))

		var p_power: float = float(p.get("power_w", 0.0))
		if String(p.get("type", "")) == "power" and not bool(p.get("nuclear", false)):
			net_power_w += p_power * solar_eff
		else:
			net_power_w += p_power

		var d_rate: float = float(p.get("data_mbps", 0.0))
		if d_rate > 0.0:
			data_gen_mbps += d_rate
		elif d_rate < 0.0:
			downlink_mbps += abs(d_rate) * _quest_downlink_mult

	var part_prep_bonus: int = mini(installed_parts.size() * 4, 20)
	var target_gb: float = max(1.0, get_target_download_gb())
	var data_ratio: float = clampf(downloaded_data_gb / target_gb, 0.0, 1.0)
	var data_bonus: int = int(round(data_ratio * 20.0))
	landing_success_chance += part_prep_bonus + data_bonus

	if dsn_locked:
		landing_success_chance += 8

	science_score += get_dsn_bonus_science()

	science_score = max(0, science_score)
	landing_success_chance = clamp(landing_success_chance, 0, 100)
	EventBus.telemetry_changed.emit()

func get_dsn_extra_gb() -> float:
	return maxf(0.0, downloaded_data_gb - get_target_download_gb())

func get_dsn_bonus_tiers_completed() -> int:
	var extra_gb: float = get_dsn_extra_gb()
	return clampi(int(floor(extra_gb / DSN_EXTRA_STEP_GB)), 0, DSN_MAX_EXTRA_STEPS)

func get_dsn_bonus_science() -> int:
	return get_dsn_bonus_tiers_completed() * DSN_EXTRA_SCIENCE_PER_STEP

func get_dsn_max_bonus_gb() -> float:
	return get_target_download_gb() + (DSN_EXTRA_STEP_GB * float(DSN_MAX_EXTRA_STEPS))

func sync_dsn_input(new_freq: float) -> void:
	dsn_freq_value = clampf(new_freq, 0.0, 100.0)
	if is_network_active:
		NetworkClient.send_relay("dsn_input", { "freq": dsn_freq_value })

func sync_dsn_state(station_idx: int, target_center: float, station_timer: float, downloaded_gb: float, ssd_used: float, locked: bool) -> void:
	dsn_station_idx = station_idx
	dsn_target_center = target_center
	dsn_station_timer = station_timer
	downloaded_data_gb = downloaded_gb
	ssd_used_gb = ssd_used
	dsn_locked = locked
	if is_network_active:
		NetworkClient.send_relay("dsn_state", {
			"station_idx": station_idx,
			"target_center": target_center,
			"station_timer": station_timer,
			"downloaded_gb": downloaded_gb,
			"ssd_used": ssd_used,
			"locked": locked
		})

func start_crisis_vote(quest_id: String) -> void:
	active_crisis_id = quest_id
	crisis_votes.clear()
	last_crisis_vote_result.clear()

func cast_crisis_vote(quest_id: String, option_idx: int) -> void:
	active_crisis_id = quest_id
	crisis_votes[PlayerProfile.full_tag] = option_idx
	if is_network_active:
		NetworkClient.send_relay("crisis_vote", {
			"quest_id": quest_id,
			"voter_tag": PlayerProfile.full_tag,
			"option_idx": option_idx
		})
	EventBus.telemetry_changed.emit()

func resolve_crisis_vote_network(quest_id: String, winner_idx: int, was_tie: bool, is_timeout: bool) -> void:
	last_crisis_vote_result = {
		"quest_id": quest_id,
		"winner_idx": winner_idx,
		"was_tie": was_tie,
		"is_timeout": is_timeout
	}
	if is_network_active:
		NetworkClient.send_relay("crisis_resolve", last_crisis_vote_result)
	EventBus.telemetry_changed.emit()

func apply_minigame_bonus(mass_delta: float, power_delta: float, landing_delta: int, science_delta: int, log_text: String) -> void:
	_quest_mass_delta += mass_delta
	_quest_power_delta += power_delta
	_quest_landing_delta += landing_delta
	_quest_science_delta += science_delta
	if log_text != "":
		decision_logs.append(log_text)
	recalculate()
	if is_network_active:
		NetworkClient.send_relay("minigame_bonus", {
			"mass_delta": mass_delta,
			"power_delta": power_delta,
			"landing_delta": landing_delta,
			"science_delta": science_delta,
			"log_text": log_text
		})

func is_random_quest_budget_valid(opt: Dictionary) -> bool:
	var b_delta: float = float(opt.get("budget_delta", 0.0))
	if b_delta < 0.0 and budget_m + b_delta < 0.0:
		return false
	return true

func get_effective_mass_kg() -> float:
	var site_penalty: Dictionary = MissionValidator.get_launch_site_penalty(current_mission, selected_launch_site)
	return total_mass_kg + float(site_penalty.get("mass_penalty_kg", 0.0))

func get_effective_mass_limit_kg() -> float:
	if not selected_rocket.is_empty():
		return float(selected_rocket.get("max_mass_kg", 999999.0))
	return float(current_mission.get("max_mass_kg", 999999.0))

func get_target_download_gb() -> float:
	var mid: String = String(current_mission.get("id", ""))
	match mid:
		"leo_climate_aqua":
			return 120.0
		"lunar_pole_lro":
			return 180.0
		"mars_perseverance":
			return 240.0
		"europa_juno":
			return 300.0
		_:
			return 150.0

func mark_briefing_completed() -> void:
	if not briefing_completed:
		briefing_completed = true
		if is_network_active:
			NetworkClient.send_relay("briefing_done", {})

func set_power_wiring_broken(broken: bool) -> void:
	if power_wiring_broken == broken:
		return
	power_wiring_broken = broken
	if is_network_active:
		NetworkClient.send_relay("power_wiring", { "broken": broken })

func trigger_launch_sequence() -> void:
	if is_network_active:
		NetworkClient.send_relay("launch_rocket", {})
	get_tree().change_scene_to_file("res://scenes/world/landing_sim.tscn")

func _on_net_relay(event_name: String, data: Dictionary, from_peer_id: int) -> void:
	match event_name:
		"player_state":
			EventBus.remote_player_updated.emit(from_peer_id, data)
		"request_states":
			EventBus.network_states_requested.emit(String(data.get("scene", "")))
		"buy_part":
			var part_id: String = String(data.get("part_id", ""))
			var part: Dictionary = _find_by_id(parts_data.get("parts", []), part_id, -1)
			if not part.is_empty():
				var cost: float = float(part.get("cost_m", 0))
				if budget_m >= cost:
					budget_m -= cost
					purchased_parts.append(part)
					var spawn_payload: Dictionary = part.duplicate(true)
					spawn_payload["_box_id"] = String(data.get("box_id", ""))
					spawn_payload["_jx"] = float(data.get("jx", 0.0))
					spawn_payload["_jy"] = float(data.get("jy", 0.0))
					EventBus.cargo_spawned.emit(spawn_payload)
					EventBus.telemetry_changed.emit()
		"box_pickup":
			EventBus.box_picked_up.emit(String(data.get("box_id", "")), int(data.get("peer_id", from_peer_id)))
		"box_drop":
			EventBus.box_dropped.emit(
				String(data.get("box_id", "")),
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
			)
		"install_part":
			_apply_remote_install_part(String(data.get("part_id", "")), String(data.get("box_id", "")))
		"select_rocket":
			var r_id: String = String(data.get("rocket_id", ""))
			if r_id != "":
				selected_rocket = _find_by_id(parts_data.get("rockets", []), r_id, 0)
				_paid_rocket_cost = float(data.get("paid_cost", _paid_rocket_cost))
				budget_m = float(data.get("budget_m", budget_m))
				var log_line: String = String(data.get("log_line", ""))
				if log_line != "":
					decision_logs.append(log_line)
				EventBus.rocket_changed.emit(selected_rocket)
				recalculate()
		"side_quest_option":
			var q_id: String = String(data.get("quest_id", ""))
			var opt: Dictionary = data.get("opt", {}) if data.get("opt") is Dictionary else {}
			if not opt.is_empty():
				apply_side_quest_option(opt, q_id, false)
		"briefing_done":
			briefing_completed = true
			EventBus.status_message.emit("BRİFİNG TAMAMLANDI: Ekip üyesi görev hedeflerini onayladı.", false)
		"power_wiring":
			power_wiring_broken = bool(data.get("broken", false))
			EventBus.telemetry_changed.emit()
		"minigame_bonus":
			_quest_mass_delta += float(data.get("mass_delta", 0.0))
			_quest_power_delta += float(data.get("power_delta", 0.0))
			_quest_landing_delta += int(data.get("landing_delta", 0))
			_quest_science_delta += int(data.get("science_delta", 0))
			var log_txt: String = String(data.get("log_text", ""))
			if log_txt != "":
				decision_logs.append(log_txt)
			recalculate()
		"dsn_input":
			dsn_freq_value = clampf(float(data.get("freq", dsn_freq_value)), 0.0, 100.0)
			EventBus.telemetry_changed.emit()
		"dsn_state":
			dsn_station_idx = int(data.get("station_idx", dsn_station_idx))
			dsn_target_center = float(data.get("target_center", dsn_target_center))
			dsn_station_timer = float(data.get("station_timer", dsn_station_timer))
			downloaded_data_gb = float(data.get("downloaded_gb", downloaded_data_gb))
			ssd_used_gb = float(data.get("ssd_used", ssd_used_gb))
			dsn_locked = bool(data.get("locked", dsn_locked))
			recalculate()
		"crisis_trigger":
			var q_id: String = String(data.get("quest_id", ""))
			for q in get_available_side_quests_for_mission():
				if String(q.get("id", "")) == q_id:
					if not _triggered_crisis_ids.has(q_id):
						_triggered_crisis_ids.append(q_id)
					EventBus.crisis_alert.emit(q_id.to_upper())
					EventBus.side_quest_triggered.emit(q)
					break
		"crisis_vote":
			var q_id: String = String(data.get("quest_id", ""))
			if active_crisis_id == "" or active_crisis_id == q_id:
				active_crisis_id = q_id
				crisis_votes[String(data.get("voter_tag", ""))] = int(data.get("option_idx", 0))
				EventBus.telemetry_changed.emit()
		"crisis_resolve":
			last_crisis_vote_result = data.duplicate(true)
			EventBus.telemetry_changed.emit()
		"launch_rocket":
			if ResourceLoader.exists("res://scenes/world/landing_sim.tscn"):
				get_tree().change_scene_to_file("res://scenes/world/landing_sim.tscn")

func is_power_lab_decided() -> bool:
	var quests: Array = get_available_side_quests_for_mission()
	for q in quests:
		if not bool(q.get("is_random_crisis", false)) and String(q.get("room", "")) == "POWER_LAB":
			var q_id: String = String(q.get("id", ""))
			if not resolved_quest_ids.has(q_id):
				return false
	return true

func validate_launch() -> Dictionary:
	return MissionValidator.validate_build(
		current_mission,
		selected_rocket,
		selected_launch_site,
		installed_parts,
		total_mass_kg,
		net_power_w,
		power_cycling_enabled,
		junocam_degraded,
		is_power_lab_decided(),
		briefing_completed,
		power_wiring_broken
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
		score_mult,
		power_cycling_enabled,
		junocam_degraded,
		purchased_parts,
		is_power_lab_decided(),
		briefing_completed,
		budget_m,
		power_wiring_broken
	)
	if bool(report.get("success", false)):
		LeaderboardManager.add_record(
			String(current_mission.get("id", "unknown")),
			elapsed_time_sec,
			int(report.get("score", 0))
		)
	EventBus.mission_completed.emit(bool(report.get("success", false)), report)
	return report
