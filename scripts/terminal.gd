extends Area2D

enum TerminalType { BRIEFING, MARKET, ASSEMBLY, POWER_LAB, DSN_COMMS, LAUNCH }

@export var terminal_type: TerminalType = TerminalType.MARKET
@export var prompt_text: String = "[E] Etkileşim"

func _ready() -> void:
	$PromptLabel.text = prompt_text
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
		if p.interactable_target == self and p.carried_box != null:
			var box: Node2D = p.carried_box
			GameState.install_part(box.part_data)
			p.carried_box = null
			box.queue_free()
			break
