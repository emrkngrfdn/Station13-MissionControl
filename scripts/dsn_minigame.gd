extends PanelContainer

const STATIONS: Array[String] = ["GOLDSTONE (ABD)", "MADRID (İSPANYA)", "CANBERRA (AVUSTRALYA)"]

@onready var station_label: Label = %StationLabel
@onready var stats_label: Label = %DSNStatsLabel
@onready var lock_status_label: Label = %LockStatusLabel
@onready var freq_slider: HSlider = %FreqSlider

var _station_timer: float = 0.0
var _station_idx: int = 0
var _drift_dir: float = 1.0
var _tip_label: Label = null

func _ready() -> void:
	visible = false
	_ensure_tip_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)

func _ensure_tip_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _tip_label != null:
		return
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 10)
	_tip_label.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	vbox.add_child(_tip_label)

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

	# Sinyal frekansı hafifçe kayar; oyuncu 38..62 yeşil bölgesinde tutmaya çalışır
	if randf() < 0.03:
		_drift_dir = -_drift_dir
	freq_slider.value = clamp(freq_slider.value + _drift_dir * 18.0 * delta, 0.0, 100.0)

	if Input.is_action_pressed("ui_left"):
		freq_slider.value = clamp(freq_slider.value - 55.0 * delta, 0.0, 100.0)
	if Input.is_action_pressed("ui_right"):
		freq_slider.value = clamp(freq_slider.value + 55.0 * delta, 0.0, 100.0)

	var locked: bool = freq_slider.value >= 38.0 and freq_slider.value <= 62.0
	var window_remaining: float = max(0.0, 6.0 - _station_timer)
	var window_open: bool = window_remaining > 0.8
	GameState.dsn_locked = locked and window_open

	if locked and window_open:
		var speed_mbps: float = max(GameState.downlink_mbps, 6.0)
		var transferred_gb: float = (speed_mbps / 8.0) * delta
		GameState.downloaded_data_gb += transferred_gb
		GameState.ssd_used_gb = max(0.0, GameState.ssd_used_gb - transferred_gb * 0.5)
		EventBus.telemetry_changed.emit()

	_refresh_labels(locked, window_open, window_remaining)

func _refresh_labels(locked: bool, window_open: bool = true, window_remaining: float = 5.0) -> void:
	var win_state: String = "AÇIK (%.1fs)" % window_remaining if window_open else "GEÇİŞ (EL DEĞİŞİMİ)"
	station_label.text = "İSTASYON: %s | GÖRÜŞ PENCERESİ: %s" % [STATIONS[_station_idx], win_state]
	var ssd_pct: int = int(round((GameState.ssd_used_gb / max(1.0, GameState.ssd_capacity_gb)) * 100.0))
	var eff_mbps: float = max(GameState.downlink_mbps, 6.0)
	var gb_per_sec: float = eff_mbps / 8.0
	stats_label.text = "İNDİRİLEN: %.1f GB (%.1f GB/sn) | SSD: %%%d (%.1f/%.0f GB) | ANTEN: %.0f Mbps" % [
		GameState.downloaded_data_gb,
		gb_per_sec,
		ssd_pct,
		GameState.ssd_used_gb,
		GameState.ssd_capacity_gb,
		GameState.downlink_mbps
	]
	if not window_open:
		lock_status_label.text = "YER İSTASYONU UFUK DEĞİŞİMİ — YENİ ANTEN KİLİTLENİYOR..."
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	elif locked:
		lock_status_label.text = "SİNYAL KİLİTLENDİ (LOCK) — UYDU BELLEĞİNDEN VERİ AKTARILIYOR"
		lock_status_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	else:
		lock_status_label.text = "SİNYAL KAYDI! FREKANSI ORTADA (38-62) TUTUN"
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))

	_refresh_upgrade_tip()

func _refresh_upgrade_tip() -> void:
	if _tip_label == null:
		return
	var has_ka: bool = GameState.has_installed_tag("comms_kaband")
	var has_s: bool = GameState.has_installed_tag("comms_sband")

	if has_ka:
		_tip_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
		_tip_label.text = "ANTEN DURUMU: Ka-Band Derin Uzay Çanağı (150 Mbps) takılı — Maksimum indirme hızındasın!"
	elif has_s:
		_tip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_tip_label.text = "HIZ ARTIRMA İPUCU: Şu an S-Band Anten (5 Mbps) takılı. 150 Mbps hıza çıkmak için Mağaza'dan 'Ka-Band Derin Uzay Çanağı' alıp Montaj Hangarı'nda tak!"
	else:
		_tip_label.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
		_tip_label.text = "HIZ ARTIRMA İPUCU: Henüz anten takılı değil (Temel 0.8 GB/sn). Hızlandırmak için Mağaza'dan 'S-Band Anten' (5 Mbps) veya 'Ka-Band Derin Uzay Çanağı' (150 Mbps) alıp Montaj Hangarı'nda tak!"

func _on_left_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value - 12.0, 0.0, 100.0)

func _on_right_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value + 12.0, 0.0, 100.0)

func _on_close_pressed() -> void:
	visible = false
