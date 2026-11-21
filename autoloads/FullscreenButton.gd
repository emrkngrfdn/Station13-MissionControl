extends CanvasLayer

const FULLSCREEN_SHEET: Texture2D = preload("res://assets/ui/btn_fullscreen.png")

var _btn: TextureButton = null
var _tex_shrink: AtlasTexture = null
var _tex_expand: AtlasTexture = null
var _last_is_fullscreen: bool = false

func _ready() -> void:
	layer = 90

	_tex_shrink = AtlasTexture.new()
	_tex_shrink.atlas = FULLSCREEN_SHEET
	_tex_shrink.region = Rect2(0, 0, 19, 19)

	_tex_expand = AtlasTexture.new()
	_tex_expand.atlas = FULLSCREEN_SHEET
	_tex_expand.region = Rect2(24, 0, 19, 19)

	_btn = TextureButton.new()
	_btn.name = "FullscreenToggleBtn"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_btn.ignore_texture_size = true
	_btn.stretch_mode = TextureButton.STRETCH_SCALE
	_btn.anchor_left = 1.0
	_btn.anchor_top = 0.0
	_btn.anchor_right = 1.0
	_btn.anchor_bottom = 0.0
	_btn.offset_left = -29.0
	_btn.offset_right = -6.0
	_btn.offset_top = 6.0
	_btn.offset_bottom = 29.0
	_btn.pivot_offset = Vector2(11.5, 11.5)

	_btn.mouse_entered.connect(func() -> void:
		_btn.scale = Vector2(1.08, 1.08)
		_btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
	)
	_btn.mouse_exited.connect(func() -> void:
		_btn.scale = Vector2.ONE
		_btn.modulate = Color.WHITE
	)
	_btn.button_down.connect(func() -> void:
		_btn.scale = Vector2(0.94, 0.94)
		_btn.modulate = Color(0.85, 0.9, 0.96, 1.0)
	)
	_btn.button_up.connect(func() -> void:
		if _btn.is_hovered():
			_btn.scale = Vector2(1.08, 1.08)
			_btn.modulate = Color(1.15, 1.15, 1.15, 1.0)
		else:
			_btn.scale = Vector2.ONE
			_btn.modulate = Color.WHITE
	)

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
		_btn.offset_bottom = top_y + 23.0

func _is_fullscreen() -> bool:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _refresh_button(force: bool) -> void:
	var is_fs: bool = _is_fullscreen()
	if not force and is_fs == _last_is_fullscreen:
		return
	_last_is_fullscreen = is_fs
	if _btn != null:
		_btn.texture_normal = _tex_shrink if is_fs else _tex_expand
		_btn.tooltip_text = "Küçült" if is_fs else "Tam Ekran"

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
