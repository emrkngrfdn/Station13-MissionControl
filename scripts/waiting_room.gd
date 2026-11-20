extends Node2D

const ASTRONAUT_SHEET: Texture2D = preload("res://assets/astronaut_sheet.png")
const PLAYER_SCENE: PackedScene = preload("res://scenes/entities/player.tscn")
const HUD_PLAYERS_SHEET: Texture2D = preload("res://assets/ui/hud_players_sheet.png")
const SETTINGS_COLORS_BAR: Texture2D = preload("res://assets/ui/settings_colors_bar.png")
const SETTINGS_PANEL_SHEET: Texture2D = preload("res://assets/ui/settings_panel_sheet.png")

const HELMET_REGIONS: Array[Rect2] = [
	Rect2(8, 62, 19, 19),  # Kırmızı
	Rect2(56, 62, 19, 19), # Mavi
	Rect2(32, 62, 19, 19), # Sarı
	Rect2(80, 62, 19, 19)  # Yeşil
]

const DIGIT_REGIONS: Array[Rect2] = [
	Rect2(116, 6, 5, 12),  # 1
	Rect2(114, 23, 9, 12), # 2
	Rect2(114, 42, 9, 12), # 3
	Rect2(113, 61, 10, 12) # 4
]

const CREW_POSITIONS: Array[Vector2] = [
	Vector2(305, 189),
	Vector2(349, 189),
	Vector2(327, 212)
]

const SUIT_COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.35, 1),
	Color(0.25, 0.75, 0.98, 1),
	Color(0.98, 0.82, 0.25, 1),
	Color(0.32, 0.88, 0.55, 1)
]

@onready var room_info_label: Label = %RoomInfoLabel
@onready var mission_summary_label: Label = %MissionSummaryLabel
@onready var player_count_icon: TextureRect = %PlayerCountIcon
@onready var helmet_slots: Control = %HelmetSlots
@onready var settings_backdrop: ColorRect = %SettingsBackdrop
@onready var settings_panel: Control = %HostSettingsPanel
@onready var host_lock_badge: Label = %HostLockBadge
@onready var mission_option: OptionButton = %MissionOption
@onready var modifier_option: OptionButton = %ModifierOption
@onready var launch_site_option: OptionButton = %LaunchSiteOption
@onready var mission_desc: Label = %MissionDesc
@onready var color_row: Control = %ColorRow
@onready var public_btn: TextureButton = %PublicBtn
@onready var private_btn: TextureButton = %PrivateBtn
@onready var leaderboard_list: VBoxContainer = %LeaderboardList
@onready var crew_dummies: Node2D = $CrewDummies
@onready var player: CharacterBody2D = $Player
@onready var back_btn: TextureButton = $HUD/BottomBar/BackBtn
@onready var start_btn: TextureButton = $HUD/BottomBar/StartBtn
@onready var close_btn: TextureButton = $HUD/HostSettingsPanel/CloseBtn
@onready var holo_beacon: Label = %HoloBeacon
@onready var holo_prompt: Label = $HostLaptopTerminal/PromptLabel

var _beacon_t: float = 0.0
var _remote_players: Dictionary = {}

func _ready() -> void:
	_set_settings_open(false)
	holo_prompt.modulate.a = 0.0
	_setup_texture_button(back_btn)
	_setup_texture_button(start_btn)
	_setup_texture_button(close_btn)
	_setup_texture_button(public_btn)
	_setup_texture_button(private_btn)
	for c_btn in color_row.get_children():
		if c_btn is TextureButton:
			c_btn.pivot_offset = c_btn.size * 0.5
	var empty_img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var empty_tex := ImageTexture.create_from_image(empty_img)
	for opt in [mission_option, modifier_option, launch_site_option]:
		opt.add_theme_icon_override("arrow", empty_tex)
	_populate_selectors()
	EventBus.lobby_updated.connect(_on_lobby_updated)
	EventBus.telemetry_changed.connect(_refresh_top_bar)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.remote_player_updated.connect(_on_remote_player_updated)
	EventBus.remote_player_left.connect(_on_remote_player_left)
	_on_lobby_updated(GameState.lobby_players)
	_refresh_room_type_buttons()
	_refresh_host_permissions()
	_refresh_top_bar()
	_refresh_leaderboard()

