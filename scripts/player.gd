extends CharacterBody2D

const CELL_W: float = 50.0
const CELL_H: float = 46.75
const COL_CENTER_X: Array[float] = [32.0, 28.0, 24.0, 18.0, 16.0]

@export var base_speed: float = 120.0
@export var is_local_player: bool = true
@export var peer_id: int = 0
@export var player_tag: String = ""

var interactable_target: Node = null
var carried_box: Node2D = null
var virtual_move_dir: Vector2 = Vector2.ZERO

var _row_idx: int = 0
var _anim_timer: float = 0.0
var _walk_frame: int = 0
var _vert_phase: int = 0
var _current_col: int = 0
var _net_target_pos: Vector2 = Vector2.ZERO
var _has_net_state: bool = false
var _net_send_timer: float = 0.0
var _net_idle_timer: float = 0.0
var _last_sent_sig: String = ""
var _name_label: Label = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	EventBus.lobby_updated.connect(_on_lobby_updated)
	if not is_local_player:
		collision_layer = 0
		collision_mask = 0
		_net_target_pos = global_position
		_ensure_name_label()
	else:
		EventBus.network_states_requested.connect(_on_network_states_requested)
		if GameState.is_network_active:
			call_deferred("_announce_presence")
	_sync_color_row()
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.enabled = is_local_player
		if is_local_player:
			cam.make_current()

func _exit_tree() -> void:
	if EventBus.lobby_updated.is_connected(_on_lobby_updated):
		EventBus.lobby_updated.disconnect(_on_lobby_updated)
	if EventBus.network_states_requested.is_connected(_on_network_states_requested):
		EventBus.network_states_requested.disconnect(_on_network_states_requested)

func _get_scene_tag() -> String:
	if not is_inside_tree() or get_tree().current_scene == null:
		return ""
	var p: String = get_tree().current_scene.scene_file_path
	if p.contains("waiting_room"):
		return "waiting"
	if p.contains("station"):
		return "station"
	return ""

func _announce_presence() -> void:
	if not is_local_player or not GameState.is_network_active:
		return
	force_send_network_state()
	NetworkClient.send_relay("request_states", { "scene": _get_scene_tag() })

func _on_network_states_requested(scene_tag: String) -> void:
	if is_local_player and GameState.is_network_active and (scene_tag == "" or scene_tag == _get_scene_tag()):
		force_send_network_state()

func force_send_network_state() -> void:
	if not is_local_player or not GameState.is_network_active or not is_inside_tree():
		return
	_net_send_timer = 0.0
	_net_idle_timer = 0.0
	_last_sent_sig = "%d|%.1f|%.1f|%d|%s|%.2f" % [
		_current_col,
		global_position.x,
		global_position.y,
		1 if sprite.flip_h else 0,
		str(carried_box != null),
		sprite.rotation
	]
	NetworkClient.send_relay("player_state", {
		"scene": _get_scene_tag(),
		"x": snappedf(global_position.x, 0.1),
		"y": snappedf(global_position.y, 0.1),
		"anim_col": _current_col,
		"flip_h": sprite.flip_h,
		"rot": snappedf(sprite.rotation, 0.01),
		"off_y": snappedf(sprite.offset.y, 0.1)
	})

func setup_remote(p_peer_id: int, p_tag: String, start_pos: Vector2) -> void:
	is_local_player = false
	peer_id = p_peer_id
	player_tag = p_tag
	global_position = start_pos
	_net_target_pos = start_pos
	collision_layer = 0
	collision_mask = 0
	_ensure_name_label()
	if sprite != null:
		_sync_color_row()
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.enabled = false

func _ensure_name_label() -> void:
	if _name_label == null:
		_name_label = Label.new()
		_name_label.z_index = 20
		_name_label.z_as_relative = false
		_name_label.offset_left = -45.0
		_name_label.offset_top = -32.0
		_name_label.offset_right = 45.0
		_name_label.offset_bottom = -18.0
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.add_theme_font_size_override("font_size", 8)
		_name_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		_name_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.09, 0.95))
		_name_label.add_theme_constant_override("outline_size", 2)
		add_child(_name_label)
	_name_label.text = player_tag

func apply_remote_state(state: Dictionary) -> void:
	var msg_scene: String = String(state.get("scene", ""))
	var my_scene: String = _get_scene_tag()
	if msg_scene != "" and my_scene != "" and msg_scene != my_scene:
		return
	_net_target_pos = Vector2(
		float(state.get("x", global_position.x)),
		float(state.get("y", global_position.y))
	)
	if not _has_net_state or global_position.distance_to(_net_target_pos) > 160.0:
		global_position = _net_target_pos
		_has_net_state = true
	sprite.flip_h = bool(state.get("flip_h", false))
	sprite.rotation = float(state.get("rot", 0.0))
	sprite.offset.y = float(state.get("off_y", 0.0))
	_update_sprite_frame(clampi(int(state.get("anim_col", 0)), 0, 4))

