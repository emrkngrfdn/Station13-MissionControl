extends Node2D

const CARGO_BOX_SCENE: PackedScene = preload("res://scenes/entities/cargo_box.tscn")

@onready var budget_label: Label = %BudgetLabel
@onready var mass_label: Label = %MassLabel
@onready var power_label: Label = %PowerLabel
@onready var data_label: Label = %DataLabel
@onready var timer_label: Label = %TimerLabel
@onready var status_label: Label = %StatusLabel
@onready var conveyor_spawn: Marker2D = $ConveyorSpawnPoint
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	EventBus.telemetry_changed.connect(_update_hud)
	EventBus.cargo_spawned.connect(_on_cargo_spawned)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.side_quest_resolved.connect(_on_side_quest_resolved)
	_update_hud()
	_show_status("Görev Başladı: %s — Terminallere yürüyüp [Space/E] ile etkileşime geç!" % GameState.current_mission.get("name", ""))

func _process(_delta: float) -> void:
	var total_sec: int = int(GameState.elapsed_time_sec)
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	timer_label.text = "T-PLUS %02d:%02d" % [mins, secs]

func _update_hud() -> void:
	var rocket_cap: float = float(GameState.selected_rocket.get("max_mass_kg", 0.0))
	var mass_ok: bool = GameState.total_mass_kg <= rocket_cap
	var power_ok: bool = GameState.net_power_w >= 0.0

	budget_label.text = "BUDGET: $%.0fM" % GameState.budget_m
	mass_label.text = "MASS: %.0f/%.0fkg" % [GameState.total_mass_kg, rocket_cap]
	mass_label.modulate = Color(0.4, 0.95, 0.55) if mass_ok else Color(1.0, 0.35, 0.35)

	power_label.text = "POWER: %+.0fW" % GameState.net_power_w
	power_label.modulate = Color(0.4, 0.95, 0.55) if power_ok else Color(1.0, 0.35, 0.35)

	data_label.text = "DATA: %.1fGB | İNİŞ: %%%d" % [GameState.downloaded_data_gb, GameState.landing_success_chance]

func _on_cargo_spawned(part_data: Dictionary) -> void:
	var box := CARGO_BOX_SCENE.instantiate()
	var jitter := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	box.global_position = conveyor_spawn.global_position + jitter
	add_child(box)
	box.setup(part_data)
	_show_status("Kargo geldi: %s (Alıp Montaj Hangarı'na götür!)" % part_data.get("name", "Parça"))

func _on_side_quest_resolved(opt: Dictionary) -> void:
	_show_status("Karar uygulandı: %s" % opt.get("result_note", ""))

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "LAUNCH":
		var check: Dictionary = GameState.validate_launch()
		if check["can_launch"]:
			get_tree().change_scene_to_file("res://scenes/world/landing_sim.tscn")
		else:
			_show_status("FIRLATMA ENGELLENDİ: %s" % check["errors"][0])

func _on_interact_btn_pressed() -> void:
	if player and player.interactable_target != null:
		if player.interactable_target.has_method("interact"):
			player.interactable_target.interact()

func _show_status(msg: String) -> void:
	status_label.text = msg
