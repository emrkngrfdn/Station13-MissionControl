extends PanelContainer

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
		btn.add_theme_font_size_override("font_size", 9)
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
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.15, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.28, 0.48, 0.7, 1.0)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_purchased_panel.add_theme_stylebox_override("panel", style)

	_purchased_list_label = Label.new()
	_purchased_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purchased_list_label.add_theme_font_size_override("font_size", 10)
	_purchased_list_label.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
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
			Color(1.0, 0.85, 0.35) if is_active else Color(0.8, 0.88, 0.95)
		)

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
	var selected_idx: int = 0
	for i in range(rockets.size()):
		var r: Dictionary = rockets[i]
		rocket_option.add_item("%s (%.0f kg)" % [String(r.get("name", "")), float(r.get("max_mass_kg", 0))])
		if String(r.get("id", "")) == selected_id:
			selected_idx = i
	rocket_option.selected = selected_idx

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

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 3)

		var title: Label = Label.new()
		var badge_txt: String = ""
		if bought_count > 0:
			badge_txt += " [x%d Alındı]" % bought_count
		if installed:
			badge_txt += " [MONTE]"
		title.text = String(p.get("name", "Parça")) + badge_txt
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6) if installed else Color(0.45, 0.85, 1.0))
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
		stats.add_theme_font_size_override("font_size", 9)
		vbox.add_child(stats)

		var note: Label = Label.new()
		note.text = String(p.get("notes", ""))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_vertical = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 8)
		note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
		vbox.add_child(note)

		var btn: Button = Button.new()
		btn.text = "SATIN AL ($%dM)" % int(p.get("cost_m", 0))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 24)
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
	var rockets: Array = GameState.parts_data.get("rockets", [])
	if idx >= 0 and idx < rockets.size():
		GameState.select_rocket(String(rockets[idx].get("id", "")))
		_refresh_header()
		status_label.text = "Roket güncellendi: %s" % String(rockets[idx].get("name", ""))

func _on_close_pressed() -> void:
	visible = false
