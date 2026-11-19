extends Node2D

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")
const CARGO_BOX_SCENE: PackedScene = preload("res://scenes/entities/cargo_box.tscn")

@onready var budget_label: Label = %BudgetLabel
@onready var mass_label: Label = %MassLabel
@onready var power_label: Label = %PowerLabel
@onready var science_label: Label = get_node_or_null("%ScienceLabel") as Label
@onready var data_label: Label = %DataLabel
@onready var timer_label: Label = %TimerLabel
@onready var status_label: Label = %StatusLabel
@onready var conveyor_spawn: Marker2D = $ConveyorSpawnPoint
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	_style_status_banner()
	EventBus.telemetry_changed.connect(_update_hud)
	EventBus.cargo_spawned.connect(_on_cargo_spawned)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_resolved.connect(_on_side_quest_resolved)
	if EventBus.has_signal("status_message"):
		EventBus.status_message.connect(_on_status_message)
	_update_hud()
	_show_status("Görev Başladı: %s — Terminallere yürüyüp [Space/E] ile etkileşime geç!" % String(GameState.current_mission.get("name", "")))

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
	var jitter: Vector2 = Vector2(randf_range(-10, 10), randf_range(-10, 10))
	box.global_position = conveyor_spawn.global_position + jitter
	add_child(box)
	box.setup(part_data)
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
		get_tree().change_scene_to_file("res://scenes/world/landing_sim.tscn")

func _on_interact_btn_pressed() -> void:
	if player and player.has_method("try_interact"):
		player.try_interact()

func _show_status(msg: String, is_error: bool = false) -> void:
	status_label.text = msg
	if is_error:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4, 1.0))
	else:
		status_label.add_theme_color_override("font_color", Color(0.95, 0.98, 0.72, 1.0))
