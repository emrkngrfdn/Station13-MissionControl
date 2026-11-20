extends Node2D

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")
const CARGO_BOX_SCENE: PackedScene = preload("res://scenes/entities/cargo_box.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/entities/player.tscn")

@onready var budget_label: Label = %BudgetLabel
@onready var mass_label: Label = %MassLabel
@onready var power_label: Label = %PowerLabel
@onready var science_label: Label = get_node_or_null("%ScienceLabel") as Label
@onready var data_label: Label = %DataLabel
@onready var timer_label: Label = %TimerLabel
@onready var status_label: Label = %StatusLabel
@onready var conveyor_spawn: Marker2D = $ConveyorSpawnPoint
@onready var player: CharacterBody2D = $Player

var _remote_players: Dictionary = {}
var _boxes_by_id: Dictionary = {}

func _ready() -> void:
	_style_status_banner()
	EventBus.telemetry_changed.connect(_update_hud)
	EventBus.cargo_spawned.connect(_on_cargo_spawned)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_resolved.connect(_on_side_quest_resolved)
	EventBus.remote_player_updated.connect(_on_remote_player_updated)
	EventBus.remote_player_left.connect(_on_remote_player_left)
	EventBus.box_picked_up.connect(_on_box_picked_up)
	EventBus.box_dropped.connect(_on_box_dropped)
	EventBus.box_installed.connect(_on_box_installed)
	if EventBus.has_signal("status_message"):
		EventBus.status_message.connect(_on_status_message)
	_spawn_remote_players()
	_update_hud()
	_show_status("Görev: %s — Terminallerle etkileşim için [E] veya Etkileşim butonunu kullan." % String(GameState.current_mission.get("name", "")))
	_show_mission_intro_modal()

func _spawn_remote_players() -> void:
	if not GameState.is_network_active:
		return
	var offset_idx: int = 0
	for p in GameState.lobby_players:
		var pid: int = int(p.get("peer_id", 0))
		if pid <= 0 or pid == GameState.my_peer_id:
			continue
		if _remote_players.has(pid) and is_instance_valid(_remote_players[pid]):
			continue
		var rp: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
		var spawn_pos: Vector2 = player.global_position + Vector2((offset_idx + 1) * 18.0, 0.0)
		rp.set("is_local_player", false)
		rp.set("peer_id", pid)
		rp.set("player_tag", String(p.get("tag", "Mürettebat")))
		add_child(rp)
		rp.call("setup_remote", pid, String(p.get("tag", "Mürettebat")), spawn_pos)
		_remote_players[pid] = rp
		offset_idx += 1

func _on_remote_player_updated(peer_id: int, state: Dictionary) -> void:
	if not _remote_players.has(peer_id) or not is_instance_valid(_remote_players[peer_id]):
		_spawn_remote_players()
	if _remote_players.has(peer_id) and is_instance_valid(_remote_players[peer_id]):
		_remote_players[peer_id].call("apply_remote_state", state)

