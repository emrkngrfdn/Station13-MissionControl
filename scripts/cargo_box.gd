extends Area2D

var part_data: Dictionary = {}
var carrier: Node2D = null

func setup(data: Dictionary) -> void:
	part_data = data
	if has_node("Label"):
		var lbl: Label = $Label
		lbl.text = String(data.get("name", "Kargo")).substr(0, 10)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
		lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.1, 1.0))
		lbl.add_theme_constant_override("outline_size", 3)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and carrier == null:
		body.set("interactable_target", self)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.get("interactable_target") == self:
		body.set("interactable_target", null)

func interact() -> void:
	if carrier != null:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.get("interactable_target") == self:
			var old_box: Node2D = p.get("carried_box")
			var swap_pos: Vector2 = global_position
			if old_box != null and is_instance_valid(old_box) and old_box != self:
				if p.has_method("drop_carried_box"):
					p.drop_carried_box(swap_pos)

			carrier = p
			p.set("carried_box", self)
			p.set("interactable_target", null)
			reparent(p)
			position = Vector2(0, -18)
			EventBus.status_message.emit("ALINDI: %s (Montaj Hangarı'na götür veya [INTERACT] ile bırak)" % String(part_data.get("name", "Kargo")), false)
			break
