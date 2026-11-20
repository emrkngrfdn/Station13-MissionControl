extends CanvasLayer

var _btn: Button = null
var _last_is_fullscreen: bool = false

func _ready() -> void:
	layer = 90
	_btn = Button.new()
	_btn.name = "FullscreenToggleBtn"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_btn.anchor_left = 1.0
	_btn.anchor_top = 0.0
	_btn.anchor_right = 1.0
	_btn.anchor_bottom = 0.0
	_btn.offset_left = -78.0
	_btn.offset_right = -6.0
	_btn.offset_top = 6.0
	_btn.offset_bottom = 24.0
	_btn.add_theme_font_size_override("font_size", 8)

	var sb_norm: StyleBoxFlat = StyleBoxFlat.new()
	sb_norm.bg_color = Color(0.06, 0.11, 0.19, 0.88)
	sb_norm.border_width_left = 1
	sb_norm.border_width_top = 1
	sb_norm.border_width_right = 1
	sb_norm.border_width_bottom = 1
	sb_norm.border_color = Color(0.36, 0.72, 0.96, 0.9)
	sb_norm.corner_radius_top_left = 2
	sb_norm.corner_radius_top_right = 2
	sb_norm.corner_radius_bottom_right = 2
	sb_norm.corner_radius_bottom_left = 2
	sb_norm.content_margin_left = 5.0
	sb_norm.content_margin_right = 5.0
	sb_norm.content_margin_top = 2.0
	sb_norm.content_margin_bottom = 2.0

	var sb_hov: StyleBoxFlat = sb_norm.duplicate() as StyleBoxFlat
	sb_hov.bg_color = Color(0.12, 0.2, 0.34, 0.95)
	sb_hov.border_color = Color(0.58, 0.9, 1.0, 1.0)

	_btn.add_theme_stylebox_override("normal", sb_norm)
	_btn.add_theme_stylebox_override("hover", sb_hov)
	_btn.add_theme_stylebox_override("pressed", sb_hov)
	_btn.add_theme_color_override("font_color", Color(0.84, 0.95, 1.0, 1.0))

	_btn.pressed.connect(_on_fullscreen_pressed)
	add_child(_btn)
	_refresh_button(true)

func _process(_delta: float) -> void:
	_update_vertical_offset()
	var is_fs: bool = _is_fullscreen()
	if is_fs != _last_is_fullscreen:
		_refresh_button(false)

func _update_vertical_offset() -> void:
	if _btn == null or not is_inside_tree():
		return
	var cur: Node = get_tree().current_scene
	var is_station: bool = cur != null and cur.scene_file_path.contains("station.tscn")
	var top_y: float = 29.0 if is_station else 6.0
	if not is_equal_approx(_btn.offset_top, top_y):
		_btn.offset_top = top_y
		_btn.offset_bottom = top_y + 18.0

func _is_fullscreen() -> bool:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _refresh_button(force: bool) -> void:
	var is_fs: bool = _is_fullscreen()
	if not force and is_fs == _last_is_fullscreen:
		return
	_last_is_fullscreen = is_fs
	if _btn != null:
		_btn.text = "[✕] KÜÇÜLT" if is_fs else "[⛶] TAM EKRAN"

func _on_fullscreen_pressed() -> void:
	if _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("try { if (screen.orientation && screen.orientation.unlock) { screen.orientation.unlock(); } } catch(e) {}")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("try { if (screen.orientation && screen.orientation.lock) { screen.orientation.lock('landscape').catch(function(){}); } } catch(e) {}")
	_refresh_button(true)