func _on_remote_player_left(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		var rp: Node = _remote_players[peer_id]
		if is_instance_valid(rp):
			if rp.get("carried_box") != null and is_instance_valid(rp.get("carried_box")):
				var dropped_box: Node2D = rp.get("carried_box")
				dropped_box.reparent(self)
				dropped_box.global_position = rp.global_position + Vector2(0, 16)
				dropped_box.set("carrier", null)
			rp.queue_free()
		_remote_players.erase(peer_id)

func _on_box_picked_up(box_id: String, peer_id: int) -> void:
	if not _boxes_by_id.has(box_id):
		return
	var box: Node2D = _boxes_by_id[box_id]
	if not is_instance_valid(box):
		_boxes_by_id.erase(box_id)
		return
	var target_p: Node2D = player if peer_id == GameState.my_peer_id else _remote_players.get(peer_id, null)
	if target_p == null or not is_instance_valid(target_p):
		return
	box.set("carrier", target_p)
	target_p.set("carried_box", box)
	box.reparent(target_p)
	box.position = Vector2(0, -18)

func _on_box_dropped(box_id: String, pos: Vector2) -> void:
	if not _boxes_by_id.has(box_id):
		return
	var box: Node2D = _boxes_by_id[box_id]
	if not is_instance_valid(box):
		_boxes_by_id.erase(box_id)
		return
	var prev_carrier: Variant = box.get("carrier")
	if prev_carrier is Node and is_instance_valid(prev_carrier):
		(prev_carrier as Node).set("carried_box", null)
	box.reparent(self)
	box.global_position = pos
	box.set("carrier", null)

func _on_box_installed(box_id: String) -> void:
	if not _boxes_by_id.has(box_id):
		return
	var box: Node2D = _boxes_by_id[box_id]
	if is_instance_valid(box):
		var prev_carrier: Variant = box.get("carrier")
		if prev_carrier is Node and is_instance_valid(prev_carrier):
			(prev_carrier as Node).set("carried_box", null)
		box.queue_free()
	_boxes_by_id.erase(box_id)

func _style_status_banner() -> void:
	var top_bar: PanelContainer = get_node_or_null("HUD/TopBar") as PanelContainer
	if top_bar != null:
		var top_sb: StyleBoxFlat = StyleBoxFlat.new()
		top_sb.bg_color = Color(0.11, 0.145, 0.21, 0.94)
		top_sb.border_width_left = 1
		top_sb.border_width_top = 1
		top_sb.border_width_right = 1
		top_sb.border_width_bottom = 2
		top_sb.border_color = Color(0.38, 0.49, 0.64, 1.0)
		top_sb.content_margin_left = 8.0
		top_sb.content_margin_right = 8.0
		top_sb.content_margin_top = 3.0
		top_sb.content_margin_bottom = 3.0
		top_sb.anti_aliasing = false
		top_bar.add_theme_stylebox_override("panel", top_sb)

	var box_style: StyleBoxFlat = StationFrameDrawer.make_modal_stylebox(
		Color(0.08, 0.17, 0.30, 0.95),
		Color(0.36, 0.68, 0.94, 1.0)
	)
	box_style.content_margin_left = 10.0
	box_style.content_margin_right = 10.0
	box_style.content_margin_top = 4.0
	box_style.content_margin_bottom = 4.0
	status_label.add_theme_stylebox_override("normal", box_style)
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	status_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.09, 0.95))
	status_label.add_theme_constant_override("outline_size", 2)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _process(_delta: float) -> void:
	var total_sec: int = int(GameState.elapsed_time_sec)
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	timer_label.text = "T-PLUS %02d:%02d" % [mins, secs]

func _update_hud() -> void:
	var eff_mass: float = GameState.get_effective_mass_kg()
	var eff_limit: float = GameState.get_effective_mass_limit_kg()
	var mass_ok: bool = eff_mass <= eff_limit
	var power_ok: bool = GameState.net_power_w >= 0.0
	var target_gb: float = GameState.get_target_download_gb()

	budget_label.text = "BUDGET: $%.0fM" % GameState.budget_m
	mass_label.text = "MASS: %.0f/%.0fkg%s" % [eff_mass, eff_limit, "" if mass_ok else " (AŞILDI!)"]
	mass_label.modulate = Color(0.4, 0.95, 0.55) if mass_ok else Color(1.0, 0.35, 0.35)

	power_label.text = "POWER: %+.0fW" % GameState.net_power_w
	power_label.modulate = Color(0.4, 0.95, 0.55) if power_ok else Color(1.0, 0.35, 0.35)

	var target_sci: int = int(GameState.current_mission.get("target_science", 500))
	var dsn_bonus_sci: int = GameState.get_dsn_bonus_science()
	var sci_ok: bool = GameState.science_score >= target_sci
	if science_label != null:
		var bonus_tag: String = " (+%d)" % dsn_bonus_sci if dsn_bonus_sci > 0 else ""
		science_label.text = "BİLİM: %d/%d%s" % [GameState.science_score, target_sci, bonus_tag]
		science_label.modulate = Color(0.4, 0.95, 0.55) if sci_ok else Color(1.0, 0.85, 0.35)

	data_label.text = "DATA: %.1f/%.0fGB | İNİŞ: %%%d" % [GameState.downloaded_data_gb, target_gb, GameState.landing_success_chance]

