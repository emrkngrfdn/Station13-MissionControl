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
var _time_limit: float = 20.0

var _timer_box: VBoxContainer = null
var _timer_label: Label = null
var _timer_bar: ProgressBar = null
var _close_btn: Button = null
var _ack_btn: Button = null
var _fail_mission_btn: Button = null

func _ready() -> void:
	visible = false
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_close_btn = get_node_or_null("VBox/Header/CloseBtn") as Button
	_ensure_extra_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_triggered.connect(_on_random_crisis_triggered)
	EventBus.mission_started.connect(_reset_quests)

func _ensure_extra_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null:
		return

	if _timer_box == null:
		_timer_box = VBoxContainer.new()
		_timer_box.add_theme_constant_override("separation", 2)
		_timer_box.visible = false

		_timer_label = Label.new()
		_timer_label.add_theme_font_size_override("font_size", 11)
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
		_timer_label.text = "ACİL MÜDAHALE SÜRESİ: 20.0s"

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

	if _ack_btn == null:
		_ack_btn = Button.new()
		_ack_btn.text = "OKUDUM / KAPAT"
		_ack_btn.visible = false
		_ack_btn.pressed.connect(_on_close_pressed)
		vbox.add_child(_ack_btn)

	if _fail_mission_btn == null:
		_fail_mission_btn = Button.new()
		_fail_mission_btn.text = "BÜTÇE TÜKENDİ — GÖREVİ BAŞARISIZ SONLANDIR"
		_fail_mission_btn.visible = false
		_fail_mission_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		_fail_mission_btn.pressed.connect(_on_fail_mission_pressed)
		vbox.add_child(_fail_mission_btn)

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
	if terminal_name == "BRIEFING":
		GameState.mark_briefing_completed()
		EventBus.status_message.emit("BRİFİNG TAMAMLANDI: Görev hedefleri ve mühendislik kısıtları onaylandı.", false)
		var quests: Array = GameState.get_available_side_quests_for_mission()
		for q in quests:
			var q_id: String = String(q.get("id", ""))
			if not bool(q.get("is_random_crisis", false)) and not _resolved_quest_ids.has(q_id) and not GameState.resolved_quest_ids.has(q_id):
				if String(q.get("room", "")) != "POWER_LAB":
					open_quest(q)
					return
		_open_briefing_summary()
	elif terminal_name == "POWER_LAB":
		var quests: Array = GameState.get_available_side_quests_for_mission()
		for q in quests:
			var q_id: String = String(q.get("id", ""))
			if not bool(q.get("is_random_crisis", false)) and String(q.get("room", "")) == "POWER_LAB":
				if not _resolved_quest_ids.has(q_id) and not GameState.resolved_quest_ids.has(q_id):
					open_quest(q)
					return

func _open_briefing_summary() -> void:
	_current_quest = {}
	_is_resolving = true
	_has_timer = false
	visible = true

	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = true

	var m: Dictionary = GameState.current_mission
	title_label.text = "GÖREV BRİFİNGİ ONAYLANDI: %s" % String(m.get("name", "Görev"))
	title_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
	desc_label.text = "%s\n\n• Yörünge: %s\n• Nominal Güç: %.0f W | Kütle Limiti: %.0f kg\n• Hedef Bilim Puanı: %d" % [
		String(m.get("description", "")),
		String(m.get("orbit_label", "")),
		float(m.get("nominal_power_w", 0.0)),
		float(m.get("max_mass_kg", 0.0)),
		int(m.get("target_science", 500))
	]
	for child in options_box.get_children():
		child.queue_free()
	feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	feedback_label.text = "Brifing tamamlandı! Şimdi Tedarik Mağazası ve Güç Lab odalarına geçebilirsin."

func open_quest(quest_data: Dictionary) -> void:
	_current_quest = quest_data
	_is_resolving = false
	visible = true

	var is_crisis: bool = bool(quest_data.get("is_random_crisis", false))
	var limit: float = float(quest_data.get("time_limit_sec", 0.0))
	if is_crisis and limit <= 0.0:
		limit = 20.0

	_has_timer = limit > 0.0
	_time_limit = limit
	_time_remaining = limit

	if _timer_box != null:
		_timer_box.visible = _has_timer
	if _timer_bar != null:
		_timer_bar.value = 100.0
	if _close_btn != null:
		_close_btn.visible = not is_crisis
	if _ack_btn != null:
		_ack_btn.visible = false
	if _fail_mission_btn != null:
		_fail_mission_btn.visible = false

	title_label.text = String(quest_data.get("title", "MÜHENDİSLİK KARARI"))
	title_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.42, 0.35) if is_crisis else Color(0.95, 0.72, 0.25)
	)
	desc_label.text = String(quest_data.get("description", ""))
	feedback_label.text = ""

	for child in options_box.get_children():
		child.queue_free()

	var affordable_count: int = 0
	for opt in quest_data.get("options", []):
		var b_delta: float = float(opt.get("budget_delta", 0.0))
		var can_afford: bool = b_delta >= 0.0 or (GameState.budget_m + b_delta >= 0.0)
		if can_afford:
			affordable_count += 1
		var btn: Button = Button.new()
		btn.text = String(opt.get("label", "Seçenek")) + ("" if can_afford else " [YETERSİZ BÜTÇE]")
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not can_afford:
			btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		btn.pressed.connect(_on_option_chosen.bind(opt))
		options_box.add_child(btn)

	if affordable_count == 0 and not is_crisis:
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		feedback_label.text = "HATA — BÜTÇE TÜKENDİ! Bu karar için yeterli bütçeniz kalmadı (Mevcut: $%.0fM). Görev başarısız!" % GameState.budget_m
		EventBus.status_message.emit("BÜTÇE TÜKENDİ: Güç Lab / Brifing kararı için paranız kalmadı — Görev Başarısız!", true)
		if _fail_mission_btn != null:
			_fail_mission_btn.visible = true

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
	if not GameState.is_random_quest_budget_valid(opt):
		var req_cost: float = abs(float(opt.get("budget_delta", 0.0)))
		var err_msg: String = "HATA — BÜTÇE YETERSİZ! Bu seçenek için $%.0fM gerekiyor (Mevcut bütçen: $%.0fM)." % [
			req_cost, GameState.budget_m
		]
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		feedback_label.text = err_msg
		EventBus.status_message.emit(err_msg, true)
		return
	_resolve_with_option(opt, false, false)

func _on_fail_mission_pressed() -> void:
	visible = false
	GameState.decision_logs.append("Bütçe tamamen tükendiği için Power Lab / Brifing kararı verilemedi ve görev başarısız sonlandırıldı.")
	get_tree().change_scene_to_file("res://scenes/world/landing_sim.tscn")

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

	# Otomatik kapanmaz: Oyuncu sonucu rahatça okuduktan sonra kendi kapatır
	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = true

func _on_close_pressed() -> void:
	_is_resolving = false
	_has_timer = false
	if _ack_btn != null:
		_ack_btn.visible = false
	if _fail_mission_btn != null:
		_fail_mission_btn.visible = false
	visible = false
