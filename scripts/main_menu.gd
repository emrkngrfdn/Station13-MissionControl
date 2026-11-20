extends Control

@onready var nickname_input: LineEdit = %NicknameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var status_label: Label = %MenuStatusLabel

var _open_browser_btn: Button = null
var _browser_modal: PanelContainer = null
var _search_input: LineEdit = null
var _public_rooms_list: VBoxContainer = null
var _refresh_timer: float = 0.0
var _is_connecting: bool = false

func _ready() -> void:
	nickname_input.text = PlayerProfile.nickname
	status_label.text = "Profilin: %s" % PlayerProfile.full_tag
	room_code_input.placeholder_text = "Özel Oda Kodu (örn: KZM-47)"

	var solo_btn: Button = get_node_or_null("CenterBox/MenuPanel/VBox/SoloBtn") as Button
	if solo_btn != null:
		solo_btn.visible = false

	NetworkClient.public_rooms_fetched.connect(_on_public_rooms_fetched)
	NetworkClient.room_created.connect(_on_net_room_created)
	NetworkClient.room_joined.connect(_on_net_room_joined)
	NetworkClient.join_failed.connect(_on_net_join_failed)

	_setup_room_browser_ui()

	if GameState.last_join_error != "":
		status_label.text = GameState.last_join_error
		status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		GameState.last_join_error = ""
	elif not NetworkClient.is_server_configured():
		status_label.text = "Çevrimiçi sunucu henüz ayarlı değil."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))

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

func _setup_room_browser_ui() -> void:
	var vbox: Node = get_node_or_null("CenterBox/MenuPanel/VBox")
	if vbox == null or _browser_modal != null:
		return

	_open_browser_btn = Button.new()
	_open_browser_btn.text = "AÇIK ODALARI ARA (PUBLIC)"
	_open_browser_btn.add_theme_font_size_override("font_size", 10)
	_open_browser_btn.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	_open_browser_btn.pressed.connect(_on_open_browser_pressed)

	var status_idx: int = status_label.get_index()
	vbox.add_child(_open_browser_btn)
	vbox.move_child(_open_browser_btn, status_idx)

	_browser_modal = PanelContainer.new()
	_browser_modal.visible = false
	_browser_modal.anchors_preset = Control.PRESET_CENTER
	_browser_modal.anchor_left = 0.5
	_browser_modal.anchor_top = 0.5
	_browser_modal.anchor_right = 0.5
	_browser_modal.anchor_bottom = 0.5
	_browser_modal.offset_left = -220.0
	_browser_modal.offset_top = -125.0
	_browser_modal.offset_right = 220.0
	_browser_modal.offset_bottom = 125.0
	_browser_modal.z_index = 20

	var modal_style: StyleBoxFlat = StyleBoxFlat.new()
	modal_style.bg_color = Color(0.05, 0.08, 0.14, 0.98)
	modal_style.border_width_left = 2
	modal_style.border_width_top = 2
	modal_style.border_width_right = 2
	modal_style.border_width_bottom = 2
	modal_style.border_color = Color(0.32, 0.72, 0.96, 1.0)
	modal_style.content_margin_left = 10.0
	modal_style.content_margin_right = 10.0
	modal_style.content_margin_top = 8.0
	modal_style.content_margin_bottom = 8.0
	_browser_modal.add_theme_stylebox_override("panel", modal_style)

	var modal_vbox: VBoxContainer = VBoxContainer.new()
	modal_vbox.add_theme_constant_override("separation", 6)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)

	var browser_title: Label = Label.new()
	browser_title.text = "AÇIK ODALAR (PUBLIC) — ODA ARAMA"
	browser_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_title.add_theme_font_size_override("font_size", 11)
	browser_title.add_theme_color_override("font_color", Color(0.45, 0.88, 1.0))
	header_row.add_child(browser_title)

	var close_btn: Button = Button.new()
	close_btn.text = "X KAPAT"
	close_btn.add_theme_font_size_override("font_size", 9)
	close_btn.pressed.connect(_on_close_browser_pressed)
	header_row.add_child(close_btn)
	modal_vbox.add_child(header_row)

	var search_row: HBoxContainer = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)

	_search_input = LineEdit.new()
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.placeholder_text = "Oda kodu, kurucu veya görev ara..."
	_search_input.add_theme_font_size_override("font_size", 9)
	_search_input.text_changed.connect(_on_search_changed)
	search_row.add_child(_search_input)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "YENİLE"
	refresh_btn.add_theme_font_size_override("font_size", 9)
	refresh_btn.pressed.connect(_refresh_public_rooms)
	search_row.add_child(refresh_btn)
	modal_vbox.add_child(search_row)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_public_rooms_list = VBoxContainer.new()
	_public_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_public_rooms_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_public_rooms_list)
	modal_vbox.add_child(scroll)

	_browser_modal.add_child(modal_vbox)
	add_child(_browser_modal)

func _on_open_browser_pressed() -> void:
	if _browser_modal != null:
		_browser_modal.visible = true
		_refresh_timer = 0.0
		_refresh_public_rooms()

func _on_close_browser_pressed() -> void:
	if _browser_modal != null:
		_browser_modal.visible = false

func _on_search_changed(_new_text: String) -> void:
	_refresh_public_rooms()

func _refresh_public_rooms() -> void:
	if _public_rooms_list == null:
		return
	for child in _public_rooms_list.get_children():
		child.queue_free()

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
		var err_lbl: Label = Label.new()
		err_lbl.text = error_msg
		err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_lbl.add_theme_font_size_override("font_size", 9)
		err_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		_public_rooms_list.add_child(err_lbl)
		return

	if rooms.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Açık (Public) oda bulunamadı. Özel odalar burada görünmez."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
		_public_rooms_list.add_child(empty_lbl)
		return

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
	var create_btn: Button = get_node_or_null("CenterBox/MenuPanel/VBox/CreateRoomBtn") as Button
	var join_btn: Button = get_node_or_null("CenterBox/MenuPanel/VBox/JoinRow/JoinBtn") as Button
	var solo_btn: Button = get_node_or_null("CenterBox/MenuPanel/VBox/SoloBtn") as Button
	if create_btn != null:
		create_btn.disabled = connecting
	if join_btn != null:
		join_btn.disabled = connecting
	if solo_btn != null:
		solo_btn.disabled = connecting
	if _open_browser_btn != null:
		_open_browser_btn.disabled = connecting
	if msg != "":
		status_label.text = msg
		status_label.add_theme_color_override("font_color", color)

func _on_join_listed_room(code: String) -> void:
	if _is_connecting:
		return
	_apply_nickname()
	_set_connecting_state(true, "Odaya bağlanılıyor (%s)..." % code)
	NetworkClient.join_room(code, PlayerProfile.full_tag)

func _apply_nickname() -> void:
	PlayerProfile.set_nickname(nickname_input.text)
	status_label.text = "Profilin: %s" % PlayerProfile.full_tag

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
