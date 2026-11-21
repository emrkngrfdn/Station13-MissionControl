extends Control

const ROOM_BROWSER_PANEL_TEX: Texture2D = preload("res://assets/ui/room_browser_panel.png")
const ROOM_BROWSER_ELEMENTS_TEX: Texture2D = preload("res://assets/ui/room_browser_elements.png")

@onready var nickname_input: LineEdit = %NicknameInput
@onready var player_tag_label: Label = %PlayerTagLabel
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var status_label: Label = %MenuStatusLabel
@onready var create_room_btn: TextureButton = %CreateRoomBtn
@onready var join_btn: TextureButton = %JoinBtn
@onready var open_browser_btn: TextureButton = %OpenBrowserBtn

var _browser_backdrop: ColorRect = null
var _browser_modal: TextureRect = null
var _search_input: LineEdit = null
var _rooms_scroll: ScrollContainer = null
var _public_rooms_list: VBoxContainer = null
var _empty_state_box: VBoxContainer = null
var _empty_state_label: Label = null
var _refresh_timer: float = 0.0
var _is_connecting: bool = false

func _ready() -> void:
	nickname_input.text = PlayerProfile.nickname
	if PlayerProfile.player_id != "":
		player_tag_label.text = "#%s" % PlayerProfile.player_id
		player_tag_label.visible = true
	else:
		player_tag_label.visible = false
	status_label.text = ""
	status_label.visible = false
	room_code_input.placeholder_text = "Özel Oda Kodu"

	_setup_texture_button(create_room_btn)
	_setup_texture_button(join_btn)
	_setup_texture_button(open_browser_btn)

	NetworkClient.public_rooms_fetched.connect(_on_public_rooms_fetched)
	NetworkClient.room_created.connect(_on_net_room_created)
	NetworkClient.room_joined.connect(_on_net_room_joined)
	NetworkClient.join_failed.connect(_on_net_join_failed)

	_setup_room_browser_ui()

	if GameState.last_join_error != "":
		status_label.text = GameState.last_join_error
		status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		status_label.visible = true
		GameState.last_join_error = ""
	elif not NetworkClient.is_server_configured():
		status_label.text = "Çevrimiçi sunucu henüz ayarlı değil."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
		status_label.visible = true

func _exit_tree() -> void:
	if NetworkClient.public_rooms_fetched.is_connected(_on_public_rooms_fetched):
		NetworkClient.public_rooms_fetched.disconnect(_on_public_rooms_fetched)
	if NetworkClient.room_created.is_connected(_on_net_room_created):
		NetworkClient.room_created.disconnect(_on_net_room_created)
	if NetworkClient.room_joined.is_connected(_on_net_room_joined):
		NetworkClient.room_joined.disconnect(_on_net_room_joined)
	if NetworkClient.join_failed.is_connected(_on_net_join_failed):
		NetworkClient.join_failed.disconnect(_on_net_join_failed)

func _process(delta: float) -> void:
	if _browser_modal == null or not _browser_modal.visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= 3.0:
		_refresh_timer = 0.0
		_refresh_public_rooms()

func _setup_texture_button(btn: TextureButton) -> void:
	if btn == null:
		return
	btn.pivot_offset = btn.size * 0.5
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			btn.scale = Vector2(1.02, 1.02)
			btn.modulate = Color(1.12, 1.12, 1.12, 1.0)
	)
	btn.mouse_exited.connect(func() -> void:
		btn.scale = Vector2.ONE
		btn.modulate = Color(0.6, 0.65, 0.7, 0.7) if btn.disabled else Color.WHITE
	)
	btn.button_down.connect(func() -> void:
		if not btn.disabled:
			btn.scale = Vector2(0.97, 0.97)
			btn.modulate = Color(0.85, 0.9, 0.96, 1.0)
	)
	btn.button_up.connect(func() -> void:
		if btn.disabled:
			btn.scale = Vector2.ONE
			btn.modulate = Color(0.6, 0.65, 0.7, 0.7)
		elif btn.is_hovered():
			btn.scale = Vector2(1.02, 1.02)
			btn.modulate = Color(1.12, 1.12, 1.12, 1.0)
		else:
			btn.scale = Vector2.ONE
			btn.modulate = Color.WHITE
	)

