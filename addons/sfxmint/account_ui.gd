@tool
extends Node
const UITheme = preload("ui_theme.gd")

signal connect_requested(secret: String, remember: bool)
signal connection_canceled
signal refresh_requested
signal disconnect_requested
signal forget_requested
signal save_requested(directory: String, format: String)
signal website_requested(url: String)
signal retry_save_requested

var connection: Window
var settings: Window
var key_input: LineEdit
var remember: CheckBox
var connect_button: Button
var connect_message: Label
var paste_button: Button
var connecting := false
var account_line: Label
var key_line: Label
var storage_line: Label
var allowance: Label
var settings_message: Label
var folder: LineEdit
var format: OptionButton
var forget_button: Button
var retry_save: Button
var replace_button: Button
var disconnect_button: Button
var host: Control

func label(parent: Node, value: String) -> Label:
	var node := Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func row(parent: Node) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", 12)
	parent.add_child(node)
	return node

func button(parent: Node, value: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func window(title: String, dimensions: Vector2i) -> Window:
	var node := Window.new()
	node.title = title
	node.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	node.min_size = Vector2i(Vector2(dimensions) * host.ui_scale)
	node.size = node.min_size
	node.theme = host.theme
	node.transient = true
	node.exclusive = true
	node.visible = false
	host.add_child(node)
	return node

func content(parent: Window) -> VBoxContainer:
	var backdrop := Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel", UITheme.box(UITheme.background(host), Color.TRANSPARENT, host.ui_scale, 0, 0, 0))
	parent.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, int(20 * host.ui_scale))
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(10 * host.ui_scale))
	margin.add_child(box)
	return box

func setup(parent: Control) -> void:
	host = parent
	connection = window("Connect to SFXMint", Vector2i(580, 370))
	connection.close_requested.connect(cancel_connection)
	var box := content(connection)
	label(box, "Use your SFXMint API key to generate audio in Godot.")
	var key_header := row(box)
	label(key_header, "API key")
	button(key_header, "Create API key", func(): website_requested.emit("https://sfxmint.com/dashboard/keys"))
	var key_row := row(box)
	key_input = LineEdit.new()
	key_input.secret = true
	key_input.placeholder_text = "Paste your SFXMint API key"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.text_changed.connect(func(_value): connect_button.disabled = connecting or key_input.text.strip_edges().is_empty())
	key_input.text_submitted.connect(func(_value): submit())
	key_row.add_child(key_input)
	var reveal := button(key_row, "Show", func(): pass)
	reveal.toggle_mode = true
	reveal.toggled.connect(func(value): key_input.secret = not value; reveal.text = "Hide" if value else "Show")
	paste_button = button(key_row, "Paste", func(): key_input.text = DisplayServer.clipboard_get().strip_edges(); connect_button.disabled = key_input.text.is_empty())
	remember = CheckBox.new()
	remember.text = "Remember on this device"
	remember.button_pressed = true
	box.add_child(remember)
	label(box, "Saved in your system's secure storage. Never included in your project or game export.")
	connect_message = label(box, "")
	connect_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(HSeparator.new())
	label(box, "Library search and downloads work without a key.")
	var actions := row(box)
	label(actions, "")
	button(actions, "Cancel", cancel_connection)
	connect_button = button(actions, "Connect", submit)
	UITheme.primary(connect_button)
	connect_button.disabled = true
	connect_button.custom_minimum_size.x = 100
	settings = window("SFXMint settings", Vector2i(620, 580))
	settings.close_requested.connect(settings.hide)
	box = content(settings)
	var heading := row(box)
	label(heading, "Account").add_theme_font_size_override("font_size", int(16 * host.ui_scale))
	label(heading, "This device")
	account_line = label(box, "Not connected")
	var identity := row(box)
	key_line = label(identity, "API key: not connected")
	replace_button = button(identity, "Replace key", func(): settings.hide(); host._open_connection())
	storage_line = label(box, "Not saved — this session only")
	retry_save = button(box, "Retry saving securely", func(): retry_save_requested.emit())
	retry_save.hide()
	var balance := row(box)
	allowance = label(balance, "Connect to check your allowance.")
	button(balance, "Refresh", func(): refresh_requested.emit())
	button(balance, "Get credits", func(): website_requested.emit("https://sfxmint.com/pricing?utm_source=godot&utm_medium=plugin"))
	var account_actions := row(box)
	disconnect_button = button(account_actions, "Disconnect", func(): disconnect_requested.emit())
	disconnect_button.tooltip_text = "Disconnect for this editor session. The saved key remains on this device."
	forget_button = button(account_actions, "Remove saved key", func(): forget_requested.emit())
	forget_button.tooltip_text = "Remove the device credential. An active connection continues for this session."
	box.add_child(HSeparator.new())
	heading = row(box)
	label(heading, "Project defaults").add_theme_font_size_override("font_size", int(16 * host.ui_scale))
	label(heading, "Current Godot project")
	label(box, "Import folder")
	var folder_row := row(box)
	folder = LineEdit.new()
	folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_row.add_child(folder)
	button(folder_row, "Browse", pick_folder)
	var format_row := row(box)
	label(format_row, "Preferred format")
	format = OptionButton.new()
	format.add_item("WAV")
	format.add_item("OGG")
	format_row.add_child(format)
	label(box, "Available formats depend on the selected file. Defaults affect future imports; existing files stay where they are.")
	settings_message = label(box, "")
	settings_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions = row(box)
	label(actions, "")
	button(actions, "Cancel", settings.hide)
	UITheme.primary(button(actions, "Save project settings", func(): save_requested.emit(folder.text.strip_edges(), "ogg" if format.selected == 1 else "wav")))

func open_connection() -> void:
	settings.hide()
	key_input.clear()
	key_input.secret = true
	connect_message.text = ""
	set_connecting(false)
	connection.popup_centered()
	key_input.grab_focus.call_deferred()

func submit() -> void:
	if connect_button.disabled: return
	connect_requested.emit(key_input.text.strip_edges(), remember.button_pressed)

func cancel_connection() -> void:
	connection_canceled.emit()
	key_input.clear()
	connection.hide()
	set_connecting(false)

func set_connecting(value: bool) -> void:
	connecting = value
	paste_button.disabled = value
	connect_button.text = "Connecting…" if value else "Connect"
	connect_button.disabled = value or key_input.text.strip_edges().is_empty()
	key_input.editable = not value
	remember.disabled = value

func show_settings(preferences: Dictionary) -> void:
	folder.text = str(preferences.get("directory", "res://audio/sfxmint/"))
	format.select(1 if preferences.get("format", "wav") == "ogg" else 0)
	settings_message.text = ""
	settings.popup_centered()

func pick_folder() -> void:
	var picker := EditorFileDialog.new()
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	picker.access = EditorFileDialog.ACCESS_RESOURCES
	picker.current_dir = folder.text if DirAccess.dir_exists_absolute(folder.text) else "res://"
	settings.add_child(picker)
	picker.dir_selected.connect(func(path): folder.text = path.trim_suffix("/") + "/"; picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.6)

func shutdown() -> void:
	key_input.clear()
	connection.queue_free()
	settings.queue_free()
