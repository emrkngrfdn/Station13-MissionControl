extends Area2D

enum TerminalType { BRIEFING, MARKET, ASSEMBLY, POWER_LAB, DSN_COMMS, LAUNCH }

@export var terminal_type: TerminalType = TerminalType.MARKET
@export var prompt_text: String = "[E] Etkileşim"
@export var show_placeholder_visual: bool = true
@export var beacon_mode: bool = false

var _beacon_t: float = 0.0
var _base_label_y: float = -32.0
var _idle_text: String = ""

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
	if beacon_mode:
		_setup_beacon_style()
	else:
		$PromptLabel.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _setup_beacon_style() -> void:
	var inv_sx: float = 1.0 / maxf(absf(scale.x), 0.1)
	var inv_sy: float = 1.0 / maxf(absf(scale.y), 0.1)
	$PromptLabel.scale = Vector2(inv_sx, inv_sy)
	$PromptLabel.position = Vector2(-48.0 * inv_sx, -32.0 * inv_sy)
	_base_label_y = $PromptLabel.position.y
	_idle_text = prompt_text.to_upper() + " ▼"
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.content_margin_left = 6.0
	sb.content_margin_top = 2.0
	sb.content_margin_right = 6.0
	sb.content_margin_bottom = 3.0
	sb.bg_color = Color(0.05, 0.1, 0.18, 0.92)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 0.8, 0.3, 1)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	sb.corner_radius_bottom_left = 2
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_size = 2
	$PromptLabel.add_theme_stylebox_override("normal", sb)
	$PromptLabel.add_theme_color_override("font_color", Color(1, 0.88, 0.42, 1))
	$PromptLabel.text = _idle_text
	$PromptLabel.modulate = Color.WHITE
	$PromptLabel.visible = true

func _process(delta: float) -> void:
	if beacon_mode and $PromptLabel.visible:
		_beacon_t += delta
		var inv_sy: float = 1.0 / maxf(absf(scale.y), 0.1)
		$PromptLabel.position.y = _base_label_y + sin(_beacon_t * 3.2) * 2.5 * inv_sy

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.interactable_target = self
		if beacon_mode:
			$PromptLabel.text = "[E] ETKİLEŞİM ▼"
			$PromptLabel.modulate = Color(0.55, 1.0, 0.78, 1.0)
		else:
			$PromptLabel.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.interactable_target == self:
		body.interactable_target = null
		if beacon_mode:
			$PromptLabel.text = _idle_text
			$PromptLabel.modulate = Color.WHITE
		else:
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
