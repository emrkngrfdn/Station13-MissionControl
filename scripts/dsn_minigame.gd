extends PanelContainer

const STATIONS: Array[String] = ["GOLDSTONE (ABD)", "MADRID (İSPANYA)", "CANBERRA (AVUSTRALYA)"]

@onready var station_label: Label = %StationLabel
@onready var stats_label: Label = %DSNStatsLabel
@onready var lock_status_label: Label = %LockStatusLabel
@onready var freq_slider: HSlider = %FreqSlider

var _station_timer: float = 0.0
var _station_idx: int = 0
var _drift_dir: float = 1.0

func _ready() -> void:
	visible = false
	EventBus.terminal_opened.connect(_on_terminal_opened)

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "DSN_COMMS":
		visible = true
		freq_slider.value = 50.0
		_refresh_labels(true)

func _process(delta: float) -> void:
	if not visible:
		return

	_station_timer += delta
	if _station_timer >= 6.0:
		_station_timer = 0.0
		_station_idx = (_station_idx + 1) % STATIONS.size()

	# Sinyal frekansı hafifçe kayar; oyuncu 40..60 yeşil bölgesinde tutmaya çalışır
	if randf() < 0.03:
		_drift_dir = -_drift_dir
	freq_slider.value = clamp(freq_slider.value + _drift_dir * 18.0 * delta, 0.0, 100.0)

	if Input.is_action_pressed("ui_left"):
		freq_slider.value = clamp(freq_slider.value - 55.0 * delta, 0.0, 100.0)
	if Input.is_action_pressed("ui_right"):
		freq_slider.value = clamp(freq_slider.value + 55.0 * delta, 0.0, 100.0)

	var locked: bool = freq_slider.value >= 38.0 and freq_slider.value <= 62.0
	if locked:
		var speed_mbps: float = max(GameState.downlink_mbps, 2.0)
		GameState.downloaded_data_gb += (speed_mbps / 25.0) * delta
		EventBus.telemetry_changed.emit()

	_refresh_labels(locked)

func _refresh_labels(locked: bool) -> void:
	station_label.text = "YER İSTASYONU: %s" % STATIONS[_station_idx]
	stats_label.text = "İNDİRİLEN: %.1f GB | ANTEN HIZI: %.0f Mbps" % [
		GameState.downloaded_data_gb,
		GameState.downlink_mbps
	]
	if locked:
		lock_status_label.text = "SİNYAL KİLİTLENDİ (LOCK) — VERİ AKTARILIYOR"
		lock_status_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	else:
		lock_status_label.text = "SİNYAL KAYDI! FREKANSI ORTADA (38-62) TUTUN"
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))

func _on_left_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value - 12.0, 0.0, 100.0)

func _on_right_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value + 12.0, 0.0, 100.0)

func _on_close_pressed() -> void:
	visible = false
