extends PanelContainer

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")

const STATIONS: Array[String] = ["GOLDSTONE (ABD)", "MADRID (İSPANYA)", "CANBERRA (AVUSTRALYA)"]
const STATION_DEFAULT_CENTERS: Array[float] = [24.0, 52.0, 78.0]

@onready var station_label: Label = %StationLabel
@onready var stats_label: Label = %DSNStatsLabel
@onready var lock_status_label: Label = %LockStatusLabel
@onready var freq_slider: HSlider = %FreqSlider

var _station_timer: float = 0.0
var _station_idx: int = 0
var _drift_dir: float = 1.0
var _target_center: float = 24.0
var _target_half_width: float = 11.0
var _tip_label: Label = null
var _goal_label: Label = null
var _goal_bar: ProgressBar = null
var _bonus_label: Label = null
var _band_bar: Control = null
var _zone_rect: ColorRect = null
var _needle_rect: ColorRect = null
var _updating_slider_from_net: bool = false
var _net_sync_timer: float = 0.0
var _last_announced_tier: int = 0

func _ready() -> void:
	visible = false
	StationFrameDrawer.apply_modal_style(self, "green")
	StationFrameDrawer.style_close_button(get_node_or_null("VBox/Header/CloseBtn") as Button)
	var title_lbl: Label = get_node_or_null("VBox/Header/Title") as Label
	if title_lbl != null:
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	if station_label != null:
		station_label.add_theme_font_size_override("font_size", 10)
	if stats_label != null:
		stats_label.add_theme_font_size_override("font_size", 10)
	if lock_status_label != null:
		lock_status_label.add_theme_font_size_override("font_size", 11)
	_ensure_tip_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.telemetry_changed.connect(_on_telemetry_synced)
	if freq_slider != null and not freq_slider.value_changed.is_connected(_on_slider_value_changed):
		freq_slider.value_changed.connect(_on_slider_value_changed)

func _exit_tree() -> void:
	if EventBus.terminal_opened.is_connected(_on_terminal_opened):
		EventBus.terminal_opened.disconnect(_on_terminal_opened)
	if EventBus.telemetry_changed.is_connected(_on_telemetry_synced):
		EventBus.telemetry_changed.disconnect(_on_telemetry_synced)

func _ensure_tip_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _tip_label != null:
		return
	_goal_label = Label.new()
	_goal_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_goal_label)

	_goal_bar = ProgressBar.new()
	_goal_bar.min_value = 0.0
	_goal_bar.max_value = 100.0
	_goal_bar.value = 0.0
	_goal_bar.custom_minimum_size = Vector2(0, 15)
	_goal_bar.show_percentage = true
	vbox.add_child(_goal_bar)

	_bonus_label = Label.new()
	_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bonus_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(_bonus_label)

	var stats_idx: int = stats_label.get_index() if stats_label != null else 0
	vbox.move_child(_goal_label, stats_idx)
	vbox.move_child(_goal_bar, stats_idx + 1)
	vbox.move_child(_bonus_label, stats_idx + 2)

	_band_bar = Control.new()
	_band_bar.custom_minimum_size = Vector2(0, 14)
	_band_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg_rect: ColorRect = ColorRect.new()
	bg_rect.color = Color(0.08, 0.12, 0.2, 1.0)
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band_bar.add_child(bg_rect)

	_zone_rect = ColorRect.new()
	_zone_rect.color = Color(0.22, 0.78, 0.42, 0.88)
	_zone_rect.anchor_top = 0.0
	_zone_rect.anchor_bottom = 1.0
	_band_bar.add_child(_zone_rect)

	_needle_rect = ColorRect.new()
	_needle_rect.color = Color(1.0, 0.92, 0.3, 1.0)
	_needle_rect.anchor_top = 0.0
	_needle_rect.anchor_bottom = 1.0
	_needle_rect.offset_left = -2.0
	_needle_rect.offset_right = 2.0
	_band_bar.add_child(_needle_rect)

	var slider_idx: int = freq_slider.get_index() if freq_slider != null else vbox.get_child_count()
	vbox.add_child(_band_bar)
	vbox.move_child(_band_bar, slider_idx)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 9)
	_tip_label.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	vbox.add_child(_tip_label)

