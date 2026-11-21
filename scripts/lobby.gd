extends Control

const MissionValidator = preload("res://scripts/MissionValidator.gd")

@onready var nickname_input: LineEdit = %NicknameInput
@onready var add_player_input: LineEdit = %AddPlayerInput
@onready var crew_list: VBoxContainer = %CrewList
@onready var mission_option: OptionButton = %MissionOption
@onready var modifier_option: OptionButton = %ModifierOption
@onready var launch_site_option: OptionButton = %LaunchSiteOption
@onready var mission_desc: Label = %MissionDesc
@onready var budget_label: Label = %BudgetLabel
@onready var leaderboard_list: VBoxContainer = %LeaderboardList

var _mode_status_label: Label = null
var _net_status_label: Label = null
var _ip_input: LineEdit = null
var _host_btn: Button = null
var _join_btn: Button = null
var _start_btn: Button = null

func _ready() -> void:
	nickname_input.text = PlayerProfile.nickname
	if not nickname_input.text_changed.is_connected(_on_nickname_changed):
		nickname_input.text_changed.connect(_on_nickname_changed)
	if not add_player_input.text_submitted.is_connected(_on_add_player_submitted):
		add_player_input.text_submitted.connect(_on_add_player_submitted)

	_setup_extra_lobby_controls()
	_populate_selectors()
	_sync_launch_site_dropdown()

	EventBus.lobby_updated.connect(_refresh_crew_list)
	EventBus.telemetry_changed.connect(_refresh_mission_info)
	EventBus.leaderboard_updated.connect(_refresh_leaderboard)
	if EventBus.has_signal("network_status_changed"):
		EventBus.network_status_changed.connect(_on_network_status_changed)

	_refresh_crew_list(GameState.lobby_players)
	_refresh_mission_info()
	_refresh_leaderboard()
	LeaderboardManager.fetch_from_server()

func _setup_extra_lobby_controls() -> void:
	var crew_vbox: Node = crew_list.get_parent()
	_start_btn = get_node_or_null("MarginContainer/MainVBox/Columns/MissionPanel/MissionVBox/StartBtn") as Button

	if crew_vbox != null and crew_vbox.get_node_or_null("NetBar") == null:
		var net_bar: HBoxContainer = HBoxContainer.new()
		net_bar.name = "NetBar"
		net_bar.add_theme_constant_override("separation", 3)

		_ip_input = LineEdit.new()
		_ip_input.text = "127.0.0.1"
		_ip_input.placeholder_text = "IP"
		_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ip_input.add_theme_font_size_override("font_size", 9)

		_host_btn = Button.new()
		_host_btn.text = "Oda Kur"
		_host_btn.add_theme_font_size_override("font_size", 9)
		_host_btn.pressed.connect(_on_host_room_pressed)

		_join_btn = Button.new()
		_join_btn.text = "Katıl"
		_join_btn.add_theme_font_size_override("font_size", 9)
		_join_btn.pressed.connect(_on_join_room_pressed)

		net_bar.add_child(_ip_input)
		net_bar.add_child(_host_btn)
		net_bar.add_child(_join_btn)
		crew_vbox.add_child(net_bar)

		_mode_status_label = Label.new()
		_mode_status_label.name = "ModeStatusLabel"
		_mode_status_label.add_theme_font_size_override("font_size", 9)
		_mode_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		crew_vbox.add_child(_mode_status_label)

		_net_status_label = Label.new()
		_net_status_label.name = "NetStatusLabel"
		_net_status_label.add_theme_font_size_override("font_size", 8)
		_net_status_label.modulate = Color(0.65, 0.82, 0.95)
		_net_status_label.text = "Ağ: Yerel / ENet Hazır (Port 7777)"
		crew_vbox.add_child(_net_status_label)

