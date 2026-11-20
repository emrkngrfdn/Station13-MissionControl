extends PanelContainer

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")

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
var _option_buttons: Array[Button] = []

var _orbit_game_active: bool = false
var _orbit_alignment_done: bool = false
var _orbit_cursor_deg: float = 20.0
var _orbit_dir: float = 1.0
var _orbit_target_deg: float = 98.0
var _orbit_status_lbl: Label = null
var _orbit_needle: ColorRect = null
var _orbit_lock_btn: Button = null

var _wiring_done: bool = false
var _wire_fault_triggered: bool = false
var _wire_bonus_active: bool = false
var _bg_wire_trip_timer: float = 0.0
var _next_bg_wire_trip_interval: float = 48.0
var _bg_wire_trip_count: int = 0
var _dragging_wire_id: int = -1
var _drag_mouse_pos: Vector2 = Vector2.ZERO
var _matched_wires: Array[int] = []
var _wire_defs: Array[Dictionary] = []
var _right_wire_order: Array[int] = []
var _wire_canvas: Control = null
var _pending_result_msg: String = ""

func _ready() -> void:
	visible = false
	z_index = 60
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_font_size_override("font_size", 11)
	feedback_label.add_theme_font_size_override("font_size", 10)
	_close_btn = get_node_or_null("VBox/Header/CloseBtn") as Button
	StationFrameDrawer.apply_modal_style(self, "blue")
	StationFrameDrawer.style_close_button(_close_btn)
	_ensure_extra_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_triggered.connect(_on_random_crisis_triggered)
	EventBus.mission_started.connect(_reset_quests)
	EventBus.telemetry_changed.connect(_on_vote_telemetry_updated)

func _exit_tree() -> void:
	if EventBus.terminal_opened.is_connected(_on_terminal_opened):
		EventBus.terminal_opened.disconnect(_on_terminal_opened)
	if EventBus.side_quest_triggered.is_connected(_on_random_crisis_triggered):
		EventBus.side_quest_triggered.disconnect(_on_random_crisis_triggered)
	if EventBus.mission_started.is_connected(_reset_quests):
		EventBus.mission_started.disconnect(_reset_quests)
	if EventBus.telemetry_changed.is_connected(_on_vote_telemetry_updated):
		EventBus.telemetry_changed.disconnect(_on_vote_telemetry_updated)

func _set_frame_accent(mode: String) -> void:
	StationFrameDrawer.apply_modal_style(self, mode)

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
		_timer_label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
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
		_ack_btn.add_theme_font_size_override("font_size", 10)
		_ack_btn.visible = false
		_ack_btn.pressed.connect(_on_close_pressed)
		vbox.add_child(_ack_btn)

	if _fail_mission_btn == null:
		_fail_mission_btn = Button.new()
		_fail_mission_btn.text = "BÜTÇE TÜKENDİ — GÖREVİ BAŞARISIZ SONLANDIR"
		_fail_mission_btn.add_theme_font_size_override("font_size", 10)
		_fail_mission_btn.visible = false
		_fail_mission_btn.add_theme_color_override("font_color", Color(0.95, 0.5, 0.48))
		_fail_mission_btn.pressed.connect(_on_fail_mission_pressed)
		vbox.add_child(_fail_mission_btn)

func _process(delta: float) -> void:
	if GameState.is_mission_active and _wiring_done and _bg_wire_trip_count < 2 and (not GameState.is_network_active or GameState.is_room_host):
		var in_crisis: bool = visible and bool(_current_quest.get("is_random_crisis", false))
		if not in_crisis and not visible:
			_bg_wire_trip_timer += delta
			if _bg_wire_trip_timer >= _next_bg_wire_trip_interval:
				_bg_wire_trip_timer = 0.0
				_next_bg_wire_trip_interval = randf_range(40.0, 70.0)
				_trigger_background_wire_trip()

	if visible and _orbit_game_active:
		_orbit_cursor_deg += _orbit_dir * 115.0 * delta
		if _orbit_cursor_deg >= 180.0:
			_orbit_cursor_deg = 180.0
			_orbit_dir = -1.0
		elif _orbit_cursor_deg <= 0.0:
			_orbit_cursor_deg = 0.0
			_orbit_dir = 1.0
		if _orbit_needle != null:
			var ratio: float = clampf(_orbit_cursor_deg / 180.0, 0.0, 1.0)
			_orbit_needle.anchor_left = ratio
			_orbit_needle.anchor_right = ratio
		if _orbit_status_lbl != null:
			_orbit_status_lbl.text = "YÖRÜNGE AÇISI: %03.0f° | HEDEF PENCERE: %03.0f° (±16° Yeşil / ±5° Tam İsabet)" % [
				_orbit_cursor_deg, _orbit_target_deg
			]

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
	_orbit_game_active = false
	_orbit_alignment_done = false
	_wiring_done = false
	_wire_fault_triggered = false
	_wire_bonus_active = false
	_bg_wire_trip_timer = 0.0
	_next_bg_wire_trip_interval = randf_range(40.0, 70.0)
	_bg_wire_trip_count = 0
	_matched_wires.clear()

