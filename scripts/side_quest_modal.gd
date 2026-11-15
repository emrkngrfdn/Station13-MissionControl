extends PanelContainer

@onready var title_label: Label = %QuestTitle
@onready var desc_label: Label = %QuestDesc
@onready var options_box: VBoxContainer = %OptionsBox
@onready var feedback_label: Label = %QuestFeedback

var _resolved_quest_ids: Array[String] = []
var _current_quest: Dictionary = {}
var _is_resolving: bool = false

var _has_timer: bool = false
var _time_remaining: float = 0.0
var _time_limit: float = 12.0

var _timer_box: VBoxContainer = null
var _timer_label: Label = null
var _timer_bar: ProgressBar = null
var _close_btn: Button = null

func _ready() -> void:
	visible = false
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_close_btn = get_node_or_null("VBox/Header/CloseBtn") as Button
	_ensure_timer_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_triggered.connect(_on_random_crisis_triggered)
	EventBus.mission_started.connect(_reset_quests)

func _ensure_timer_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _timer_box != null:
		return

	_timer_box = VBoxContainer.new()
	_timer_box.add_theme_constant_override("separation", 2)
	_timer_box.visible = false

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 11)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	_timer_label.text = "ACİL MÜDAHALE SÜRESİ: 12.0s"

	_timer_bar = ProgressBar.new()
	_timer_bar.custom_minimum_size = Vector2(0, 10)
	_timer_bar.show_percentage = false
	_timer_bar.max_value = 100.0
	_timer_bar.value = 100.0

	_timer_box.add_child(_timer_label)
	_timer_box.add_child(_timer_bar)

	var desc_idx: int = desc_label.get_index()
	vbox.add_child(_timer_box)
	vbox.move_child(_timer_box, desc_idx)

func _process(delta: float) -> void:
	if not visible or _is_resolving or not _has_timer:
		return

	_time_remaining = max(0.0, _time_remaining - delta)
	var pct: float = (_time_remaining / max(0.1, _time_limit)) * 100.0
	if _timer_bar != null:
		_timer_bar.value = pct
	if _timer_label != null:
		var mode: String = String(_current_quest.get("timeout_mode", "random"))
		var mode_hint: String = "(Süre biterse SİSTEM KAYBEDER!)" if mode == "fail_penalty" else "(Süre biterse rastgele seçilir)"
		_timer_label.text = "ACİL MÜDAHALE SÜRESİ: %.1fs %s" % [_time_remaining, mode_hint]
		if _time_remaining <= 5.0:
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))

	if _time_remaining <= 0.0:
		_on_crisis_timeout()

func _reset_quests() -> void:
	_resolved_quest_ids.clear()
	_is_resolving = false
	_has_timer = false

func _on_random_crisis_triggered(quest_data: Dictionary) -> void:
	if visible:
		return
	var q_id: String = String(quest_data.get("id", ""))
	if q_id != "" and _resolved_quest_ids.has(q_id):
		return
	open_quest(quest_data)

func _on_terminal_opened(terminal_name: String) -> void:
	if visible:
		return
	if terminal_name in ["POWER_LAB", "BRIEFING"]:
		var quests: Array = GameState.get_available_side_quests_for_mission()
		var room_quests: Array = []
		var crisis_quests: Array = []

		for q in quests:
			var q_id: String = String(q.get("id", ""))
			if _resolved_quest_ids.has(q_id) or GameState.resolved_quest_ids.has(q_id):
				continue
			if bool(q.get("is_random_crisis", false)):
				crisis_quests.append(q)
			elif terminal_name == "BRIEFING" or String(q.get("room", "")) == terminal_name:
				room_quests.append(q)

		if not room_quests.is_empty():
			open_quest(room_quests[0])
			return

		if terminal_name == "BRIEFING" and not crisis_quests.is_empty():
			crisis_quests.shuffle()
			open_quest(crisis_quests[0])

func open_quest(quest_data: Dictionary) -> void:
	_current_quest = quest_data
	_is_resolving = false
	visible = true

	var is_crisis: bool = bool(quest_data.get("is_random_crisis", false))
	var limit: float = float(quest_data.get("time_limit_sec", 0.0))
	if is_crisis and limit <= 0.0:
		limit = 12.0

	_has_timer = limit > 0.0
	_time_limit = limit
	_time_remaining = limit

	if _timer_box != null:
		_timer_box.visible = _has_timer
	if _timer_bar != null:
		_timer_bar.value = 100.0
	if _close_btn != null:
		_close_btn.visible = not is_crisis

	title_label.text = String(quest_data.get("title", "MÜHENDİSLİK KARARI"))
	title_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.42, 0.35) if is_crisis else Color(0.95, 0.72, 0.25)
	)
	desc_label.text = String(quest_data.get("description", ""))
	feedback_label.text = ""

	for child in options_box.get_children():
		child.queue_free()

	for opt in quest_data.get("options", []):
		var btn: Button = Button.new()
		btn.text = String(opt.get("label", "Seçenek"))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_option_chosen.bind(opt))
		options_box.add_child(btn)

func _on_crisis_timeout() -> void:
	if _is_resolving:
		return
	var mode: String = String(_current_quest.get("timeout_mode", "random"))
	if mode == "fail_penalty" and _current_quest.has("timeout_outcome"):
		var fail_opt: Dictionary = _current_quest.get("timeout_outcome", {})
		_resolve_with_option(fail_opt, true)
		return

	var options: Array = _current_quest.get("options", [])
	if not options.is_empty():
		var random_opt: Dictionary = options[randi() % options.size()].duplicate(true)
		_resolve_with_option(random_opt, true, true)

func _on_option_chosen(opt: Dictionary) -> void:
	_resolve_with_option(opt, false, false)

func _resolve_with_option(opt: Dictionary, is_timeout: bool, was_random: bool = false) -> void:
	if _is_resolving:
		return
	_is_resolving = true
	_has_timer = false

	var q_id: String = String(_current_quest.get("id", ""))
	if q_id != "" and not _resolved_quest_ids.has(q_id):
		_resolved_quest_ids.append(q_id)

	for child in options_box.get_children():
		if child is Button:
			(child as Button).disabled = true

	GameState.apply_side_quest_option(opt, q_id)

	var result_msg: String = String(opt.get("result_note", ""))
	if not GameState.decision_logs.is_empty():
		result_msg = GameState.decision_logs[-1]

	if is_timeout and was_random:
		result_msg = "SÜRE DOLDU! Rastgele seçim yapıldı → " + result_msg

	var is_bad: bool = is_timeout or result_msg.contains("HASAR") or result_msg.contains("BAŞARISIZ") or result_msg.contains("ÇÖKTÜ") or result_msg.contains("SAPMA") or result_msg.contains("TÜKENDİ") or result_msg.contains("TAKLA") or result_msg.contains("SÜRE DOLDU")
	feedback_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.45, 0.4) if is_bad else Color(0.4, 0.95, 0.55)
	)
	feedback_label.text = "SONUÇ: " + result_msg

	await get_tree().create_timer(2.2 if is_timeout else 1.8).timeout
	if is_instance_valid(self) and _is_resolving:
		visible = false
		_is_resolving = false

func _on_close_pressed() -> void:
	_is_resolving = false
	_has_timer = false
	visible = false
