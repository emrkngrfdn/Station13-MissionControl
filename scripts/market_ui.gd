extends PanelContainer

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")

const ICON_CAMERA: Texture2D = preload("res://assets/parts/camera_optical.png")
const ICON_SPECTROMETER: Texture2D = preload("res://assets/parts/spectrometer.png")
const ICON_SENSOR_CUBE: Texture2D = preload("res://assets/parts/sensor_cube.png")
const ICON_SOLAR_STD: Texture2D = preload("res://assets/parts/solar_std.png")
const ICON_SOLAR_HEX: Texture2D = preload("res://assets/parts/solar_hex.png")
const ICON_BATTERY: Texture2D = preload("res://assets/parts/power_battery.png")
const ICON_ANTENNA_WHIP: Texture2D = preload("res://assets/parts/antenna_whip.png")
const ICON_ANTENNA_DISH: Texture2D = preload("res://assets/parts/antenna_dish.png")
const ICON_AVIONICS: Texture2D = preload("res://assets/parts/avionics_cpu.png")
const ICON_THERMAL: Texture2D = preload("res://assets/parts/thermal_mli.png")

const PART_ICON_BY_ID: Dictionary = {
	"aqua_airs": ICON_SPECTROMETER,
	"aqua_modis": ICON_CAMERA,
	"aqua_amsre": ICON_SPECTROMETER,
	"aqua_ceres": ICON_SENSOR_CUBE,
	"lro_lend": ICON_SPECTROMETER,
	"lro_diviner": ICON_SENSOR_CUBE,
	"lro_lola": ICON_AVIONICS,
	"lro_lroc": ICON_CAMERA,
	"lro_lamp": ICON_SENSOR_CUBE,
	"lro_survival_heater": ICON_THERMAL,
	"juno_mwr": ICON_SPECTROMETER,
	"juno_jiram": ICON_SENSOR_CUBE,
	"juno_jade": ICON_SENSOR_CUBE,
	"juno_cam": ICON_CAMERA,
	"juno_radiation_vault": ICON_AVIONICS,
	"mars_supercam": ICON_SPECTROMETER,
	"mars_pixl": ICON_SPECTROMETER,
	"mars_sherloc": ICON_SPECTROMETER,
	"mars_moxie": ICON_SENSOR_CUBE,
	"mars_mastcam_z": ICON_CAMERA,
	"mars_meda": ICON_SENSOR_CUBE,
	"solar_std": ICON_SOLAR_STD,
	"solar_high_eff": ICON_SOLAR_HEX,
	"mmrtg": ICON_BATTERY,
	"rhu_battery": ICON_BATTERY,
	"antenna_s": ICON_ANTENNA_WHIP,
	"antenna_x": ICON_ANTENNA_WHIP,
	"antenna_ka": ICON_ANTENNA_DISH,
	"star_tracker_cpu": ICON_AVIONICS,
	"rad750_cpu": ICON_AVIONICS,
	"mli_thermal_shield": ICON_THERMAL
}

const CATEGORIES: Array[Dictionary] = [
	{ "id": "payload", "label": "BİLİM" },
	{ "id": "power", "label": "GÜÇ" },
	{ "id": "comms", "label": "İLETİŞİM" },
	{ "id": "avionics", "label": "AVİYONİK" },
	{ "id": "survival", "label": "KORUMA" }
]

@onready var budget_label: Label = %MarketBudgetLabel
@onready var rocket_option: OptionButton = %RocketOption
@onready var parts_grid: GridContainer = %PartsGrid
@onready var status_label: Label = %MarketStatusLabel

var _selected_category: String = "payload"
var _cart: Array[Dictionary] = []

var _category_bar: HBoxContainer = null
var _category_buttons: Dictionary = {}
var _body_hbox: HBoxContainer = null
var _cart_panel: PanelContainer = null
var _cart_list: VBoxContainer = null
var _cart_total_label: Label = null
var _cart_remaining_label: Label = null
var _cart_mass_label: Label = null
var _buy_dispense_btn: Button = null
var _clear_cart_btn: Button = null
var _comm_label: Label = null
var _mass_badge: Label = null
var _purchased_strip: Label = null

func _ready() -> void:
	visible = false
	_apply_retro_market_shell()
	_build_retro_layout()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.telemetry_changed.connect(_refresh_all)
	EventBus.mission_started.connect(_on_mission_reset)

func _exit_tree() -> void:
	if EventBus.terminal_opened.is_connected(_on_terminal_opened):
		EventBus.terminal_opened.disconnect(_on_terminal_opened)
	if EventBus.telemetry_changed.is_connected(_refresh_all):
		EventBus.telemetry_changed.disconnect(_refresh_all)
	if EventBus.mission_started.is_connected(_on_mission_reset):
		EventBus.mission_started.disconnect(_on_mission_reset)

func _on_mission_reset() -> void:
	_cart.clear()