func _on_random_crisis_triggered(quest_data: Dictionary) -> void:
	if visible and bool(_current_quest.get("is_random_crisis", false)) and not _is_resolving:
		return
	var q_id: String = String(quest_data.get("id", ""))
	if q_id != "" and _resolved_quest_ids.has(q_id):
		return
	_orbit_game_active = false
	_dragging_wire_id = -1
	move_to_front()
	open_quest(quest_data)

func _on_terminal_opened(terminal_name: String) -> void:
	if visible and bool(_current_quest.get("is_random_crisis", false)) and not _is_resolving:
		return
	if terminal_name == "BRIEFING":
		GameState.mark_briefing_completed()
		EventBus.status_message.emit("BRİFİNG TAMAMLANDI: Görev hedefleri ve mühendislik kısıtları onaylandı.", false)
		var next_q: Dictionary = _get_next_briefing_quest()
		if not next_q.is_empty():
			open_quest(next_q)
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
		if not _wiring_done:
			visible = true
			move_to_front()
			var has_existing_wires: bool = not _wire_defs.is_empty() and not _matched_wires.is_empty()
			_build_power_wiring_ui(_pending_result_msg if _pending_result_msg != "" else "Güç kaynağı seçildi.", has_existing_wires)
		else:
			_open_power_lab_summary()

func _open_power_lab_summary() -> void:
	_current_quest = {}
	_is_resolving = true
	_has_timer = false
	visible = true
	move_to_front()
	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = true
	title_label.text = "GÜÇ LAB: HAZIR"
	title_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
	_set_frame_accent("green")
	desc_label.text = "Net Güç: %+.0f W  |  Batarya: %%%.0f" % [
		GameState.net_power_w,
		GameState.battery_charge_pct
	]
	for child in options_box.get_children():
		child.queue_free()
	feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	feedback_label.text = "Ek güç için Mağaza'yı kullanabilirsin."

func _get_next_briefing_quest() -> Dictionary:
	var quests: Array = GameState.get_available_side_quests_for_mission()
	for q in quests:
		var q_id: String = String(q.get("id", ""))
		if not bool(q.get("is_random_crisis", false)) and not _resolved_quest_ids.has(q_id) and not GameState.resolved_quest_ids.has(q_id):
			if String(q.get("room", "")) != "POWER_LAB":
				return q
	return {}

