extends Node

const MissionValidator = preload("res://scripts/MissionValidator.gd")

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const ACTIVE_ROOMS_PATH: String = "user://active_rooms.json"
const ROOM_HEARTBEAT_TIMEOUT_SEC: float = 6.0
const CRISIS_MIN_INTERVAL_SEC: float = 95.0
const CRISIS_MAX_INTERVAL_SEC: float = 135.0
const MAX_RANDOM_CRISES_PER_MISSION: int = 2
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
var _room_heartbeat_timer: float = 0.0

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

# Özel Mekanikler (Mars Power Cycling / MOXIE 300W, JunoCam Radyasyon, DSN SSD)
var power_cycling_enabled: bool = false
var battery_charge_pct: float = 100.0
var junocam_degraded: bool = false
var ssd_used_gb: float = 0.0
var ssd_capacity_gb: float = 64.0
var dsn_locked: bool = false
var briefing_completed: bool = false

var purchased_parts: Array = []
var installed_parts: Array = []
var selected_rocket: Dictionary = {}
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
	if is_room_open:
		_room_heartbeat_timer += delta
		if _room_heartbeat_timer >= 1.5:
			_room_heartbeat_timer = 0.0
			if is_room_host:
				_save_active_room_entry()
			else:
				_poll_active_room_as_client()

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
# 4 KİŞİLİK LOBİ & MULTIPLAYER ODA / SENKRONİZASYON ALTYAPISI
# ============================================================================