func _apply_retro_market_shell() -> void:
	var shell_sb: StyleBoxFlat = StyleBoxFlat.new()
	shell_sb.bg_color = Color(0.08, 0.145, 0.195, 0.98)
	shell_sb.border_width_left = 3
	shell_sb.border_width_top = 3
	shell_sb.border_width_right = 3
	shell_sb.border_width_bottom = 4
	shell_sb.border_color = Color(0.42, 0.56, 0.64, 1.0)
	shell_sb.corner_radius_top_left = 5
	shell_sb.corner_radius_top_right = 5
	shell_sb.corner_radius_bottom_left = 5
	shell_sb.corner_radius_bottom_right = 5
	shell_sb.content_margin_left = 8.0
	shell_sb.content_margin_right = 8.0
	shell_sb.content_margin_top = 6.0
	shell_sb.content_margin_bottom = 6.0
	shell_sb.shadow_color = Color(0.01, 0.02, 0.05, 0.78)
	shell_sb.shadow_size = 6
	shell_sb.shadow_offset = Vector2(2, 3)
	shell_sb.anti_aliasing = false
	add_theme_stylebox_override("panel", shell_sb)

func _build_retro_layout() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _body_hbox != null:
		return

	var header: HBoxContainer = get_node_or_null("VBox/Header") as HBoxContainer
	var title_lbl: Label = get_node_or_null("VBox/Header/Title") as Label
	if title_lbl != null:
		title_lbl.text = "UZAY TEDARİK MAĞAZASI"
		title_lbl.add_theme_font_size_override("font_size", 11)
		title_lbl.add_theme_color_override("font_color", Color(0.98, 0.72, 0.22))
		title_lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.09))
		title_lbl.add_theme_constant_override("outline_size", 2)

	if header != null:
		_comm_label = Label.new()
		_comm_label.add_theme_font_size_override("font_size", 7)
		_comm_label.add_theme_color_override("font_color", Color(0.38, 0.94, 0.58))
		_comm_label.text = "BANT BAĞLANTISI: ÇEVRİMİÇİ\nKATALOG ERİŞİMİ: HAZIR"
		header.add_child(_comm_label)
		header.move_child(_comm_label, budget_label.get_index())

	if budget_label != null:
		budget_label.add_theme_font_size_override("font_size", 10)
		budget_label.add_theme_color_override("font_color", Color(0.45, 0.96, 0.62))
		var b_sb: StyleBoxFlat = StyleBoxFlat.new()
		b_sb.bg_color = Color(0.05, 0.10, 0.14, 0.96)
		b_sb.border_width_left = 1
		b_sb.border_width_top = 1
		b_sb.border_width_right = 1
		b_sb.border_width_bottom = 2
		b_sb.border_color = Color(0.36, 0.56, 0.66, 1.0)
		b_sb.content_margin_left = 6.0
		b_sb.content_margin_right = 6.0
		b_sb.content_margin_top = 2.0
		b_sb.content_margin_bottom = 2.0
		b_sb.anti_aliasing = false
		budget_label.add_theme_stylebox_override("normal", b_sb)

	var close_btn: Button = get_node_or_null("VBox/Header/CloseBtn") as Button
	if close_btn != null:
		close_btn.text = "İSTASYONA DÖN [X]"
		StationFrameDrawer.style_close_button(close_btn)
		close_btn.add_theme_font_size_override("font_size", 8)

	# Kategori Sekmeleri (Klasör Sekmesi Görünümü)
	_category_bar = HBoxContainer.new()
	_category_bar.add_theme_constant_override("separation", 3)
	for cat in CATEGORIES:
		var cid: String = String(cat["id"])
		var btn: Button = Button.new()
		btn.text = String(cat["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 20)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_on_category_selected.bind(cid))
		_category_bar.add_child(btn)
		_category_buttons[cid] = btn
	vbox.add_child(_category_bar)
	vbox.move_child(_category_bar, 0)

	# Roket Barına Kütle Göstergesi Ekle
	var rocket_bar: HBoxContainer = get_node_or_null("VBox/RocketBar") as HBoxContainer
	if rocket_bar != null:
		var r_lbl: Label = rocket_bar.get_node_or_null("RocketLbl") as Label
		if r_lbl != null:
			r_lbl.add_theme_font_size_override("font_size", 8)
			r_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 0.96))
		if rocket_option != null:
			rocket_option.add_theme_font_size_override("font_size", 8)
		_mass_badge = Label.new()
		_mass_badge.add_theme_font_size_override("font_size", 8)
		_mass_badge.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6))
		rocket_bar.add_child(_mass_badge)

	# Ana 2 Sütunlu Gövde: Sol = Parça Kartları, Sağ = Alışveriş Sepeti
	var scroll_node: ScrollContainer = get_node_or_null("VBox/Scroll") as ScrollContainer
	_body_hbox = HBoxContainer.new()
	_body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_hbox.add_theme_constant_override("separation", 6)

	var scroll_idx: int = scroll_node.get_index() if scroll_node != null else 3
	vbox.add_child(_body_hbox)
	vbox.move_child(_body_hbox, scroll_idx)

	if scroll_node != null:
		scroll_node.reparent(_body_hbox)
		scroll_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll_node.size_flags_stretch_ratio = 2.05

	_build_cart_sidebar()
	_body_hbox.add_child(_cart_panel)

	# Alt Durum ve Alınanlar Şeridi
	_purchased_strip = Label.new()
	_purchased_strip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purchased_strip.add_theme_font_size_override("font_size", 8)
	_purchased_strip.add_theme_color_override("font_color", Color(0.72, 0.86, 0.94))
	var status_idx: int = status_label.get_index()
	vbox.add_child(_purchased_strip)
	vbox.move_child(_purchased_strip, status_idx)

	if status_label != null:
		status_label.add_theme_font_size_override("font_size", 8)
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_cart_sidebar() -> void:
	_cart_panel = PanelContainer.new()
	_cart_panel.custom_minimum_size = Vector2(174, 0)
	_cart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var cart_sb: StyleBoxFlat = StyleBoxFlat.new()
	cart_sb.bg_color = Color(0.055, 0.105, 0.145, 0.98)
	cart_sb.border_width_left = 2
	cart_sb.border_width_top = 2
	cart_sb.border_width_right = 2
	cart_sb.border_width_bottom = 3
	cart_sb.border_color = Color(0.35, 0.50, 0.58, 1.0)
	cart_sb.corner_radius_top_left = 4
	cart_sb.corner_radius_top_right = 4
	cart_sb.corner_radius_bottom_left = 4
	cart_sb.corner_radius_bottom_right = 4
	cart_sb.content_margin_left = 6.0
	cart_sb.content_margin_right = 6.0
	cart_sb.content_margin_top = 5.0
	cart_sb.content_margin_bottom = 5.0
	cart_sb.anti_aliasing = false
	_cart_panel.add_theme_stylebox_override("panel", cart_sb)

	var c_vbox: VBoxContainer = VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 4)
	_cart_panel.add_child(c_vbox)

	var c_title: Label = Label.new()
	c_title.text = "ALIŞVERİŞ SEPETİ"
	c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_title.add_theme_font_size_override("font_size", 9)
	c_title.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	c_vbox.add_child(c_title)

	var c_sub: Label = Label.new()
	c_sub.text = "TESLİMAT DEFTERİ"
	c_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_sub.add_theme_font_size_override("font_size", 7)
	c_sub.add_theme_color_override("font_color", Color(0.55, 0.68, 0.78))
	c_vbox.add_child(c_sub)

	var c_scroll: ScrollContainer = ScrollContainer.new()
	c_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c_vbox.add_child(c_scroll)

	_cart_list = VBoxContainer.new()
	_cart_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cart_list.add_theme_constant_override("separation", 3)
	c_scroll.add_child(_cart_list)

	var totals_box: VBoxContainer = VBoxContainer.new()
	totals_box.add_theme_constant_override("separation", 1)
	c_vbox.add_child(totals_box)

	_cart_total_label = Label.new()
	_cart_total_label.add_theme_font_size_override("font_size", 8)
	_cart_total_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	totals_box.add_child(_cart_total_label)

	_cart_remaining_label = Label.new()
	_cart_remaining_label.add_theme_font_size_override("font_size", 8)
	_cart_remaining_label.add_theme_color_override("font_color", Color(0.45, 0.96, 0.62))
	totals_box.add_child(_cart_remaining_label)

	_cart_mass_label = Label.new()
	_cart_mass_label.add_theme_font_size_override("font_size", 7)
	_cart_mass_label.add_theme_color_override("font_color", Color(0.76, 0.86, 0.94))
	totals_box.add_child(_cart_mass_label)

	# Sarı-Siyah Uyarı Şeritli "SATIN AL & BANDA GÖNDER" Çerçevesi
	var hazard_wrap: PanelContainer = PanelContainer.new()
	var hw_sb: StyleBoxFlat = StyleBoxFlat.new()
	hw_sb.bg_color = Color(0.08, 0.11, 0.13, 1.0)
	hw_sb.border_width_left = 2
	hw_sb.border_width_top = 2
	hw_sb.border_width_right = 2
	hw_sb.border_width_bottom = 2
	hw_sb.border_color = Color(0.95, 0.72, 0.18, 1.0)
	hw_sb.content_margin_left = 4.0
	hw_sb.content_margin_right = 4.0
	hw_sb.content_margin_top = 4.0
	hw_sb.content_margin_bottom = 4.0
	hw_sb.anti_aliasing = false
	hazard_wrap.add_theme_stylebox_override("panel", hw_sb)
	hazard_wrap.draw.connect(_on_hazard_wrap_draw.bind(hazard_wrap, Color(0.92, 0.68, 0.16, 0.95), Color(0.08, 0.10, 0.12, 1.0)))
	c_vbox.add_child(hazard_wrap)

	_buy_dispense_btn = Button.new()
	_buy_dispense_btn.text = "SATIN AL &\nBANDA GÖNDER"
	_buy_dispense_btn.custom_minimum_size = Vector2(0, 34)
	_buy_dispense_btn.focus_mode = Control.FOCUS_NONE
	_buy_dispense_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_buy_dispense_btn.add_theme_font_size_override("font_size", 8)
	_buy_dispense_btn.add_theme_color_override("font_color", Color(0.86, 0.98, 0.92))
	var buy_sb: StyleBoxFlat = StyleBoxFlat.new()
	buy_sb.bg_color = Color(0.11, 0.36, 0.30, 1.0)
	buy_sb.border_width_left = 1
	buy_sb.border_width_top = 1
	buy_sb.border_width_right = 1
	buy_sb.border_width_bottom = 2
	buy_sb.border_color = Color(0.32, 0.85, 0.68, 1.0)
	buy_sb.anti_aliasing = false
	var buy_hov: StyleBoxFlat = buy_sb.duplicate() as StyleBoxFlat
	buy_hov.bg_color = Color(0.15, 0.48, 0.40, 1.0)
	var buy_dis: StyleBoxFlat = buy_sb.duplicate() as StyleBoxFlat
	buy_dis.bg_color = Color(0.12, 0.16, 0.20, 0.9)
	buy_dis.border_color = Color(0.30, 0.36, 0.42, 0.8)
	_buy_dispense_btn.add_theme_stylebox_override("normal", buy_sb)
	_buy_dispense_btn.add_theme_stylebox_override("hover", buy_hov)
	_buy_dispense_btn.add_theme_stylebox_override("pressed", buy_hov)
	_buy_dispense_btn.add_theme_stylebox_override("disabled", buy_dis)
	_buy_dispense_btn.pressed.connect(_on_buy_dispense_pressed)
	hazard_wrap.add_child(_buy_dispense_btn)

	_clear_cart_btn = Button.new()
	_clear_cart_btn.text = "SEPETİ TEMİZLE"
	_clear_cart_btn.focus_mode = Control.FOCUS_NONE
	_clear_cart_btn.add_theme_font_size_override("font_size", 7)
	_clear_cart_btn.pressed.connect(_on_clear_cart_pressed)
	c_vbox.add_child(_clear_cart_btn)

