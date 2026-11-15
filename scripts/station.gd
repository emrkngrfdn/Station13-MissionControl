extends Node2D

const CARGO_BOX_SCENE: PackedScene = preload("res://scenes/entities/cargo_box.tscn")

@onready var budget_label: Label = %BudgetLabel
@onready var mass_label: Label = %MassLabel
@onready var power_label: Label = %PowerLabel
@onready var landing_label: Label = %LandingLabel
@onready var timer_label: Label = %TimerLabel
@onready var status_label: Label = %StatusLabel
@onready var conveyor_spawn: Marker2D = $ConveyorSpawnPoint

func _ready() -> void:
	EventBus.telemetry_changed.connect(_update_hud)
	EventBus.cargo_spawned.connect(_on_cargo_spawned)
	EventBus.terminal_opened.connect(_on_terminal_opened)
	_update_hud()
	_show_status("Görev Başladı: %s — Terminallere yürüyüp [E/Space] ile etkileşime geç!" % GameState.current_mission.get("name", ""))

func _process(_delta: float) -> void:
	var total_sec: int = int(GameState.elapsed_time_sec)
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	timer_label.text = "SÜRE: %02d:%02d" % [mins, secs]

func _update_hud() -> void:
	var rocket_cap: float = float(GameState.selected_rocket.get("max_mass_kg", 0.0))
	var mass_ok: bool = GameState.total_mass_kg <= rocket_cap
	var power_ok: bool = GameState.net_power_w >= 0.0

	budget_label.text = "BÜTÇE: $%.0fM" % GameState.budget_m
	mass_label.text = "KÜTLE: %.0f/%.0f kg" % [GameState.total_mass_kg, rocket_cap]
	mass_label.modulate = Color(0.4, 0.95, 0.5) if mass_ok else Color(1.0, 0.35, 0.35)

	power_label.text = "GÜÇ: %+.0f W" % GameState.net_power_w
	power_label.modulate = Color(0.4, 0.95, 0.5) if power_ok else Color(1.0, 0.35, 0.35)

	landing_label.text = "İNİŞ: %%%d | BİLİM: %d" % [GameState.landing_success_chance, GameState.science_score]

func _on_cargo_spawned(part_data: Dictionary) -> void:
	var box := CARGO_BOX_SCENE.instantiate()
	var jitter := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	box.global_position = conveyor_spawn.global_position + jitter
	add_child(box)
	box.setup(part_data)
	_show_status("Kargo geldi: %s (Alıp Montaj Hangarı'na götür!)" % part_data.get("name", "Parça"))

func _on_terminal_opened(terminal_name: String) -> void:
	match terminal_name:
		"LAUNCH":
			var check: Dictionary = GameState.validate_launch()
			if check["can_launch"]:
				_show_status("Fırlatma Doğrulaması BAŞARILI! (Uyarı: %d)" % check["warnings"].size())
			else:
				_show_status("FIRLATMA ENGELLENDİ: %s" % check["errors"][0])
		_:
			_show_status("%s terminali açıldı (UI penceresi bağlanacak)." % terminal_name)

func _show_status(msg: String) -> void:
	status_label.text = msg