func _open_briefing_summary() -> void:
	_current_quest = {}
	_is_resolving = true
	_has_timer = false
	visible = true
	move_to_front()

	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = true

	var m: Dictionary = GameState.current_mission
	var site_name: String = String(GameState.selected_launch_site.get("name", "-"))
	title_label.text = "BRİFİNG RAPORU: %s" % String(m.get("name", "Görev"))
	title_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_set_frame_accent("blue")

	var lines: Array[String] = []
	lines.append("• Fırlatma Üssü: %s | Yörünge: %s" % [site_name, String(m.get("orbit_label", ""))])
	lines.append("• Güncel Durum: Bütçe $%.0fM | Kütle %.0f/%.0f kg | İniş %%%d" % [
		GameState.budget_m,
		GameState.get_effective_mass_kg(),
		GameState.get_effective_mass_limit_kg(),
		GameState.landing_success_chance
	])
	lines.append("")
	lines.append("YAPILAN SEÇİMLER & SONUÇLAR:")
	if GameState.decision_logs.is_empty():
		lines.append("• Henüz karar kaydı yok.")
	else:
		for log_item in GameState.decision_logs:
			lines.append("✓ " + str(log_item))

	desc_label.text = "\n".join(lines)
	for child in options_box.get_children():
		child.queue_free()
	if not _orbit_alignment_done:
		_build_orbit_alignment_ui("Görev hedefleri onaylandı.")
		return
	feedback_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	feedback_label.text = "Brifing tamam! Mağaza ve Güç Lab'a geçebilirsin."

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

	var room_type: String = String(quest_data.get("room", "BRIEFING"))
	if is_crisis:
		_set_frame_accent("red")
	elif room_type == "POWER_LAB":
		_set_frame_accent("green")
	else:
		_set_frame_accent("blue")
	title_label.text = String(quest_data.get("title", "MÜHENDİSLİK KARARI"))
	title_label.add_theme_color_override(
		"font_color",
		Color(0.98, 0.55, 0.52) if is_crisis else (Color(0.58, 0.94, 0.78) if room_type == "POWER_LAB" else Color(0.68, 0.88, 1.0))
	)
	desc_label.text = String(quest_data.get("description", ""))
	feedback_label.text = ""

	for child in options_box.get_children():
		child.queue_free()
	_option_buttons.clear()

	var q_id: String = String(quest_data.get("id", ""))
	if _is_multiplayer_vote_active():
		GameState.start_crisis_vote(q_id)

	var opts: Array = quest_data.get("options", [])
	var affordable_count: int = 0
	for idx in range(opts.size()):
		var opt: Dictionary = opts[idx]
		var b_delta: float = float(opt.get("budget_delta", 0.0))
		var can_afford: bool = b_delta >= 0.0 or (GameState.budget_m + b_delta >= 0.0)
		if can_afford:
			affordable_count += 1
		var btn: Button = Button.new()
		btn.text = String(opt.get("label", "Seçenek")) + ("" if can_afford else " [YETERSİZ BÜTÇE]")
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 10)
		var sb_norm: StyleBoxFlat = StationFrameDrawer.make_option_button_stylebox(true)
		var sb_hov: StyleBoxFlat = StationFrameDrawer.make_option_button_stylebox(false)
		btn.add_theme_stylebox_override("normal", sb_norm)
		btn.add_theme_stylebox_override("hover", sb_hov)
		btn.add_theme_stylebox_override("pressed", sb_hov)
		btn.add_theme_stylebox_override("disabled", sb_norm)
		if not can_afford:
			btn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		btn.pressed.connect(_on_option_chosen.bind(opt, idx))
		options_box.add_child(btn)
		_option_buttons.append(btn)

	if _is_multiplayer_vote_active():
		_refresh_vote_buttons()

	if affordable_count == 0 and not is_crisis:
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		feedback_label.text = "HATA — BÜTÇE TÜKENDİ! Bu karar için yeterli bütçeniz kalmadı (Mevcut: $%.0fM). Görev başarısız!" % GameState.budget_m
		EventBus.status_message.emit("BÜTÇE TÜKENDİ: Güç Lab / Brifing kararı için paranız kalmadı — Görev Başarısız!", true)
		if _fail_mission_btn != null:
			_fail_mission_btn.visible = true

func _is_multiplayer_vote_active() -> bool:
	return bool(_current_quest.get("is_random_crisis", false)) and (not GameState.is_solo or GameState.lobby_players.size() > 1)

func _on_vote_telemetry_updated() -> void:
	if not visible or _is_resolving or not _is_multiplayer_vote_active():
		return
	var q_id: String = String(_current_quest.get("id", ""))
	var res: Dictionary = GameState.last_crisis_vote_result
	if not res.is_empty() and String(res.get("quest_id", "")) == q_id:
		var w_idx: int = int(res.get("winner_idx", 0))
		var was_tie: bool = bool(res.get("was_tie", false))
		var is_t: bool = bool(res.get("is_timeout", false))
		var opts: Array = _current_quest.get("options", [])
		if w_idx >= 0 and w_idx < opts.size():
			_resolve_with_option(opts[w_idx], is_t, was_tie)
			return
	_refresh_vote_buttons()