func _on_hazard_wrap_draw(ctrl: Control, stripe_col: Color, bg_col: Color) -> void:
	var w: float = ctrl.size.x
	var h: float = ctrl.size.y
	if w <= 2.0 or h <= 2.0:
		return
	ctrl.draw_rect(Rect2(0, 0, w, h), bg_col, true)
	var step: float = 10.0
	var x: float = -h
	while x < w + h:
		var pts := PackedVector2Array([
			Vector2(x, h),
			Vector2(x + 5.0, h),
			Vector2(x + h + 5.0, 0.0),
			Vector2(x + h, 0.0)
		])
		ctrl.draw_colored_polygon(pts, stripe_col)
		x += step
	ctrl.draw_rect(Rect2(0, 0, w, h), stripe_col, false, 1.5)

func _on_card_bezel_draw(ctrl: Control, is_hazard: bool, is_installed: bool) -> void:
	var w: float = ctrl.size.x
	var h: float = ctrl.size.y
	if w <= 8.0 or h <= 8.0:
		return
	if is_hazard:
		_on_hazard_wrap_draw(ctrl, Color(0.92, 0.45, 0.16, 0.9), Color(0.16, 0.06, 0.06, 1.0))
		return
	# Üst sağ ve alt sağ LED göstergeleri (retro donanım paneli)
	var led_y: float = 4.0
	var cols: Array[Color] = [
		Color(0.32, 0.96, 0.52) if is_installed else Color(0.25, 0.72, 0.96),
		Color(0.98, 0.82, 0.25),
		Color(0.92, 0.34, 0.32)
	]
	for i in range(cols.size()):
		ctrl.draw_rect(Rect2(w - 22.0 + float(i) * 5.0, led_y, 3.0, 3.0), cols[i], true)
		ctrl.draw_rect(Rect2(w - 22.0 + float(i) * 5.0, h - 7.0, 3.0, 3.0), cols[(i + 1) % cols.size()], true)

