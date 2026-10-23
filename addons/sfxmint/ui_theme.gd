@tool
extends RefCounted
# Plugin tokens. Editor chrome and its preferences are never changed.
const ACCENT = Color("#00d4b0")
const ACCENT_LIGHT = Color("#087d68")
const ON_ACCENT = Color("#092e29")
const DARK_BG = Color("#1b2226")
const DARK_SURFACE = Color("#171e22")
const DARK_FIELD = Color("#20282d")
const DARK_BORDER = Color("#354047")
const DARK_TEXT = Color("#e6eaec")
const DARK_MUTED = Color("#a5afb4")

static func dark(control: Control) -> bool:
	return control.get_theme_color("font_color", "Label").get_luminance() > 0.5

static func accent(control: Control) -> Color:
	return ACCENT if dark(control) else ACCENT_LIGHT

static func background(control: Control) -> Color:
	return DARK_BG if dark(control) else Color("#edf1f2")

static func surface(control: Control) -> Color:
	return DARK_SURFACE if dark(control) else Color("#ffffff")

static func border(control: Control) -> Color:
	return DARK_BORDER if dark(control) else Color("#cbd4d8")

static func muted(control: Control) -> Color:
	return DARK_MUTED if dark(control) else Color("#59666c")

static func box(color: Color, edge: Color, scale: float, radius := 5.0, x := 10.0, y := 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(int(scale) if edge.a > 0 else 0)
	style.set_corner_radius_all(int(radius * scale))
	style.content_margin_left = x * scale
	style.content_margin_right = x * scale
	style.content_margin_top = y * scale
	style.content_margin_bottom = y * scale
	return style

static func apply(control: Control, scale: float) -> void:
	var is_dark := dark(control)
	var theme := Theme.new()
	if Engine.is_editor_hint():
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme: theme.merge_with(editor_theme)
	var fg := DARK_TEXT if is_dark else Color("#243138")
	var field := DARK_FIELD if is_dark else Color("#f8fafb")
	var edge := DARK_BORDER if is_dark else Color("#cbd4d8")
	var brand := ACCENT if is_dark else ACCENT_LIGHT
	theme.default_font_size = int(13 * scale)
	for type in ["Label", "Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton", "LineEdit", "TextEdit", "PopupMenu", "TabBar"]:
		theme.set_font_size("font_size", type, int(13 * scale))
		theme.set_color("font_color", type, fg)
		theme.set_color("font_hover_color", type, fg)
		theme.set_color("font_pressed_color", type, fg)
		theme.set_color("font_disabled_color", type, Color(fg, 0.4))
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box(field, edge, scale))
		theme.set_stylebox("hover", type, box(field.lightened(0.06), edge.lightened(0.12), scale))
		theme.set_stylebox("pressed", type, box(field.darkened(0.08), brand, scale))
		theme.set_stylebox("disabled", type, box(Color(field, 0.5), Color(edge, 0.4), scale))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, Color(brand, 0.8), scale))
		theme.set_constant("h_separation", type, int(6 * scale))
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, box(surface(control), edge, scale, 5, 10, 8))
		theme.set_stylebox("read_only", type, box(surface(control), edge, scale, 5, 10, 8))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, brand, scale, 5))
		theme.set_color("font_placeholder_color", type, Color(fg, 0.45))
		theme.set_color("caret_color", type, brand)
	for type in ["CheckButton", "CheckBox"]:
		for state in ["normal", "pressed", "disabled", "hover", "hover_pressed"]:
			theme.set_stylebox(state, type, box(Color.TRANSPARENT, Color.TRANSPARENT, scale, 0, 2, 3))
		theme.set_constant("h_separation", type, int(7 * scale))
	# Keep native toggle/radio geometry while matching the plugin accent.
	for type in ["CheckButton", "CheckBox"]:
		for name in ["checked", "checked_disabled", "radio_checked", "radio_checked_disabled"]:
			if theme.has_icon(name, type): theme.set_icon(name, type, recolor_accent(theme.get_icon(name, type), brand))
	theme.set_color("accent_color", "Editor", brand)
	theme.set_color("font_focus_color", "Button", brand)
	theme.set_stylebox("panel", "PopupPanel", box(surface(control), edge, scale, 6, 14, 14))
	for type in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Color(edge, 0.8)
		line.thickness = maxi(1, int(scale))
		line.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, line)
	for type in ["HBoxContainer", "VBoxContainer", "HFlowContainer"]:
		theme.set_constant("separation", type, int(6 * scale))
		theme.set_constant("h_separation", type, int(6 * scale))
		theme.set_constant("v_separation", type, int(6 * scale))
	control.theme = theme