func _populate_selectors() -> void:
	mission_option.clear()
	for m in GameState.missions_data.get("missions", []):
		mission_option.add_item("%s [%s]" % [String(m.get("name", "")), String(m.get("difficulty", ""))])

	modifier_option.clear()
	for mod in GameState.missions_data.get("budget_modifiers", []):
		modifier_option.add_item(String(mod.get("name", "")))

	launch_site_option.clear()
	for site in GameState.missions_data.get("launch_sites", []):
		launch_site_option.add_item(String(site.get("name", "")))

func _refresh_crew_list(players: Array) -> void:
	for child in crew_list.get_children():
		child.queue_free()

	var is_solo_mode: bool = GameState.is_solo

	for i in range(4):
		var slot_panel: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.16, 0.24, 0.95) if i < players.size() else Color(0.07, 0.09, 0.14, 0.8)
		style.border_width_left = 2
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.content_margin_left = 5.0
		style.content_margin_right = 4.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var lbl: Label = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 9)

		if i < players.size():
			var p: Dictionary = players[i]
			var p_color: Color = p.get("color", Color.WHITE)
			style.border_color = p_color
			var role_tag: String = " [HOST]" if bool(p.get("is_host", false)) else " [CO-OP]"
			lbl.text = "%d. %s%s" % [i + 1, String(p.get("tag", "")), role_tag]
			lbl.modulate = p_color
			row.add_child(lbl)

			if not bool(p.get("is_host", false)):
				var remove_btn: Button = Button.new()
				remove_btn.text = "✕"
				remove_btn.add_theme_font_size_override("font_size", 8)
				var slot_idx: int = i
				remove_btn.pressed.connect(func() -> void:
					GameState.remove_player_from_lobby(slot_idx)
				)
				row.add_child(remove_btn)
		elif is_solo_mode and i == 1:
			var drone_color: Color = Color(0.35, 0.9, 0.95)
			style.border_color = Color(0.2, 0.55, 0.65)
			lbl.text = "2. [SOLO DESTEK: Helper Drone]"
			lbl.modulate = drone_color
			row.add_child(lbl)
		else:
			style.border_color = Color(0.2, 0.26, 0.35)
			lbl.text = "%d. [BOŞ SLOT — Nickname#ID ekle]" % (i + 1)
			lbl.modulate = Color(0.55, 0.6, 0.65)
			row.add_child(lbl)

		slot_panel.add_theme_stylebox_override("panel", style)
		slot_panel.add_child(row)
		crew_list.add_child(slot_panel)

	if _mode_status_label != null:
		if is_solo_mode:
			_mode_status_label.text = "MOD: SOLO (is_solo = true → 1 Astronot + Dron)"
			_mode_status_label.modulate = Color(0.45, 0.95, 0.75)
		else:
			_mode_status_label.text = "MOD: CO-OP (is_solo = false → %d Astronot)" % players.size()
			_mode_status_label.modulate = Color(1.0, 0.85, 0.4)

	if _start_btn != null:
		_start_btn.text = "GÖREVİ BAŞLAT (SOLO + DRON)" if is_solo_mode else "GÖREVİ BAŞLAT (%d KİŞİ CO-OP)" % players.size()

func _refresh_mission_info() -> void:
	var m: Dictionary = GameState.current_mission
	var site_pen: Dictionary = MissionValidator.get_launch_site_penalty(m, GameState.selected_launch_site)
	var pen_text: String = ""
	if float(site_pen.get("mass_penalty_kg", 0.0)) > 0.0:
		pen_text = "\n[ÜS CEZASI]: +%.0f kg (%s)" % [
			float(site_pen.get("mass_penalty_kg", 0.0)),
			String(site_pen.get("note", ""))
		]

	mission_desc.text = "%s\nYörünge: %s | Güç: %.0f W | Kütle Limiti: %.0f kg%s" % [
		String(m.get("description", "")),
		String(m.get("orbit_label", "")),
		float(m.get("nominal_power_w", 0.0)),
		float(m.get("max_mass_kg", 0.0)),
		pen_text
	]
	budget_label.text = "DİNAMİK BÜTÇE: $%.0fM | ROKET: %s" % [
		GameState.budget_m,
		String(GameState.selected_rocket.get("name", "-"))
	]