func _get_part_icon(part: Dictionary) -> Texture2D:
	var pid: String = String(part.get("id", ""))
	if PART_ICON_BY_ID.has(pid):
		return PART_ICON_BY_ID[pid]
	var ptype: String = String(part.get("type", "payload"))
	match ptype:
		"power":
			return ICON_SOLAR_STD
		"comms":
			return ICON_ANTENNA_DISH
		"avionics":
			return ICON_AVIONICS
		"survival":
			return ICON_THERMAL
		_:
			return ICON_SPECTROMETER

func _is_hazard_part(part: Dictionary) -> bool:
	var tags: Array = part.get("tags", [])
	var notes: String = String(part.get("notes", ""))
	return tags.has("peak_power_trap") or tags.has("radiation_degrading_camera") or notes.begins_with("KRİTİK") or notes.begins_with("MÜHENDİSLİK TUZAĞI")

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "MARKET":
		open_market()

func open_market() -> void:
	visible = true
	move_to_front()
	_populate_rockets()
	_refresh_category_buttons()
	_populate_parts()
	_refresh_header()
	_refresh_cart()
	_refresh_purchased_list()
	status_label.add_theme_color_override("font_color", Color(0.75, 0.90, 0.98))
	status_label.text = "Parçaları sepete ekleyin ve 'SATIN AL & BANDA GÖNDER' ile kargo bandına çıkarın."

func _on_category_selected(cat_id: String) -> void:
	_selected_category = cat_id
	_refresh_category_buttons()
	_populate_parts()

