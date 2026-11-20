extends Control

signal direction_changed(dir: Vector2)

@export var base_radius: float = 26.0
@export var knob_radius: float = 11.0
@export var max_drag_distance: float = 22.0
@export var deadzone: float = 0.15
@export var base_color: Color = Color(0.08, 0.14, 0.24, 0.55)
@export var border_color: Color = Color(0.38, 0.68, 0.94, 0.78)
@export var knob_color: Color = Color(0.55, 0.85, 1.0, 0.85)
@export var active_knob_color: Color = Color(0.45, 0.96, 0.72, 0.95)

var current_direction: Vector2 = Vector2.ZERO

var _pointer_id: int = -1 # -1 = idle, -2 = mouse, >= 0 = touch index
var _knob_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_reset_joystick()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te: InputEventScreenTouch = event as InputEventScreenTouch
		if te.pressed and _pointer_id == -1:
			_pointer_id = te.index
			_update_from_local_pos(te.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _pointer_id == -1:
				_pointer_id = -2
				_update_from_local_pos(mb.position)
				accept_event()
			elif not mb.pressed and _pointer_id == -2:
				_reset_joystick()
				accept_event()
	elif event is InputEventMouseMotion and _pointer_id == -2:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_update_from_local_pos(mm.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if _pointer_id < 0:
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

func _update_from_local_pos(local_pos: Vector2) -> void:
	var center: Vector2 = size * 0.5
	var delta: Vector2 = local_pos - center
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
	_knob_offset = Vector2.ZERO
	current_direction = Vector2.ZERO
	if had_input:
		direction_changed.emit(Vector2.ZERO)
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = (size * 0.5).round()
	var is_active: bool = _pointer_id != -1
	draw_circle(center, base_radius, base_color, true, -1.0, false)
	draw_arc(center, base_radius, 0.0, TAU, 16, border_color, 1.5, false)
	draw_arc(center, base_radius * 0.45, 0.0, TAU, 12, Color(border_color.r, border_color.g, border_color.b, 0.25), 1.0, false)

	var k_color: Color = active_knob_color if is_active else knob_color
	var knob_pos: Vector2 = center + _knob_offset
	draw_circle(knob_pos, knob_radius, k_color, true, -1.0, false)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 12, Color(0.05, 0.09, 0.16, 0.85), 1.2, false)