func _format_duration_local(time_sec: float) -> String:
	var total_tenths: int = int(round(time_sec * 10.0))
	var mins: int = (total_tenths / 10) / 60
	var secs: int = (total_tenths / 10) % 60
	var tenths: int = total_tenths % 10
	return "%02d:%02d.%d" % [mins, secs, tenths]

func _refresh_leaderboard() -> void:
	for child in leaderboard_list.get_children():
		child.queue_free()

	var current_id: String = String(GameState.current_mission.get("id", ""))
	var mission_records: Array = LeaderboardManager.get_records_for_mission(current_id)

	if mission_records.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Henüz kayıt yok. İlk rekoru kır!"
		empty_lbl.modulate = Color(0.6, 0.65, 0.7)
		leaderboard_list.add_child(empty_lbl)
		return

	var rank_colors: Array[Color] = [
		Color(1.0, 0.86, 0.35),
		Color(0.82, 0.88, 0.95),
		Color(0.9, 0.65, 0.45)
	]

	for idx in range(mission_records.size()):
		var rec: Dictionary = mission_records[idx]
		var lbl: Label = Label.new()
		var t_sec: float = float(rec.get("time_sec", 0.0))
		lbl.text = "#%d %s — %s (%ds) | %dp" % [
			idx + 1,
			String(rec.get("team", "")),
			_format_duration_local(t_sec),
			int(round(t_sec)),
			int(rec.get("score", 0))
		]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.clip_text = true
		lbl.modulate = rank_colors[idx] if idx < rank_colors.size() else Color.WHITE
		leaderboard_list.add_child(lbl)

func _on_nickname_changed(new_text: String) -> void:
	if new_text.strip_edges() != "":
		GameState.update_host_nickname(new_text)

func _on_nickname_submitted(new_text: String) -> void:
	GameState.update_host_nickname(new_text)

func _on_add_player_submitted(_text: String) -> void:
	_on_add_player_pressed()

func _on_add_player_pressed() -> void:
	if GameState.add_player_to_lobby(add_player_input.text):
		add_player_input.text = ""

func _on_host_room_pressed() -> void:
	GameState.create_offline_solo_room()

func _on_join_room_pressed() -> void:
	var code: String = _ip_input.text if _ip_input != null else ""
	if code.strip_edges() != "":
		NetworkClient.join_room(code, PlayerProfile.full_tag)

func _on_network_status_changed(status_text: String, is_online: bool) -> void:
	if _net_status_label != null:
		_net_status_label.text = status_text
		_net_status_label.modulate = Color(0.45, 0.95, 0.65) if is_online else Color(0.75, 0.75, 0.8)

func _on_mission_selected(_idx: int) -> void:
	GameState.setup_mission(mission_option.selected, modifier_option.selected)
	_sync_launch_site_dropdown()
	_refresh_leaderboard()

func _on_modifier_selected(_idx: int) -> void:
	GameState.setup_mission(mission_option.selected, modifier_option.selected)

func _on_launch_site_selected(idx: int) -> void:
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	if idx >= 0 and idx < sites.size():
		GameState.select_launch_site(String(sites[idx].get("id", "")))

func _sync_launch_site_dropdown() -> void:
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	var target_id: String = String(GameState.selected_launch_site.get("id", ""))
	for i in range(sites.size()):
		if String(sites[i].get("id", "")) == target_id:
			launch_site_option.selected = i
			break

func _on_start_mission_pressed() -> void:
	if nickname_input.text.strip_edges() != "":
		GameState.update_host_nickname(nickname_input.text)
	GameState.start_mission()
	if ResourceLoader.exists("res://scenes/world/station.tscn"):
		get_tree().change_scene_to_file("res://scenes/world/station.tscn")
	else:
		mission_desc.text = "Hazır! Sıradaki adım: res://scenes/world/station.tscn sahnesini oluşturun."