func _refresh_vote_buttons() -> void:
	var opts: Array = _current_quest.get("options", [])
	var counts: Dictionary = {}
	for voter in GameState.crisis_votes.keys():
		var idx_v: int = int(GameState.crisis_votes[voter])
		counts[idx_v] = int(counts.get(idx_v, 0)) + 1
	var my_vote: int = int(GameState.crisis_votes.get(PlayerProfile.full_tag, -1))

	for i in range(min(_option_buttons.size(), opts.size())):
		var opt: Dictionary = opts[i]
		var b_delta: float = float(opt.get("budget_delta", 0.0))
		var can_afford: bool = b_delta >= 0.0 or (GameState.budget_m + b_delta >= 0.0)
		var base_txt: String = String(opt.get("label", "Seçenek")) + ("" if can_afford else " [YETERSİZ BÜTÇE]")
		var c: int = int(counts.get(i, 0))
		var vote_tag: String = " | [%d Oy]" % c
		if i == my_vote:
			vote_tag += " [SENİN OYUN]"
		_option_buttons[i].text = base_txt + vote_tag

	var total_players: int = max(1, GameState.lobby_players.size())
	feedback_label.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	feedback_label.text = "OYLAMA: %d / %d oyuncu oy verdi (Eşit oy olursa rastgele seçilir)." % [GameState.crisis_votes.size(), total_players]

func _finalize_crisis_vote(is_timeout: bool) -> void:
	if _is_resolving:
		return
	var q_id: String = String(_current_quest.get("id", ""))
	var opts: Array = _current_quest.get("options", [])
	if opts.is_empty():
		return

	if GameState.crisis_votes.is_empty() and is_timeout and String(_current_quest.get("timeout_mode", "random")) == "fail_penalty" and _current_quest.has("timeout_outcome"):
		var fail_opt: Dictionary = _current_quest.get("timeout_outcome", {})
		_resolve_with_option(fail_opt, true)
		return

	var counts: Array[int] = []
	for _i in range(opts.size()):
		counts.append(0)
	for voter in GameState.crisis_votes.keys():
		var idx_v: int = int(GameState.crisis_votes[voter])
		if idx_v >= 0 and idx_v < counts.size():
			counts[idx_v] += 1

	var max_votes: int = -1
	for c in counts:
		if c > max_votes:
			max_votes = c

	var tied_indices: Array[int] = []
	for i in range(counts.size()):
		if counts[i] == max_votes:
			tied_indices.append(i)

	var was_tie: bool = tied_indices.size() > 1
	var winner_idx: int = tied_indices[randi() % tied_indices.size()]
	GameState.resolve_crisis_vote_network(q_id, winner_idx, was_tie, is_timeout)

func _on_crisis_timeout() -> void:
	if _is_resolving:
		return
	if _is_multiplayer_vote_active():
		if not GameState.is_network_active or GameState.is_room_host:
			_finalize_crisis_vote(true)
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

func _on_option_chosen(opt: Dictionary, opt_idx: int = 0) -> void:
	if not GameState.is_random_quest_budget_valid(opt):
		var req_cost: float = abs(float(opt.get("budget_delta", 0.0)))
		var err_msg: String = "HATA — BÜTÇE YETERSİZ! Bu seçenek için $%.0fM gerekiyor (Mevcut bütçen: $%.0fM)." % [
			req_cost, GameState.budget_m
		]
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		feedback_label.text = err_msg
		EventBus.status_message.emit(err_msg, true)
		return
	if _is_multiplayer_vote_active():
		var q_id: String = String(_current_quest.get("id", ""))
		GameState.cast_crisis_vote(q_id, opt_idx)
		_refresh_vote_buttons()
		var total_players: int = max(1, GameState.lobby_players.size())
		if GameState.crisis_votes.size() >= total_players and (not GameState.is_network_active or GameState.is_room_host):
			_finalize_crisis_vote(false)
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

	var is_crisis_q: bool = bool(_current_quest.get("is_random_crisis", false))
	var room_name: String = String(_current_quest.get("room", ""))
	if not is_crisis_q and room_name != "POWER_LAB":
		var next_briefing_q: Dictionary = _get_next_briefing_quest()
		if not next_briefing_q.is_empty():
			open_quest(next_briefing_q)
			return
		if not _orbit_alignment_done:
			_build_orbit_alignment_ui(result_msg)
			return
	if not is_crisis_q and room_name == "POWER_LAB" and not _wiring_done:
		_build_power_wiring_ui(result_msg)
		return

	var l_delta: int = GameState.last_quest_landing_delta
	var has_bad_keyword: bool = is_timeout or result_msg.contains("BOZULDU") or result_msg.contains("HASAR") or result_msg.contains("BAŞARISIZ") or result_msg.contains("ÇÖKTÜ") or result_msg.contains("SAPMA") or result_msg.contains("TÜKENDİ") or result_msg.contains("TAKLA") or result_msg.contains("DONMA") or result_msg.contains("SÜRE DOLDU")
	var result_color: Color = Color(0.4, 0.95, 0.55)
	if has_bad_keyword or l_delta < 0 or GameState.last_quest_is_negative:
		result_color = Color(1.0, 0.45, 0.4)
	elif l_delta == 0:
		result_color = Color(1.0, 0.82, 0.35)
	feedback_label.add_theme_color_override("font_color", result_color)
	feedback_label.text = "SONUÇ: " + result_msg

	# Otomatik kapanmaz: Oyuncu sonucu rahatça okuduktan sonra kendi kapatır
	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = true