func _exit_tree() -> void:
	if EventBus.lobby_updated.is_connected(_on_lobby_updated):
		EventBus.lobby_updated.disconnect(_on_lobby_updated)
	if EventBus.telemetry_changed.is_connected(_refresh_top_bar):
		EventBus.telemetry_changed.disconnect(_refresh_top_bar)
	if EventBus.terminal_opened.is_connected(_on_terminal_opened):
		EventBus.terminal_opened.disconnect(_on_terminal_opened)
	if EventBus.remote_player_updated.is_connected(_on_remote_player_updated):
		EventBus.remote_player_updated.disconnect(_on_remote_player_updated)
	if EventBus.remote_player_left.is_connected(_on_remote_player_left):
		EventBus.remote_player_left.disconnect(_on_remote_player_left)

func _process(delta: float) -> void:
	_beacon_t += delta
	holo_beacon.visible = not settings_panel.visible
	if holo_beacon.visible:
		holo_beacon.position.y = 136.0 + sin(_beacon_t * 3.2) * 2.5
		if holo_prompt.visible:
			holo_beacon.text = "[E] ETKİLEŞİM ▼"
			holo_beacon.modulate = Color(0.55, 1.0, 0.78, 1.0)
		else:
			holo_beacon.text = "[E] AYARLAR ▼"
			holo_beacon.modulate = Color.WHITE

func _setup_texture_button(btn: TextureButton) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(func() -> void:
		btn.scale = Vector2(1.05, 1.05)
		btn.modulate = Color(1.14, 1.14, 1.14, 1.0)
	)
	btn.mouse_exited.connect(func() -> void:
		btn.scale = Vector2.ONE
		btn.modulate = Color.WHITE
	)
	btn.button_down.connect(func() -> void:
		btn.scale = Vector2(0.94, 0.94)
		btn.modulate = Color(0.82, 0.88, 0.95, 1.0)
	)
	btn.button_up.connect(func() -> void:
		if btn.is_hovered():
			btn.scale = Vector2(1.05, 1.05)
			btn.modulate = Color(1.14, 1.14, 1.14, 1.0)
		else:
			btn.scale = Vector2.ONE
			btn.modulate = Color.WHITE
	)

func _populate_selectors() -> void:
	mission_option.clear()
	for m in GameState.missions_data.get("missions", []):
		mission_option.add_item("%s [%s]" % [m.get("name", ""), m.get("difficulty", "")])

	modifier_option.clear()
	for mod in GameState.missions_data.get("budget_modifiers", []):
		modifier_option.add_item(mod.get("name", ""))

	launch_site_option.clear()
	for site in GameState.missions_data.get("launch_sites", []):
		launch_site_option.add_item(site.get("name", ""))

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "BRIEFING":
		_set_settings_open(not settings_panel.visible)

func _set_settings_open(is_open: bool) -> void:
	settings_panel.visible = is_open
	settings_backdrop.visible = is_open

func _color_to_row(c: Color) -> int:
	if c.b > 0.7 and c.r < 0.5:
		return 1 # Mavi
	if c.r > 0.8 and c.g > 0.7:
		return 2 # Sarı
	if c.g > 0.7 and c.r < 0.5:
		return 3 # Yeşil
	return 0 # Kırmızı

