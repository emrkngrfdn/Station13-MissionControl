extends Control

signal direction_changed(dir: Vector2)

const CONTROLS_SHEET: Texture2D = preload("res://assets/ui/mobile_controls.png")

@export var base_radius: float = 30.0
@export var knob_radius: float = 13.0
@export var max_drag_distance: float = 22.0
@export var deadzone: float = 0.15
@export var rest_center: Vector2 = Vector2(54.0, 174.0)

var current_direction: Vector2 = Vector2.ZERO

var _pointer_id: int = -1 # -1 = idle, -2 = mouse, >= 0 = touch index
var _active_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
var _base_tex: AtlasTexture = null
var _knob_tex: AtlasTexture = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_base_tex = AtlasTexture.new()
	_base_tex.atlas = CONTROLS_SHEET
	_base_tex.region = Rect2(0, 0, 100, 101)
	_knob_tex = AtlasTexture.new()
	_knob_tex.atlas = CONTROLS_SHEET
	_knob_tex.region = Rect2(124, 30, 44, 43)
	_active_center = rest_center
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_reset_joystick()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te: InputEventScreenTouch = event as InputEventScreenTouch
		if te.pressed and _pointer_id == -1:
			_pointer_id = te.index
			_start_at_local_pos(te.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _pointer_id == -1:
				_pointer_id = -2
				_start_at_local_pos(mb.position)
				accept_event()
			elif not mb.pressed and _pointer_id == -2:
				_reset_joystick()
				accept_event()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_update_from_local_pos(mm.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if _pointer_id == -1:
		return
	if _pointer_id == -2:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_reset_joystick()
		elif event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			var local_ev: InputEventMouseMotion = make_input_local(mm) as InputEventMouseMotion
			_update_from_local_pos(local_ev.position)
		return
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index == _pointer_id:
			var local_ev: InputEventScreenDrag = make_input_local(sd) as InputEventScreenDrag
			_update_from_local_pos(local_ev.position)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if not st.pressed and st.index == _pointer_id:
			_reset_joystick()

func _start_at_local_pos(local_pos: Vector2) -> void:
	_active_center = Vector2(
		clampf(local_pos.x, base_radius + 4.0, maxf(base_radius + 4.0, size.x - base_radius - 4.0)),
		clampf(local_pos.y, base_radius + 4.0, maxf(base_radius + 4.0, size.y - base_radius - 4.0))
	)
	_knob_offset = Vector2.ZERO
	if current_direction != Vector2.ZERO:
		current_direction = Vector2.ZERO
		direction_changed.emit(Vector2.ZERO)
	queue_redraw()

func _update_from_local_pos(local_pos: Vector2) -> void:
	var delta: Vector2 = local_pos - _active_center
	var dist: float = delta.length()
	if dist > max_drag_distance and dist > 0.001:
		delta = delta.normalized() * max_drag_distance
		dist = max_drag_distance
	_knob_offset = delta.round()

	var norm_strength: float = dist / max_drag_distance if max_drag_distance > 0.0 else 0.0
	var new_dir: Vector2 = Vector2.ZERO
	if norm_strength > deadzone and dist > 0.001:
		var scaled: float = (norm_strength - deadzone) / (1.0 - deadzone)
		new_dir = delta.normalized() * clampf(scaled, 0.0, 1.0)

	if new_dir != current_direction:
		current_direction = new_dir
		direction_changed.emit(current_direction)
	queue_redraw()

func _reset_joystick() -> void:
	var had_input: bool = _pointer_id != -1 or current_direction != Vector2.ZERO
	_pointer_id = -1
	_active_center = rest_center
	_knob_offset = Vector2.ZERO
	current_direction = Vector2.ZERO
	if had_input:
		direction_changed.emit(Vector2.ZERO)
	queue_redraw()

func _draw() -> void:
	var is_active: bool = _pointer_id != -1
	var center: Vector2 = (_active_center if is_active else rest_center).round()
	var alpha_mult: float = 0.92 if is_active else 0.56

	if _base_tex != null:
		var base_size: Vector2 = Vector2(base_radius * 2.0, base_radius * 2.0)
		draw_texture_rect(_base_tex, Rect2(center - base_size * 0.5, base_size), false, Color(1.0, 1.0, 1.0, alpha_mult))
	if _knob_tex != null:
		var knob_pos: Vector2 = center + _knob_offset
		var knob_size: Vector2 = Vector2(knob_radius * 2.0, knob_radius * 2.0)
		var knob_alpha: float = 1.0 if is_active else 0.80
		draw_texture_rect(_knob_tex, Rect2(knob_pos - knob_size * 0.5, knob_size), false, Color(1.0, 1.0, 1.0, knob_alpha))
