extends CharacterBody2D

const CELL_W: float = 50.0
const CELL_H: float = 46.75
const COL_CENTER_X: Array[float] = [32.0, 28.0, 24.0, 18.0, 16.0]

@export var base_speed: float = 120.0

var interactable_target: Node = null
var carried_box: Node2D = null

var _row_idx: int = 0
var _anim_timer: float = 0.0
var _walk_frame: int = 0
var _vert_phase: int = 0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	EventBus.lobby_updated.connect(_on_lobby_updated)
	_sync_color_row()

<<<<<<< HEAD
func _on_lobby_updated(_players: Array) -> void:
	_sync_color_row()

func _sync_color_row() -> void:
	if GameState.lobby_players.size() > 0:
		var c: Color = GameState.lobby_players[0].get("color", Color.CORAL)
		_row_idx = _color_to_row(c)
		_update_sprite_frame(0)

func _color_to_row(c: Color) -> int:
	if c.b > 0.7 and c.r < 0.5:
		return 1 # Mavi
	if c.r > 0.8 and c.g > 0.7:
		return 2 # Sarı
	if c.g > 0.7 and c.r < 0.5:
		return 3 # Yeşil
	return 0 # Kırmızı

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed_mult := 0.80 if carried_box != null else 1.0
=======
func _physics_process(_delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed_mult: float = 0.80 if carried_box != null else 1.0
>>>>>>> origin/zuley
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

func _apply_corner_nudge(dir: Vector2, step_len: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var probe: Vector2 = dir * maxf(step_len, 2.5)
	for d: float in [1.5, 3.0, 4.5, 6.0]:
		var clear_pos := not test_move(global_transform.translated(perp * d), probe)
		var clear_neg := not test_move(global_transform.translated(-perp * d), probe)
		var nudge_dir := Vector2.ZERO
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
	var y_pos: float = floor(_row_idx * CELL_H)
	sprite.region_rect = Rect2(col * CELL_W, y_pos, CELL_W, 46.0)
	var cx: float = COL_CENTER_X[col]
	sprite.offset.x = (cx - 25.0) if sprite.flip_h else (25.0 - cx)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		try_interact()

func try_interact() -> void:
	if interactable_target != null and is_instance_valid(interactable_target):
		if interactable_target.has_method("interact"):
			interactable_target.interact()
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
