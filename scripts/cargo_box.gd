extends Area2D

var part_data: Dictionary = {}
var box_id: String = ""
var carrier: Node2D = null

func setup(data: Dictionary) -> void:
	part_data = data
	if data.has("_box_id"):
		box_id = String(data.get("_box_id", ""))
	if has_node("Label"):
		var lbl: Label = $Label
		lbl.text = String(data.get("name", "Kargo")).substr(0, 22)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
		lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.1, 1.0))
		lbl.add_theme_constant_override("outline_size", 3)

func _ready() -> void:
	add_to_group("cargo_box")
	if has_node("CollisionShape2D"):
		var col: CollisionShape2D = $CollisionShape2D
		if col.shape is RectangleShape2D:
			var rect: RectangleShape2D = (col.shape as RectangleShape2D).duplicate() as RectangleShape2D
			rect.size = Vector2(32, 32)
			col.shape = rect
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and bool(body.get("is_local_player")) and carrier == null:
		body.set("interactable_target", self)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and bool(body.get("is_local_player")) and body.get("interactable_target") == self:
		body.set("interactable_target", null)

func interact() -> void:
	if carrier != null:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	var target_player: Node2D = null
	var best_dist: float = 999999.0
	for p in players:
		if p is Node2D and bool(p.get("is_local_player")):
			var p_node: Node2D = p as Node2D
			if p_node.get("interactable_target") == self:
				target_player = p_node
				break
			var d: float = p_node.global_position.distance_to(global_position)
			if d < best_dist:
				best_dist = d
				target_player = p_node

	if target_player != null:
		var old_box: Node2D = target_player.get("carried_box")
		var swap_pos: Vector2 = global_position
		if old_box != null and is_instance_valid(old_box) and old_box != self:
			if target_player.has_method("drop_carried_box"):
				target_player.drop_carried_box(swap_pos)

		carrier = target_player
		target_player.set("carried_box", self)
		target_player.set("interactable_target", null)
		reparent(target_player)
		position = Vector2(0, -18)
		EventBus.status_message.emit("ALINDI: %s (Montaj Hangarı'na götür veya [E/Space] ile bırak)" % String(part_data.get("name", "Kargo")), false)
		if GameState.is_network_active and box_id != "":
			NetworkClient.send_relay("box_pickup", {
				"box_id": box_id,
				"peer_id": GameState.my_peer_id
			})