func _setup_room_browser_ui() -> void:
	if _browser_modal != null:
		return

	_browser_backdrop = ColorRect.new()
	_browser_backdrop.visible = false
	_browser_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_browser_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_browser_backdrop.z_index = 19
	add_child(_browser_backdrop)

	_browser_modal = TextureRect.new()
	_browser_modal.visible = false
	_browser_modal.texture = ROOM_BROWSER_PANEL_TEX
	_browser_modal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_browser_modal.stretch_mode = TextureRect.STRETCH_SCALE
	_browser_modal.position = Vector2(100, 55)
	_browser_modal.size = Vector2(441, 250)
	_browser_modal.z_index = 20

	var close_tex: AtlasTexture = AtlasTexture.new()
	close_tex.atlas = ROOM_BROWSER_ELEMENTS_TEX
	close_tex.region = Rect2(352, 0, 60, 23)
	var close_btn: TextureButton = TextureButton.new()
	close_btn.texture_normal = close_tex
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_SCALE
	close_btn.position = Vector2(364, 11)
	close_btn.size = Vector2(60, 23)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_on_close_browser_pressed)
	_setup_texture_button(close_btn)
	_browser_modal.add_child(close_btn)

	var search_tex: AtlasTexture = AtlasTexture.new()
	search_tex.atlas = ROOM_BROWSER_ELEMENTS_TEX
	search_tex.region = Rect2(0, 24, 348, 26)
	var search_bg: TextureRect = TextureRect.new()
	search_bg.texture = search_tex
	search_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	search_bg.stretch_mode = TextureRect.STRETCH_SCALE
	search_bg.position = Vector2(18, 37)
	search_bg.size = Vector2(342, 24)
	_browser_modal.add_child(search_bg)

	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	empty_style.content_margin_left = 4.0
	empty_style.content_margin_right = 4.0
	empty_style.content_margin_bottom = 3.0
	_search_input = LineEdit.new()
	_search_input.position = Vector2(22, -1)
	_search_input.size = Vector2(314, 22)
	_search_input.placeholder_text = "Oda kodu, kurucu veya görev ara..."
	_search_input.add_theme_font_size_override("font_size", 9)
	_search_input.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_search_input.add_theme_color_override("font_placeholder_color", Color(0.48, 0.60, 0.75, 0.85))
	_search_input.add_theme_stylebox_override("normal", empty_style)
	_search_input.add_theme_stylebox_override("focus", empty_style)
	_search_input.text_changed.connect(_on_search_changed)
	search_bg.add_child(_search_input)

	var refresh_tex: AtlasTexture = AtlasTexture.new()
	refresh_tex.atlas = ROOM_BROWSER_ELEMENTS_TEX
	refresh_tex.region = Rect2(352, 25, 60, 23)
	var refresh_btn: TextureButton = TextureButton.new()
	refresh_btn.texture_normal = refresh_tex
	refresh_btn.ignore_texture_size = true
	refresh_btn.stretch_mode = TextureButton.STRETCH_SCALE
	refresh_btn.position = Vector2(364, 37)
	refresh_btn.size = Vector2(60, 23)
	refresh_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	refresh_btn.pressed.connect(_refresh_public_rooms.bind(false))
	_setup_texture_button(refresh_btn)
	_browser_modal.add_child(refresh_btn)

	_rooms_scroll = ScrollContainer.new()
	_rooms_scroll.position = Vector2(22, 70)
	_rooms_scroll.size = Vector2(397, 160)
	_rooms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_public_rooms_list = VBoxContainer.new()
	_public_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_public_rooms_list.add_theme_constant_override("separation", 4)
	_rooms_scroll.add_child(_public_rooms_list)
	_browser_modal.add_child(_rooms_scroll)

	_empty_state_box = VBoxContainer.new()
	_empty_state_box.visible = false
	_empty_state_box.position = Vector2(22, 70)
	_empty_state_box.size = Vector2(397, 160)
	_empty_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_state_box.add_theme_constant_override("separation", 8)

	var astro_tex: AtlasTexture = AtlasTexture.new()
	astro_tex.atlas = ROOM_BROWSER_ELEMENTS_TEX
	astro_tex.region = Rect2(149, 78, 110, 65)
	var astro_rect: TextureRect = TextureRect.new()
	astro_rect.texture = astro_tex
	astro_rect.custom_minimum_size = Vector2(110, 65)
	astro_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_empty_state_box.add_child(astro_rect)

	_empty_state_label = Label.new()
	_empty_state_label.text = "PUBLIC ODA BULUNAMADI"
	_empty_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_state_label.add_theme_font_size_override("font_size", 10)
	_empty_state_label.add_theme_color_override("font_color", Color(0.76, 0.87, 1.0))
	_empty_state_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1, 0.95))
	_empty_state_label.add_theme_constant_override("outline_size", 2)
	_empty_state_label.add_theme_constant_override("line_spacing", 3)
	_empty_state_box.add_child(_empty_state_label)
	_browser_modal.add_child(_empty_state_box)

	add_child(_browser_modal)

func _on_open_browser_pressed() -> void:
	if _browser_modal != null:
		if _browser_backdrop != null:
			_browser_backdrop.visible = true
		_browser_modal.visible = true
		_refresh_timer = 0.0
		_refresh_public_rooms(true)

func _on_close_browser_pressed() -> void:
	if _browser_modal != null:
		_browser_modal.visible = false
	if _browser_backdrop != null:
		_browser_backdrop.visible = false

func _on_search_changed(_new_text: String) -> void:
	_refresh_public_rooms(false)