func _on_lobby_updated(_players: Array) -> void:
	_sync_color_row()
	if is_local_player and GameState.is_network_active:
		call_deferred("force_send_network_state")

func _sync_color_row() -> void:
	var c: Color = GameState.get_local_player_color() if is_local_player else GameState.get_player_color_by_peer(peer_id)
	_row_idx = _color_to_row(c)
	_update_sprite_frame(_current_col)

func _color_to_row(c: Color) -> int:
	if c.b > 0.7 and c.r < 0.5:
		return 1 # Mavi
	if c.r > 0.8 and c.g > 0.7:
		return 2 # Sarı
	if c.g > 0.7 and c.r < 0.5:
		return 3 # Yeşil
	return 0 # Kırmızı

func _physics_process(delta: float) -> void:
	if not is_local_player:
		global_position = global_position.lerp(_net_target_pos, minf(1.0, delta * 18.0))
		return
	var kb_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var input_dir: Vector2 = (kb_dir + virtual_move_dir).limit_length(1.0)
	var speed_mult: float = 0.80 if carried_box != null else 1.0
	velocity = input_dir * base_speed * speed_mult
	move_and_slide()
	if input_dir.length() > 0.1 and get_slide_collision_count() > 0:
		if get_position_delta().length() < velocity.length() * delta * 0.5:
			_apply_corner_nudge(input_dir.normalized(), velocity.length() * delta)

	if carried_box != null:
		if input_dir.x < -0.05:
			sprite.flip_h = true
		elif input_dir.x > 0.05:
			sprite.flip_h = false
		sprite.rotation = 0.0
		if input_dir.length() > 0.1:
			_anim_timer += delta
			if _anim_timer >= 0.14:
				_anim_timer = 0.0
				_vert_phase = (_vert_phase + 1) % 2
			sprite.offset.y = -1.5 if _vert_phase == 0 else 0.0
		else:
			_anim_timer = 0.0
			sprite.offset.y = 0.0
		_update_sprite_frame(4)
	elif input_dir.length() > 0.1:
		if abs(input_dir.y) > abs(input_dir.x):
			# Dikey hareket (aşağı / yukarı): ön yüz yürüme animasyonu
			sprite.flip_h = false
			_anim_timer += delta
			if _anim_timer >= 0.11:
				_anim_timer = 0.0
				_vert_phase = (_vert_phase + 1) % 4
			match _vert_phase:
				0:
					sprite.offset.y = -1.5
					sprite.rotation = -0.07
				2:
					sprite.offset.y = -1.5
					sprite.rotation = 0.07
				_:
					sprite.offset.y = 0.0
					sprite.rotation = 0.0
			_update_sprite_frame(0)
		else:
			# Yatay hareket (sağ / sol): yan yürüme kareleri
			if input_dir.x < -0.05:
				sprite.flip_h = true
			elif input_dir.x > 0.05:
				sprite.flip_h = false
			sprite.rotation = 0.0
			sprite.offset.y = 0.0
			_anim_timer += delta
			if _anim_timer >= 0.14:
				_anim_timer = 0.0
				_walk_frame = (_walk_frame + 1) % 3
			_update_sprite_frame(1 + _walk_frame)
	else:
		_anim_timer = 0.0
		_vert_phase = 0
		sprite.flip_h = false
		sprite.rotation = 0.0
		sprite.offset.y = 0.0
		_update_sprite_frame(0)

	if GameState.is_network_active:
		_net_send_timer += delta
		_net_idle_timer += delta
		var sig: String = "%d|%.1f|%.1f|%d|%s|%.2f" % [
			_current_col,
			global_position.x,
			global_position.y,
			1 if sprite.flip_h else 0,
			str(carried_box != null),
			sprite.rotation
		]
		if (sig != _last_sent_sig and (_net_send_timer >= 0.066 or input_dir.length() <= 0.05)) or _net_idle_timer >= 1.0:
			force_send_network_state()

