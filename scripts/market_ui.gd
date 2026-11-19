extends PanelContainer

const StationFrameDrawer = preload("res://scripts/StationFrameDrawer.gd")

@onready var budget_label: Label = %MarketBudgetLabel
@onready var rocket_option: OptionButton = %RocketOption
@onready var parts_grid: GridContainer = %PartsGrid
@onready var status_label: Label = %MarketStatusLabel

const CATEGORIES: Array[Dictionary] = [
	{ "id": "payload", "label": "BİLİM CİHAZLARI" },
	{ "id": "power", "label": "GÜÇ" },
	{ "id": "comms", "label": "İLETİŞİM" },
	{ "id": "avionics", "label": "AVİYONİK" },
	{ "id": "survival", "label": "KORUMA" }
]

var _selected_category: String = "payload"
var _category_bar: HBoxContainer = null
var _category_buttons: Dictionary = {}
var _purchased_panel: PanelContainer = null
var _purchased_list_label: Label = null

func _ready() -> void:
	visible = false
	StationFrameDrawer.apply_modal_style(self, "blue")
	StationFrameDrawer.style_close_button(get_node_or_null("VBox/Header/CloseBtn") as Button)
	var title_lbl: Label = get_node_or_null("VBox/Header/Title") as Label
	if title_lbl != null:
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.45))
	if budget_label != null:
		budget_label.add_theme_font_size_override("font_size", 11)
	if status_label != null:
		status_label.add_theme_font_size_override("font_size", 10)
	_ensure_category_bar_ui()
	_ensure_purchased_list_ui()
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.telemetry_changed.connect(_refresh_all)

func _ensure_category_bar_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _category_bar != null:
		return

	_category_bar = HBoxContainer.new()
	_category_bar.add_theme_constant_override("separation", 4)

	for cat in CATEGORIES:
		var cid: String = String(cat["id"])
		var btn: Button = Button.new()
		btn.text = String(cat["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_category_selected.bind(cid))
		_category_bar.add_child(btn)
		_category_buttons[cid] = btn

	var scroll_node: Node = get_node_or_null("VBox/Scroll")
	var insert_idx: int = scroll_node.get_index() if scroll_node != null else 2
	vbox.add_child(_category_bar)
	vbox.move_child(_category_bar, insert_idx)

func _ensure_purchased_list_ui() -> void:
	var vbox: Node = get_node_or_null("VBox")
	if vbox == null or _purchased_panel != null:
		return

	_purchased_panel = PanelContainer.new()
	_purchased_panel.add_theme_stylebox_override("panel", StationFrameDrawer.make_card_stylebox(Color(0.38, 0.5, 0.66, 1.0), Color(0.12, 0.16, 0.23, 0.95)))

	_purchased_list_label = Label.new()
	_purchased_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purchased_list_label.add_theme_font_size_override("font_size", 10)
	_purchased_list_label.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	_purchased_list_label.text = "ALINAN EKİPMANLAR: Henüz satın alma yapılmadı."
	_purchased_panel.add_child(_purchased_list_label)

	var status_idx: int = status_label.get_index()
	vbox.add_child(_purchased_panel)
	vbox.move_child(_purchased_panel, status_idx)

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "MARKET":
		open_market()

func open_market() -> void:
	visible = true
	_populate_rockets()
	_refresh_category_buttons()
	_populate_parts()
	_refresh_header()
	_refresh_purchased_list()
	status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	status_label.text = "Kategori seçip parça alın; satın alınanlar kargo bandına düşer."

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
			Color(1.0, 0.88, 0.35) if is_active else Color(0.76, 0.86, 0.96)
		)
		var tab_sb: StyleBoxFlat = StyleBoxFlat.new()
		tab_sb.bg_color = Color(0.18, 0.25, 0.36, 1.0) if is_active else Color(0.08, 0.12, 0.2, 0.95)
		tab_sb.border_width_left = 1
		tab_sb.border_width_top = 2 if is_active else 1
		tab_sb.border_width_right = 1
		tab_sb.border_width_bottom = 2
		tab_sb.border_color = Color(0.95, 0.72, 0.22, 1.0) if is_active else Color(0.25, 0.38, 0.52, 1.0)
		tab_sb.corner_radius_top_left = 2
		tab_sb.corner_radius_top_right = 2
		tab_sb.content_margin_left = 6.0
		tab_sb.content_margin_right = 6.0
		tab_sb.content_margin_top = 3.0
		tab_sb.content_margin_bottom = 3.0
		btn.add_theme_stylebox_override("normal", tab_sb)

func _refresh_all() -> void:
	if not visible:
		return
	_refresh_header()
	_refresh_purchased_list()
	_refresh_category_buttons()
	_populate_parts()

func _refresh_header() -> void:
	if not visible:
		return
	var eff_mass: float = GameState.get_effective_mass_kg()
	var eff_limit: float = GameState.get_effective_mass_limit_kg()
	budget_label.text = "BÜTÇE: $%.0fM | KÜTLE: %.0f/%.0f kg" % [
		GameState.budget_m,
		eff_mass,
		eff_limit
	]
	if GameState.budget_m <= 0.0 or eff_mass > eff_limit:
		budget_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	else:
		budget_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))

