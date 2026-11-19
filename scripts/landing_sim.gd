extends Control

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")

@onready var main_panel: PanelContainer = $Margin/Panel
@onready var phase_label: Label = %PhaseLabel
@onready var progress_bar: ProgressBar = %EDLProgress
@onready var summary_label: Label = %SummaryLabel
@onready var metrics_label: Label = %MetricsLabel
@onready var details_label: Label = %DetailsLabel
@onready var return_btn: Button = %ReturnLobbyBtn

var _sim_time: float = 0.0
var _sim_done: bool = false
var _report_box: VBoxContainer = null
const SIM_DURATION: float = 2.2

func _ready() -> void:
	StationFrameDrawer.apply_modal_style(main_panel, "blue")
	return_btn.disabled = true
	return_btn.custom_minimum_size = Vector2(0, 28)
	summary_label.text = "FIRLATMA VE EDL SİMÜLASYONU ÇALIŞIYOR..."
	metrics_label.text = "Görev: %s | Roket: %s | Üs: %s" % [
		String(GameState.current_mission.get("name", "")),
		String(GameState.selected_rocket.get("name", "")),
		String(GameState.selected_launch_site.get("name", "-"))
	]
	details_label.text = "Telemetri verileri, kütle/güç dengesi ve NASA görev kısıtları doğrulanıyor..."
	_ensure_report_box()

func _ensure_report_box() -> void:
	var scroll: ScrollContainer = get_node_or_null("Margin/Panel/VBox/Scroll") as ScrollContainer
	if scroll == null or _report_box != null:
		return
	_report_box = VBoxContainer.new()
	_report_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_box.add_theme_constant_override("separation", 6)
	_report_box.visible = false
	scroll.add_child(_report_box)

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

	StationFrameDrawer.apply_modal_style(main_panel, "green" if success else "red")
	phase_label.text = "EDL & GÖREV TELEMETRİ RAPORU TAMAMLANDI"
	phase_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.94, 0.78) if success else Color(0.98, 0.62, 0.60)
	)
	summary_label.text = "%s — %s" % [
		String(report.get("summary", "SONUÇ")),
		String(GameState.current_mission.get("name", ""))
	]
	summary_label.add_theme_color_override(
		"font_color",
		Color(0.45, 0.96, 0.65) if success else Color(1.0, 0.45, 0.42)
	)

	var total_sec: int = int(GameState.elapsed_time_sec)
	var time_str: String = "%02d:%02d" % [total_sec / 60, total_sec % 60]
	var score_val: int = int(report.get("score", 0))
	metrics_label.text = "TOPLAM SKOR: %d | SÜRE: %s | KALAN BÜTÇE: $%.0fM | İNİŞ BAŞARISI: %%%d" % [
		score_val,
		time_str,
		GameState.budget_m,
		GameState.landing_success_chance
	]

	_build_structured_report(report, success, time_str)
	return_btn.disabled = false

