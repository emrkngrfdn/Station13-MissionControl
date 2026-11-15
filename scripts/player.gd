extends CharacterBody2D

@export var base_speed: float = 240.0

var interactable_target: Node = null
var carried_box: Node2D = null

func _ready() -> void:
	add_to_group("player")
	if GameState.lobby_players.size() > 0:
		$BodyVisual.color = GameState.lobby_players[0]["color"]

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed_mult := 0.80 if carried_box != null else 1.0
	velocity = input_dir * base_speed * speed_mult
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and interactable_target != null:
		if interactable_target.has_method("interact"):
			interactable_target.interact()