func _refresh_category_buttons() -> void:
	var all_parts: Array = GameState.get_available_parts_for_mission()
	var counts: Dictionary = {}
	for p in all_parts:
		var t: String = String(p.get("type", "payload"))
		counts[t] = int(counts.get(t, 0)) + 1

	for cat in CATEGORIES:
		var cid: String = String(cat["id"])
		var btn: Button = _category_buttons.get(cid, null)
		if btn == null:
			continue
		var c: int = int(counts.get(cid, 0))
		btn.text = "%s (%d)" % [String(cat["label"]), c]
		var is_active: bool = (cid == _selected_category)
		btn.add_theme_color_override(
			"font_color",
			Color(1.0, 0.85, 0.30) if is_active else Color(0.74, 0.85, 0.92)
		)
		var tab_sb: StyleBoxFlat = StyleBoxFlat.new()
		tab_sb.bg_color = Color(0.14, 0.23, 0.29, 1.0) if is_active else Color(0.06, 0.10, 0.14, 0.95)
		tab_sb.border_width_left = 1
		tab_sb.border_width_top = 2 if is_active else 1
		tab_sb.border_width_right = 1
		tab_sb.border_width_bottom = 0 if is_active else 2
		tab_sb.border_color = Color(0.96, 0.72, 0.22, 1.0) if is_active else Color(0.28, 0.40, 0.48, 1.0)
		tab_sb.corner_radius_top_left = 3
		tab_sb.corner_radius_top_right = 3
		tab_sb.content_margin_left = 4.0
		tab_sb.content_margin_right = 4.0
		tab_sb.content_margin_top = 2.0
		tab_sb.content_margin_bottom = 2.0
		tab_sb.anti_aliasing = false
		btn.add_theme_stylebox_override("normal", tab_sb)
		btn.add_theme_stylebox_override("hover", tab_sb)
		btn.add_theme_stylebox_override("pressed", tab_sb)

func _refresh_all() -> void:
	if not visible:
		return
	_refresh_header()
	_refresh_purchased_list()
	_refresh_category_buttons()
	_populate_parts()
	_refresh_cart()

func _refresh_header() -> void:
	if not visible:
		return
	var eff_mass: float = GameState.get_effective_mass_kg()
	var eff_limit: float = GameState.get_effective_mass_limit_kg()
	budget_label.text = "BÜTÇE: $%.0fM" % GameState.budget_m
	if GameState.budget_m <= 0.0:
		budget_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	else:
		budget_label.add_theme_color_override("font_color", Color(0.45, 0.96, 0.62))

	if _mass_badge != null:
		_mass_badge.text = "KÜTLE: %.0f/%.0f kg" % [eff_mass, eff_limit]
		_mass_badge.add_theme_color_override(
			"font_color",
			Color(1.0, 0.38, 0.35) if eff_mass > eff_limit else Color(0.45, 0.95, 0.62)
		)

func _refresh_purchased_list() -> void:
	if _purchased_strip == null:
		return
	var summary: Array = GameState.get_purchased_summary()
	if summary.is_empty():
		_purchased_strip.text = "ALINAN EKİPMANLAR: Henüz satın alma yapılmadı."
		return

	var items: Array[String] = []
	for entry in summary:
		var count: int = int(entry.get("count", 1))
		var name_str: String = String(entry.get("name", "Parça"))
		var tag: String = " [MONTE]" if bool(entry.get("installed", false)) else ""
		if count > 1:
			items.append("%s (x%d%s)" % [name_str, count, tag])
		else:
			items.append("%s%s" % [name_str, tag])
	_purchased_strip.text = "ALINAN EKİPMANLAR: " + ", ".join(items)

func _get_cart_count_for_id(pid: String) -> int:
	var c: int = 0
	for item in _cart:
		if String(item.get("id", "")) == pid:
			c += 1
	return c

func _get_cart_total_cost() -> float:
	var total: float = 0.0
	for item in _cart:
		total += float(item.get("cost_m", 0.0))
	return total

func _get_cart_total_mass() -> float:
	var total: float = 0.0
	for item in _cart:
		total += float(item.get("mass_kg", 0.0))
	return total

func _populate_rockets() -> void:
	rocket_option.clear()
	var rockets: Array = GameState.parts_data.get("rockets", [])
	var selected_id: String = String(GameState.selected_rocket.get("id", ""))
	var bus_mass: float = float(GameState.current_mission.get("bus_dry_mass_kg", 0.0))
	var distance_au: float = float(GameState.current_mission.get("distance_au", 1.0))
	var needs_deep_space: bool = distance_au > 1.2

	var compatible: Array = []
	for r in rockets:
		var r_dict: Dictionary = r
		var r_id: String = String(r_dict.get("id", ""))
		var r_cap: float = float(r_dict.get("max_mass_kg", 0.0))
		var r_deep: bool = bool(r_dict.get("deep_space", false))
		if r_id != selected_id:
			if r_cap < bus_mass:
				continue
			if needs_deep_space and not r_deep:
				continue
		compatible.append(r_dict)

	compatible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("max_mass_kg", 0.0)) < float(b.get("max_mass_kg", 0.0))
	)

	var current_tier_idx: int = 0
	for i in range(compatible.size()):
		if String(compatible[i].get("id", "")) == selected_id:
			current_tier_idx = i
			break

	for i in range(compatible.size()):
		var r_dict: Dictionary = compatible[i]
		var r_cap: float = float(r_dict.get("max_mass_kg", 0.0))
		var upgrade_cost: float = GameState.get_rocket_upgrade_cost(r_dict)
		var label: String = "%s (%.0f kg)" % [String(r_dict.get("name", "")), r_cap]
		var is_locked: bool = i > current_tier_idx + 1
		if is_locked:
			label += " [KİLİTLİ]"
		elif upgrade_cost > 0.0:
			label += " [+$%.0fM]" % upgrade_cost
		rocket_option.add_item(label)
		rocket_option.set_item_metadata(i, r_dict)
		if is_locked:
			rocket_option.set_item_disabled(i, true)
	if rocket_option.item_count > 0:
		rocket_option.selected = current_tier_idx