func _setup_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _load_active_rooms() -> Dictionary:
	if not FileAccess.file_exists(ACTIVE_ROOMS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(ACTIVE_ROOMS_PATH, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var raw_rooms: Dictionary = parsed
	var now: float = Time.get_unix_time_from_system()
	var valid_rooms: Dictionary = {}
	var changed: bool = false
	for key in raw_rooms.keys():
		var r: Variant = raw_rooms[key]
		if r is Dictionary:
			var updated_at: float = float((r as Dictionary).get("updated_at", 0.0))
			if now - updated_at <= ROOM_HEARTBEAT_TIMEOUT_SEC:
				valid_rooms[String(key)] = r
			else:
				changed = true
	if changed:
		_write_active_rooms(valid_rooms)
	return valid_rooms

func _write_active_rooms(rooms: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(ACTIVE_ROOMS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(rooms))

func _serialize_players(players: Array) -> Array:
	var out: Array = []
	for i in range(players.size()):
		var p: Dictionary = players[i]
		out.append({
			"tag": String(p.get("tag", "")),
			"color_idx": i % SLOT_COLORS.size(),
			"is_host": bool(p.get("is_host", false)),
			"role": String(p.get("role", "Mürettebat")),
			"peer_id": int(p.get("peer_id", 0))
		})
	return out

func _deserialize_players(raw_players: Array) -> Array:
	var out: Array = []
	for i in range(raw_players.size()):
		var p: Dictionary = raw_players[i]
		var c_idx: int = int(p.get("color_idx", i)) % SLOT_COLORS.size()
		out.append({
			"tag": String(p.get("tag", "")),
			"color": SLOT_COLORS[c_idx],
			"is_host": bool(p.get("is_host", i == 0)),
			"role": String(p.get("role", "Mürettebat")),
			"peer_id": int(p.get("peer_id", 0))
		})
	return out

func _save_active_room_entry() -> void:
	if not is_room_open or room_code == "":
		return
	var rooms: Dictionary = _load_active_rooms()
	if is_room_host and rooms.has(room_code):
		var existing: Dictionary = rooms[room_code]
		var remote_raw: Array = existing.get("players", [])
		if remote_raw.size() > lobby_players.size():
			lobby_players = _deserialize_players(remote_raw)
			is_solo = lobby_players.size() == 1
			EventBus.lobby_updated.emit(lobby_players)

	var port_num: int = int(rooms.get(room_code, {}).get("port", DEFAULT_PORT))
	var host_tag: String = PlayerProfile.full_tag
	if lobby_players.size() > 0:
		host_tag = String(lobby_players[0].get("tag", PlayerProfile.full_tag))
	rooms[room_code] = {
		"room_code": room_code,
		"port": port_num,
		"updated_at": Time.get_unix_time_from_system(),
		"is_public": is_room_public,
		"is_mission_active": is_mission_active,
		"host_name": host_tag,
		"mission_name": String(current_mission.get("name", "")),
		"mission_idx": current_mission_idx,
		"modifier_idx": current_modifier_idx,
		"rocket_id": String(selected_rocket.get("id", "")),
		"site_id": String(selected_launch_site.get("id", "")),
		"players": _serialize_players(lobby_players)
	}
	_write_active_rooms(rooms)

func _poll_active_room_as_client() -> void:
	if not is_room_open or is_room_host or room_code == "":
		return
	var rooms: Dictionary = _load_active_rooms()
	if not rooms.has(room_code):
		leave_room()
		return
	var r: Dictionary = rooms[room_code]
	is_room_public = bool(r.get("is_public", true))
	var remote_m: int = int(r.get("mission_idx", current_mission_idx))
	var remote_mod: int = int(r.get("modifier_idx", current_modifier_idx))
	var remote_site: String = String(r.get("site_id", ""))
	if remote_m != current_mission_idx or remote_mod != current_modifier_idx:
		setup_mission(remote_m, remote_mod)
	if remote_site != "" and remote_site != String(selected_launch_site.get("id", "")):
		select_launch_site(remote_site)
	var synced_players: Array = _deserialize_players(r.get("players", []))
	if synced_players.size() != lobby_players.size():
		lobby_players = synced_players
		is_solo = lobby_players.size() == 1
		EventBus.lobby_updated.emit(lobby_players)

func _generate_random_room_code() -> String:
	var letters: String = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	var p1: String = ""
	for _i in range(3):
		p1 += letters[randi() % letters.length()]
	var num: int = randi_range(10, 99)
	return "%s-%02d" % [p1, num]

func get_public_rooms(filter_text: String = "") -> Array:
	var rooms: Dictionary = _load_active_rooms()
	var clean_filter: String = filter_text.strip_edges().to_lower()
	var out: Array = []
	for key in rooms.keys():
		var r: Dictionary = rooms[key]
		if not bool(r.get("is_public", false)):
			continue
		if bool(r.get("is_mission_active", false)):
			continue
		if clean_filter != "":
			var code_l: String = String(r.get("room_code", "")).to_lower()
			var host_l: String = String(r.get("host_name", "")).to_lower()
			var mission_l: String = String(r.get("mission_name", "")).to_lower()
			if not code_l.contains(clean_filter) and not host_l.contains(clean_filter) and not mission_l.contains(clean_filter):
				continue
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("updated_at", 0.0)) > float(b.get("updated_at", 0.0))
	)
	return out

func _remove_active_room_entry(code_to_remove: String) -> void:
	if code_to_remove == "":
		return
	var rooms: Dictionary = _load_active_rooms()
	if rooms.has(code_to_remove):
		rooms.erase(code_to_remove)
		_write_active_rooms(rooms)

func set_room_public(public_room: bool) -> void:
	if is_room_open and not is_room_host:
		return
	is_room_public = public_room
	if is_room_open:
		_save_active_room_entry()
	EventBus.telemetry_changed.emit()

func create_room(public_room: bool = false) -> String:
	leave_room()
	reset_lobby()
	randomize()
	var rooms: Dictionary = _load_active_rooms()
	var candidate: String = _generate_random_room_code()
	while rooms.has(candidate):
		candidate = _generate_random_room_code()

	room_code = candidate
	is_room_open = true
	is_room_host = true
	is_room_public = public_room
	var port: int = 7700 + randi_range(1, 99)
	host_room(port)
	_save_active_room_entry()
	return room_code

func host_room(port: int = DEFAULT_PORT) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		EventBus.network_status_changed.emit("Yerel Oda Aktif (%s)" % room_code, false)
		return err
	multiplayer.multiplayer_peer = peer
	is_network_active = true
	if room_code == "":
		room_code = _generate_random_room_code()
	is_room_open = true
	is_room_host = true
	if lobby_players.size() > 0:
		lobby_players[0]["peer_id"] = 1
	_save_active_room_entry()
	EventBus.network_status_changed.emit("Host Aktif — %s (Port %d)" % [room_code, port], true)
	EventBus.lobby_updated.emit(lobby_players)
	return OK

func join_room(code: String, player_tag: String = "") -> bool:
	var clean_code: String = code.strip_edges().to_upper()
	if clean_code == "":
		last_join_error = "Lütfen geçerli bir Oda Kodu girin (örn: KZM-47)!"
		return false

	var rooms: Dictionary = _load_active_rooms()
	if not rooms.has(clean_code):
		last_join_error = "HATA: '%s' kodlu açık bir oda bulunamadı! Sadece aktif kurulu odalara katılabilirsiniz." % clean_code
		EventBus.network_status_changed.emit(last_join_error, false)
		return false

	var room_info: Dictionary = rooms[clean_code]
	if bool(room_info.get("is_mission_active", false)):
		last_join_error = "HATA: '%s' odasında görev zaten başlamış!" % clean_code
		EventBus.network_status_changed.emit(last_join_error, false)
		return false

	var existing_players: Array = _deserialize_players(room_info.get("players", []))
	if existing_players.size() >= MAX_PLAYERS:
		last_join_error = "HATA: '%s' odası tamamen dolu (4/4)!" % clean_code
		EventBus.network_status_changed.emit(last_join_error, false)
		return false

	leave_room()
	room_code = clean_code
	is_room_open = true
	is_room_host = false
	lobby_players = existing_players

	var tag_to_join: String = player_tag.strip_edges() if player_tag.strip_edges() != "" else PlayerProfile.full_tag
	add_player_to_lobby(tag_to_join)

	room_info["players"] = _serialize_players(lobby_players)
	rooms[clean_code] = room_info
	_write_active_rooms(rooms)

	var port: int = int(room_info.get("port", DEFAULT_PORT))
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client("127.0.0.1", port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		is_network_active = true
		EventBus.network_status_changed.emit("Odaya Bağlanıldı: %s" % room_code, true)
	last_join_error = ""
	return true

func set_host_color(new_color: Color) -> void:
	if lobby_players.size() > 0:
		lobby_players[0]["color"] = new_color
		for i in range(1, lobby_players.size()):
			var c: Color = lobby_players[i].get("color", SLOT_COLORS[i % SLOT_COLORS.size()])
			if c.is_equal_approx(new_color):
				lobby_players[i]["color"] = _pick_distinct_color(i)
		_broadcast_lobby_state()

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
	for p in lobby_players:
		if String(p.get("tag", "")) == PlayerProfile.full_tag:
			return p.get("color", Color.CORAL)
	if lobby_players.size() > 0:
		return lobby_players[0].get("color", Color.CORAL)
	return Color.CORAL

func leave_room() -> void:
	if is_room_host and room_code != "":
		_remove_active_room_entry(room_code)
	if is_inside_tree() and multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_network_active = false
	is_room_open = false
	is_room_host = false
	room_code = ""
	EventBus.network_status_changed.emit("Çevrimdışı / Yerel Lobi Modu", false)

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		EventBus.network_status_changed.emit("Oyuncu bağlandı (Peer #%d)..." % peer_id, true)

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		for i in range(lobby_players.size() - 1, 0, -1):
			if int(lobby_players[i].get("peer_id", -1)) == peer_id:
				lobby_players.remove_at(i)
		_reindex_lobby_slots()
		_broadcast_lobby_state()

func _on_connected_to_server() -> void:
	EventBus.network_status_changed.emit("Odaya bağlandı! (%s)" % PlayerProfile.full_tag, true)
	_rpc_register_player.rpc_id(1, PlayerProfile.full_tag)

func _on_connection_failed() -> void:
	leave_room()
	EventBus.network_status_changed.emit("Sunucuya bağlanılamadı.", false)

func _on_server_disconnected() -> void:
	leave_room()
	reset_lobby()
	EventBus.network_status_changed.emit("Host bağlantıyı kapattı.", false)

@rpc("any_peer", "reliable")
func _rpc_register_player(player_tag: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var normalized: String = _normalize_tag(player_tag)
	for i in range(lobby_players.size()):
		if String(lobby_players[i].get("tag", "")) == normalized:
			lobby_players[i]["peer_id"] = sender_id
			_broadcast_lobby_state()
			return
	if lobby_players.size() >= MAX_PLAYERS:
		return
	var roles: Array[String] = ["Komutan", "Sistem Müh.", "Yük Uzmanı", "Uçuş Müh."]
	var idx: int = lobby_players.size()
	lobby_players.append({
		"tag": normalized,
		"color": _pick_distinct_color(),
		"is_host": false,
		"role": roles[idx],
		"peer_id": sender_id
	})
	is_solo = lobby_players.size() == 1
	_broadcast_lobby_state()

func _broadcast_lobby_state() -> void:
	EventBus.lobby_updated.emit(lobby_players)
	if is_room_open and is_room_host:
		_save_active_room_entry()
	if is_network_active and multiplayer.is_server():
		_rpc_sync_lobby_state.rpc(
			lobby_players,
			current_mission_idx,
			current_modifier_idx,
			String(selected_rocket.get("id", "")),
			String(selected_launch_site.get("id", ""))
		)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_lobby_state(
	synced_players: Array,
	mission_idx: int,
	modifier_idx: int,
	rocket_id: String,
	site_id: String
) -> void:
	lobby_players = synced_players
	is_solo = lobby_players.size() == 1
	setup_mission(mission_idx, modifier_idx, false)
	if rocket_id != "":
		select_rocket(rocket_id, false)
	if site_id != "":
		select_launch_site(site_id, false)
	EventBus.lobby_updated.emit(lobby_players)

func reset_lobby() -> void:
	lobby_players = [{
		"tag": PlayerProfile.full_tag,
		"color": SLOT_COLORS[0],
		"is_host": true,
		"role": "Komutan",
		"peer_id": 1
	}]
	is_solo = true
	if missions_data.has("missions") and missions_data["missions"].size() > 0:
		setup_mission(0, 0)
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
	lobby_players.append({
		"tag": normalized,
		"color": _pick_distinct_color(),
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
	recalculate()
	if broadcast and is_network_active and multiplayer.is_server():
		_broadcast_lobby_state()

func _find_by_id(items: Array, target_id: String, fallback_idx: int = 0) -> Dictionary:
	for item in items:
		if String(item.get("id", "")) == target_id:
			return item
	if fallback_idx >= 0 and items.size() > fallback_idx:
		return items[fallback_idx]
	return {}

func select_rocket(rocket_id: String, broadcast: bool = true) -> void:
	selected_rocket = _find_by_id(parts_data.get("rockets", []), rocket_id, 0)
	EventBus.rocket_changed.emit(selected_rocket)
	recalculate()
	if broadcast and is_network_active and multiplayer.is_server():
		_broadcast_lobby_state()

func select_launch_site(site_id: String, broadcast: bool = true) -> void:
	selected_launch_site = _find_by_id(missions_data.get("launch_sites", []), site_id, 0)
	EventBus.launch_site_changed.emit(selected_launch_site)
	recalculate()
	if broadcast and is_network_active and multiplayer.is_server():
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
	_crisis_timer = 0.0
	_triggered_crisis_ids.clear()
	_next_crisis_interval = randf_range(CRISIS_MIN_INTERVAL_SEC, CRISIS_MAX_INTERVAL_SEC)
	is_mission_active = true
	EventBus.mission_started.emit()
	if is_network_active and multiplayer.is_server():
		_rpc_start_mission.rpc()

@rpc("authority", "call_remote", "reliable")
func _rpc_start_mission() -> void:
	is_solo = lobby_players.size() == 1
	elapsed_time_sec = 0.0
	downloaded_data_gb = 0.0
	ssd_used_gb = 12.0
	is_mission_active = true
	EventBus.mission_started.emit()
	if ResourceLoader.exists("res://scenes/world/station.tscn"):
		get_tree().change_scene_to_file("res://scenes/world/station.tscn")

func buy_part(part: Dictionary) -> bool:
	var cost: float = float(part.get("cost_m", 0))
	if budget_m < cost:
		return false
	budget_m -= cost
	purchased_parts.append(part)
	EventBus.cargo_spawned.emit(part)
	EventBus.telemetry_changed.emit()
	if is_network_active:
		_rpc_sync_buy_part.rpc(String(part.get("id", "")))
	return true

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_buy_part(part_id: String) -> void:
	var part: Dictionary = _find_by_id(parts_data.get("parts", []), part_id, -1)
	if not part.is_empty():
		var cost: float = float(part.get("cost_m", 0))
		if budget_m >= cost:
			budget_m -= cost
			purchased_parts.append(part)
			EventBus.cargo_spawned.emit(part)
			EventBus.telemetry_changed.emit()

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

func install_part(part: Dictionary) -> bool:
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
		_rpc_sync_install_part.rpc(pid)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_install_part(part_id: String) -> void:
	var part: Dictionary = _find_by_id(parts_data.get("parts", []), part_id, -1)
	if not part.is_empty() and not is_part_installed(part_id):
		installed_parts.append(part)
		recalculate()

func uninstall_part(index: int) -> void:
	if index >= 0 and index < installed_parts.size():
		var removed: Dictionary = installed_parts[index]
		budget_m += float(removed.get("cost_m", 0))
		installed_parts.remove_at(index)
		if not has_installed_tag("radiation_degrading_camera"):
			junocam_degraded = false
		recalculate()

func apply_side_quest_option(opt: Dictionary, quest_id: String = "") -> void:
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
			if randf() < float(resolved_opt.get("chance_success", 0.50)):
				s_delta += 240
				l_delta += 10
				note = "GÜNEŞ PATLAMASI KAYDEDİLDİ (%50 Şans Tuttu!): Kameralar CME patlamasını doğrudan yakaladı (+240 Bilim Puanı, +%10 İniş)!"
			else:
				s_delta -= 120
				p_delta -= 40.0
				l_delta -= 20
				note = "İŞLEMCİ HASARI (%50 Risk Gerçekleşti!): Yüksek enerjili protonlar ana işlemci/hafıza kartına kalıcı hasar verdi (-40W, -120 Bilim, -%20 İniş)!"
		"MICROMETEOROID_BURN":
			var has_nav: bool = has_installed_tag("laser_altimeter") or has_installed_tag("rover_navigation") or has_installed_type("avionics")
			var win_chance: float = 0.85 if has_nav else float(resolved_opt.get("chance_success", 0.40))
			if randf() < win_chance:
				l_delta += 15
				s_delta += 50
				note = "ACİL MANEVRA BAŞARILI: Navigasyon bilgisayarı yakıt sızıntısı bitmeden aracı hedef yörüngeye oturttu (+%15 İniş, +50 Bilim)!"
			else:
				m_delta += 85.0
				l_delta -= 20
				note = "DELTA-V SAPMASI: Navigasyon bilgisayarı hızı yetmedi! Plansız manevra fazladan yakıt tüketti (+85 kg Kütle Cezası, -%20 İniş)!"
		"DUST_STORM_HIBERNATE":
			var has_nuclear_or_heater: bool = has_installed_tag("nuclear_power") or has_installed_tag("thermal_survival") or String(current_mission.get("power_source_type", "")) == "mmrtg"
			if has_nuclear_or_heater:
				l_delta += 15
				note = "KIŞ UYKUSU BAŞARILI: MMRTG / Termal Isıtıcı sayesinde toz fırtınası donma riski olmadan güvenle atlatıldı (+%15 İniş)!"
			elif randf() < float(resolved_opt.get("chance_success", 0.50)):
				p_delta -= 15.0
				l_delta += 5
				note = "ŞANSLI UYANIŞ: MMRTG yoktu ancak fırtına dinince bataryalar sınırda da olsa yeniden canlandı (-15W Güç)."
			else:
				p_delta -= 60.0
				l_delta -= 25
				note = "DONMA HASARI: Araçta MMRTG / Isıtıcı olmadığı için kış uykusunda bataryalar soğuktan ağır güç kaybetti (-60W, -%25 İniş)!"
		"DUST_STORM_SHAKE":
			if randf() < float(resolved_opt.get("chance_success", 0.40)):
				p_delta += 25.0
				l_delta += 10
				note = "PANELLER TEMİZLENDİ (%40 Şans Tuttu!): Robotik kol sarsıntısı ve rüzgar darbesiyle toz tabakası dağıldı (+25W, +%10 İniş)!"
			else:
				p_delta -= 75.0
				l_delta -= 30
				note = "BATARYA REZERVİ TÜKENDİ: Paneller temizlenemedi ve kol hareketi kritik batarya rezervini bitirdi (-75W, -%30 İniş)!"
		"HGA_LOW_GAIN_FALLBACK":
			_quest_downlink_mult = 0.25
		"HGA_THERMAL_SHOCK":
			if randf() < float(resolved_opt.get("chance_success", 0.30)):
				s_delta += 160
				l_delta += 15
				note = "ANTEN KURTULDU (%30 Galileo Termal Şoku Tuttu!): Güneş/gölge genleşmesiyle sıkışan ana anten açıldı (+160 Bilim, +%15 İniş)!"
			else:
				m_delta += 65.0
				p_delta -= 25.0
				l_delta -= 20
				note = "YÖNELİM BOZULDU (%70 Risk): Anten kurtulmadı; dönüş manevrasında yönelim kontrolü bozuldu ve yakıt harcandı (+65 kg, -25W, -%20 İniş)!"
		"SEU_HARD_REBOOT":
			if randf() < float(resolved_opt.get("chance_success", 0.55)):
				p_delta -= 10.0
				l_delta += 5
				note = "HARD REBOOT BAŞARILI: Uçuş bilgisayarı yeniden başlatıldı ve yıldız izleyici sensörler yönelimi yakaladı (-10W, +%5 İniş)."
			else:
				p_delta -= 35.0
				s_delta -= 70
				l_delta -= 25
				note = "TAKLA (TUMBLE) KRİZİ: Reboot sonrası uçuş parametreleri sıfırlandı ve araç takla atmaya başladı (-35W, -70 Bilim, -%25 İniş)!"
		"SEU_COLD_BACKUP":
			if has_installed_type("avionics"):
				l_delta += 20
				s_delta += 50
				note = "COLD-BACKUP DEVREDE: Kurulu aviyonik/yedek bilgisayar modülü devreye girdi; 1202 Alarmı hasarsız çözüldü (+%20 İniş, +50 Bilim)!"
			elif budget_m >= 15.0:
				b_delta -= 15.0
				m_delta += 10.0
				if randf() < 0.55:
					l_delta += 10
					note = "COLD-BACKUP ACİL YAMASI TUTTU: Yedek donanım yoktu ancak -$15M ve +10kg rezerv ile sistem kurtarıldı (+%10 İniş)."
				else:
					p_delta -= 45.0
					l_delta -= 25
					note = "COLD-BACKUP BAŞARISIZ (%45 Risk): Aviyonik modül olmadığı için -$15M harcanmasına rağmen yedek sistem senkronize olamadı (-45W, -%25 İniş)!"
			else:
				p_delta -= 60.0
				l_delta -= 35
				note = "SİSTEM ÇÖKTÜ: Tasarımda yedek bilgisayar için aviyonik parça veya bütçe ayrılmadığı için Cold-Backup devreye giremedi (-60W, -%35 İniş)!"

	if not is_random_quest_budget_valid(opt):
		EventBus.status_message.emit("BÜTÇE YETERSİZ! Bu işlem için yeterli bütçeniz yok (Mevcut: $%.0fM)." % budget_m, true)
		return

	budget_m = max(0.0, budget_m + b_delta)
	_quest_mass_delta += m_delta
	_quest_power_delta += p_delta
	_quest_landing_delta += l_delta
	_quest_science_delta += s_delta

	if resolved_opt.has("set_launch_site"):
		select_launch_site(String(resolved_opt["set_launch_site"]))

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

	science_score = max(0, science_score)
	landing_success_chance = clamp(landing_success_chance, 0, 100)
	EventBus.telemetry_changed.emit()

func sync_dsn_input(new_freq: float) -> void:
	dsn_freq_value = clampf(new_freq, 0.0, 100.0)
	if is_network_active:
		_rpc_sync_dsn_input.rpc(dsn_freq_value)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_dsn_input(new_freq: float) -> void:
	dsn_freq_value = clampf(new_freq, 0.0, 100.0)
	EventBus.telemetry_changed.emit()

func sync_dsn_state(station_idx: int, target_center: float, station_timer: float, downloaded_gb: float, ssd_used: float, locked: bool) -> void:
	dsn_station_idx = station_idx
	dsn_target_center = target_center
	dsn_station_timer = station_timer
	downloaded_data_gb = downloaded_gb
	ssd_used_gb = ssd_used
	dsn_locked = locked
	if is_network_active:
		_rpc_sync_dsn_state.rpc(station_idx, target_center, station_timer, downloaded_gb, ssd_used, locked)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_dsn_state(station_idx: int, target_center: float, station_timer: float, downloaded_gb: float, ssd_used: float, locked: bool) -> void:
	dsn_station_idx = station_idx
	dsn_target_center = target_center
	dsn_station_timer = station_timer
	downloaded_data_gb = downloaded_gb
	ssd_used_gb = ssd_used
	dsn_locked = locked
	recalculate()

func start_crisis_vote(quest_id: String) -> void:
	active_crisis_id = quest_id
	crisis_votes.clear()
	last_crisis_vote_result.clear()

func cast_crisis_vote(quest_id: String, option_idx: int) -> void:
	active_crisis_id = quest_id
	crisis_votes[PlayerProfile.full_tag] = option_idx
	if is_network_active:
		_rpc_cast_crisis_vote.rpc(quest_id, PlayerProfile.full_tag, option_idx)
	EventBus.telemetry_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_cast_crisis_vote(quest_id: String, voter_tag: String, option_idx: int) -> void:
	if active_crisis_id == "" or active_crisis_id == quest_id:
		active_crisis_id = quest_id
		crisis_votes[voter_tag] = option_idx
		EventBus.telemetry_changed.emit()

func resolve_crisis_vote_network(quest_id: String, winner_idx: int, was_tie: bool, is_timeout: bool) -> void:
	last_crisis_vote_result = {
		"quest_id": quest_id,
		"winner_idx": winner_idx,
		"was_tie": was_tie,
		"is_timeout": is_timeout
	}
	if is_network_active:
		_rpc_resolve_crisis_vote.rpc(quest_id, winner_idx, was_tie, is_timeout)
	EventBus.telemetry_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_resolve_crisis_vote(quest_id: String, winner_idx: int, was_tie: bool, is_timeout: bool) -> void:
	last_crisis_vote_result = {
		"quest_id": quest_id,
		"winner_idx": winner_idx,
		"was_tie": was_tie,
		"is_timeout": is_timeout
	}
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
		_rpc_apply_minigame_bonus.rpc(mass_delta, power_delta, landing_delta, science_delta, log_text)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_minigame_bonus(mass_delta: float, power_delta: float, landing_delta: int, science_delta: int, log_text: String) -> void:
	_quest_mass_delta += mass_delta
	_quest_power_delta += power_delta
	_quest_landing_delta += landing_delta
	_quest_science_delta += science_delta
	if log_text != "":
		decision_logs.append(log_text)
	recalculate()

func is_random_quest_budget_valid(opt: Dictionary) -> bool:
	var b_delta: float = float(opt.get("budget_delta", 0.0))
	if b_delta < 0.0 and budget_m + b_delta < 0.0:
		return false
	return true

func get_effective_mass_kg() -> float:
	var site_penalty: Dictionary = MissionValidator.get_launch_site_penalty(current_mission, selected_launch_site)
	return total_mass_kg + float(site_penalty.get("mass_penalty_kg", 0.0))

func get_effective_mass_limit_kg() -> float:
	var rocket_cap: float = float(selected_rocket.get("max_mass_kg", 999999.0))
	var mission_cap: float = float(current_mission.get("max_mass_kg", 999999.0))
	return min(rocket_cap, mission_cap)

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
	briefing_completed = true

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
		briefing_completed
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
		budget_m
	)
	if bool(report.get("success", false)):
		LeaderboardManager.add_record(
			String(current_mission.get("id", "unknown")),
			elapsed_time_sec,
			int(report.get("score", 0))
		)
	EventBus.mission_completed.emit(bool(report.get("success", false)), report)
	return report