func _get_mission_orbit_target_deg() -> float:
	var mid: String = String(GameState.current_mission.get("id", ""))
	match mid:
		"leo_climate_aqua":
			return 98.0
		"lunar_pole_lro":
			return 52.0
		"mars_perseverance":
			return 126.0
		"europa_juno":
			return 142.0
		_:
			return 90.0

func _build_orbit_alignment_ui(prev_result: String) -> void:
	_pending_result_msg = prev_result
	_orbit_target_deg = _get_mission_orbit_target_deg()
	_orbit_cursor_deg = 15.0
	_orbit_dir = 1.0
	_orbit_game_active = true
	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = false

	title_label.text = "BRİFİNG MİNİ GÖREV: FIRLATMA PENCERESİ & YÖRÜNGE HİZALAMA"
	title_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_set_frame_accent("blue")
	desc_label.text = "KARAR: %s\nŞimdi roket fırlatma vektörünü hedef yörünge penceresine (Yeşil/Altın bölge) hizalayıp KİLİTLE! Tam isabet ek yakıt/kütle tasarrufu sağlar." % prev_result

	for child in options_box.get_children():
		child.queue_free()

	_orbit_status_lbl = Label.new()
	_orbit_status_lbl.add_theme_font_size_override("font_size", 10)
	_orbit_status_lbl.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	options_box.add_child(_orbit_status_lbl)

	var radar_bar: Control = Control.new()
	radar_bar.custom_minimum_size = Vector2(0, 18)
	radar_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.07, 0.11, 0.18, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	radar_bar.add_child(bg)

	var green_zone: ColorRect = ColorRect.new()
	green_zone.color = Color(0.2, 0.78, 0.42, 0.85)
	green_zone.anchor_top = 0.0
	green_zone.anchor_bottom = 1.0
	green_zone.anchor_left = clampf((_orbit_target_deg - 16.0) / 180.0, 0.0, 1.0)
	green_zone.anchor_right = clampf((_orbit_target_deg + 16.0) / 180.0, 0.0, 1.0)
	radar_bar.add_child(green_zone)

	var gold_zone: ColorRect = ColorRect.new()
	gold_zone.color = Color(1.0, 0.88, 0.25, 0.95)
	gold_zone.anchor_top = 0.0
	gold_zone.anchor_bottom = 1.0
	gold_zone.anchor_left = clampf((_orbit_target_deg - 5.0) / 180.0, 0.0, 1.0)
	gold_zone.anchor_right = clampf((_orbit_target_deg + 5.0) / 180.0, 0.0, 1.0)
	radar_bar.add_child(gold_zone)

	_orbit_needle = ColorRect.new()
	_orbit_needle.color = Color(1.0, 1.0, 1.0, 1.0)
	_orbit_needle.anchor_top = 0.0
	_orbit_needle.anchor_bottom = 1.0
	_orbit_needle.offset_left = -2.0
	_orbit_needle.offset_right = 2.0
	radar_bar.add_child(_orbit_needle)
	options_box.add_child(radar_bar)

	_orbit_lock_btn = Button.new()
	_orbit_lock_btn.text = "FIRLATMA PENCERESİNİ KİLİTLE!"
	_orbit_lock_btn.add_theme_font_size_override("font_size", 10)
	_orbit_lock_btn.custom_minimum_size = Vector2(0, 26)
	_orbit_lock_btn.pressed.connect(_on_orbit_lock_pressed)
	options_box.add_child(_orbit_lock_btn)

	feedback_label.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	feedback_label.text = "İbre yeşil veya altın bölgeden geçerken KİLİTLE butonuna bas!"