func _populate_parts() -> void:
	for child in parts_grid.get_children():
		child.queue_free()

	var counts_by_id: Dictionary = {}
	for entry in GameState.get_purchased_summary():
		counts_by_id[String(entry.get("id", ""))] = int(entry.get("count", 0))

	var parts: Array = GameState.get_available_parts_for_mission()
	for p in parts:
		var p_type: String = String(p.get("type", "payload"))
		if _selected_category != "all" and p_type != _selected_category:
			continue

		var pid: String = String(p.get("id", ""))
		var bought_count: int = int(counts_by_id.get(pid, 0))
		var cart_count: int = _get_cart_count_for_id(pid)
		var installed: bool = GameState.is_part_installed(pid)
		var is_hazard: bool = _is_hazard_part(p)

		# Retro Donanım Çerçevesi
		var bezel: PanelContainer = PanelContainer.new()
		bezel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bezel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var bezel_sb: StyleBoxFlat = StyleBoxFlat.new()
		bezel_sb.bg_color = Color(0.18, 0.09, 0.07, 1.0) if is_hazard else Color(0.24, 0.32, 0.37, 1.0)
		bezel_sb.border_width_left = 2
		bezel_sb.border_width_top = 2
		bezel_sb.border_width_right = 2
		bezel_sb.border_width_bottom = 3
		bezel_sb.border_color = Color(0.95, 0.56, 0.16, 1.0) if is_hazard else (Color(0.35, 0.85, 0.62, 1.0) if installed else Color(0.46, 0.58, 0.66, 1.0))
		bezel_sb.corner_radius_top_left = 4
		bezel_sb.corner_radius_top_right = 4
		bezel_sb.corner_radius_bottom_left = 4
		bezel_sb.corner_radius_bottom_right = 4
		bezel_sb.content_margin_left = 4.0
		bezel_sb.content_margin_right = 4.0
		bezel_sb.content_margin_top = 9.0
		bezel_sb.content_margin_bottom = 9.0
		bezel_sb.anti_aliasing = false
		bezel.add_theme_stylebox_override("panel", bezel_sb)
		bezel.draw.connect(_on_card_bezel_draw.bind(bezel, is_hazard, installed))

		# İç Koyu Ekran
		var screen: PanelContainer = PanelContainer.new()
		screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var scr_sb: StyleBoxFlat = StyleBoxFlat.new()
		scr_sb.bg_color = Color(0.12, 0.05, 0.06, 0.96) if is_hazard else Color(0.05, 0.11, 0.145, 0.98)
		scr_sb.border_width_left = 1
		scr_sb.border_width_top = 1
		scr_sb.border_width_right = 1
		scr_sb.border_width_bottom = 1
		scr_sb.border_color = Color(0.68, 0.25, 0.18, 0.9) if is_hazard else Color(0.14, 0.24, 0.30, 1.0)
		scr_sb.content_margin_left = 5.0
		scr_sb.content_margin_right = 5.0
		scr_sb.content_margin_top = 4.0
		scr_sb.content_margin_bottom = 4.0
		scr_sb.anti_aliasing = false
		screen.add_theme_stylebox_override("panel", scr_sb)
		bezel.add_child(screen)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 3)
		screen.add_child(vbox)

		# Başlık Satırı
		var title: Label = Label.new()
		var badge_txt: String = ""
		if bought_count > 0:
			badge_txt += " [x%d]" % bought_count
		if cart_count > 0:
			badge_txt += " [+%d]" % cart_count
		if installed:
			badge_txt += " [MONTE]"
		title.text = String(p.get("name", "Parça")).to_upper() + badge_txt
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 9)
		title.add_theme_color_override(
			"font_color",
			Color(1.0, 0.78, 0.34) if is_hazard else (Color(0.55, 0.96, 0.72) if installed else Color(0.84, 0.94, 1.0))
		)
		vbox.add_child(title)

		# Orta Alan: Sol Piksel İkon + Sağ İstatistikler
		var mid_hbox: HBoxContainer = HBoxContainer.new()
		mid_hbox.add_theme_constant_override("separation", 5)
		vbox.add_child(mid_hbox)

		var icon_frame: PanelContainer = PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(46, 46)
		var if_sb: StyleBoxFlat = StyleBoxFlat.new()
		if_sb.bg_color = Color(0.03, 0.07, 0.11, 0.95)
		if_sb.border_width_left = 1
		if_sb.border_width_top = 1
		if_sb.border_width_right = 1
		if_sb.border_width_bottom = 1
		if_sb.border_color = Color(0.75, 0.42, 0.22, 0.85) if is_hazard else Color(0.22, 0.38, 0.46, 0.9)
		if_sb.content_margin_left = 2.0
		if_sb.content_margin_right = 2.0
		if_sb.content_margin_top = 2.0
		if_sb.content_margin_bottom = 2.0
		if_sb.anti_aliasing = false
		icon_frame.add_theme_stylebox_override("panel", if_sb)

		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = _get_part_icon(p)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_frame.add_child(icon_rect)
		mid_hbox.add_child(icon_frame)

		var stats_lbl: Label = Label.new()
		stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats_lbl.add_theme_font_size_override("font_size", 8)
		var pwr: float = float(p.get("power_w", 0.0))
		var pwr_str: String = "%+.0fW" % pwr
		if p.has("peak_power_w"):
			pwr_str += " (Tepe %.0fW)" % float(p["peak_power_w"])
		var d_rate: float = float(p.get("data_mbps", 0.0))
		var sci: int = int(p.get("science", 0))
		var l_bon: int = int(p.get("landing_bonus", 0))
		var stat_lines: Array[String] = [
			"FİYAT: $%dM" % int(p.get("cost_m", 0)),
			"KÜTLE: %.1f kg" % float(p.get("mass_kg", 0.0)),
			"GÜÇ: %s" % pwr_str
		]
		if d_rate > 0.0:
			stat_lines.append("VERİ: %.0f MB/s" % d_rate)
		elif d_rate < 0.0:
			stat_lines.append("HIZ: %.0f Mbps" % absf(d_rate))
		if sci > 0:
			stat_lines.append("BİLİM: +%d" % sci)
		elif l_bon > 0:
			stat_lines.append("İNİŞ: +%%%d" % l_bon)
		stats_lbl.text = "\n".join(stat_lines)
		stats_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
		mid_hbox.add_child(stats_lbl)

		# Not Satırı
		var note: Label = Label.new()
		note.text = String(p.get("notes", ""))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_vertical = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 7)
		note.add_theme_color_override(
			"font_color",
			Color(1.0, 0.74, 0.45) if is_hazard else Color(0.72, 0.82, 0.88)
		)
		vbox.add_child(note)

		# Sepete Ekle Butonu
		var btn: Button = Button.new()
		btn.text = "+ SEPETE EKLE ($%dM)" % int(p.get("cost_m", 0))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 20)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 8)
		var btn_sb: StyleBoxFlat = StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.45, 0.18, 0.10, 1.0) if is_hazard else Color(0.11, 0.25, 0.34, 1.0)
		btn_sb.border_width_left = 1
		btn_sb.border_width_top = 1
		btn_sb.border_width_right = 1
		btn_sb.border_width_bottom = 2
		btn_sb.border_color = Color(0.95, 0.58, 0.20, 1.0) if is_hazard else Color(0.32, 0.68, 0.86, 1.0)
		btn_sb.anti_aliasing = false
		var btn_hov: StyleBoxFlat = btn_sb.duplicate() as StyleBoxFlat
		btn_hov.bg_color = btn_sb.bg_color.lightened(0.16)
		btn.add_theme_stylebox_override("normal", btn_sb)
		btn.add_theme_stylebox_override("hover", btn_hov)
		btn.add_theme_stylebox_override("pressed", btn_hov)
		btn.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		btn.pressed.connect(_on_add_to_cart_pressed.bind(p))
		vbox.add_child(btn)

		parts_grid.add_child(bezel)

