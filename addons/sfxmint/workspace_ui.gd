@tool
extends RefCounted
const UITheme = preload("ui_theme.gd")

static func compact_label(p, parent: Node, text: String) -> Label:
	var node: Label = p._label(parent, text)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node

static func icon_button(p, parent: Node, icon_name: String, fallback: String, action: Callable) -> Button:
	var node: Button = p._button(parent, fallback, action)
	var texture := UITheme.icon(p, icon_name)
	if texture:
		node.text = ""
		node.icon = texture
	node.tooltip_text = fallback
	node.custom_minimum_size = Vector2(26, 26) * p.ui_scale
	node.add_theme_constant_override("icon_max_width", int(16 * p.ui_scale))
	UITheme.quiet(node, p.ui_scale)
	return node

static func build(p) -> void:
	p.add_theme_constant_override("separation", 0)
	var surface := PanelContainer.new()
	surface.add_theme_stylebox_override("panel", UITheme.box(UITheme.background(p), UITheme.border(p), p.ui_scale, 5, 0, 0))
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(surface)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, int(10 * p.ui_scale))
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(6 * p.ui_scale))
	margin.add_child(body)
	var header: HBoxContainer = p._row(body)
	var logo := TextureRect.new()
	logo.texture = load("res://addons/sfxmint/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(24, 24) * p.ui_scale
	header.add_child(logo)
	var brand := compact_label(p, header, "SFXMint")
	brand.add_theme_font_size_override("font_size", int(15 * p.ui_scale))
	var divider := VSeparator.new()
	header.add_child(divider)
	var navigation := ButtonGroup.new()
	for i in range(3):
		var nav: Button = p._button(header, ["Library", "Studio", "In project"][i], func(): p.tabs.current_tab = i)
		nav.toggle_mode = true
		nav.button_group = navigation
		UITheme.navigation(nav, p.ui_scale)
		p.nav_buttons.append(nav)
	p.nav_buttons[0].button_pressed = true
	p._label(header, "")
	if p.api.origin != p.API.DEFAULT_ORIGIN:
		compact_label(p, header, "Demo mode")
	p.account_button = p._button(header, "Connect account", p._account_menu)
	UITheme.quiet(p.account_button, p.ui_scale)
	p.account_label = Label.new()
	p.account_label.hide()
	header.add_child(p.account_label)
	icon_button(p, header, "Tools", "Settings", p._open_settings)
	body.add_child(HSeparator.new())
	p.tabs = TabContainer.new()
	p.tabs.tabs_visible = false
	p.tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	p.tabs.tab_changed.connect(func(index):
		p.nav_buttons[index].button_pressed = true
		p._stop_preview()
		p.selected_sound = {}
		p._update_player()
		p._responsive.call_deferred()
		if index == 1: p._render_tasks()
		elif index == 2: p._render_project())
	body.add_child(p.tabs)
	var library := VBoxContainer.new()
	library.name = "Library"
	p.tabs.add_child(library)
	var search: HBoxContainer = p._row(library)
	p.query = LineEdit.new()
	p.query.placeholder_text = "Describe a sound for your game…"
	p.query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.query.text_submitted.connect(func(_value): p._search())
	search.add_child(p.query)
	p._button(search, "Search", p._search)
	p._button(search, "Generate this", p._from_search)
	var filters := HFlowContainer.new()
	library.add_child(filters)
	p.category = OptionButton.new()
	p.category.add_item("All categories")
	for name in ["ui", "retro-game", "impact", "footsteps", "ambience", "animal", "magic-scifi", "horror", "door", "water", "feedback"]: p.category.add_item(name)
	filters.add_child(p.category)
	compact_label(p, filters, "Max seconds (0 = any)")
	p.max_seconds = SpinBox.new()
	p.max_seconds.max_value = 60
	p.max_seconds.step = 0.1
	filters.add_child(p.max_seconds)
	p._label(library, "Free library · No key needed · AI-generated audio")
	p.results = p._scroll(library)
	p._label(p.results, "Describe a sound, or try one of these:")
	var examples := HFlowContainer.new()
	p.results.add_child(examples)
	for example in ["Coin pickup", "Footsteps", "Sword hit", "UI click"]:
		p._button(examples, example, func(): p.query.text = example; p._search())
	var studio := VBoxContainer.new()
	studio.name = "Studio"
	studio.add_theme_constant_override("separation", int(8 * p.ui_scale))
	p.tabs.add_child(studio)
	var selection := HBoxContainer.new()
	studio.add_child(selection)
	p.asset_choice = OptionButton.new()
	p.asset_choice.custom_minimum_size.x = 140 * p.ui_scale
	p.asset_choice.clip_text = true
	p.asset_choice.item_selected.connect(p._choose_asset)
	selection.add_child(p.asset_choice)
	icon_button(p, selection, "Add", "New sound", p._new_asset)
	p.round_choice = OptionButton.new()
	p.round_choice.item_selected.connect(p._choose_round)
	selection.add_child(p.round_choice)
	var segments := PanelContainer.new()
	segments.add_theme_stylebox_override("panel", UITheme.box(Color.TRANSPARENT, UITheme.border(p), p.ui_scale, 16, 0, 0))
	selection.add_child(segments)
	var types := HBoxContainer.new()
	types.add_theme_constant_override("separation", 0)
	segments.add_child(types)
	var type_group := ButtonGroup.new()
	for kind in ["sound", "ambience", "music"]:
		var type_button: Button = p._button(types, p.Sound.kind_label(kind), func(): p._set_kind(kind))
		type_button.toggle_mode = true
		type_button.button_group = type_group
		type_button.button_pressed = kind == "sound"
		UITheme.segment(type_button, p.ui_scale)
		p.type_buttons[kind] = type_button
	p._label(selection, "")
	icon_button(p, selection, "History", "Recent account generations", p._recent_orders)
	p.composer = VBoxContainer.new()
	studio.add_child(p.composer)
	p.prompt = TextEdit.new()
	p.prompt.placeholder_text = "Describe the sound and its moment in your game…"
	p.prompt.tab_input_mode = false
	p.prompt.custom_minimum_size.y = 54 * p.ui_scale
	p.prompt.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and event.is_command_or_control_pressed():
			p.prompt.accept_event()
			p._generate())
	p.prompt.text_changed.connect(p._draft_changed)
	p.composer.add_child(p.prompt)
	p.source_row = p._row(p.composer)
	p.source_label = p._label(p.source_row, "")
	p._button(p.source_row, "Clear source", p._clear_source)
	p.source_row.hide()
	var options := HFlowContainer.new()
	p.composer.add_child(options)
	p.detail_row = HBoxContainer.new()
	options.add_child(p.detail_row)
	p.details_toggle = CheckButton.new()
	p.details_toggle.text = "Details"
	p.details_toggle.button_pressed = true
	p.details_toggle.toggled.connect(func(_value): p._details_changed())
	p.detail_row.add_child(p.details_toggle)
	p.detail_chips = HBoxContainer.new()
	p.detail_row.add_child(p.detail_chips)
	UITheme.quiet(p._button(p.detail_row, "Add", p._add_detail), p.ui_scale)
	p.suggest_button = icon_button(p, p.detail_row, "Reload", "Suggest details", p._suggest_details)
	for child in p.detail_row.get_children(): child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.detail_row.hide()
	var settings := HBoxContainer.new()
	options.add_child(settings)
	p.start_button = p._button(settings, "Start from", p._start_from)
	p.duration = OptionButton.new()
	p.duration.tooltip_text = "Length"
	settings.add_child(p.duration)
	p.fixed_length = compact_label(p, settings, "30 s original")
	p.fixed_length.hide()
	p.variations = OptionButton.new()
	p.variations.tooltip_text = "Number of candidates"
	settings.add_child(p.variations)
	p._set_capabilities({"durations": [0.2, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 7, 8, 9, 10], "variations": [1, 2, 4]})
	p.enhance = CheckButton.new()
	p.enhance.text = "AI Enhance"
	p.enhance.button_pressed = true
	p.enhance.toggled.connect(func(_value): p._details_changed(); p._draft_changed())
	settings.add_child(p.enhance)
	p.generate_button = p._button(settings, "Generate", p._generate)
	p.duration.item_selected.connect(func(_value): p._draft_changed())
	p.variations.item_selected.connect(func(_value): p._draft_changed())
	p.allowance = p._label(studio, "Connect an account to generate. Library sounds stay free.")
	p.allowance.add_theme_font_size_override("font_size", int(11 * p.ui_scale))
	p.allowance.add_theme_color_override("font_color", UITheme.muted(p))
	p.plans_row = p._row(studio)
	p.plans_row.hide()
	p._label(p.plans_row, "Need more allowance? Your draft is kept.")
	p._button(p.plans_row, "View plans", func(): p._open_website("https://sfxmint.com/pricing?utm_source=godot&utm_medium=plugin"))
	p._button(p.plans_row, "Refresh", p._refresh_account)
	p.take_layout = HBoxContainer.new()
	p.take_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.take_layout.add_theme_constant_override("separation", int(10 * p.ui_scale))
	studio.add_child(p.take_layout)
	var candidate_frame := PanelContainer.new()
	candidate_frame.add_theme_stylebox_override("panel", UITheme.box(UITheme.surface(p), UITheme.border(p), p.ui_scale, 5, 0, 0))
	candidate_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidate_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.take_layout.add_child(candidate_frame)
	var candidate_box := VBoxContainer.new()
	candidate_box.add_theme_constant_override("separation", 0)
	candidate_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidate_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	candidate_frame.add_child(candidate_box)
	var result_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: result_margin.add_theme_constant_override("margin_" + side, int(8 * p.ui_scale))
	candidate_box.add_child(result_margin)
	var result_heading: HBoxContainer = p._row(result_margin)
	p.result_label = p._label(result_heading, "No tracks yet")
	p.result_label.add_theme_font_size_override("font_size", int(16 * p.ui_scale))
	p.only_starred = CheckBox.new()
	p.only_starred.text = "Starred"
	p.only_starred.toggled.connect(func(_value): p._render_takes())
	result_heading.add_child(p.only_starred)
	var column_panel := PanelContainer.new()
	column_panel.add_theme_stylebox_override("panel", UITheme.row_style(p, p.ui_scale))
	candidate_box.add_child(column_panel)
	var columns: HBoxContainer = p._row(column_panel)
	for spec in [["#", 20], ["Track", 72], ["Listen", 30]]:
		var title := compact_label(p, columns, spec[0])
		title.custom_minimum_size.x = float(spec[1]) * p.ui_scale
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(fill)
	var length := compact_label(p, columns, "Length")
	length.custom_minimum_size.x = 43 * p.ui_scale
	var star := compact_label(p, columns, "Star")
	star.custom_minimum_size.x = 28 * p.ui_scale
	var tail := Control.new()
	tail.custom_minimum_size.x = 24 * p.ui_scale
	columns.add_child(tail)
	p.generation_rows = p._scroll(candidate_box)
	p.generation_rows.add_theme_constant_override("separation", 0)
	p.generation_rows.get_parent().custom_minimum_size.y = 168 * p.ui_scale
	p.inspector_frame = PanelContainer.new()
	p.inspector_frame.add_theme_stylebox_override("panel", UITheme.box(UITheme.surface(p), UITheme.border(p), p.ui_scale, 5, 12, 12))
	p.take_layout.add_child(p.inspector_frame)
	p.inspector = VBoxContainer.new()
	p.inspector.custom_minimum_size.x = 190 * p.ui_scale
	p.inspector.add_theme_constant_override("separation", int(4 * p.ui_scale))
	p.inspector_frame.add_child(p.inspector)
	p.inspector_title = p._label(p.inspector, "Select a take")
	p.inspector_title.add_theme_font_size_override("font_size", int(19 * p.ui_scale))
	p.inspector_title.custom_minimum_size.x = 190 * p.ui_scale
	p._label(p.inspector, "Version to preview & import").custom_minimum_size.x = 190 * p.ui_scale
	p.variant_rows = VBoxContainer.new()
	p.inspector.add_child(p.variant_rows)
	p.inspector.add_child(HSeparator.new())
	var format_row: HBoxContainer = p._row(p.inspector)
	compact_label(p, format_row, "Format")
	p.format_choice = OptionButton.new()
	p.format_choice.item_selected.connect(p._choose_format)
	format_row.add_child(p.format_choice)
	p.metadata_label = p._label(p.inspector, "")
	p.metadata_label.custom_minimum_size.x = 190 * p.ui_scale
	p.inspector_popup = PopupPanel.new()
	p.add_child(p.inspector_popup)
	var project := VBoxContainer.new()
	project.name = "In project"
	p.tabs.add_child(project)
	var project_header: HBoxContainer = p._row(project)
	p._label(project_header, "Local audio stays playable without this plugin or a connection.")
	p._button(project_header, "Refresh", p._render_project)
	p.project_rows = p._scroll(project)
	body.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(6 * p.ui_scale))
	body.add_child(footer)
	p.play_button = icon_button(p, footer, "Play", "Play selected audio", p._toggle_player)
	UITheme.round_button(p.play_button, p.ui_scale)
	var playing := VBoxContainer.new()
	playing.custom_minimum_size.x = 145 * p.ui_scale
	footer.add_child(playing)
	p.player_label = p._label(playing, "Select audio")
	p.player_label.clip_text = true
	p.player_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.player_time = p._label(playing, "")
	p.seek = HSlider.new()
	p.seek.custom_minimum_size.x = 48 * p.ui_scale
	p.seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.seek.step = 0.01
	p.seek.editable = false
	p.seek.drag_started.connect(func(): p.seek_dragging = true)
	p.seek.drag_ended.connect(func(changed):
		p.seek_dragging = false
		if changed and p.player.stream: p.player.seek(p.seek.value))
	footer.add_child(p.seek)
	p.repeat_playback = CheckButton.new()
	p.repeat_playback.text = "Repeat"
	p.repeat_playback.tooltip_text = "Repeat playback of this file. This does not change the imported audio."
	footer.add_child(p.repeat_playback)
	p.volume = HSlider.new()
	var volume: HSlider = p.volume
	volume.custom_minimum_size.x = 45 * p.ui_scale
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = float(p.storage.settings.get("volume", 0.7))
	p.player.volume_linear = volume.value
	volume.tooltip_text = "Preview volume"
	volume.value_changed.connect(func(value): p.player.volume_linear = value; p.storage.settings.volume = value; p.storage.save_settings())
	footer.add_child(volume)
	p.directory = LineEdit.new()
	p.directory.text = p.storage.settings.directory
	p.directory.editable = false
	p.directory.custom_minimum_size.x = 90 * p.ui_scale
	p.directory.tooltip_text = "Import folder"
	footer.add_child(p.directory)
	icon_button(p, footer, "Folder", "Choose import folder", p._choose_directory)
	p.inspector_toggle = icon_button(p, footer, "GuiTabMenuHl", "Version & format", p._open_inspector)
	p.inspector_toggle.hide()
	p.import_button = p._button(footer, "Import", p._import_selected)
	p.import_button.disabled = true
	p.import_button.icon = UITheme.icon(p, "Import")
	p.import_button.add_theme_constant_override("icon_max_width", int(16 * p.ui_scale))
	UITheme.primary(p.import_button)
	for child in footer.get_children(): child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.status = p._label(body, "Ready. Select audio to audition or import.")
	p.status.max_lines_visible = 1
	p.status.add_theme_font_size_override("font_size", int(11 * p.ui_scale))
	p.status.add_theme_color_override("font_color", Color(p.get_theme_color("font_color", "Label"), 0.72))
