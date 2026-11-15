extends CharacterBody2D

@export var follow_speed: float = 110.0
@export var follow_distance: float = 26.0

var target_player: Node2D = null
var carried_box: Node2D = null

func _ready() -> void:
	visible = false
	queue_free()
	return

func _physics_process(_delta: float) -> void:
	if target_player == null:
		return
	var dist := global_position.distance_to(target_player.global_position)
	if dist > follow_distance:
		var dir := (target_player.global_position - global_position).normalized()
		velocity = dir * follow_speed
		move_and_slide()
