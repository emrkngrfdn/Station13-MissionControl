class_name StationFrameDrawer
extends Node

## İstasyon arka planıyla uyumlu, yumuşak (soft) mavi ve yeşil piksel-art
## panel ve buton stilleri üreten yardımcı sınıf.

static func make_modal_stylebox(bg_col: Color = Color(0.08, 0.17, 0.30, 0.96), border_col: Color = Color(0.36, 0.68, 0.94, 1.0)) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_width_left = 2
	sb.border_width_top = 3
	sb.border_width_right = 2
	sb.border_width_bottom = 4
	sb.border_color = border_col
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_detail = 2
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.shadow_color = Color(0.02, 0.05, 0.1, 0.55)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(2, 2)
	sb.anti_aliasing = false
	return sb

static func apply_modal_style(modal: PanelContainer, theme_mode: String = "blue") -> void:
	if modal == null:
		return
	match theme_mode:
		"green":
			modal.add_theme_stylebox_override("panel", make_modal_stylebox(
				Color(0.07, 0.21, 0.22, 0.96),
				Color(0.32, 0.78, 0.64, 1.0)
			))
		"red":
			modal.add_theme_stylebox_override("panel", make_modal_stylebox(
				Color(0.22, 0.10, 0.14, 0.96),
				Color(0.88, 0.42, 0.44, 1.0)
			))
		_:
			modal.add_theme_stylebox_override("panel", make_modal_stylebox(
				Color(0.08, 0.17, 0.30, 0.96),
				Color(0.36, 0.68, 0.94, 1.0)
			))

static func style_close_button(btn: Button) -> void:
	if btn == null:
		return
	var sb_n: StyleBoxFlat = StyleBoxFlat.new()
	sb_n.bg_color = Color(0.34, 0.14, 0.18, 0.96)
	sb_n.border_width_left = 2
	sb_n.border_width_top = 2
	sb_n.border_width_right = 2
	sb_n.border_width_bottom = 3
	sb_n.border_color = Color(0.86, 0.40, 0.44, 1.0)
	sb_n.corner_radius_top_left = 4
	sb_n.corner_radius_top_right = 4
	sb_n.corner_radius_bottom_left = 4
	sb_n.corner_radius_bottom_right = 4
	sb_n.corner_detail = 1
	sb_n.content_margin_left = 9.0
	sb_n.content_margin_right = 9.0
	sb_n.content_margin_top = 3.0
	sb_n.content_margin_bottom = 4.0
	sb_n.anti_aliasing = false

	var sb_h: StyleBoxFlat = sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.46, 0.18, 0.22, 1.0)
	sb_h.border_color = Color(0.98, 0.56, 0.56, 1.0)

	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_n)
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_font_size_override("font_size", 10)
	if btn.text == "X":
		btn.text = "X KAPAT"

static func make_card_stylebox(border_col: Color = Color(0.36, 0.62, 0.86, 1.0), bg_col: Color = Color(0.11, 0.21, 0.35, 0.95)) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.border_color = border_col
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.corner_detail = 2
	sb.content_margin_left = 9.0
	sb.content_margin_right = 9.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	sb.anti_aliasing = false
	return sb

static func make_option_button_stylebox(normal: bool = true) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.24, 0.40, 0.96) if normal else Color(0.17, 0.33, 0.53, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 3
	sb.border_color = Color(0.38, 0.68, 0.94, 1.0) if normal else Color(0.58, 0.84, 1.0, 1.0)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.corner_detail = 2
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.anti_aliasing = false
	return sb