func _refresh_public_rooms(show_loading: bool = false) -> void:
	if _public_rooms_list == null:
		return
	var is_empty_already: bool = _empty_state_box != null and _empty_state_box.visible
	if show_loading and not is_empty_already and _public_rooms_list.get_child_count() == 0:
		if _rooms_scroll != null:
			_rooms_scroll.visible = true
		var loading_lbl: Label = Label.new()
		loading_lbl.text = "Açık odalar sunucudan yükleniyor..."
		loading_lbl.add_theme_font_size_override("font_size", 9)
		loading_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
		_public_rooms_list.add_child(loading_lbl)

	var query: String = _search_input.text if _search_input != null else ""
	NetworkClient.fetch_public_rooms(query)

func _on_public_rooms_fetched(rooms: Array, error_msg: String) -> void:
	if _public_rooms_list == null:
		return
	for child in _public_rooms_list.get_children():
		child.queue_free()

	if error_msg != "":
		if _empty_state_box != null:
			_empty_state_box.visible = false
		if _rooms_scroll != null:
			_rooms_scroll.visible = true
		var err_lbl: Label = Label.new()
		err_lbl.text = error_msg
		err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_lbl.add_theme_font_size_override("font_size", 9)
		err_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		_public_rooms_list.add_child(err_lbl)
		return

	if rooms.is_empty():
		if _rooms_scroll != null:
			_rooms_scroll.visible = false
		if _empty_state_box != null:
			_empty_state_box.visible = true
		return

	if _empty_state_box != null:
		_empty_state_box.visible = false
	if _rooms_scroll != null:
		_rooms_scroll.visible = true

	for r in rooms:
		var code: String = String(r.get("room_code", ""))
		var host_name: String = String(r.get("host_name", "Host"))
		var mission_name: String = String(r.get("mission_name", "Görev"))
		var p_count: int = int(r.get("player_count", 1))
		var max_p: int = int(r.get("max_players", 4))

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var info_lbl: Label = Label.new()
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_lbl.clip_text = true
		info_lbl.add_theme_font_size_override("font_size", 9)
		info_lbl.text = "[%s] %s | %s (%d/%d)" % [code, host_name, mission_name, p_count, max_p]
		row.add_child(info_lbl)

		var join_btn: Button = Button.new()
		join_btn.text = "KATIL"
		join_btn.add_theme_font_size_override("font_size", 9)
		join_btn.disabled = _is_connecting
		join_btn.pressed.connect(_on_join_listed_room.bind(code))
		row.add_child(join_btn)

		_public_rooms_list.add_child(row)

func _set_connecting_state(connecting: bool, msg: String = "", color: Color = Color(0.55, 0.88, 1.0)) -> void:
	_is_connecting = connecting
	var dim: Color = Color(0.6, 0.65, 0.7, 0.7) if connecting else Color.WHITE
	for btn in [create_room_btn, join_btn, open_browser_btn]:
		if btn != null:
			btn.disabled = connecting
			btn.scale = Vector2.ONE
			btn.modulate = dim
	if msg != "":
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)
		status_label.visible = true
	else:
		status_label.text = ""
		status_label.visible = false

func _on_join_listed_room(code: String) -> void:
	if _is_connecting:
		return
	_apply_nickname()
	_set_connecting_state(true, "Odaya bağlanılıyor (%s)..." % code)
	NetworkClient.join_room(code, PlayerProfile.full_tag)

func _apply_nickname() -> void:
	PlayerProfile.set_nickname(nickname_input.text)
	nickname_input.text = PlayerProfile.nickname

func _on_create_room_pressed() -> void:
	if _is_connecting:
		return
	_apply_nickname()
	GameState.leave_room()
	GameState.reset_lobby()
	_set_connecting_state(true, "Çevrimiçi oda oluşturuluyor...")
	NetworkClient.create_room(
		false,
		PlayerProfile.full_tag,
		GameState.current_mission_idx,
		GameState.current_modifier_idx,
		String(GameState.current_mission.get("name", "")),
		String(GameState.selected_rocket.get("id", "")),
		String(GameState.selected_launch_site.get("id", ""))
	)

func _on_join_room_pressed() -> void:
	if _is_connecting:
		return
	_apply_nickname()
	var code: String = room_code_input.text.strip_edges().to_upper()
	if code == "":
		status_label.text = "Lütfen bir Oda Kodu girin (örn: KZM-47)!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		status_label.visible = true
		return
	_set_connecting_state(true, "Odaya bağlanılıyor (%s)..." % code)
	NetworkClient.join_room(code, PlayerProfile.full_tag)

func _on_net_room_created(peer_id: int, code: String, net_state: Dictionary) -> void:
	_set_connecting_state(false)
	GameState.apply_network_room_state(peer_id, code, net_state, true)
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")

func _on_net_room_joined(peer_id: int, code: String, net_state: Dictionary) -> void:
	_set_connecting_state(false)
	GameState.apply_network_room_state(peer_id, code, net_state, false)
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")

func _on_net_join_failed(error_msg: String) -> void:
	_set_connecting_state(false, error_msg, Color(1.0, 0.4, 0.35))
	if _browser_modal != null and _browser_modal.visible:
		_refresh_public_rooms()
