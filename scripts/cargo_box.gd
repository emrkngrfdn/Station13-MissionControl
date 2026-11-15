extends Area2D

var part_data: Dictionary = {}
var carrier: Node2D = null

func setup(data: Dictionary) -> void:
	part_data = data
	if has_node("Label"):
		$Label.text = str(data.get("name", "Kargo")).substr(0, 8)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and carrier == null:
		body.interactable_target = self

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.interactable_target == self:
		body.interactable_target = null

func interact() -> void:
	if carrier != null:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.interactable_target == self and p.carried_box == null:
			carrier = p
			p.carried_box = self
			reparent(p)
			position = Vector2(0, -18)
			break