func _build_structured_report(report: Dictionary, success: bool, time_str: String) -> void:
	if _report_box == null:
		return
	details_label.visible = false
	_report_box.visible = true
	for child in _report_box.get_children():
		child.queue_free()

	# 1. İSTATİSTİK KARTLARI (3x2 Grid)
	var stats_grid: GridContainer = GridContainer.new()
	stats_grid.columns = 3
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 6)
	stats_grid.add_theme_constant_override("v_separation", 6)

	var target_sci: int = int(GameState.current_mission.get("target_science", 500))
	var sci_val: int = int(report.get("science_score", 0))
	var dsn_sci: int = GameState.get_dsn_bonus_science()
	var sci_sub: String = "Hedef: %d%s" % [target_sci, (" (+%d DSN)" % dsn_sci) if dsn_sci > 0 else ""]
	stats_grid.add_child(_make_stat_tile(
		"BİLİM PUANI",
		str(sci_val),
		sci_sub,
		sci_val >= target_sci
	))

	var target_gb: float = GameState.get_target_download_gb()
	var down_gb: float = float(report.get("downloaded_data_gb", 0.0))
	var extra_gb: float = GameState.get_dsn_extra_gb()
	var dsn_tier: int = GameState.get_dsn_bonus_tiers_completed()
	var data_sub: String = "Hedef: %.0f GB (+%.1f Ek | %d/4)" % [target_gb, extra_gb, dsn_tier]
	stats_grid.add_child(_make_stat_tile(
		"İNEN VERİ (DSN)",
		"%.1f GB" % down_gb,
		data_sub,
		down_gb >= target_gb
	))

	var eff_mass: float = GameState.get_effective_mass_kg()
	var mass_lim: float = GameState.get_effective_mass_limit_kg()
	stats_grid.add_child(_make_stat_tile(
		"TOPLAM KÜTLE",
		"%.0f kg" % eff_mass,
		"Limit: %.0f kg" % mass_lim,
		eff_mass <= mass_lim
	))

	stats_grid.add_child(_make_stat_tile(
		"NET GÜÇ DENGESİ",
		"%+.0f W" % GameState.net_power_w,
		"Batarya: %%%.0f" % GameState.battery_charge_pct,
		GameState.net_power_w >= 0.0
	))

	stats_grid.add_child(_make_stat_tile(
		"İNİŞ GÜVENLİĞİ",
		"%%%d" % GameState.landing_success_chance,
		"Minimum: %60",
		GameState.landing_success_chance >= 60
	))

	stats_grid.add_child(_make_stat_tile(
		"OPERASYON SÜRESİ",
		time_str,
		"Kalan Bütçe: $%.0fM" % GameState.budget_m,
		GameState.budget_m >= 0.0
	))

	_report_box.add_child(stats_grid)

	# 2. ARAÇ VE MONTE EDİLEN EKİPMANLAR
	var part_names: Array[String] = []
	for p in GameState.installed_parts:
		var pname: String = String(p.get("name", "Ekipman"))
		var psci: int = int(p.get("science", 0))
		if psci > 0:
			part_names.append("%s (+%d Bilim)" % [pname, psci])
		else:
			part_names.append(pname)
	var parts_text: String = ", ".join(part_names) if not part_names.is_empty() else "Hiçbir ekipman monte edilmedi!"
	var config_lines: Array[String] = [
		"• Fırlatma Aracı: %s" % String(GameState.selected_rocket.get("name", "-")),
		"• Fırlatma Üssü: %s" % String(GameState.selected_launch_site.get("name", "-")),
		"• Monte Edilen Ekipman (%d): %s" % [GameState.installed_parts.size(), parts_text]
	]
	_report_box.add_child(_make_section_card(
		"ARAÇ KONFİGÜRASYONU & EKİPMANLAR",
		config_lines,
		Color(0.38, 0.68, 0.94, 1.0),
		Color(0.11, 0.21, 0.34, 0.94),
		Color(0.68, 0.88, 1.0)
	))

	# 3. KRİTİK HATALAR (Varsa)
	var errs: Array = report.get("errors", [])
	if not errs.is_empty():
		var err_lines: Array[String] = []
		for e in errs:
			err_lines.append("✖ " + str(e))
		_report_box.add_child(_make_section_card(
			"GÖREV BAŞARISIZLIK SEBEPLERİ (%d HATA)" % errs.size(),
			err_lines,
			Color(0.88, 0.40, 0.42, 1.0),
			Color(0.24, 0.11, 0.14, 0.95),
			Color(1.0, 0.58, 0.55)
		))

	# 4. MÜHENDİSLİK UYARILARI (Varsa)
	var warns: Array = report.get("warnings", [])
	if not warns.is_empty():
		var warn_lines: Array[String] = []
		for w in warns:
			warn_lines.append("▲ " + str(w))
		_report_box.add_child(_make_section_card(
			"MÜHENDİSLİK UYARILARI (%d)" % warns.size(),
			warn_lines,
			Color(0.86, 0.68, 0.34, 1.0),
			Color(0.22, 0.19, 0.11, 0.94),
			Color(0.98, 0.84, 0.48)
		))

	# 5. VERİLEN KARARLAR & KRİZ SONUÇLARI
	var dec_lines: Array[String] = []
	if GameState.decision_logs.is_empty():
		dec_lines.append("• Görev sırasında ek brifing, laboratuvar veya kriz kararı kaydı oluşmadı.")
	else:
		for i in range(GameState.decision_logs.size()):
			dec_lines.append("%d) %s" % [i + 1, str(GameState.decision_logs[i])])
	_report_box.add_child(_make_section_card(
		"VERİLEN KARARLAR & KRİZ KAYITLARI (%d)" % GameState.decision_logs.size(),
		dec_lines,
		Color(0.34, 0.78, 0.64, 1.0) if success else Color(0.45, 0.64, 0.86, 1.0),
		Color(0.09, 0.22, 0.23, 0.94) if success else Color(0.10, 0.19, 0.31, 0.94),
		Color(0.58, 0.94, 0.78) if success else Color(0.72, 0.88, 1.0)
	))

func _make_stat_tile(title_txt: String, value_txt: String, sub_txt: String, is_ok: bool) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border_col: Color = Color(0.34, 0.78, 0.62, 1.0) if is_ok else Color(0.88, 0.44, 0.44, 1.0)
	var bg_col: Color = Color(0.09, 0.21, 0.24, 0.95) if is_ok else Color(0.23, 0.12, 0.16, 0.95)
	card.add_theme_stylebox_override("panel", StationFrameDrawer.make_card_stylebox(border_col, bg_col))

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)

	var t_lbl: Label = Label.new()
	t_lbl.text = title_txt
	t_lbl.add_theme_font_size_override("font_size", 8)
	t_lbl.add_theme_color_override("font_color", Color(0.74, 0.84, 0.94))
	vb.add_child(t_lbl)

	var v_lbl: Label = Label.new()
	v_lbl.text = value_txt
	v_lbl.add_theme_font_size_override("font_size", 12)
	v_lbl.add_theme_color_override("font_color", Color(0.58, 0.96, 0.74) if is_ok else Color(1.0, 0.58, 0.56))
	vb.add_child(v_lbl)

	var s_lbl: Label = Label.new()
	s_lbl.text = sub_txt
	s_lbl.add_theme_font_size_override("font_size", 8)
	s_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.94))
	s_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(s_lbl)

	card.add_child(vb)
	return card

func _make_section_card(header_txt: String, lines: Array[String], border_col: Color, bg_col: Color, title_col: Color) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", StationFrameDrawer.make_card_stylebox(border_col, bg_col))

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)

	var h_lbl: Label = Label.new()
	h_lbl.text = header_txt
	h_lbl.add_theme_font_size_override("font_size", 10)
	h_lbl.add_theme_color_override("font_color", title_col)
	vb.add_child(h_lbl)

	var body_lbl: Label = Label.new()
	body_lbl.text = "\n".join(lines)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 9)
	body_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 0.98))
	vb.add_child(body_lbl)

	card.add_child(vb)
	return card

func _on_return_lobby_pressed() -> void:
	GameState.reset_lobby()
	get_tree().change_scene_to_file("res://scenes/world/waiting_room.tscn")