func _apply_corner_nudge(dir: Vector2, step_len: float) -> void:
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var probe: Vector2 = dir * maxf(step_len, 2.5)
	for d: float in [1.5, 3.0, 4.5, 6.0]:
		var clear_pos: bool = not test_move(global_transform.translated(perp * d), probe)
		var clear_neg: bool = not test_move(global_transform.translated(-perp * d), probe)
		var nudge_dir: Vector2 = Vector2.ZERO
		if clear_pos and not clear_neg:
			nudge_dir = perp
		elif clear_neg and not clear_pos:
			nudge_dir = -perp
		if nudge_dir != Vector2.ZERO:
			var nudge_amt: float = minf(d, maxf(step_len, 1.5))
			if not test_move(global_transform, nudge_dir * nudge_amt):
				move_and_collide(nudge_dir * nudge_amt)
				move_and_collide(dir * (step_len * 0.6))
			return

func _update_sprite_frame(col: int) -> void:
	_current_col = col
	if sprite == null:
		return
	var y_pos: float = floor(_row_idx * CELL_H)
	sprite.region_rect = Rect2(col * CELL_W, y_pos, CELL_W, 46.0)
	var cx: float = COL_CENTER_X[col]
	sprite.offset.x = (cx - 25.0) if sprite.flip_h else (25.0 - cx)

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	if event.is_action_pressed("ui_accept"):
		try_interact()
	elif event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo and (ke.keycode == KEY_E or ke.physical_keycode == KEY_E):
			try_interact()

func _get_terminal_reach(t: Node2D, base_reach: float = 42.0) -> float:
	var scale_mult: float = maxf(1.0, maxf(absf(t.scale.x), absf(t.scale.y)))
	return maxf(base_reach, 34.0 * scale_mult)

func _is_terminal_in_range(t: Node2D, foot_pos: Vector2, base_reach: float = 42.0) -> bool:
	if t is Area2D and (t as Area2D).overlaps_body(self):
		return true
	return t.global_position.distance_to(foot_pos) <= _get_terminal_reach(t, base_reach)

func _find_nearest_interactable() -> Node:
	var best_node: Node = null
	var best_dist: float = 999999.0
	var foot_pos: Vector2 = global_position + Vector2(0, 6)

	if carried_box != null and is_instance_valid(carried_box):
		for t in get_tree().get_nodes_in_group("terminal"):
			if t is Node2D and int(t.get("terminal_type")) == 2: # ASSEMBLY
				var t_node: Node2D = t as Node2D
				if _is_terminal_in_range(t_node, foot_pos, 46.0):
					return t_node

	if carried_box == null:
		for b in get_tree().get_nodes_in_group("cargo_box"):
			if b is Node2D and is_instance_valid(b) and b.get("carrier") == null:
				var d_box: float = (b as Node2D).global_position.distance_to(foot_pos)
				if d_box < 42.0 and d_box < best_dist:
					best_dist = d_box
					best_node = b

	for t in get_tree().get_nodes_in_group("terminal"):
		if t is Node2D and is_instance_valid(t):
			var t_node: Node2D = t as Node2D
			var d_term: float = t_node.global_position.distance_to(foot_pos)
			if _is_terminal_in_range(t_node, foot_pos, 42.0) and d_term < best_dist:
				best_dist = d_term
				best_node = t_node

	return best_node

func try_interact() -> void:
	var target: Node = _find_nearest_interactable()
	if target == null and interactable_target != null and is_instance_valid(interactable_target):
		var foot_pos: Vector2 = global_position + Vector2(0, 6)
		if interactable_target is Node2D:
			var t_node: Node2D = interactable_target as Node2D
			if _is_terminal_in_range(t_node, foot_pos, 48.0):
				target = interactable_target

	if target != null and is_instance_valid(target):
		interactable_target = target
		if target.has_method("interact"):
			target.interact()
			return
	if carried_box != null and is_instance_valid(carried_box):
		drop_carried_box()

func drop_carried_box(target_pos: Vector2 = Vector2.INF) -> void:
	if carried_box == null or not is_instance_valid(carried_box):
		carried_box = null
		return
	var box: Node2D = carried_box
	var world_parent: Node = get_parent()
	if world_parent != null:
		box.reparent(world_parent)
	if target_pos == Vector2.INF:
		box.global_position = global_position + Vector2(0, 22)
	else:
		box.global_position = target_pos
	box.set("carrier", null)
	carried_box = null
	var box_name: String = String(box.get("part_data").get("name", "Kargo")) if box.get("part_data") is Dictionary else "Kargo"
	EventBus.status_message.emit("YERE BIRAKILDI: %s" % box_name, false)
	if is_local_player and GameState.is_network_active:
		var bid: String = String(box.get("box_id"))
		if bid != "":
			NetworkClient.send_relay("box_drop", {
				"box_id": bid,
				"x": box.global_position.x,
				"y": box.global_position.y
			})