func _on_orbit_lock_pressed() -> void:
	if not _orbit_game_active:
		_orbit_game_active = true
		if _orbit_lock_btn != null:
			_orbit_lock_btn.text = "FIRLATMA PENCERESİNİ KİLİTLE!"
		feedback_label.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
		feedback_label.text = "İbre yeşil veya altın bölgeden geçerken KİLİTLE butonuna bas!"
		return

	_orbit_game_active = false
	var diff: float = abs(_orbit_cursor_deg - _orbit_target_deg)
	if diff <= 5.5:
		_orbit_alignment_done = true
		if _orbit_lock_btn != null:
			_orbit_lock_btn.disabled = true
		var bonus_note: String = "Yörünge Penceresi TAM İSABET (%.0f° / Hedef %.0f°): -15 kg yakıt tasarrufu, +%%8 iniş, +40 bilim!" % [_orbit_cursor_deg, _orbit_target_deg]
		GameState.apply_minigame_bonus(-15.0, 0.0, 8, 40, bonus_note)
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
		feedback_label.text = "MÜKEMMEL HİZALAMA! " + bonus_note
		if _ack_btn != null:
			_ack_btn.visible = true
	elif diff <= 16.5:
		_orbit_alignment_done = true
		if _orbit_lock_btn != null:
			_orbit_lock_btn.disabled = true
		var ok_note: String = "Yörünge Penceresi Kilitlendi (%.0f° / Hedef %.0f°): -8 kg yakıt tasarrufu, +%%4 iniş, +20 bilim!" % [_orbit_cursor_deg, _orbit_target_deg]
		GameState.apply_minigame_bonus(-8.0, 0.0, 4, 20, ok_note)
		feedback_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
		feedback_label.text = "BAŞARILI! " + ok_note
		if _ack_btn != null:
			_ack_btn.visible = true
	else:
		if _orbit_lock_btn != null:
			_orbit_lock_btn.text = "PENCERE KAÇTI (%.0f°) — TEKRAR HİZALA" % _orbit_cursor_deg
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		feedback_label.text = "Hedef pencere dışına kilitlendi (%.0f°). Tekrar denemek için butona bas!" % _orbit_cursor_deg

func _build_power_wiring_ui(prev_result: String, preserve_matched: bool = false) -> void:
	_pending_result_msg = prev_result
	_dragging_wire_id = -1
	GameState.set_power_wiring_broken(true)
	if not preserve_matched:
		_wire_fault_triggered = false
		_matched_wires.clear()
	if _timer_box != null:
		_timer_box.visible = false
	if _close_btn != null:
		_close_btn.visible = true
	if _ack_btn != null:
		_ack_btn.visible = false

	title_label.text = "GÜÇ LAB: KABLO BAĞLANTISI"
	title_label.add_theme_color_override("font_color", Color(0.58, 0.94, 0.78))
	_set_frame_accent("green")
	desc_label.text = "Aynı renkli soketleri birbirine bağla (+15W Güç, +%5 İniş)."

	for child in options_box.get_children():
		child.queue_free()

	if not preserve_matched or _wire_defs.is_empty():
		_wire_defs = [
			{ "id": 0, "name": "KIRMIZI (+28V Ana)", "color": Color(0.98, 0.32, 0.32) },
			{ "id": 1, "name": "MAVİ (Termal Hat)", "color": Color(0.28, 0.72, 1.0) },
			{ "id": 2, "name": "SARI (Telemetri)", "color": Color(0.98, 0.84, 0.25) },
			{ "id": 3, "name": "YEŞİL (Sigorta)", "color": Color(0.32, 0.92, 0.5) }
		]
		_wire_defs.shuffle()
		_right_wire_order = [0, 1, 2, 3]
		_right_wire_order.shuffle()
		while _right_wire_order == [0, 1, 2, 3]:
			_right_wire_order.shuffle()

	_wire_canvas = Control.new()
	_wire_canvas.custom_minimum_size = Vector2(360, 118)
	_wire_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wire_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_canvas.draw.connect(_on_wire_canvas_draw)
	_wire_canvas.gui_input.connect(_on_wire_canvas_gui_input)
	options_box.add_child(_wire_canvas)

	if preserve_matched:
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		feedback_label.text = "Kablo koptu! Yeniden bağla (%d/4)." % _matched_wires.size()
	else:
		feedback_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		feedback_label.text = "Bağlı: 0/4"

func _get_wire_row_y(row_idx: int) -> float:
	return 8.0 + float(row_idx) * 27.0