func _refresh_purchased_list() -> void:
	if _purchased_list_label == null:
		return
	var summary: Array = GameState.get_purchased_summary()
	if summary.is_empty():
		_purchased_list_label.text = "ALINAN EKİPMANLAR: Henüz satın alma yapılmadı."
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
	_purchased_list_label.text = "ALINAN EKİPMANLAR: " + ", ".join(items)

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
			label += " [KİLİTLİ - Önce 1 alt kademe]"
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
		var installed: bool = GameState.is_part_installed(pid)

		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var card_border: Color = Color(0.45, 0.75, 0.58, 1.0) if installed else (Color(0.78, 0.66, 0.42, 1.0) if bought_count > 0 else Color(0.34, 0.43, 0.56, 1.0))
		var card_bg: Color = Color(0.14, 0.2, 0.23, 0.95) if installed else Color(0.145, 0.185, 0.26, 0.95)
		card.add_theme_stylebox_override("panel", StationFrameDrawer.make_card_stylebox(card_border, card_bg))

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)

		var title: Label = Label.new()
		var badge_txt: String = ""
		if bought_count > 0:
			badge_txt += " [x%d Alındı]" % bought_count
		if installed:
			badge_txt += " [MONTE]"
		title.text = String(p.get("name", "Parça")) + badge_txt
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 11)
		title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.72) if installed else Color(0.68, 0.88, 1.0))
		vbox.add_child(title)

		var stats: Label = Label.new()
		var pwr: float = float(p.get("power_w", 0.0))
		var pwr_str: String = "%+.0fW" % pwr
		if p.has("peak_power_w"):
			pwr_str += " (Tepe %.0fW)" % float(p["peak_power_w"])
		stats.text = "$%dM | %.1fkg | %s | Bilim +%d" % [
			int(p.get("cost_m", 0)),
			float(p.get("mass_kg", 0.0)),
			pwr_str,
			int(p.get("science", 0))
		]
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats.add_theme_font_size_override("font_size", 10)
		stats.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
		vbox.add_child(stats)

		var note: Label = Label.new()
		note.text = String(p.get("notes", ""))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_vertical = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 9)
		note.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
		vbox.add_child(note)

		var btn: Button = Button.new()
		btn.text = "SATIN AL ($%dM)" % int(p.get("cost_m", 0))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 24)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_buy_part_pressed.bind(p))
		vbox.add_child(btn)

		card.add_child(vbox)
		parts_grid.add_child(card)

func _on_buy_part_pressed(part: Dictionary) -> void:
	var cost: int = int(part.get("cost_m", 0))
	var p_name: String = String(part.get("name", "Ekipman"))
	if GameState.buy_part(part):
		status_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6))
		status_label.text = "SATIN ALINDI: %s kargo bandına bırakıldı!" % p_name
		_refresh_header()
		_refresh_purchased_list()
	else:
		var err_msg: String = "HATA — BÜTÇE YETERSİZ! %s için $%dM gerekli (Mevcut bütçen: $%.0fM)!" % [
			p_name, cost, GameState.budget_m
		]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		status_label.text = err_msg
		EventBus.status_message.emit(err_msg, true)

func _on_rocket_selected(idx: int) -> void:
	if idx >= 0 and idx < rocket_option.item_count:
		var r: Dictionary = rocket_option.get_item_metadata(idx)
		var upgrade_cost: float = GameState.get_rocket_upgrade_cost(r)
		var ok: bool = GameState.select_rocket(String(r.get("id", "")))
		_populate_rockets()
		_refresh_header()
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