func _on_cargo_spawned(part_data: Dictionary) -> void:
	var box: Node2D = CARGO_BOX_SCENE.instantiate()
	var jitter: Vector2 = Vector2(
		float(part_data.get("_jx", randf_range(-10.0, 10.0))),
		float(part_data.get("_jy", randf_range(-10.0, 10.0)))
	)
	box.global_position = conveyor_spawn.global_position + jitter
	add_child(box)
	box.setup(part_data)
	var bid: String = String(part_data.get("_box_id", ""))
	if bid != "":
		_boxes_by_id[bid] = box
	_show_status("KARGO GELDİ: %s — Alıp Montaj Hangarı'na götür!" % String(part_data.get("name", "Parça")), false)

func _on_side_quest_resolved(opt: Dictionary) -> void:
	_show_status("Karar uygulandı: %s" % String(opt.get("result_note", "")))

func _on_status_message(msg: String, is_error: bool) -> void:
	_show_status(msg, is_error)

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "LAUNCH":
		if not GameState.briefing_completed:
			_show_status("FIRLATMA ENGELLENDİ: Önce Görev Brifingi (Briefing) terminalinden görev ve fırlatma kararını onayla!", true)
			return
		if not GameState.is_power_lab_decided():
			_show_status("FIRLATMA ENGELLENDİ: Önce Güç Laboratuvarı'ndan güç kaynağı kararını belirle!", true)
			return
		if GameState.power_wiring_broken:
			_show_status("FIRLATMA ENGELLENDİ: Güç Laboratuvarı'nda kopan kabloları düzeltmeden fırlatma yapılamaz!", true)
			return
		GameState.trigger_launch_sequence()

func _on_interact_btn_pressed() -> void:
	if player and player.has_method("try_interact"):
		player.try_interact()

func _on_joystick_direction_changed(dir: Vector2) -> void:
	if player != null:
		player.virtual_move_dir = dir

func _show_status(msg: String, is_error: bool = false) -> void:
	status_label.text = msg
	if is_error:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4, 1.0))
	else:
		status_label.add_theme_color_override("font_color", Color(0.95, 0.98, 0.72, 1.0))

func _show_mission_intro_modal() -> void:
	var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "MissionIntroBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.09, 0.65)
	backdrop.z_index = 55
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 0)
	StationFrameDrawer.apply_modal_style(panel, "blue")
	center.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var m_name: String = String(GameState.current_mission.get("name", "Uzay Görevi"))
	var target_sci: int = int(GameState.current_mission.get("target_science", 500))
	var target_gb: float = GameState.get_target_download_gb()
	var eff_limit: float = GameState.get_effective_mass_limit_kg()

	var title_lbl: Label = Label.new()
	title_lbl.text = "GÖREV AMACI: %s" % m_name.to_upper()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0))
	vbox.add_child(title_lbl)

	var goal_lbl: Label = Label.new()
	goal_lbl.text = "Hedefler: Kütle ≤ %.0f kg | Bilim ≥ %d | Veri ≥ %.0f GB" % [eff_limit, target_sci, target_gb]
	goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_lbl.add_theme_font_size_override("font_size", 10)
	goal_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.45))
	vbox.add_child(goal_lbl)

	var steps_lbl: Label = Label.new()
	steps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps_lbl.add_theme_font_size_override("font_size", 10)
	steps_lbl.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	steps_lbl.text = (
		"NE YAPACAĞIZ?\n" +
		"1. Brifing: Görevi onayla ve yörüngeyi kilitle.\n" +
		"2. Güç Lab: Güç sistemini seç ve kabloları bağla.\n" +
		"3. Mağaza & Montaj: Parça al, gelen kargoyu Monte Et terminaline bırak.\n" +
		"4. DSN Kulesi: Gerekli veriyi (DATA) indir.\n" +
		"5. Fırlat: Tüm şartlar tamamsa roketi fırlat!"
	)
	vbox.add_child(steps_lbl)

	var start_btn: Button = Button.new()
	start_btn.text = "ANLADIM / BAŞLA"
	start_btn.custom_minimum_size = Vector2(150, 26)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_size_override("font_size", 10)
	start_btn.pressed.connect(func() -> void:
		backdrop.queue_free()
	)
	vbox.add_child(start_btn)