func _on_wire_canvas_draw() -> void:
	if _wire_canvas == null:
		return
	var w: float = max(320.0, _wire_canvas.size.x)
	var h: float = max(118.0, _wire_canvas.size.y)
	_wire_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.08, 0.14, 0.95), true)
	_wire_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.42, 0.62, 0.9), false, 1.5)

	var left_w: float = 128.0
	var right_x: float = w - 128.0
	var font: Font = ThemeDB.fallback_font

	for row_i in range(4):
		var wy: float = _get_wire_row_y(row_i)
		var l_info: Dictionary = _wire_defs[row_i]
		var l_col: Color = l_info["color"]
		var l_done: bool = _matched_wires.has(row_i)
		var l_bg: Color = Color(l_col.r * 0.35, l_col.g * 0.35, l_col.b * 0.35, 0.95) if l_done else Color(0.1, 0.14, 0.22, 0.95)
		_wire_canvas.draw_rect(Rect2(6, wy, left_w, 21), l_bg, true)
		_wire_canvas.draw_rect(Rect2(6, wy, left_w, 21), l_col, false, 2.0)
		_wire_canvas.draw_circle(Vector2(6.0 + left_w, wy + 10.5), 5.5, l_col)
		if font != null:
			_wire_canvas.draw_string(font, Vector2(12, wy + 15), String(l_info["name"]), HORIZONTAL_ALIGNMENT_LEFT, left_w - 10.0, 9, Color.WHITE)

		var r_wid: int = _right_wire_order[row_i]
		var r_info: Dictionary = _wire_defs[r_wid]
		var r_col: Color = r_info["color"]
		var r_done: bool = _matched_wires.has(r_wid)
		var r_bg: Color = Color(r_col.r * 0.35, r_col.g * 0.35, r_col.b * 0.35, 0.95) if r_done else Color(0.1, 0.14, 0.22, 0.95)
		_wire_canvas.draw_rect(Rect2(right_x, wy, 122.0, 21), r_bg, true)
		_wire_canvas.draw_rect(Rect2(right_x, wy, 122.0, 21), r_col, false, 2.0)
		_wire_canvas.draw_circle(Vector2(right_x, wy + 10.5), 5.5, r_col)
		if font != null:
			_wire_canvas.draw_string(font, Vector2(right_x + 8.0, wy + 15), String(r_info["name"]), HORIZONTAL_ALIGNMENT_LEFT, 112.0, 9, Color.WHITE)

	# Bağlanmış kabloları çiz
	for wid in _matched_wires:
		var start_p: Vector2 = Vector2(6.0 + left_w, _get_wire_row_y(wid) + 10.5)
		var r_row: int = _right_wire_order.find(wid)
		if r_row != -1:
			var end_p: Vector2 = Vector2(right_x, _get_wire_row_y(r_row) + 10.5)
			var w_col: Color = _wire_defs[wid]["color"]
			_wire_canvas.draw_line(start_p, end_p, Color(0, 0, 0, 0.6), 7.0)
			_wire_canvas.draw_line(start_p, end_p, w_col, 4.5)
			_wire_canvas.draw_circle(start_p, 6.0, Color.WHITE)
			_wire_canvas.draw_circle(end_p, 6.0, Color.WHITE)

	# Çekilmekte olan aktif kabloyu çiz
	if _dragging_wire_id != -1:
		var drag_start: Vector2 = Vector2(6.0 + left_w, _get_wire_row_y(_dragging_wire_id) + 10.5)
		var d_col: Color = _wire_defs[_dragging_wire_id]["color"]
		_wire_canvas.draw_line(drag_start, _drag_mouse_pos, Color(0, 0, 0, 0.65), 7.0)
		_wire_canvas.draw_line(drag_start, _drag_mouse_pos, d_col, 4.5)
		_wire_canvas.draw_circle(_drag_mouse_pos, 6.5, d_col)
		_wire_canvas.draw_circle(_drag_mouse_pos, 3.0, Color.WHITE)

func _get_row_at_y(pos_y: float) -> int:
	for i in range(4):
		var wy: float = _get_wire_row_y(i)
		if pos_y >= wy - 3.0 and pos_y <= wy + 24.0:
			return i
	return -1

