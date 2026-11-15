extends Node2D

const ASTRONAUT_SHEET: Texture2D = preload("res://assets/astronaut_sheet.png")
const HUD_PLAYERS_SHEET: Texture2D = preload("res://assets/ui/hud_players_sheet.png")

const HELMET_REGIONS: Array[Rect2] = [
	Rect2(8, 62, 19, 19),  # Kırmızı
	Rect2(56, 62, 19, 19), # Mavi
	Rect2(32, 62, 19, 19), # Sarı
	Rect2(80, 62, 19, 19)  # Yeşil
]

const CREW_POSITIONS: Array[Vector2] = [
	Vector2(370, 158),
	Vector2(415, 158),
	Vector2(370, 210)
]

const SUIT_COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.35, 1),
	Color(0.25, 0.75, 0.98, 1),
	Color(0.98, 0.82, 0.25, 1),
	Color(0.32, 0.88, 0.55, 1)
]

@onready var room_info_label: Label = %RoomInfoLabel
@onready var mission_summary_label: Label = %MissionSummaryLabel
@onready var player_count_label: Label = %PlayerCountLabel
@onready var helmet_slots: Control = %HelmetSlots
@onready var settings_panel: PanelContainer = %HostSettingsPanel
@onready var mission_option: OptionButton = %MissionOption
@onready var modifier_option: OptionButton = %ModifierOption
@onready var launch_site_option: OptionButton = %LaunchSiteOption
@onready var mission_desc: Label = %MissionDesc
@onready var add_player_input: LineEdit = %AddPlayerInput
@onready var leaderboard_list: VBoxContainer = %LeaderboardList
@onready var crew_dummies: Node2D = $CrewDummies
@onready var player: CharacterBody2D = $Player

var _visibility_toggle_btn: Button = null

func _ready() -> void:
	settings_panel.visible = false
	_ensure_visibility_setting_ui()
	_populate_selectors()
	EventBus.lobby_updated.connect(_on_lobby_updated)
	EventBus.telemetry_changed.connect(_refresh_top_bar)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	_on_lobby_updated(GameState.lobby_players)
	_refresh_top_bar()
	_refresh_leaderboard()
	_apply_host_permissions()

func _ensure_visibility_setting_ui() -> void:
	var vbox: Node = settings_panel.get_node_or_null("VBox")
	if vbox == null or _visibility_toggle_btn != null:
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl: Label = Label.new()
	lbl.text = "Oda Görünürlüğü:"
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)

	_visibility_toggle_btn = Button.new()
	_visibility_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_visibility_toggle_btn.add_theme_font_size_override("font_size", 10)
	_visibility_toggle_btn.pressed.connect(_on_toggle_room_visibility_pressed)
	row.add_child(_visibility_toggle_btn)

	vbox.add_child(row)
	vbox.move_child(row, 1)

func _on_toggle_room_visibility_pressed() -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		return
	GameState.set_room_public(not GameState.is_room_public)

func _apply_host_permissions() -> void:
	var is_host: bool = GameState.is_room_host or not GameState.is_room_open
	mission_option.disabled = not is_host
	modifier_option.disabled = not is_host
	launch_site_option.disabled = not is_host
	if _visibility_toggle_btn != null:
		_visibility_toggle_btn.disabled = not is_host
	if add_player_input != null:
		add_player_input.editable = is_host
	var start_btn: BaseButton = get_node_or_null("HUD/TopBar/StartBtn") as BaseButton
	if start_btn == null:
		start_btn = find_child("StartBtn", true, false) as BaseButton
	if start_btn != null:
		start_btn.disabled = not is_host
		if not is_host and start_btn is Button:
			(start_btn as Button).text = "KURUCU BEKLENİYOR"

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
		settings_panel.visible = not settings_panel.visible

func _color_to_row(c: Color) -> int:
	if c.b > 0.7 and c.r < 0.5:
		return 1 # Mavi
	if c.r > 0.8 and c.g > 0.7:
		return 2 # Sarı
	if c.g > 0.7 and c.r < 0.5:
		return 3 # Yeşil
	return 0 # Kırmızı

func _on_lobby_updated(players: Array) -> void:
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
	_refresh_top_bar()

func _refresh_helmet_slots(players: Array) -> void:
	player_count_label.text = str(players.size())
	var slots: Array[Node] = helmet_slots.get_children()
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
	var vis_tag: String = "PUBLIC" if GameState.is_room_public else "PRIVATE"
	room_info_label.text = "ODA: %s (%s) | OYUNCU: %d/4" % [GameState.room_code, vis_tag, GameState.lobby_players.size()]
	mission_summary_label.text = "GÖREV: %s | BÜTÇE: $%.0fM | ROKET: %s" % [
		m.get("name", "-"),
		GameState.budget_m,
		GameState.selected_rocket.get("name", "-")
	]
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
	if _visibility_toggle_btn != null:
		if GameState.is_room_public:
			_visibility_toggle_btn.text = "PUBLIC (Açık Odalarda Görünür)"
			_visibility_toggle_btn.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6))
		else:
			_visibility_toggle_btn.text = "PRIVATE (Sadece Oda Koduyla Giriş)"
			_visibility_toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_sync_launch_site_dropdown()
	_apply_host_permissions()

func _refresh_leaderboard() -> void:
	for child in leaderboard_list.get_children():
		child.queue_free()

	var current_id: String = GameState.current_mission.get("id", "")
	var count: int = 0
	for rec in LeaderboardManager.records:
		if rec.get("mission_id", "") == current_id:
			var lbl: Label = Label.new()
			lbl.text = "%s — %.1fs | Skor: %d" % [
				rec.get("team", ""),
				float(rec.get("time_sec", 0.0)),
				int(rec.get("score", 0))
			]
			leaderboard_list.add_child(lbl)
			count += 1
	if count == 0:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Bu görevde henüz rekor yok."
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

func _on_add_player_pressed() -> void:
	if GameState.add_player_to_lobby(add_player_input.text):
		add_player_input.text = ""

func _on_color_btn_pressed(idx: int) -> void:
	GameState.set_host_color(SUIT_COLORS[idx % SUIT_COLORS.size()])

func _on_toggle_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible

func _on_close_settings_pressed() -> void:
	settings_panel.visible = false

func _on_back_menu_pressed() -> void:
	GameState.leave_room()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_start_mission_pressed() -> void:
	if GameState.is_room_open and not GameState.is_room_host:
		return
	GameState.start_mission()
	get_tree().change_scene_to_file("res://scenes/world/station.tscn")
