extends Area2D

enum TerminalType { BRIEFING, MARKET, ASSEMBLY, POWER_LAB, DSN_COMMS, LAUNCH }

@export var terminal_type: TerminalType = TerminalType.MARKET
@export var prompt_text: String = "[E] Etkileşim"
@export var show_placeholder_visual: bool = true

func _ready() -> void:
	add_to_group("terminal")
	$ConsoleVisual.visible = show_placeholder_visual
	$PromptLabel.text = prompt_text
	if terminal_type == TerminalType.DSN_COMMS:
		position.y += 28.0
	if has_node("CollisionShape2D"):
		var col: CollisionShape2D = $CollisionShape2D
		if col.shape is CircleShape2D:
			var circ: CircleShape2D = (col.shape as CircleShape2D).duplicate() as CircleShape2D
			circ.radius = 30.0
			col.shape = circ
	$PromptLabel.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.interactable_target = self
		$PromptLabel.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.interactable_target == self:
		body.interactable_target = null
		$PromptLabel.visible = false

func interact() -> void:
	match terminal_type:
		TerminalType.ASSEMBLY:
			_try_install_carried_box()
		_:
			EventBus.terminal_opened.emit(TerminalType.keys()[terminal_type])

func _try_install_carried_box() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.carried_box != null and is_instance_valid(p.carried_box):
			var box: Node2D = p.carried_box
			if GameState.install_part(box.part_data):
				p.carried_box = null
				box.queue_free()
			return
	EventBus.status_message.emit("MONTAJ HANGARI: Monte etmek için önce kargo bandından bir ekipman kutusu alıp buraya getir!", true)