func _pick_new_target_for_station() -> void:
	var base_c: float = STATION_DEFAULT_CENTERS[_station_idx % STATION_DEFAULT_CENTERS.size()]
	var candidate: float = clampf(base_c + randf_range(-8.0, 8.0), 15.0, 85.0)
	if abs(candidate - _target_center) < 18.0:
		candidate = clampf(_target_center + (26.0 if _target_center < 50.0 else -26.0), 15.0, 85.0)
	_target_center = candidate

func _on_slider_value_changed(val: float) -> void:
	if _updating_slider_from_net:
		return
	GameState.sync_dsn_input(val)

func _on_telemetry_synced() -> void:
	if not visible:
		return
	if GameState.is_network_active and not GameState.is_room_host:
		_station_idx = GameState.dsn_station_idx % STATIONS.size()
		_target_center = GameState.dsn_target_center
		_station_timer = GameState.dsn_station_timer
	if abs(freq_slider.value - GameState.dsn_freq_value) > 0.25:
		_updating_slider_from_net = true
		freq_slider.value = GameState.dsn_freq_value
		_updating_slider_from_net = false

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "DSN_COMMS":
		visible = true
		_last_announced_tier = GameState.get_dsn_bonus_tiers_completed()
		if not GameState.is_network_active or GameState.is_room_host:
			_station_timer = GameState.dsn_station_timer
			_station_idx = GameState.dsn_station_idx % STATIONS.size()
			_target_center = GameState.dsn_target_center
			if _target_center <= 0.0:
				_pick_new_target_for_station()
		else:
			_station_timer = GameState.dsn_station_timer
			_station_idx = GameState.dsn_station_idx % STATIONS.size()
			_target_center = GameState.dsn_target_center
		_updating_slider_from_net = true
		freq_slider.value = GameState.dsn_freq_value
		_updating_slider_from_net = false
		_refresh_labels(abs(freq_slider.value - _target_center) <= _target_half_width)

func _get_effective_gb_per_sec() -> float:
	var mbps: float = max(0.0, GameState.downlink_mbps)
	return 2.5 + clampf(sqrt(mbps) * 0.55, 0.0, 7.0)

func _process(delta: float) -> void:
	if not visible:
		return

	var is_authority: bool = (not GameState.is_network_active) or GameState.is_room_host

	var max_bonus_gb: float = GameState.get_dsn_max_bonus_gb()
	var is_dsn_maxed: bool = GameState.downloaded_data_gb >= max_bonus_gb

	if is_dsn_maxed:
		if is_authority and GameState.dsn_locked:
			GameState.dsn_locked = false
			GameState.recalculate()
			if GameState.is_network_active:
				GameState.sync_dsn_state(_station_idx, _target_center, _station_timer, GameState.downloaded_data_gb, GameState.ssd_used_gb, false)
		_refresh_labels(false, true, maxf(0.0, 6.0 - _station_timer))
		return

	if Input.is_action_pressed("ui_left"):
		freq_slider.value = clamp(freq_slider.value - 55.0 * delta, 0.0, 100.0)
	if Input.is_action_pressed("ui_right"):
		freq_slider.value = clamp(freq_slider.value + 55.0 * delta, 0.0, 100.0)

	if is_authority:
		_station_timer += delta
		if _station_timer >= 6.0:
			_station_timer = 0.0
			_station_idx = (_station_idx + 1) % STATIONS.size()
			_pick_new_target_for_station()

		# Sinyal frekansı hafifçe kayar; 4 oyuncu da oku hedef bandına kaydırabilir
		if randf() < 0.03:
			_drift_dir = -_drift_dir
		_updating_slider_from_net = true
		freq_slider.value = clamp(freq_slider.value + _drift_dir * 18.0 * delta, 0.0, 100.0)
		GameState.dsn_freq_value = freq_slider.value
		_updating_slider_from_net = false
	else:
		_station_idx = GameState.dsn_station_idx % STATIONS.size()
		_target_center = GameState.dsn_target_center
		_station_timer = GameState.dsn_station_timer

	var locked: bool = abs(freq_slider.value - _target_center) <= _target_half_width
	var window_remaining: float = max(0.0, 6.0 - _station_timer)
	var window_open: bool = window_remaining > 0.8

	if is_authority:
		var prev_locked: bool = GameState.dsn_locked
		GameState.dsn_locked = locked and window_open
		if locked and window_open:
			var prev_tier: int = GameState.get_dsn_bonus_tiers_completed()
			var transferred_gb: float = _get_effective_gb_per_sec() * delta
			GameState.downloaded_data_gb = minf(max_bonus_gb, GameState.downloaded_data_gb + transferred_gb)
			GameState.ssd_used_gb = max(0.0, GameState.ssd_used_gb - transferred_gb * 0.5)
			GameState.recalculate()
			var new_tier: int = GameState.get_dsn_bonus_tiers_completed()
			if new_tier > prev_tier and new_tier > _last_announced_tier:
				_last_announced_tier = new_tier
				var bonus_sci: int = GameState.get_dsn_bonus_science()
				EventBus.status_message.emit(
					"DSN EK VERİ KADEME %d/%d TAMAMLANDI! +%d Bilim Puanı eklendi (Toplam DSN Bonusu: +%d Bilim)!" % [
						new_tier,
						GameState.DSN_MAX_EXTRA_STEPS,
						GameState.DSN_EXTRA_SCIENCE_PER_STEP,
						bonus_sci
					],
					false
				)
		elif prev_locked != GameState.dsn_locked:
			GameState.recalculate()

		_net_sync_timer += delta
		if GameState.is_network_active and _net_sync_timer >= 0.1:
			_net_sync_timer = 0.0
			GameState.sync_dsn_state(_station_idx, _target_center, _station_timer, GameState.downloaded_data_gb, GameState.ssd_used_gb, GameState.dsn_locked)

	_refresh_labels(locked, window_open, window_remaining)