func _on_lobby_updated(players: Array) -> void:
	if GameState.is_network_active:
		var active_ids: Dictionary = {}
		var slot_idx: int = 0
		for i in range(players.size()):
			var p: Dictionary = players[i]
			var pid: int = int(p.get("peer_id", 0))
			if pid == GameState.my_peer_id or pid <= 0:
				continue
			active_ids[pid] = true
			if not _remote_players.has(pid) or not is_instance_valid(_remote_players[pid]):
				var rp: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
				var spawn_pos: Vector2 = CREW_POSITIONS[slot_idx % CREW_POSITIONS.size()]
				rp.set("is_local_player", false)
				rp.set("peer_id", pid)
				rp.set("player_tag", String(p.get("tag", "Mürettebat")))
				crew_dummies.add_child(rp)
				rp.call("setup_remote", pid, String(p.get("tag", "Mürettebat")), spawn_pos)
				_remote_players[pid] = rp
			else:
				var existing_rp: Node = _remote_players[pid]
				existing_rp.set("player_tag", String(p.get("tag", "Mürettebat")))
				existing_rp.call("_sync_color_row")
			slot_idx += 1

		for old_pid in _remote_players.keys():
			if not active_ids.has(old_pid):
				var old_node: Node = _remote_players[old_pid]
				if is_instance_valid(old_node):
					old_node.queue_free()
				_remote_players.erase(old_pid)
	else:
		_remote_players.clear()
		for child in crew_dummies.get_children():
			child.queue_free()

		var slot_idx: int = 0
		for i in range(players.size()):
			var p: Dictionary = players[i]
			if String(p.get("tag", "")) == PlayerProfile.full_tag:
				continue
			var dummy: Node2D = Node2D.new()
			dummy.position = CREW_POSITIONS[slot_idx % CREW_POSITIONS.size()]
			slot_idx += 1

			var spr: Sprite2D = Sprite2D.new()
			spr.texture = ASTRONAUT_SHEET
			spr.scale = Vector2(0.85, 0.85)
			spr.offset.x = -7.0
			spr.region_enabled = true
			var p_color: Color = p.get("color", SUIT_COLORS[i % SUIT_COLORS.size()])
			var row: int = _color_to_row(p_color)
			spr.region_rect = Rect2(0, floor(row * 46.75), 50, 46)
			dummy.add_child(spr)

			var tag: Label = Label.new()
			tag.text = p.get("tag", "Crew")
			tag.z_index = 20
			tag.z_as_relative = false
			tag.offset_left = -35
			tag.offset_top = -30
			tag.offset_right = 35
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.add_theme_font_size_override("font_size", 8)
			dummy.add_child(tag)

			crew_dummies.add_child(dummy)

	_refresh_helmet_slots(players)
	_refresh_color_buttons(players)
	_refresh_host_permissions()
	_refresh_top_bar()

func _on_remote_player_updated(peer_id: int, state: Dictionary) -> void:
	if _remote_players.has(peer_id) and is_instance_valid(_remote_players[peer_id]):
		_remote_players[peer_id].call("apply_remote_state", state)