func _on_add_to_cart_pressed(part: Dictionary) -> void:
	var cost: float = float(part.get("cost_m", 0.0))
	var p_name: String = String(part.get("name", "Ekipman"))
	var projected_total: float = _get_cart_total_cost() + cost
	if projected_total > GameState.budget_m:
		var err_msg: String = "BÜTÇE YETERSİZ! %s ($%.0fM) sepete eklenirse toplam $%.0fM bütçeni ($%.0fM) aşıyor!" % [
			p_name, cost, projected_total, GameState.budget_m
		]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		status_label.text = err_msg
		EventBus.status_message.emit(err_msg, true)
		return
	_cart.append(part)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.94, 0.82))
	status_label.text = "SEPETE EKLENDİ: %s ($%.0fM)" % [p_name, cost]
	_populate_parts()
	_refresh_cart()

func _refresh_cart() -> void:
	if _cart_list == null:
		return
	for child in _cart_list.get_children():
		child.queue_free()

	if _cart.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Sepet boş.\nSoldan parça ekleyip\n'SATIN AL' butonuna bas."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 8)
		empty_lbl.add_theme_color_override("font_color", Color(0.58, 0.68, 0.76))
		_cart_list.add_child(empty_lbl)
	else:
		for idx in range(_cart.size()):
			var item: Dictionary = _cart[idx]
			var row_panel: PanelContainer = PanelContainer.new()
			var r_sb: StyleBoxFlat = StyleBoxFlat.new()
			r_sb.bg_color = Color(0.08, 0.15, 0.21, 0.96)
			r_sb.border_width_left = 1
			r_sb.border_width_top = 1
			r_sb.border_width_right = 1
			r_sb.border_width_bottom = 1
			r_sb.border_color = Color(0.24, 0.38, 0.48, 1.0)
			r_sb.content_margin_left = 4.0
			r_sb.content_margin_right = 3.0
			r_sb.content_margin_top = 2.0
			r_sb.content_margin_bottom = 2.0
			r_sb.anti_aliasing = false
			row_panel.add_theme_stylebox_override("panel", r_sb)

			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row_panel.add_child(row)

			var mini_icon: TextureRect = TextureRect.new()
			mini_icon.texture = _get_part_icon(item)
			mini_icon.custom_minimum_size = Vector2(20, 20)
			mini_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mini_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mini_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(mini_icon)

			var info_lbl: Label = Label.new()
			info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_lbl.clip_text = true
			info_lbl.add_theme_font_size_override("font_size", 7)
			info_lbl.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
			info_lbl.text = "%s\n$%dM | %.0fkg" % [
				String(item.get("name", "Parça")),
				int(item.get("cost_m", 0)),
				float(item.get("mass_kg", 0.0))
			]
			row.add_child(info_lbl)

			var rem_btn: Button = Button.new()
			rem_btn.text = "✕"
			rem_btn.focus_mode = Control.FOCUS_NONE
			rem_btn.add_theme_font_size_override("font_size", 7)
			rem_btn.add_theme_color_override("font_color", Color(1.0, 0.52, 0.48))
			rem_btn.pressed.connect(_on_remove_cart_item.bind(idx))
			row.add_child(rem_btn)

			_cart_list.add_child(row_panel)

	var total_cost: float = _get_cart_total_cost()
	var remaining: float = GameState.budget_m - total_cost
	var cart_mass: float = _get_cart_total_mass()
	var eff_mass: float = GameState.get_effective_mass_kg() + cart_mass
	var mass_limit: float = GameState.get_effective_mass_limit_kg()

	_cart_total_label.text = "TOPLAM TUTAR: $%.0fM" % total_cost
	_cart_remaining_label.text = "KALAN BÜTÇE: $%.0fM" % remaining
	_cart_remaining_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.4, 0.35) if remaining < 0.0 else Color(0.45, 0.96, 0.62)
	)
	_cart_mass_label.text = "SEPET KÜTLE: +%.0f kg (Top: %.0f/%.0f)" % [cart_mass, eff_mass, mass_limit]
	_cart_mass_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.58, 0.35) if eff_mass > mass_limit else Color(0.74, 0.86, 0.94)
	)

	var can_buy: bool = not _cart.is_empty() and remaining >= 0.0
	if _buy_dispense_btn != null:
		_buy_dispense_btn.disabled = not can_buy
		_buy_dispense_btn.text = (
			"BÜTÇE YETERSİZ!" if (not _cart.is_empty() and remaining < 0.0) else "SATIN AL &\nBANDA GÖNDER"
		)
	if _clear_cart_btn != null:
		_clear_cart_btn.visible = not _cart.is_empty()