func _refresh_labels(locked: bool, window_open: bool = true, window_remaining: float = 5.0) -> void:
	var win_state: String = "AÇIK (%.1fs)" % window_remaining if window_open else "GEÇİŞ (EL DEĞİŞİMİ)"
	station_label.text = "İSTASYON: %s | GÖRÜŞ PENCERESİ: %s" % [STATIONS[_station_idx], win_state]
	var ssd_pct: int = int(round((GameState.ssd_used_gb / max(1.0, GameState.ssd_capacity_gb)) * 100.0))
	var gb_per_sec: float = _get_effective_gb_per_sec()
	var target_gb: float = GameState.get_target_download_gb()
	var downloaded_gb: float = GameState.downloaded_data_gb
	var goal_pct: float = clampf((downloaded_gb / max(1.0, target_gb)) * 100.0, 0.0, 100.0)
	var extra_gb: float = GameState.get_dsn_extra_gb()
	var bonus_tier: int = GameState.get_dsn_bonus_tiers_completed()
	var max_tiers: int = GameState.DSN_MAX_EXTRA_STEPS
	var step_gb: float = GameState.DSN_EXTRA_STEP_GB
	var step_sci: int = GameState.DSN_EXTRA_SCIENCE_PER_STEP
	var bonus_sci: int = GameState.get_dsn_bonus_science()
	var max_extra_gb: float = step_gb * float(max_tiers)

	if _goal_label != null:
		if downloaded_gb >= target_gb:
			_goal_label.text = "VERİ HEDEFİ TAMAMLANDI: %.1f / %.0f GB (%%%d) — Ek Veri ile Bilim Puanı Kazanabilirsin!" % [downloaded_gb, target_gb, int(round(goal_pct))]
			_goal_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.5))
		else:
			_goal_label.text = "GÖREV VERİ HEDEFİ: %.1f / %.0f GB (%%%d) | İndirilecek: %.1f GB" % [downloaded_gb, target_gb, int(round(goal_pct)), max(0.0, target_gb - downloaded_gb)]
			_goal_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	if _goal_bar != null:
		if downloaded_gb < target_gb:
			_goal_bar.value = goal_pct
		else:
			var extra_pct: float = clampf((extra_gb / max(1.0, max_extra_gb)) * 100.0, 0.0, 100.0)
			_goal_bar.value = extra_pct

	if _bonus_label != null:
		if downloaded_gb < target_gb:
			_bonus_label.text = "EK BİLİM BONUSU (0/%d): Hedef (%.0f GB) dolduktan sonra her +%.0f GB ek veri +%d Bilim Puanı verir (Maks 4 kademe: +%d Bilim)." % [
				max_tiers, target_gb, step_gb, step_sci, max_tiers * step_sci
			]
			_bonus_label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
		elif bonus_tier < max_tiers:
			var next_tier_gb: float = target_gb + float(bonus_tier + 1) * step_gb
			var rem_gb: float = maxf(0.0, next_tier_gb - downloaded_gb)
			_bonus_label.text = "EK BİLİM KADEME %d/%d AKTİF (+%d Bilim) | Sonraki +%d Bilim için: %.1f GB kaldı (Hedef: %.0f GB |Toplam Bilim: %d)" % [
				bonus_tier, max_tiers, bonus_sci, step_sci, rem_gb, next_tier_gb, GameState.science_score
			]
			_bonus_label.add_theme_color_override("font_color", Color(0.45, 0.98, 0.75))
		else:
			_bonus_label.text = "MAKSİMUM EK VERİ BONUSU (%d/%d TAMAMLANDI): +%d Bilim Puanı kazanıldı! (Toplam Bilim: %d)" % [
				max_tiers, max_tiers, bonus_sci, GameState.science_score
			]
			_bonus_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))

	stats_label.text = "İNDİRİLEN: %.1f/%.0f GB (+%.1f GB Ek) | HIZ: %.1f GB/sn | BİLİM: %d (+%d DSN) | ANTEN: %.0f Mbps" % [
		downloaded_gb,
		target_gb,
		extra_gb,
		gb_per_sec,
		GameState.science_score,
		bonus_sci,
		GameState.downlink_mbps
	]
	if _zone_rect != null:
		_zone_rect.anchor_left = clampf((_target_center - _target_half_width) / 100.0, 0.0, 1.0)
		_zone_rect.anchor_right = clampf((_target_center + _target_half_width) / 100.0, 0.0, 1.0)
	if _needle_rect != null:
		var needle_ratio: float = clampf(freq_slider.value / 100.0, 0.0, 1.0)
		_needle_rect.anchor_left = needle_ratio
		_needle_rect.anchor_right = needle_ratio

	var t_min: float = max(0.0, _target_center - _target_half_width)
	var t_max: float = min(100.0, _target_center + _target_half_width)
	if downloaded_gb >= GameState.get_dsn_max_bonus_gb():
		lock_status_label.text = "VERİ İLETİMİ TAMAMLANDI — MAKSİMUM EK BİLİM ALINDI!"
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	elif not window_open:
		lock_status_label.text = "YER İSTASYONU UFUK DEĞİŞİMİ — YENİ İSTASYON GELİYOR..."
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	elif locked:
		lock_status_label.text = "SİNYAL KİLİTLENDİ (%.0f-%.0f) — VERİ AKTARILIYOR!" % [t_min, t_max]
		lock_status_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	else:
		var dir_hint: String = "SAĞA KAYDIR >>" if freq_slider.value < t_min else "<< SOLA KAYDIR"
		lock_status_label.text = "SİNYAL KAYDI! HEDEF BANT: %.0f-%.0f (%s)" % [t_min, t_max, dir_hint]
		lock_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))

	_refresh_upgrade_tip()

func _refresh_upgrade_tip() -> void:
	if _tip_label == null:
		return
	var mbps: float = GameState.downlink_mbps

	if mbps >= 100.0:
		_tip_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
		_tip_label.text = "ANTEN DURUMU: Yüksek hızlı anten aktif (%.0f Mbps) — İndirme hızın maksimum seviyede!" % mbps
	elif mbps > 0.0:
		_tip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_tip_label.text = "HIZ ARTIRMA İPUCU: Mevcut anten hızı %.0f Mbps. İndirme hızını artırmak için daha güçlü bir iletişim anteni kullanabilirsin." % mbps
	else:
		_tip_label.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
		_tip_label.text = "HIZ ARTIRMA İPUCU: Şu an temel hızdasın. Veri indirme hızını artırmak için daha yüksek Mbps'li bir anten takabilirsin."

func _on_left_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value - 12.0, 0.0, 100.0)

func _on_right_pressed() -> void:
	freq_slider.value = clamp(freq_slider.value + 12.0, 0.0, 100.0)

func _on_close_pressed() -> void:
	visible = false