func _on_remote_player_left(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		var node: Node = _remote_players[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_remote_players.erase(peer_id)

func _refresh_color_buttons(players: Array) -> void:
	var my_idx: int = 0
	if GameState.is_network_active:
		for i in range(players.size()):
			if int(players[i].get("peer_id", -1)) == GameState.my_peer_id:
				my_idx = i
				break
	elif GameState.is_room_open and not GameState.is_room_host:
		for i in range(players.size()):
			if String(players[i].get("tag", "")) == PlayerProfile.full_tag:
				my_idx = i
				break

	var my_color_idx: int = -1
	var taken: Array[bool] = [false, false, false, false]
	for i in range(players.size()):
		var c: Color = players[i].get("color", SUIT_COLORS[i % SUIT_COLORS.size()])
		var c_idx: int = _color_to_helmet_idx(c)
		if i == my_idx:
			my_color_idx = c_idx
		else:
			taken[c_idx] = true

	var btns := color_row.get_children()
	for idx in range(btns.size()):
		var btn := btns[idx] as TextureButton
		if btn == null:
			continue
		if taken[idx]:
			btn.disabled = true
			btn.position.y = 3.0
			btn.scale = Vector2(0.94, 0.94)
			btn.modulate = Color(0.42, 0.44, 0.5, 0.65)
			btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		elif idx == my_color_idx:
			btn.disabled = false
			btn.position.y = -3.0
			btn.scale = Vector2(1.05, 1.05)
			btn.modulate = Color(1.18, 1.18, 1.18, 1.0)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			btn.disabled = false
			btn.position.y = 0.0
			btn.scale = Vector2.ONE
			btn.modulate = Color(0.92, 0.94, 0.98, 1.0)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _refresh_room_type_buttons() -> void:
	var pub_atlas := AtlasTexture.new()
	pub_atlas.atlas = SETTINGS_PANEL_SHEET
	pub_atlas.region = Rect2(283, 7, 127, 32) if GameState.is_room_public else Rect2(16, 7, 125, 32)
	public_btn.texture_normal = pub_atlas

	var priv_atlas := AtlasTexture.new()
	priv_atlas.atlas = SETTINGS_PANEL_SHEET
	priv_atlas.region = Rect2(413, 9, 124, 30) if GameState.is_room_public else Rect2(142, 7, 130, 32)
	private_btn.texture_normal = priv_atlas

func _refresh_host_permissions() -> void:
	var can_edit: bool = (not GameState.is_room_open) or GameState.is_room_host
	host_lock_badge.visible = not can_edit
	mission_option.disabled = not can_edit
	modifier_option.disabled = not can_edit
	launch_site_option.disabled = not can_edit
	public_btn.disabled = not can_edit
	private_btn.disabled = not can_edit
	start_btn.disabled = not can_edit

	var dim: Color = Color.WHITE if can_edit else Color(0.58, 0.62, 0.68, 0.8)
	mission_option.modulate = dim
	modifier_option.modulate = dim
	launch_site_option.modulate = dim
	public_btn.modulate = dim
	private_btn.modulate = dim
	start_btn.modulate = dim if can_edit else Color(0.5, 0.52, 0.58, 0.7)

func _refresh_helmet_slots(players: Array) -> void:
	var count_idx: int = clampi(players.size(), 1, 4) - 1
	var digit_atlas := AtlasTexture.new()
	digit_atlas.atlas = HUD_PLAYERS_SHEET
	digit_atlas.region = DIGIT_REGIONS[count_idx]
	player_count_icon.texture = digit_atlas

	var slots := helmet_slots.get_children()
	for i in range(slots.size()):
		var slot: TextureRect = slots[i] as TextureRect
		if slot == null:
			continue
		if i < players.size():
			var c: Color = players[i].get("color", SUIT_COLORS[i % SUIT_COLORS.size()])
			var idx: int = _color_to_helmet_idx(c)
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = HUD_PLAYERS_SHEET
			atlas.region = HELMET_REGIONS[idx]
			slot.texture = atlas
			slot.visible = true
		else:
			slot.visible = false

func _color_to_helmet_idx(c: Color) -> int:
	if c.b > 0.7 and c.r < 0.5:
		return 1 # Mavi
	if c.r > 0.8 and c.g > 0.7:
		return 2 # Sarı
	if c.g > 0.7 and c.r < 0.5:
		return 3 # Yeşil
	return 0 # Kırmızı

func _refresh_top_bar() -> void:
	var m: Dictionary = GameState.current_mission
	var code_txt: String = GameState.room_code if GameState.room_code != "" else "LOKAL"
	if GameState.is_network_active and GameState.room_code != "":
		var vis_txt: String = "AÇIK" if GameState.is_room_public else "ÖZEL"
		room_info_label.text = "%s (%s)" % [code_txt, vis_txt]
	else:
		room_info_label.text = "ODA: %s" % code_txt
	mission_summary_label.text = "GÖREV:\n%s" % m.get("name", "-")
	mission_desc.text = "%s\nYörünge: %s | Güç: %.0fW | Kütle Limiti: %.0fkg" % [
		m.get("description", ""),
		m.get("orbit_label", ""),
		float(m.get("nominal_power_w", 0.0)),
		float(m.get("max_mass_kg", 0.0))
	]
	if mission_option.selected != GameState.current_mission_idx and GameState.current_mission_idx < mission_option.item_count:
		mission_option.selected = GameState.current_mission_idx
	if modifier_option.selected != GameState.current_modifier_idx and GameState.current_modifier_idx < modifier_option.item_count:
		modifier_option.selected = GameState.current_modifier_idx
	_refresh_room_type_buttons()
	_sync_launch_site_dropdown()
	_refresh_host_permissions()

func _refresh_leaderboard() -> void:
	for child in leaderboard_list.get_children():
		child.queue_free()

	var current_id: String = GameState.current_mission.get("id", "")
	var count: int = 0
	for rec in LeaderboardManager.records:
		if rec.get("mission_id", "") == current_id:
			var bar := TextureRect.new()
			bar.custom_minimum_size = Vector2(236, 24)
			var bar_atlas := AtlasTexture.new()
			bar_atlas.atlas = SETTINGS_COLORS_BAR
			bar_atlas.region = Rect2(0, 65, 267, 32)
			bar.texture = bar_atlas
			bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

			var lbl := Label.new()
			lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			lbl.offset_left = 8
			lbl.offset_right = -8
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 8)
			lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
			lbl.text = "%s — %.1fs | Skor: %d" % [
				rec.get("team", ""),
				float(rec.get("time_sec", 0.0)),
				int(rec.get("score", 0))
			]
			lbl.clip_text = true
			bar.add_child(lbl)
			leaderboard_list.add_child(bar)
			count += 1
			if count >= 3:
				break
	if count == 0:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Bu görevde henüz rekor yok."
		empty_lbl.add_theme_font_size_override("font_size", 8)
		empty_lbl.modulate = Color(0.6, 0.65, 0.72)
		leaderboard_list.add_child(empty_lbl)

func _on_mission_selected(_idx: int) -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		_refresh_top_bar()
		return
	GameState.setup_mission(mission_option.selected, modifier_option.selected)
	_sync_launch_site_dropdown()
	_refresh_leaderboard()

func _on_modifier_selected(_idx: int) -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		_refresh_top_bar()
		return
	GameState.setup_mission(mission_option.selected, modifier_option.selected)

func _on_launch_site_selected(idx: int) -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		_refresh_top_bar()
		return
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	if idx >= 0 and idx < sites.size():
		GameState.select_launch_site(sites[idx].get("id", ""))

func _sync_launch_site_dropdown() -> void:
	var sites: Array = GameState.missions_data.get("launch_sites", [])
	var target_id: String = GameState.selected_launch_site.get("id", "")
	for i in range(sites.size()):
		if sites[i].get("id", "") == target_id:
			launch_site_option.selected = i
			break

func _on_color_btn_pressed(idx: int) -> void:
	GameState.set_my_color(SUIT_COLORS[idx % SUIT_COLORS.size()])

func _on_public_btn_pressed() -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		return
	GameState.set_room_public(true)
	_refresh_room_type_buttons()

func _on_private_btn_pressed() -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		return
	GameState.set_room_public(false)
	_refresh_room_type_buttons()

func _on_toggle_settings_pressed() -> void:
	_set_settings_open(not settings_panel.visible)

func _on_close_settings_pressed() -> void:
	_set_settings_open(false)

func _on_back_menu_pressed() -> void:
	GameState.leave_room()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_start_mission_pressed() -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		return
	GameState.start_mission()
	get_tree().change_scene_to_file("res://scenes/world/station.tscn")

func _on_joystick_direction_changed(dir: Vector2) -> void:
	if player != null:
		player.virtual_move_dir = dir

func _on_interact_btn_pressed() -> void:
	if player != null and player.has_method("try_interact"):
		player.try_interact()