func _on_remove_cart_item(idx: int) -> void:
	if idx >= 0 and idx < _cart.size():
		_cart.remove_at(idx)
		_populate_parts()
		_refresh_cart()

func _on_clear_cart_pressed() -> void:
	_cart.clear()
	_populate_parts()
	_refresh_cart()

func _on_buy_dispense_pressed() -> void:
	if _cart.is_empty():
		return
	var total_cost: float = _get_cart_total_cost()
	if total_cost > GameState.budget_m:
		var err_msg: String = "BÜTÇE YETERSİZ! Sepet toplamı $%.0fM (Mevcut: $%.0fM)." % [total_cost, GameState.budget_m]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		status_label.text = err_msg
		EventBus.status_message.emit(err_msg, true)
		return

	var bought_names: Array[String] = []
	for part in _cart:
		if GameState.buy_part(part):
			bought_names.append(String(part.get("name", "Ekipman")))
	_cart.clear()

	status_label.add_theme_color_override("font_color", Color(0.45, 0.96, 0.62))
	status_label.text = "KARGO BANDINA BIRAKILDI (%d): %s" % [bought_names.size(), ", ".join(bought_names)]
	_refresh_header()
	_refresh_purchased_list()
	_populate_parts()
	_refresh_cart()

func _on_rocket_selected(idx: int) -> void:
	if idx >= 0 and idx < rocket_option.item_count:
		var r: Dictionary = rocket_option.get_item_metadata(idx)
		var upgrade_cost: float = GameState.get_rocket_upgrade_cost(r)
		var ok: bool = GameState.select_rocket(String(r.get("id", "")))
		_populate_rockets()
		_refresh_header()
		_refresh_cart()
		if ok:
			status_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
			if upgrade_cost > 0.0:
				status_label.text = "Roket yükseltildi: %s (-$%.0fM)" % [String(r.get("name", "")), upgrade_cost]
			else:
				status_label.text = "Roket güncellendi: %s" % String(r.get("name", ""))
		else:
			status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			status_label.text = "BÜTÇE YETERSİZ! %s için +$%.0fM gerekiyor (Mevcut: $%.0fM)." % [
				String(r.get("name", "")), upgrade_cost, GameState.budget_m
			]

func _on_close_pressed() -> void:
	visible = false
