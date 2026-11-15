extends CharacterBody2D

@export var base_speed: float = 240.0

var interactable_target: Node = null
var carried_box: Node2D = null

func _ready() -> void:
	add_to_group("player")
	if GameState.lobby_players.size() > 0:
		$BodyVisual.color = GameState.lobby_players[0]["color"]

func _physics_process(_delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed_mult: float = 0.80 if carried_box != null else 1.0
	velocity = input_dir * base_speed * speed_mult
	move_and_slide()

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