func _on_wire_canvas_gui_input(event: InputEvent) -> void:
	if _wiring_done or _wire_canvas == null:
		return
	var w: float = max(320.0, _wire_canvas.size.x)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var row_i: int = _get_row_at_y(mb.position.y)
				if row_i != -1 and mb.position.x <= 155.0 and not _matched_wires.has(row_i):
					_dragging_wire_id = row_i
					_drag_mouse_pos = mb.position
					_wire_canvas.queue_redraw()
			else:
				if _dragging_wire_id != -1:
					var drop_row: int = _get_row_at_y(mb.position.y)
					if drop_row != -1 and mb.position.x >= w - 155.0:
						var target_wid: int = _right_wire_order[drop_row]
						if target_wid == _dragging_wire_id and not _matched_wires.has(target_wid):
							_matched_wires.append(target_wid)
							_dragging_wire_id = -1
							var broken_names: String = _maybe_trigger_wire_fault()
							_wire_canvas.queue_redraw()
							if broken_names != "":
								feedback_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
								feedback_label.text = "Kablo koptu: %s (%d/4). Tekrar bağla!" % [broken_names, _matched_wires.size()]
								return
							if _matched_wires.size() >= 4:
								_wiring_done = true
								GameState.set_power_wiring_broken(false)
								var wire_note: String = "Güç Lab kabloları bağlandı (+15 W, +%5 iniş)."
								if not _wire_bonus_active:
									_wire_bonus_active = true
									GameState.apply_minigame_bonus(0.0, 15.0, 5, 0, wire_note)
								feedback_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
								feedback_label.text = "Tamamlandı (4/4)! +15 W güç, +%5 iniş."
								if _ack_btn != null:
									_ack_btn.visible = true
							else:
								feedback_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
								feedback_label.text = "Bağlı: %d/4" % _matched_wires.size()
							return
						elif target_wid != _dragging_wire_id:
							feedback_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
							feedback_label.text = "Yanlış renk! Aynı renge bağla."
					_dragging_wire_id = -1
					_wire_canvas.queue_redraw()
	elif event is InputEventMouseMotion:
		if _dragging_wire_id != -1:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			_drag_mouse_pos = mm.position
			_wire_canvas.queue_redraw()

func _maybe_trigger_wire_fault() -> String:
	if _wire_fault_triggered or _matched_wires.size() < 3:
		return ""
	var trigger_chance: float = 0.35 if _matched_wires.size() == 3 else 0.45
	if randf() >= trigger_chance:
		return ""
	_wire_fault_triggered = true
	var break_count: int = 1 if randf() < 0.65 else 2
	break_count = mini(break_count, _matched_wires.size() - 1)
	var candidates: Array[int] = _matched_wires.duplicate()
	candidates.shuffle()
	var broken_labels: Array[String] = []
	for i in range(break_count):
		var wid: int = candidates[i]
		_matched_wires.erase(wid)
		broken_labels.append(String(_wire_defs[wid]["name"]))
	return ", ".join(broken_labels)

func _trigger_background_wire_trip() -> void:
	if _matched_wires.is_empty() or _wire_defs.is_empty():
		return
	_bg_wire_trip_count += 1
	_wiring_done = false
	GameState.set_power_wiring_broken(true)
	var break_count: int = 1 if randf() < 0.65 else 2
	break_count = mini(break_count, _matched_wires.size() - 1)
	var candidates: Array[int] = _matched_wires.duplicate()
	candidates.shuffle()
	var broken_labels: Array[String] = []
	for i in range(break_count):
		var wid: int = candidates[i]
		_matched_wires.erase(wid)
		broken_labels.append(String(_wire_defs[wid]["name"]))
	var broken_names: String = ", ".join(broken_labels)
	if _wire_bonus_active:
		_wire_bonus_active = false
		GameState.apply_minigame_bonus(0.0, -15.0, -5, 0, "GÜÇ LAB KABLO ATTI: %s bağlantısı koptu (-15 W, -%%5 iniş)!" % broken_names)
	EventBus.status_message.emit(
		"GÜÇ LAB UYARISI: %s kablosu attı! Güç Lab terminaline dönüp yeniden bağlayın (-15W)." % broken_names,
		true
	)

func _on_close_pressed() -> void:
	_orbit_game_active = false
	_dragging_wire_id = -1
	_is_resolving = false
	_has_timer = false
	if _ack_btn != null:
		_ack_btn.visible = false
	if _fail_mission_btn != null:
		_fail_mission_btn.visible = false
	visible = false
