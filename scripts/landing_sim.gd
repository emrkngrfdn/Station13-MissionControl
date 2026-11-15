extends Control

@onready var phase_label: Label = %PhaseLabel
@onready var progress_bar: ProgressBar = %EDLProgress
@onready var summary_label: Label = %SummaryLabel
@onready var metrics_label: Label = %MetricsLabel
@onready var details_label: Label = %DetailsLabel
@onready var return_btn: Button = %ReturnLobbyBtn

var _sim_time: float = 0.0
var _sim_done: bool = false
const SIM_DURATION: float = 2.2

func _ready() -> void:
	return_btn.disabled = true
	summary_label.text = "FIRLATMA VE EDL SİMÜLASYONU ÇALIŞIYOR..."
	metrics_label.text = "Görev: %s | Roket: %s" % [
		GameState.current_mission.get("name", ""),
		GameState.selected_rocket.get("name", "")
	]
	details_label.text = "Telemetri verileri ve NASA kısıtları doğrulanıyor..."

func _process(delta: float) -> void:
	if _sim_done:
		return

	_sim_time += delta
	var pct: float = clamp((_sim_time / SIM_DURATION) * 100.0, 0.0, 100.0)
	progress_bar.value = pct

	if pct < 40.0:
		phase_label.text = "FAZ 1/3: ROKET ATEŞLEMESİ VE YÖRÜNGEYE ÇIKIŞ..."
	elif pct < 80.0:
		phase_label.text = "FAZ 2/3: DERİN UZAY SEYRİ & RADYASYON/TERMAL TESTİ..."
	else:
		phase_label.text = "FAZ 3/3: HEDEF İNİŞ (EDL) & VERİ DOĞRULAMA..."

	if _sim_time >= SIM_DURATION:
		_sim_done = true
		_finish_simulation()

func _finish_simulation() -> void:
	var report: Dictionary = GameState.complete_mission()
	var success: bool = bool(report.get("success", false))

	phase_label.text = "SİMÜLASYON TAMAMLANDI"
	summary_label.text = report.get("summary", "SONUÇ")
	summary_label.add_theme_color_override(
		"font_color",
		Color(0.35, 0.95, 0.55) if success else Color(1.0, 0.35, 0.35)
	)

	metrics_label.text = "Süre: %.1fs | Bilim Puanı: %d | İnen Veri: %.1f GB | Toplam Skor: %d" % [
		GameState.elapsed_time_sec,
		int(report.get("science_score", 0)),
		float(report.get("downloaded_data_gb", 0.0)),
		int(report.get("score", 0))
	]

	var lines: Array[String] = []
	for err in report.get("errors", []):
		lines.append("[HATA] " + str(err))
	for warn in report.get("warnings", []):
		lines.append("[UYARI] " + str(warn))
	for log_note in GameState.decision_logs:
		lines.append("[KARAR] " + str(log_note))
	if lines.is_empty():
		lines.append("Tüm NASA mühendislik kısıtları eksiksiz karşılandı!")

	details_label.text = "\n".join(lines)
	return_btn.disabled = false

func _on_return_lobby_pressed() -> void:
	GameState.reset_lobby()
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")
