extends BaseButton

const CONTROLS_SHEET: Texture2D = preload("res://assets/ui/mobile_controls.png")

@export var icon_size: Vector2 = Vector2(38.0, 47.0)

var _is_hovered: bool = false
var _icon_tex: AtlasTexture = null

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_tex = AtlasTexture.new()
	_icon_tex.atlas = CONTROLS_SHEET
	_icon_tex.region = Rect2(228, 17, 55, 68)

	mouse_entered.connect(func() -> void:
		_is_hovered = true
		queue_redraw()
	)
	mouse_exited.connect(func() -> void:
		_is_hovered = false
		queue_redraw()
	)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	var is_down: bool = is_pressed()
	var scale_f: float = 0.93 if is_down else (1.06 if _is_hovered else 1.0)
	var draw_size: Vector2 = icon_size * scale_f
	var center: Vector2 = (size * 0.5).round()
	var glow_center: Vector2 = Vector2(center.x, center.y - draw_size.y * 0.11)
	var glow_alpha: float = 0.22 if is_down else (0.18 if _is_hovered else 0.12)
	var glow_r: float = draw_size.x * 0.56

	draw_circle(glow_center, glow_r * 1.15, Color(0.20, 0.88, 1.0, glow_alpha * 0.65), true, -1.0, true)
	draw_circle(glow_center, glow_r * 0.88, Color(0.35, 0.95, 1.0, glow_alpha), true, -1.0, true)

	var tint: Color = Color(0.85, 0.95, 1.0, 1.0) if is_down else (Color(1.10, 1.10, 1.10, 1.0) if _is_hovered else Color(1.0, 1.0, 1.0, 0.95))
	if _icon_tex != null:
		draw_texture_rect(_icon_tex, Rect2(center - draw_size * 0.5, draw_size), false, tint)