static func primary(button: Button) -> void:
	var scale := float(button.get_theme_font_size("font_size", "Button")) / 13.0
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, box(ACCENT.lightened(0.08) if state == "hover" else ACCENT, ACCENT, scale))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		button.add_theme_color_override(state, ON_ACCENT)

static func quiet(button: Button, scale: float) -> void:
	button.flat = true
	button.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, Color.TRANSPARENT, scale, 5, 6, 5))
	button.add_theme_stylebox_override("hover", box(Color(accent(button), 0.08), Color.TRANSPARENT, scale, 5, 6, 5))
	button.add_theme_stylebox_override("pressed", box(Color(accent(button), 0.12), Color.TRANSPARENT, scale, 5, 6, 5))

static func navigation(button: Button, scale: float) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := box(Color.TRANSPARENT, Color.TRANSPARENT, scale, 0, 15, 7)
		if state in ["pressed", "hover_pressed"]:
			style.border_color = accent(button)
			style.border_width_bottom = int(2 * scale)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_pressed_color", accent(button))
	button.add_theme_color_override("font_hover_pressed_color", accent(button))

static func segment(button: Button, scale: float) -> void:
	button.custom_minimum_size.x = 76 * scale
	button.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, Color.TRANSPARENT, scale, 16, 12, 6))
	button.add_theme_stylebox_override("pressed", box(ACCENT, Color.TRANSPARENT, scale, 16, 12, 6))
	button.add_theme_stylebox_override("hover_pressed", box(ACCENT.lightened(0.07), Color.TRANSPARENT, scale, 16, 12, 6))
	button.add_theme_color_override("font_pressed_color", ON_ACCENT)
	button.add_theme_color_override("font_hover_pressed_color", ON_ACCENT)

static func round_button(button: Button, scale: float) -> void:
	button.flat = false
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, box(border(button).lightened(0.06) if state == "hover" else border(button), Color.TRANSPARENT, scale, 20, 4, 4))
	button.custom_minimum_size = Vector2(30, 30) * scale

static func row_style(control: Control, scale: float, active := false) -> StyleBoxFlat:
	var style := box(Color(accent(control), 0.13) if active else Color.TRANSPARENT, border(control), scale, 0, 10, 4)
	style.set_border_width_all(0)
	style.border_width_bottom = maxi(1, int(scale))
	if active:
		style.border_width_left = int(3 * scale)
		style.border_color = accent(control)
	return style

static func selected(control: Control) -> StyleBoxFlat:
	return row_style(control, float(control.get_theme_font_size("font_size", "Label")) / 13.0, true)

static func icon(control: Control, name: String) -> Texture2D:
	return control.get_theme_icon(name, "EditorIcons") if control.has_theme_icon(name, "EditorIcons") else null

static func recolor_accent(source: Texture2D, color: Color) -> Texture2D:
	var pixels := source.get_image()
	if not pixels: return source
	for y in range(pixels.get_height()):
		for x in range(pixels.get_width()):
			var pixel := pixels.get_pixel(x, y)
			if pixel.b > pixel.r * 1.15 and pixel.b > pixel.g * 1.08:
				pixels.set_pixel(x, y, Color(color, pixel.a))
	return ImageTexture.create_from_image(pixels)
