extends PanelContainer

@onready var budget_label: Label = %MarketBudgetLabel
@onready var rocket_option: OptionButton = %RocketOption
@onready var parts_grid: GridContainer = %PartsGrid
@onready var status_label: Label = %MarketStatusLabel

func _ready() -> void:
	visible = false
	EventBus.terminal_opened.connect(_on_terminal_opened)
	EventBus.telemetry_changed.connect(_refresh_header)

func _on_terminal_opened(terminal_name: String) -> void:
	if terminal_name == "MARKET":
		open_market()

func open_market() -> void:
	visible = true
	_populate_rockets()
	_populate_parts()
	_refresh_header()
	status_label.text = "Parça seçin; satın alınanlar kargo bandına düşer."

func _refresh_header() -> void:
	if not visible:
		return
	budget_label.text = "BÜTÇE: $%.0fM | ROKET LİMİTİ: %.0f kg" % [
		GameState.budget_m,
		float(GameState.selected_rocket.get("max_mass_kg", 0.0))
	]

func _populate_rockets() -> void:
	rocket_option.clear()
	var rockets: Array = GameState.parts_data.get("rockets", [])
	var selected_id: String = GameState.selected_rocket.get("id", "")
	var selected_idx := 0
	for i in range(rockets.size()):
		var r: Dictionary = rockets[i]
		rocket_option.add_item("%s (%.0f kg)" % [r.get("name", ""), float(r.get("max_mass_kg", 0))])
		if r.get("id", "") == selected_id:
			selected_idx = i
	rocket_option.selected = selected_idx

func _populate_parts() -> void:
	for child in parts_grid.get_children():
		child.queue_free()

	var parts: Array = GameState.get_available_parts_for_mission()
	for p in parts:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)

		var title := Label.new()
		title.text = p.get("name", "Parça")
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
		vbox.add_child(title)

		var stats := Label.new()
		var pwr: float = float(p.get("power_w", 0.0))
		var pwr_str := "%+.0fW" % pwr
		if p.has("peak_power_w"):
			pwr_str += " (Tepe %.0fW)" % float(p["peak_power_w"])
		stats.text = "$%dM | %.1fkg | %s | Bilim +%d" % [
			int(p.get("cost_m", 0)),
			float(p.get("mass_kg", 0.0)),
			pwr_str,
			int(p.get("science", 0))
		]
		stats.add_theme_font_size_override("font_size", 9)
		vbox.add_child(stats)

		var note := Label.new()
		note.text = p.get("notes", "")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 8)
		note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
		vbox.add_child(note)

		var btn := Button.new()
		btn.text = "SATIN AL ($%dM)" % int(p.get("cost_m", 0))
		btn.pressed.connect(_on_buy_part_pressed.bind(p))
		vbox.add_child(btn)

		card.add_child(vbox)
		parts_grid.add_child(card)

func _on_buy_part_pressed(part: Dictionary) -> void:
	if GameState.buy_part(part):
		status_label.text = "SATIN ALINDI: %s kargo bandına bırakıldı!" % part.get("name", "")
		_refresh_header()
	else:
		status_label.text = "YETERSİZ BÜTÇE! ($%dM gerekli)" % int(part.get("cost_m", 0))

func _on_rocket_selected(idx: int) -> void:
	var rockets: Array = GameState.parts_data.get("rockets", [])
	if idx >= 0 and idx < rockets.size():
		GameState.select_rocket(rockets[idx].get("id", ""))
		_refresh_header()
		status_label.text = "Roket güncellendi: %s" % rockets[idx].get("name", "")

func _on_close_pressed() -> void:
	visible = false
