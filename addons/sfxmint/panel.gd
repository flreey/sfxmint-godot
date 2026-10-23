@tool
extends VBoxContainer

const API = preload("api.gd")
const Storage = preload("storage.gd")
const Credentials = preload("credentials.gd")
const Text = preload("strings.gd")
const Sound = preload("sound.gd")
const UI = preload("workspace_ui.gd")
const UITheme = preload("ui_theme.gd")
const AccountUI = preload("account_ui.gd")
const Waveform = preload("waveform.gd")
const SourceUI = preload("source_ui.gd")
const SOUND_ACTIONS = {"crisper": "Crisper", "heavier": "Heavier", "shorter_tail": "Shorter ring", "longer_tail": "Longer ring", "room": "In a room", "far": "Farther away", "loop": "Seamless loop"}
var api: Node
var credentials: Node
var storage: RefCounted
var player: AudioStreamPlayer
var account := ""
var account_status: Dictionary = {}
var epoch := 0
var preview_epoch := 0
var alive := true
var submitting := false
var connecting := false
var search_serial := 0
var preview_id := ""
var preview_loading := false
var preview_message := ""
var imports := {}
var tasks: Array = []
var details := {}
var poll_due := {}
var poll_errors := {}
var polling := {}
var elapsed_labels := {}
var search_constraints := {}
var search_query := ""
var imported_directories: Array = []
var tabs: TabContainer
var account_label: Label
var account_box: Window
var key_input: LineEdit
var remember: CheckBox
var connect_button: Button
var query: LineEdit
var category: OptionButton
var max_seconds: SpinBox
var results: VBoxContainer
var prompt: TextEdit
var duration: OptionButton
var variations: OptionButton
var enhance: CheckButton
var generate_button: Button
var allowance: Label
var generation_rows: VBoxContainer
var project_rows: VBoxContainer
var directory: LineEdit
var status: Label
var timer: Timer
var plans_row: HBoxContainer
var ui_scale := 1.0
var dialogs: Node
var account_button: Button
var nav_buttons: Array = []
var asset_choice: OptionButton
var round_choice: OptionButton
var type_buttons := {}
var current_kind := "sound"
var composer: VBoxContainer
var source_row: HBoxContainer
var source_label: Label
var start_button: Button
var start_source := {}
var detail_row: HBoxContainer
var detail_chips: HBoxContainer
var detail_labels: Array = []
var details_toggle: CheckButton
var details_edited := false
var suggest_button: Button
var detail_request := 0
var fixed_length: Label
var take_layout: HBoxContainer
var result_label: Label
var only_starred: CheckBox
var inspector_frame: PanelContainer
var volume: HSlider
var inspector: VBoxContainer
var inspector_title: Label
var variant_rows: VBoxContainer
var format_choice: OptionButton
var metadata_label: Label
var inspector_popup: PopupPanel
var inspector_toggle: Button
var play_button: Button
var player_label: Label
var player_time: Label
var seek: HSlider
var seek_dragging := false
var repeat_playback: CheckButton
var import_button: Button
var selected_sound := {}
var selected_task := ""
var selected_asset := ""
var drafts := {}
var draft_timer: Timer
var restoring_draft := false
var generation_kind := "sound"
var waveform_nodes := {}
var wave_cache := {}
var row_play_buttons := {}
var selected_format := "wav"
var connection_token := 0
var storage_state := "unknown"
var saved_key_exists := false
var account_stale := false
var user_connected := false
var progress_elapsed := 0.0
var source_popup: Node
var library_sources: Array = []
var recording_bus := -1
var recording_player: AudioStreamPlayer
var recording_effect: AudioEffectRecord
var recording_started := 0.0
var recording_label: Label
var recording_bytes := PackedByteArray()
var source_dialog_epoch := 0
var busy_actions := {}

func _ready() -> void:
	name = "SFXMintPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	api = API.new()
	add_child(api)
	credentials = Credentials.new()
	add_child(credentials)
	storage = Storage.new(api.origin)
	imported_directories = storage.settings.get("directories", [storage.settings.directory])
	player = AudioStreamPlayer.new()
	add_child(player)
	_build()
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_stop_preview())
	timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()
	_render_project()
	_restore_key.call_deferred()

func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, id: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = Text.text(id)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", int(8 * ui_scale))
	parent.add_child(row)
	return row

func _scroll(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _build() -> void:
	ui_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	UITheme.apply(self, ui_scale)
	UI.build(self)
	dialogs = AccountUI.new()
	add_child(dialogs)
	dialogs.setup(self)
	key_input = dialogs.key_input
	remember = dialogs.remember
	connect_button = dialogs.connect_button
	account_box = dialogs.connection
	dialogs.connect_requested.connect(_connect_key)
	dialogs.connection_canceled.connect(func(): connection_token += 1; connecting = false)
	dialogs.refresh_requested.connect(_refresh_account)
	dialogs.disconnect_requested.connect(_disconnect)
	dialogs.forget_requested.connect(_forget_key)
	dialogs.website_requested.connect(_open_website)
	dialogs.save_requested.connect(_save_project_settings)
	dialogs.retry_save_requested.connect(_retry_secure_save)
	player.finished.connect(func():
		if repeat_playback.button_pressed and not preview_id.is_empty(): player.play()
		else: _update_player())
	resized.connect(func(): _responsive.call_deferred())
	_new_asset()
	_responsive.call_deferred()

func _set_capabilities(caps: Dictionary) -> void:
	var previous_duration = duration.get_item_metadata(duration.selected) if duration.item_count > 0 else null
	var previous_count = variations.get_item_metadata(variations.selected) if variations.item_count > 0 else caps.get("default_variations", 4)
	duration.clear()
	duration.add_item(Text.text("auto"))
	duration.set_item_metadata(0, null)
	for seconds in caps.get("durations", []):
		duration.add_item(str(seconds) + " s")
		duration.set_item_metadata(duration.item_count - 1, seconds)
		if previous_duration == seconds: duration.select(duration.item_count - 1)
	variations.clear()
	for count in caps.get("variations", [1, 2, 4]):
		variations.add_item(str(int(count)) + (" takes" if current_kind == "sound" else " tracks"))
		variations.set_item_metadata(variations.item_count - 1, count)
	variations.select(maxi(0, variations.item_count - 1))
	for i in range(variations.item_count):
		if variations.get_item_metadata(i) == previous_count: variations.select(i)

func _say(message: String) -> void:
	if alive and is_instance_valid(status):
		status.text = message

func _restore_key() -> void:
	if api.origin != API.DEFAULT_ORIGIN:
		storage_state = "session"
		_say("Demo mode — local fixture service; saved production keys are not accessed.")
		return
	var token := connection_token
	var secret := OS.get_environment("SFXMINT_API_KEY").strip_edges()
	if secret.is_empty():
		var reply: Dictionary = await credentials.call_store("get")
		if not alive or token != connection_token or user_connected: return
		secret = str(reply.get("secret", "")) if reply.get("ok", false) else ""
		saved_key_exists = not secret.is_empty()
		storage_state = "saved" if saved_key_exists else "none"
	else:
		storage_state = "environment"
	if not secret.is_empty(): await _connect_key(secret, false)
	secret = ""

func _open_connection() -> void:
	connection_token += 1
	user_connected = true
	connecting = false
	dialogs.open_connection()

func _account_menu() -> void:
	if account.is_empty(): _open_connection()
	else: _open_settings()

func _open_settings() -> void:
	_update_account_ui()
	dialogs.show_settings(storage.settings)

func _connect_key(secret: String, save: bool) -> void:
	if connecting or not alive: return
	if not secret.begins_with("sfx_live_") or secret.length() != 49 or not secret.trim_prefix("sfx_live_").is_valid_hex_number():
		dialogs.connect_message.text = "Enter a valid SFXMint API key."
		_say(dialogs.connect_message.text)
		return
	connection_token += 1
	var attempt := connection_token
	connecting = true
	dialogs.set_connecting(true)
	dialogs.connect_message.text = "Checking your key…"
	# Verify a candidate without replacing the active key or its in-flight requests.
	var reply: Dictionary = await api.api("/api/v1/client-status", HTTPClient.METHOD_GET, {}, true, secret)
	if not alive or attempt != connection_token: return
	connecting = false
	dialogs.set_connecting(false)
	if not reply.ok or str(reply.get("data", {}).get("account_id", "")).is_empty():
		dialogs.connect_message.text = Text.error(reply) if not reply.ok else "The account response was incomplete. Try again."
		_say(dialogs.connect_message.text)
		return
	var old_account := account
	var previous_draft := _draft_value()
	var new_account := str(reply.data.account_id)
	if new_account != account:
		if is_instance_valid(source_popup): source_popup.shutdown()
		_save_drafts()
		epoch += 1
		_stop_preview()
		tasks = storage.tasks(new_account)
		details.clear()
		poll_due.clear()
		poll_errors.clear()
		polling.clear()
		selected_sound = {}
		selected_task = ""
		selected_asset = ""
		start_source = {}
		drafts = storage.workspace(new_account)
		if not str(previous_draft.get("prompt", "")).is_empty():
			previous_draft.source = {}
			selected_asset = "draft-" + str(Time.get_ticks_usec())
			drafts[selected_asset] = previous_draft
		elif not tasks.is_empty():
			selected_task = str(tasks[0].id)
			selected_asset = str(tasks[0].get("asset_id", tasks[0].id))
		else:
			selected_asset = "draft-" + str(Time.get_ticks_usec())
	api.key = secret
	account = new_account
	account_status = reply.data
	account_stale = false
	if user_connected or (new_account != old_account and not old_account.is_empty()): storage_state = "session"
	key_input.clear()
	dialogs.connection.hide()
	_set_capabilities(account_status.get("capabilities", {}))
	_restore_draft()
	_show_account()
	_render_tasks()
	_render_project()
	_say("Connected. Your account allowance is shared with the website.")
	if save:
		storage_state = "session"
		if remember.button_pressed:
			var saved: Dictionary = await credentials.call_store("set", secret) if api.origin == API.DEFAULT_ORIGIN else {"ok": false}
			if not alive or attempt != connection_token: return
			if saved.get("ok", false): saved_key_exists = true
			storage_state = "saved" if saved.get("ok", false) else "save_failed"
			if storage_state == "save_failed": _say(Text.text("session_only"))
	_update_account_ui()
	secret = ""

func _allowance_text() -> String:
	if account.is_empty(): return "Connect an account to generate."
	var value: Dictionary = account_status.get("allowance", {})
	var plan = value.get("plan")
	var parts: Array[String] = []
	if plan is Dictionary:
		parts.append(str(plan.get("name", "Plan")) + " · %d generations left" % int(value.get("left", 0)))
	elif int(value.get("left", 0)) > 0:
		parts.append("%d free sound generation%s left" % [int(value.left), "" if int(value.left) == 1 else "s"])
	if value.has("credits"): parts.append("%d credits available" % int(value.credits))
	return " · ".join(parts) + (" · Last known; refresh needed" if account_stale else "")

func _generation_cost() -> String:
	if account.is_empty(): return "Connect to generate"
	var value: Dictionary = account_status.get("allowance", {})
	if value.get("plan") is Dictionary and int(value.get("left", 0)) > 0: return "Uses 1 plan generation"
	if current_kind == "sound" and int(value.get("left", 0)) > 0: return "Uses 1 free generation"
	return "Uses 1 credit"

func _show_account() -> void:
	_update_account_ui()
	var caps: Dictionary = account_status.get("capabilities", {})
	var kinds: Array = caps.get("kinds", ["sound"])
	for kind in type_buttons:
		type_buttons[kind].disabled = submitting or (not account.is_empty() and kind not in kinds)
	var can_generate := not submitting and (account.is_empty() or (bool(account_status.get("generation_enabled", false)) and current_kind in kinds))
	generate_button.disabled = not can_generate
	var title := "Generate again" if not selected_task.is_empty() else "Generate"
	generate_button.text = (title + (" · " + _generation_cost().trim_prefix("Uses ") if not account.is_empty() else "")) if not submitting else "Starting…"
	allowance.text = _allowance_text() + ("" if not account.is_empty() else " Library sounds stay free.")
	if not account.is_empty() and not account_status.get("generation_enabled", false): allowance.text += " · Generation unavailable"
	if not account.is_empty() and current_kind not in kinds: allowance.text += " · This sound type is unavailable on the server"
	generate_button.tooltip_text = _generation_cost() + ". Each click starts a new request."

func _update_account_ui() -> void:
	if not is_instance_valid(dialogs): return
	account_button.text = "Connect account" if account.is_empty() else "Connected" + (" · Offline" if account_stale else "")
	account_label.text = account_button.text
	dialogs.account_line.text = "Not connected" if account.is_empty() else "Connected" + (" · Status needs refresh" if account_stale else "")
	dialogs.key_line.text = "API key: " + str(account_status.get("key", {}).get("masked", "not connected"))
	dialogs.storage_line.text = {"saved": "Saved securely on this device", "save_failed": "Connected for this session only; the key could not be saved", "environment": "Provided by this editor's environment", "none": "No saved key on this device", "session": "Not saved — this session only"}.get(storage_state, "Secure storage status not checked")
	dialogs.retry_save.visible = storage_state == "save_failed" and not account.is_empty()
	dialogs.forget_button.disabled = not saved_key_exists and storage_state != "unknown"
	if storage_state == "session" and saved_key_exists: dialogs.storage_line.text = "Current key: session only. A previous key is still saved on this device."
	dialogs.disconnect_button.disabled = account.is_empty()
	dialogs.replace_button.text = "Connect account" if account.is_empty() else "Replace key"
	dialogs.allowance.text = _allowance_text()

func _refresh_account() -> void:
	if account.is_empty():
		_open_connection()
		return
	var token := epoch
	var reply: Dictionary = await api.api("/api/v1/client-status", HTTPClient.METHOD_GET, {}, true)
	if not alive or token != epoch: return
	if reply.ok and reply.data.get("account_id") == account:
		account_status = reply.data
		account_stale = false
		_set_capabilities(account_status.get("capabilities", {}))
		_show_account()
		_say("Allowance refreshed. No generation was submitted.")
	else:
		account_stale = true
		_show_account()
		_say(Text.error(reply))
		if int(reply.get("status", 0)) in [401, 403]: _disconnect()

func _disconnect() -> void:
	if is_instance_valid(source_popup): source_popup.shutdown()
	_save_drafts()
	connection_token += 1
	user_connected = true
	epoch += 1
	api.key = ""
	account = ""
	account_status = {}
	account_stale = false
	tasks = []
	details.clear()
	poll_due.clear()
	polling.clear()
	poll_errors.clear()
	selected_sound = {}
	selected_task = ""
	start_source = {}
	submitting = false
	connecting = false
	if is_instance_valid(key_input): key_input.clear()
	if is_instance_valid(plans_row): plans_row.hide()
	_stop_preview()
	if is_instance_valid(account_label):
		_show_account()
		_render_tasks()
		_render_project()
		_update_player()
	_say("Disconnected for this session. Imported audio is unchanged.")

func _forget_key() -> void:
	if api.origin != API.DEFAULT_ORIGIN:
		_say("Demo mode does not access saved production credentials.")
		return
	var result: Dictionary = await credentials.call_store("delete")
	if not alive: return
	if result.get("ok", false):
		saved_key_exists = false
		storage_state = "session" if not account.is_empty() else "none"
		_say("Saved key removed. The current session remains connected." if not account.is_empty() else "Saved key removed.")
	else:
		_say("The saved key could not be removed. Your connection is unchanged.")
	_update_account_ui()

func _retry_secure_save() -> void:
	if account.is_empty(): return
	var token := epoch
	var result: Dictionary = await credentials.call_store("set", api.key) if api.origin == API.DEFAULT_ORIGIN else {"ok": false}
	if not alive or token != epoch: return
	if result.get("ok", false): saved_key_exists = true
	storage_state = "saved" if result.get("ok", false) else "save_failed"
	_update_account_ui()
	_say("Key saved securely." if storage_state == "saved" else Text.text("session_only"))

func _save_project_settings(path: String, format: String) -> void:
	if not Storage.safe_directory(path):
		dialogs.settings_message.text = "Choose a project directory outside addons/."
		return
	var previous: Dictionary = storage.settings.duplicate(true)
	storage.settings.directory = path.trim_suffix("/") + "/"
	storage.settings.format = format
	if storage.save_settings() != OK:
		storage.settings = previous
		dialogs.settings_message.text = "Settings could not be saved. Previous defaults are unchanged."
		return
	directory.text = storage.settings.directory
	dialogs.settings.hide()
	_render_project()
	_update_player()
	_say("Project defaults saved. Existing files are unchanged.")

func _search() -> void:
	if query.text.strip_edges().is_empty():
		_say(Text.text("msg_describe_a_sound_first"))
		return
	search_serial += 1
	var serial := search_serial
	search_query = query.text.strip_edges()
	var path := "/api/v1/search?response=structured&limit=8&format=wav&q=" + search_query.uri_encode()
	if category.selected > 0:
		path += "&category=" + category.get_item_text(category.selected).uri_encode()
	if max_seconds.value > 0:
		path += "&max_duration_ms=" + str(int(max_seconds.value * 1000))
	_say(Text.text("msg_searching"))
	var reply: Dictionary = await api.api(path)
	if not alive or serial != search_serial:
		return
	if not reply.ok:
		_say(Text.error(reply))
		return
	_clear(results)
	search_constraints = reply.data.get("constraints", {})
	var candidates: Array = reply.data.get("candidates", [])
	library_sources = candidates.duplicate(true)
	var closest: Array = reply.data.get("closest", [])
	if not candidates.is_empty():
		_label(results, Text.text("matches"))
		for sound in candidates:
			_sound_row(results, sound)
	if not closest.is_empty():
		_label(results, Text.text("related"))
		for sound in closest:
			_sound_row(results, sound)
	if candidates.is_empty() and closest.is_empty():
		_label(results, Text.text("no_match"))
	_say(Text.text("msg_search_complete_listen_before_choosing_a_sound"))

func _from_search() -> void:
	_new_asset()
	prompt.text = query.text.strip_edges()
	tabs.current_tab = 1
	prompt.grab_focus.call_deferred()
	var limit := max_seconds.value
	if search_query == query.text.strip_edges() and search_constraints.get("max_duration_ms") != null:
		limit = float(search_constraints.max_duration_ms) / 1000.0
	duration.select(0)
	if limit > 0:
		var choice := -1
		for i in range(1, duration.item_count):
			if float(duration.get_item_metadata(i)) <= limit:
				choice = i
		if choice >= 0:
			duration.select(choice)
		else:
			duration.select(0)
			_say(Text.text("msg_generation_cannot_meet_this_length_limit_choose_a_supporte"))
	var warnings: Array[String] = []
	if search_constraints.get("loop") == true: warnings.append("seamless looping")
	if search_constraints.get("recorded") == true: warnings.append("a real recording")
	if not warnings.is_empty():
		_say(Text.text("msg_generation_does_not_promise") + ", ".join(warnings) + ". Review the description before generating.")

func _draft_value() -> Dictionary:
	if not is_instance_valid(prompt) or not is_instance_valid(enhance): return {}
	return {"prompt": prompt.text, "kind": current_kind, "duration_s": duration.get_item_metadata(duration.selected), "variations": variations.get_item_metadata(variations.selected), "enhance": enhance.button_pressed, "detail_labels": detail_labels.duplicate(), "details_on": details_toggle.button_pressed, "details_edited": details_edited, "source": start_source.duplicate(true)}

func _draft_changed() -> void:
	if restoring_draft or not is_instance_valid(prompt): return
	if not selected_asset.is_empty(): drafts[selected_asset] = _draft_value()
	if not is_instance_valid(draft_timer):
		draft_timer = Timer.new()
		draft_timer.one_shot = true
		draft_timer.wait_time = 0.4
		draft_timer.timeout.connect(_save_drafts)
		add_child(draft_timer)
	draft_timer.start()

func _save_drafts() -> void:
	if is_instance_valid(storage) and not account.is_empty():
		if not selected_asset.is_empty() and is_instance_valid(prompt): drafts[selected_asset] = _draft_value()
		if storage.save_workspace(account, drafts) != OK: _say("The current draft could not be saved locally.")

func _new_asset() -> void:
	if is_instance_valid(prompt): _draft_changed()
	selected_asset = "draft-" + str(Time.get_ticks_usec())
	selected_task = ""
	selected_sound = {}
	drafts[selected_asset] = {"prompt": "", "kind": "sound", "duration_s": null, "variations": 4, "enhance": true, "detail_labels": [], "details_on": true, "source": {}}
	_restore_draft()
	_render_tasks()
	_stop_preview()
	_show_account()
	_update_player()

func _restore_draft() -> void:
	var value: Dictionary = drafts.get(selected_asset, {})
	if value.is_empty():
		var task := _active_task()
		value = {"prompt": task.get("prompt", ""), "kind": task.get("kind", "sound"), "duration_s": task.get("duration_s"), "variations": task.get("variations", 4), "enhance": task.get("enhance", true), "detail_labels": task.get("detail_labels", []), "details_on": task.get("details_on", true), "source": {}}
	restoring_draft = true
	composer.show()
	prompt.text = str(value.get("prompt", ""))
	current_kind = str(value.get("kind", "sound"))
	for i in range(duration.item_count):
		if duration.get_item_metadata(i) == value.get("duration_s"): duration.select(i)
	for i in range(variations.item_count):
		if variations.get_item_metadata(i) == value.get("variations", 4): variations.select(i)
	enhance.set_pressed_no_signal(bool(value.get("enhance", true)))
	detail_labels = value.get("detail_labels", []).duplicate()
	details_edited = bool(value.get("details_edited", not detail_labels.is_empty()))
	details_toggle.set_pressed_no_signal(bool(value.get("details_on", true)))
	start_source = value.get("source", {}).duplicate(true)
	restoring_draft = false
	_set_kind(current_kind)
	_render_detail_chips()
	_update_source()
	_draft_changed()

func _set_kind(kind: String) -> void:
	if kind not in ["sound", "ambience", "music"]: return
	current_kind = kind
	for i in range(variations.item_count): variations.set_item_text(i, str(int(variations.get_item_metadata(i))) + (" takes" if kind == "sound" else " tracks"))
	detail_request += 1
	for name in type_buttons: type_buttons[name].button_pressed = name == kind
	duration.visible = kind == "sound"
	start_button.visible = kind == "sound"
	fixed_length.visible = kind != "sound"
	fixed_length.text = "30 s base" if kind == "ambience" else "30 s original"
	detail_row.visible = kind == "ambience"
	prompt.placeholder_text = {"sound": "Describe the sound and its moment in your game…", "ambience": "Describe the place: steady wind, distant waves, birds in the trees…", "music": "Describe the background music: mood, instruments and tempo…"}[kind]
	_update_source()
	_details_changed(false)
	_draft_changed()
	_show_account()

func _sync_choices() -> void:
	if not is_instance_valid(asset_choice): return
	asset_choice.clear()
	var ids: Array = []
	if not selected_asset.is_empty(): ids.append(selected_asset)
	for task in tasks:
		var id := str(task.get("asset_id", task.id))
		if id not in ids: ids.append(id)
	for id in drafts:
		if id not in ids and not str(drafts[id].get("prompt", "")).is_empty(): ids.append(id)
	for id in ids:
		var title := str(drafts.get(id, {}).get("prompt", ""))
		if title.is_empty():
			for task in tasks:
				if str(task.get("asset_id", task.id)) == id: title = str(task.prompt); break
		asset_choice.add_item(title.left(38) if not title.is_empty() else "New sound")
		asset_choice.set_item_metadata(asset_choice.item_count - 1, id)
		if id == selected_asset: asset_choice.select(asset_choice.item_count - 1)
	round_choice.clear()
	for task in tasks:
		if str(task.get("asset_id", task.id)) != selected_asset: continue
		round_choice.add_item("Round %d" % int(task.get("round", 1)))
		round_choice.set_item_metadata(round_choice.item_count - 1, task.id)
		if task.id == selected_task: round_choice.select(round_choice.item_count - 1)
	round_choice.visible = round_choice.item_count > 0

func _choose_asset(index: int) -> void:
	_draft_changed()
	selected_asset = str(asset_choice.get_item_metadata(index))
	selected_task = ""
	for task in tasks:
		if str(task.get("asset_id", task.id)) == selected_asset: selected_task = str(task.id); break
	selected_sound = {}
	_stop_preview()
	_restore_draft()
	_render_tasks()
	_show_account()

func _choose_round(index: int) -> void:
	_draft_changed()
	selected_task = str(round_choice.get_item_metadata(index))
	selected_sound = {}
	_stop_preview()
	var task := _active_task()
	drafts[selected_asset] = task.duplicate(true)
	_restore_draft()
	_render_takes()
	_show_account()

func _responsive() -> void:
	if not is_instance_valid(inspector) or not is_inside_tree(): return
	var narrow := size.x < 700 * ui_scale
	volume.visible = size.x >= 850 * ui_scale
	directory.visible = size.x >= 650 * ui_scale
	inspector_toggle.visible = narrow and tabs.current_tab == 1
	if narrow and inspector.get_parent() == inspector_frame:
		inspector.reparent(inspector_popup, false)
		inspector.position = Vector2.ZERO
		inspector.size = inspector.get_combined_minimum_size()
		inspector_frame.hide()
		inspector_popup.hide()
	elif not narrow and inspector.get_parent() == inspector_popup:
		inspector_popup.hide()
		inspector.reparent(inspector_frame, false)
		inspector_frame.show()

func _open_inspector() -> void:
	inspector_popup.popup_centered(Vector2i(300, 330) * ui_scale)

func _details_changed(edited := true) -> void:
	if not is_instance_valid(enhance): return
	detail_request += 1
	if edited: details_edited = true
	details_toggle.disabled = not enhance.button_pressed
	detail_chips.visible = details_toggle.button_pressed and enhance.button_pressed
	suggest_button.disabled = account.is_empty() or not enhance.button_pressed or not details_toggle.button_pressed
	_draft_changed()

func _render_detail_chips() -> void:
	_clear(detail_chips)
	for value in detail_labels:
		var chip := _button(detail_chips, str(value), func(): detail_labels.erase(value); _render_detail_chips(); _details_changed())
		chip.clip_text = true
		chip.custom_minimum_size.x = minf(chip.get_theme_font("font").get_string_size(str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, chip.get_theme_font_size("font_size")).x + 46 * ui_scale, 150 * ui_scale)
		chip.icon = UITheme.icon(self, "Close")
		chip.tooltip_text = "Remove " + str(value)

func _add_detail() -> void:
	if detail_labels.size() >= 3: _say("Keep up to three detail sounds."); return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add an ambience detail"
	dialog.min_size = Vector2i(Vector2(380, 100) * ui_scale)
	var field := LineEdit.new()
	field.placeholder_text = "For example: distant ship horn"
	field.max_length = 60
	dialog.add_child(field)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var value := field.text.strip_edges()
		if not value.is_empty() and value not in detail_labels:
			detail_labels.append(value)
			details_toggle.button_pressed = true
			_render_detail_chips()
			_details_changed()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	field.text_submitted.connect(func(_value): dialog.confirmed.emit())
	dialog.popup_centered()
	field.grab_focus.call_deferred()

func _suggest_details() -> void:
	if account.is_empty(): _open_connection(); return
	var words := prompt.text.strip_edges()
	if words.length() < 2: _say("Describe the place before suggesting details."); return
	detail_request += 1
	var request := detail_request
	var token := epoch
	suggest_button.disabled = true
	suggest_button.text = "Suggesting…"
	var reply: Dictionary = await api.api("/api/v1/ambience/details", HTTPClient.METHOD_POST, {"words": words}, true)
	if not alive: return
	suggest_button.text = "Suggest details"
	suggest_button.disabled = account.is_empty() or not details_toggle.button_pressed or not enhance.button_pressed
	if token != epoch or request != detail_request or words != prompt.text.strip_edges() or current_kind != "ambience": return
	if not reply.ok: _say(Text.error(reply)); return
	detail_labels = []
	for entry in reply.data.get("details", []):
		if entry is Dictionary and entry.get("label") is String and detail_labels.size() < 3: detail_labels.append(entry.label)
	details_edited = true
	_render_detail_chips()
	_draft_changed()

func _update_source() -> void:
	source_row.visible = current_kind == "sound" and not start_source.is_empty()
	source_label.text = "Starting from: " + str(start_source.get("name", "your audio"))
	if start_source.has("upload"): source_label.text += " · Your source rights apply; not CC0"
	variations.disabled = current_kind == "sound" and (start_source.has("order") or start_source.has("upload"))
	if variations.disabled:
		for i in range(variations.item_count):
			if variations.get_item_metadata(i) == 4: variations.select(i)

func _clear_source() -> void:
	start_source = {}
	_update_source()
	_draft_changed()

func _generate() -> void:
	if submitting: return
	if account.is_empty():
		_open_connection()
		return
	var words := prompt.text.strip_edges()
	if words.is_empty() or words.length() > 400:
		_say("Describe the audio in 400 characters or fewer.")
		return
	var caps: Dictionary = account_status.get("capabilities", {})
	if current_kind not in caps.get("kinds", ["sound"]):
		_say("This sound type is not available on the server.")
		return
	var seconds = duration.get_item_metadata(duration.selected) if current_kind == "sound" else 30
	var body := {"prompt": words, "kind": current_kind, "variations": variations.get_item_metadata(variations.selected), "enhance": enhance.button_pressed, "source": "godot", "query": search_query}
	if seconds != null: body.duration_s = seconds
	if current_kind == "ambience":
		if not details_toggle.button_pressed or not enhance.button_pressed: body.details = []
		elif details_edited: body.details = detail_labels.duplicate()
	if current_kind == "sound" and not start_source.is_empty():
		if start_source.has("base"):
			body.base = start_source.base
		elif start_source.has("upload"):
			if int(start_source.get("expires_at", 0)) <= int(Time.get_unix_time_from_system() * 1000):
				_say("This uploaded source expired. Choose the audio again.")
				return
			body.from_audio = {"upload": start_source.upload}
			body.variations = 4
		elif start_source.has("order"):
			body.from_audio = {"order": start_source.order, "take": start_source.take}
			body.variations = 4
	_draft_changed()
	await _submit_generation(body)

func _submit_generation(body: Dictionary) -> void:
	if submitting or account.is_empty(): return
	for task in tasks:
		if task.status == "uncertain":
			selected_task = task.id
			selected_asset = str(task.get("asset_id", task.id))
			_render_tasks()
			_say(Text.text("uncertain"))
			return
	plans_row.hide()
	var round_number := 1
	for existing in tasks:
		if str(existing.get("asset_id", existing.id)) == selected_asset: round_number = maxi(round_number, int(existing.get("round", 1)) + 1)
	var task := {"id": "pending-" + str(Time.get_ticks_usec()), "prompt": body.prompt, "status": "uncertain", "created_at": int(Time.get_unix_time_from_system() * 1000), "duration_s": body.get("duration_s"), "variations": body.variations, "enhance": body.enhance, "kind": body.get("kind", "sound"), "asset_id": selected_asset, "round": round_number, "detail_labels": detail_labels.duplicate(), "details_on": details_toggle.button_pressed}
	tasks.push_front(task)
	if storage.save_tasks(account, tasks) != OK:
		tasks.erase(task)
		_say("Cannot save recovery state. No generation was submitted.")
		return
	selected_task = task.id
	submitting = true
	var token := epoch
	_show_account()
	_render_tasks()
	_say("Submitting generation…")
	var reply: Dictionary = await api.api("/api/v1/orders", HTTPClient.METHOD_POST, body, true)
	if not alive or token != epoch: return
	submitting = false
	if reply.ok and not str(reply.data.get("order_id", "")).is_empty():
		var pending_id: String = task.id
		task.id = reply.data.order_id
		task.status = "generating"
		if selected_task == pending_id: selected_task = task.id
		if reply.data.get("free") is Dictionary: account_status.allowance = reply.data.free
		_say("Generation started. You can keep working while it runs.")
	elif int(reply.get("status", 0)) == 0 or int(reply.get("status", 0)) >= 500 or reply.get("error") == "invalid_response":
		_say(Text.text("uncertain"))
	else:
		tasks.erase(task)
		if selected_task == task.id: selected_task = ""
		_say(Text.error(reply))
		if int(reply.get("status", 0)) in [402, 429]: _show_plans(reply)
	storage.save_tasks(account, tasks)
	_show_account()
	_render_tasks()
	_render_project()

func _show_plans(reply: Dictionary) -> void:
	plans_row.show()
	plans_row.tooltip_text = Text.error(reply)

func _tick() -> void:
	if not alive or account.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	for task in tasks:
		var id := str(task.id)
		if task.status == "generating" and is_instance_valid(elapsed_labels.get(id)):
			elapsed_labels[id].text = Text.text("generating") % _elapsed(task.created_at)
		if id.begins_with("pending-") or polling.get(id, false):
			continue
		if (task.status == "generating" or not details.has(id)) and now >= float(poll_due.get(id, 0)):
			_poll(task)

func _elapsed(created_at: float) -> String:
	var seconds := maxi(0, int(Time.get_unix_time_from_system() - created_at / 1000.0))
	return "%dm %02ds" % [seconds / 60, seconds % 60]

func _poll(task: Dictionary) -> void:
	var id := str(task.id)
	var token := epoch
	polling[id] = true
	var reply: Dictionary = await api.api("/api/v1/orders/" + id.uri_encode(), HTTPClient.METHOD_GET, {}, true)
	if not alive or token != epoch:
		return
	polling.erase(id)
	if not reply.ok:
		var errors := int(poll_errors.get(id, 0)) + 1
		poll_errors[id] = errors
		poll_due[id] = Time.get_unix_time_from_system() + mini(60, int(pow(2, mini(errors, 6))))
		if int(reply.get("status", 0)) in [401, 403]:
			_disconnect()
			_say(Text.error(reply))
		elif int(reply.get("status", 0)) == 404:
			task.status = "unavailable"
			details[id] = {"order": task, "files": []}
			storage.save_tasks(account, tasks)
			_render_tasks()
		else:
			_say(Text.text("reconnecting"))
		return
	poll_errors.erase(id)
	poll_due[id] = Time.get_unix_time_from_system() + 3
	var old_signature := _detail_signature(details.get(id, {}))
	details[id] = reply.data
	task.status = reply.data.get("order", {}).get("status", "generating")
	task.kind = reply.data.get("order", {}).get("kind", "sound")
	storage.save_tasks(account, tasks)
	if old_signature != _detail_signature(reply.data):
		_render_tasks()
		_render_project()
		if task.status != "generating":
			_refresh_account()

func _detail_signature(detail: Dictionary) -> String:
	var stable: Array = [detail.get("order", {}).get("status", "")]
	for file in detail.get("files", []):
		stable.append([file.get("index"), file.get("status"), file.get("favorite"), file.get("unlocked"), file.get("loop_cut"), file.get("details"), file.get("ogg"), file.get("sha256")])
	return JSON.stringify(stable)

func _render_tasks() -> void:
	if not is_instance_valid(generation_rows): return
	_sync_choices()
	_render_takes()

func _active_task() -> Dictionary:
	for task in tasks:
		if str(task.id) == selected_task: return task
	return {}

func _render_takes() -> void:
	_clear(generation_rows)
	waveform_nodes.clear()
	row_play_buttons.clear()
	elapsed_labels.clear()
	var task := _active_task()
	if task.is_empty():
		result_label.text = "No tracks yet"
		_label(generation_rows, "Describe what your game needs, then generate candidates to compare here.")
		_update_inspector()
		return
	if task.status == "uncertain":
		result_label.text = "Submission not confirmed"
		_label(generation_rows, Text.text("uncertain"))
		_button(generation_rows, "Check recent account orders", _recent_orders)
		_button(generation_rows, "I checked; allow a new submission", func():
			tasks.erase(task)
			storage.save_tasks(account, tasks)
			selected_task = ""
			_render_tasks())
		return
	var detail: Dictionary = details.get(task.id, {})
	var files: Array = detail.get("files", [])
	result_label.text = "%d %s" % [files.size(), "takes" if task.get("kind", "sound") == "sound" else "tracks"]
	if task.status == "generating":
		var elapsed := _label(generation_rows, Text.text("generating") % _elapsed(task.created_at))
		elapsed_labels[task.id] = elapsed
	elif task.status in ["failed", "unavailable"]:
		_label(generation_rows, "Generation failed" if task.status == "failed" else "This generation is unavailable to this account.")
	var first: Dictionary = {}
	var retained: Dictionary = {}
	for file in files:
		if file.get("status") != "ready":
			_label(generation_rows, "Take %d · %s" % [int(file.get("index", 0)), str(file.get("status", "working")).capitalize()])
			continue
		var variant := ""
		var format := str(storage.settings.get("format", "wav")) if file.get("ogg", false) else "wav"
		if selected_sound.get("order_id", "") == task.id and selected_sound.get("index") == file.index:
			variant = str(selected_sound.get("variant", ""))
			format = str(selected_sound.get("format", "wav"))
		var sound := _take_sound(task, file, variant, format)
		if sound.has("error"):
			_say(sound.error)
			sound = _take_sound(task, file)
		if first.is_empty(): first = sound
		if selected_sound.get("order_id", "") == task.id and selected_sound.get("index") == file.index: retained = sound
		if not only_starred.button_pressed or file.get("favorite", false): _candidate_row(generation_rows, sound)
	if retained.is_empty() and not first.is_empty(): retained = first
	if not retained.is_empty():
		_select_sound(retained, false, true)
	else:
		selected_sound = {}
		_update_inspector()
		_update_player()
	if only_starred.button_pressed and generation_rows.get_child_count() == 0: _label(generation_rows, "No starred takes in this round.")

func _take_sound(task: Dictionary, file: Dictionary, variant := "", format := "wav") -> Dictionary:
	return Sound.from_take(task, file, details.get(task.id, {"order": task}), account, variant, format)

func _sound_row(parent: Node, sound: Dictionary) -> void:
	_candidate_row(parent, sound)

func _candidate_row(parent: Node, sound: Dictionary) -> void:
	var id := Storage.identity(sound)
	var box := PanelContainer.new()
	box.set_meta("sound_id", id)
	box.set_meta("sound", sound)
	parent.add_child(box)
	var normal := UITheme.row_style(self, ui_scale)
	box.add_theme_stylebox_override("panel", UITheme.selected(self) if Storage.identity(selected_sound) == id else normal)
	var row := _row(box)
	row.custom_minimum_size.y = 34 * ui_scale
	var label_text := ("Take %d" if sound.get("kind", "sound") == "sound" else "Track %d") % int(sound.get("index", 0)) if sound.has("order_id") else str(sound.get("title", "Sound"))
	if sound.has("order_id"):
		var number := UI.compact_label(self, row, str(int(sound.get("index", 0))))
		number.custom_minimum_size.x = 20 * ui_scale
	var select := _button(row, label_text, func(): _select_sound(sound))
	select.flat = true
	select.clip_text = true
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.custom_minimum_size.x = (72 if sound.has("order_id") else 170) * ui_scale
	select.tooltip_text = str(sound.get("title", "")) + (" — " + str(sound.get("description", "")) if not sound.has("order_id") else "")
	select.gui_input.connect(_candidate_key_input)
	var play := UI.icon_button(self, row, "Play", "Play / pause " + label_text, func(): _select_sound(sound); _preview(sound))
	UITheme.round_button(play, ui_scale)
	row_play_buttons[id] = play
	play.gui_input.connect(_candidate_key_input)
	var wave := Waveform.new()
	row.add_child(wave)
	wave.set_peaks(wave_cache.get(id, sound.get("peaks", [])))
	wave.tooltip_text = "Waveform loads when this version is auditioned." if wave.peaks.is_empty() else "Measured audio waveform"
	waveform_nodes[id] = wave
	var length := UI.compact_label(self, row, Sound.clock(float(sound.get("duration_ms", 0)) / 1000.0))
	length.custom_minimum_size.x = 43 * ui_scale
	length.tooltip_text = str(sound.get("variant_label", "Original"))
	if sound.has("order_id"):
		var star := UI.icon_button(self, row, "Favorites", "Star this take", func(): _favorite(sound))
		star.modulate = UITheme.accent(self) if sound.get("favorite", false) else Color.WHITE
		star.tooltip_text = "Unstar this take" if sound.get("favorite", false) else "Star this take"
		star.disabled = busy_actions.has("star:" + id)
		var menu := MenuButton.new()
		menu.icon = UITheme.icon(self, "GuiTabMenuHl")
		if not menu.icon: menu.text = "More"
		menu.tooltip_text = "Take actions"
		row.add_child(menu)
		var popup := menu.get_popup()
		popup.add_item("Use description", 0)
		if sound.get("kind", "sound") == "sound":
			popup.add_item("Start from this take", 1)
			popup.set_item_disabled(popup.get_item_index(1), sound.get("locked", false))
			popup.add_separator()
			for i in range(SOUND_ACTIONS.size()):
				popup.add_item(SOUND_ACTIONS.values()[i] + " — no credit", 10 + i)
		popup.id_pressed.connect(func(action): _take_action(sound, action))
	elif sound.get("fit") == "closest":
		UI.compact_label(self, row, "Related")
	box.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _select_sound(sound))

func _select_sound(sound: Dictionary, play := false, redraw := true) -> void:
	var previous := Storage.identity(selected_sound)
	selected_sound = sound.duplicate(true)
	if previous != Storage.identity(sound): _stop_preview()
	_update_inspector()
	_update_player()
	if redraw:
		for parent in [generation_rows, results]:
			for child in parent.get_children():
				if child is PanelContainer and child.has_meta("sound_id"):
					child.add_theme_stylebox_override("panel", UITheme.selected(self) if child.get_meta("sound_id") == Storage.identity(sound) else UITheme.row_style(self, ui_scale))
	if play: _preview(selected_sound)

func _update_inspector() -> void:
	_clear(variant_rows)
	format_choice.clear()
	format_choice.add_item("WAV")
	format_choice.set_item_metadata(0, "wav")
	format_choice.disabled = selected_sound.is_empty()
	if selected_sound.is_empty():
		inspector_title.text = "Select a take"
		metadata_label.text = ""
		return
	inspector_title.text = ("Take %d" if selected_sound.get("kind", "sound") == "sound" else "Track %d") % int(selected_sound.get("index", 0)) if selected_sound.has("order_id") else str(selected_sound.get("title", "Sound"))
	var group := ButtonGroup.new()
	for choice in selected_sound.get("variants", [{"id": "original", "label": "Original", "seconds": float(selected_sound.get("duration_ms", 0)) / 1000.0}]):
		var radio := CheckBox.new()
		radio.button_group = group
		radio.text = "%s · %s" % [choice.label, Sound.clock(choice.seconds)]
		radio.button_pressed = choice.id == selected_sound.get("variant", "original")
		radio.pressed.connect(func(): _choose_variant(choice.id))
		variant_rows.add_child(radio)
	if selected_sound.get("ogg", false):
		format_choice.add_item("OGG")
		format_choice.set_item_metadata(1, "ogg")
	format_choice.select(1 if selected_sound.get("format", "wav") == "ogg" and format_choice.item_count > 1 else 0)
	var metadata: Array[String] = []
	if selected_sound.get("detail_labels") is Array and not selected_sound.detail_labels.is_empty(): metadata.append(", ".join(selected_sound.detail_labels))
	var music = details.get(selected_sound.get("order_id", ""), {}).get("order", {}).get("music")
	if music is Dictionary:
		metadata.append(str(music.get("genre", "")))
		metadata.append(", ".join(music.get("instruments", [])))
		metadata.append("%d BPM · Instrumental" % int(music.get("bpm", 0)))
	metadata.append("Listen-only · Unlock before importing" if selected_sound.get("locked", false) else str(selected_sound.get("license", "CC0-1.0")))
	metadata_label.text = "\n".join(metadata)

func _choose_variant(variant: String) -> void:
	if not selected_sound.has("order_id"): return
	var was_playing := player.playing and not player.stream_paused
	var detail: Dictionary = details.get(selected_sound.order_id, {})
	for file in detail.get("files", []):
		if file.index == selected_sound.index:
			var updated := _take_sound({"id": selected_sound.order_id}, file, variant, str(selected_sound.get("format", "wav")))
			if updated.has("error"): _say(updated.error); return
			_select_sound(updated, was_playing)
			_render_takes()
			return

func _choose_format(index: int) -> void:
	if selected_sound.is_empty(): return
	var format := str(format_choice.get_item_metadata(index))
	if not selected_sound.has("order_id"): return
	var was_playing := player.playing and not player.stream_paused
	var detail: Dictionary = details.get(selected_sound.order_id, {})
	for file in detail.get("files", []):
		if file.index == selected_sound.index:
			var updated := _take_sound({"id": selected_sound.order_id}, file, str(selected_sound.get("variant", "original")), format)
			if updated.has("error"): _say(updated.error); return
			_select_sound(updated, was_playing)
			_render_takes()
			return

func _stop_preview() -> void:
	preview_epoch += 1
	preview_id = ""
	preview_loading = false
	preview_message = ""
	if is_instance_valid(player):
		player.stop()
		player.stream_paused = false
		player.stream = null
	_update_player()

func _preview(sound: Dictionary) -> void:
	var id := Storage.identity(sound)
	if preview_id == id and preview_loading: return
	if preview_id == id and player.stream:
		if player.playing: player.stream_paused = not player.stream_paused
		else: player.play()
		_update_player()
		return
	_stop_preview()
	preview_id = id
	selected_sound = sound.duplicate(true)
	if sound.has("local_path"):
		player.stream = ResourceLoader.load(sound.local_path) as AudioStream
		if player.stream:
			selected_sound = sound
			player.play()
			_update_player()
		else:
			_stop_preview()
			_say("This local audio could not be loaded.")
		return
	preview_loading = true
	preview_message = "Preparing preview…"
	_update_player()
	_say(preview_message)
	var serial := preview_epoch
	var token := epoch
	var current: Dictionary = await _fresh_sound(sound)
	if not alive or serial != preview_epoch or token != epoch: return
	if current.has("error"):
		_stop_preview()
		_say(current.error)
		return
	preview_message = "Downloading preview…"
	_update_player()
	_say(preview_message)
	var reply: Dictionary = await api.download(str(current.get("preview_url", current.get("mp3_url", current.get("wav_url", "")))))
	if not alive or serial != preview_epoch or token != epoch: return
	if not reply.ok:
		_stop_preview()
		_say(Text.error(reply))
		return
	var stream := Sound.decode(reply.bytes)
	if stream == null or stream.get_length() <= 0:
		_stop_preview()
		_say(Text.text("msg_this_preview_could_not_be_decoded"))
		return
	preview_loading = false
	preview_message = ""
	player.stream = stream
	player.stream_paused = false
	player.play()
	wave_cache[id] = Waveform.measure(stream)
	if is_instance_valid(waveform_nodes.get(id)): waveform_nodes[id].set_peaks(wave_cache[id])
	selected_sound = current
	_update_player()
	_say("Playing " + str(current.get("variant_label", "Original")) + " · " + str(current.get("format", "wav")).to_upper())

func _fresh_sound(sound: Dictionary) -> Dictionary:
	if sound.has("local_path") or not sound.has("order_id"): return sound
	if sound.get("account_id", "") != account or account.is_empty():
		return {"error": "Connect the account that owns this generation."}
	var reply: Dictionary = await api.api("/api/v1/orders/" + str(sound.order_id).uri_encode(), HTTPClient.METHOD_GET, {}, true)
	if not reply.ok: return {"error": Text.error(reply)}
	details[sound.order_id] = reply.data
	for file in reply.data.get("files", []):
		if file.get("index") == sound.index and file.get("status") == "ready":
			return _take_sound({"id": sound.order_id}, file, str(sound.get("variant", "")), str(sound.get("format", "wav")))
	return {"error": "This take is no longer available."}

func _update_player() -> void:
	if not is_instance_valid(play_button): return
	var active := player.playing and not player.stream_paused
	play_button.icon = UITheme.icon(self, "Pause" if active else "Play")
	play_button.disabled = selected_sound.is_empty() or preview_loading
	play_button.tooltip_text = preview_message if preview_loading else "Play / pause selected audio"
	player_label.text = (("Take %d" if selected_sound.get("kind", "sound") == "sound" else "Track %d") % int(selected_sound.get("index", 0)) + " · " + str(selected_sound.get("variant_label", "Original"))) if selected_sound.has("order_id") else str(selected_sound.get("title", "Select audio"))
	if preview_loading: player_label.text = preview_message
	player_label.tooltip_text = player_label.text
	import_button.disabled = selected_sound.is_empty() or imports.has(Storage.identity(selected_sound))
	var existing: Dictionary = storage.existing(directory.text, selected_sound) if not selected_sound.is_empty() else {}
	import_button.text = "Show in FileSystem" if not existing.is_empty() else ("Unlock…" if selected_sound.get("locked", false) else "Import " + {"details": "long version", "loop": "loop", "original": str(selected_sound.get("format", "wav")).to_upper()}.get(selected_sound.get("variant", "original"), "WAV"))
	if imports.has(Storage.identity(selected_sound)): import_button.text = str(imports[Storage.identity(selected_sound)])
	import_button.tooltip_text = str(selected_sound.get("variant_label", "Original")) + " · " + str(selected_sound.get("format", "wav")).to_upper()
	seek.editable = player.stream != null and not preview_id.is_empty()
	for id in waveform_nodes:
		if is_instance_valid(waveform_nodes[id]):
			waveform_nodes[id].active = id == preview_id and active
			waveform_nodes[id].queue_redraw()
	for id in row_play_buttons:
		if is_instance_valid(row_play_buttons[id]):
			row_play_buttons[id].disabled = id == preview_id and preview_loading
			row_play_buttons[id].tooltip_text = preview_message if id == preview_id and preview_loading else "Play / pause audio"
			row_play_buttons[id].icon = UITheme.icon(self, "Pause" if id == preview_id and active else "Play")

func _process(_delta: float) -> void:
	if not is_instance_valid(seek): return
	var length := player.stream.get_length() if player.stream and not preview_id.is_empty() else float(selected_sound.get("duration_ms", 0)) / 1000.0
	seek.max_value = maxf(length, 0.01)
	if not seek_dragging: seek.set_value_no_signal(player.get_playback_position() if player.playing else 0.0)
	if is_instance_valid(waveform_nodes.get(preview_id)) and player.playing:
		waveform_nodes[preview_id].fraction = player.get_playback_position() / maxf(length, 0.01)
		waveform_nodes[preview_id].queue_redraw()
	player_time.text = Sound.clock(player.get_playback_position() if player.playing else 0.0) + " / " + Sound.clock(length)

func _toggle_player() -> void:
	if not selected_sound.is_empty(): _preview(selected_sound)

func _candidate_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]:
		var rows: Array = generation_rows.get_children() if tabs.current_tab == 1 else results.get_children()
		rows = rows.filter(func(row): return row.has_meta("sound"))
		for i in range(rows.size()):
			if rows[i].get_meta("sound_id") == Storage.identity(selected_sound):
				var next: int = clampi(i + (-1 if event.keycode == KEY_UP else 1), 0, rows.size() - 1)
				_select_sound(rows[next].get_meta("sound"))
				rows[next].get_child(0).get_child(0).grab_focus()
				accept_event()
				return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		accept_event()
		_toggle_player()

func _import_selected() -> void:
	if selected_sound.is_empty(): return
	if not selected_sound.get("locked", false):
		_import_sound(selected_sound)
		return
	var sound := selected_sound.duplicate(true)
	var token := epoch
	var confirm := ConfirmationDialog.new()
	confirm.title = "Unlock this generation"
	confirm.dialog_text = "Unlock the full-quality files for this generation with 1 credit?"
	confirm.ok_button_text = "Use 1 credit"
	add_child(confirm)
	confirm.confirmed.connect(func():
		confirm.queue_free()
		if token != epoch: return
		var reply: Dictionary = await api.api("/api/v1/orders/" + str(sound.order_id).uri_encode() + "/unlock", HTTPClient.METHOD_POST, {"credit": true}, true)
		if not alive or token != epoch: return
		if not reply.ok: _say(Text.error(reply)); return
		var fresh: Dictionary = await _fresh_sound(sound)
		if not alive or token != epoch: return
		if fresh.has("error"): _say(fresh.error); return
		_select_sound(fresh)
		_render_takes()
		_refresh_account()
		_say("Unlocked. Choose a version and import it."))
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()

func _favorite(sound: Dictionary) -> void:
	var id := "star:" + Storage.identity(sound)
	if busy_actions.has(id): return
	busy_actions[id] = true
	var token := epoch
	var reply: Dictionary = await api.api("/api/v1/orders/%s/items/%d" % [str(sound.order_id).uri_encode(), int(sound.index)], HTTPClient.METHOD_PATCH, {"favorite": not sound.get("favorite", false)}, true)
	busy_actions.erase(id)
	if not alive or token != epoch: return
	if not reply.ok: _say(Text.error(reply)); return
	for file in details.get(sound.order_id, {}).get("files", []):
		if file.index == sound.index: file.favorite = reply.data.favorite
	if selected_sound.get("order_id") == sound.order_id and selected_sound.get("index") == sound.index: selected_sound.favorite = reply.data.favorite
	_render_takes()

func _take_action(sound: Dictionary, action: int) -> void:
	if action == 0:
		prompt.text = str(details.get(sound.order_id, {}).get("order", {}).get("prompt", ""))
		_draft_changed()
	elif action == 1:
		_set_kind("sound")
		start_source = {"order": sound.order_id, "take": sound.index, "name": sound.title}
		_update_source()
		_draft_changed()
	elif action >= 10 and action - 10 < SOUND_ACTIONS.size():
		var body := {"prompt": str(details.get(sound.order_id, {}).get("order", {}).get("prompt", "")), "kind": "sound", "variations": 4, "enhance": false, "source": "godot", "refine": {"from": sound.order_id, "take": sound.index, "change": "act:" + str(SOUND_ACTIONS.keys()[action - 10])}}
		await _submit_generation(body)

func _start_from() -> void:
	if account.is_empty(): _open_connection(); return
	if is_instance_valid(source_popup): source_popup.shutdown()
	var takes: Array = []
	for id in details:
		if details[id].get("order", {}).get("kind", "sound") != "sound": continue
		for file in details[id].get("files", []):
			if file.get("status") == "ready" and not str(file.get("url", "")).is_empty():
				takes.append({"order": id, "take": file.index, "name": str(details[id].order.prompt) + " — Take " + str(file.index)})
	var library: Array = []
	for sound in library_sources: library.append({"base": sound.get("slug", ""), "name": sound.get("title", "Sound")})
	var popup := SourceUI.new()
	source_popup = popup
	add_child(popup)
	var token := epoch
	popup.selected.connect(func(source):
		if token != epoch: return
		if source.has("base"):
			var recipe: Dictionary = await api.api("/api/v1/recipes/" + str(source.base).uri_encode())
			if not alive or token != epoch: return
			if not recipe.ok or not recipe.data.get("variation", false):
				_say("This library sound has no reusable generation recipe.")
				return
			prompt.text = str(recipe.data.get("recipe", source.name))
		start_source = source
		_update_source()
		_draft_changed())
	popup.upload_requested.connect(func(bytes, kind, title):
		var reply: Dictionary = await api.upload_audio(bytes, kind)
		if not alive or token != epoch: return
		if not is_instance_valid(popup): return
		if not reply.ok:
			popup.message.text = Text.error(reply)
			popup.use_button.disabled = false
			return
		start_source = {"upload": reply.data.upload_id, "expires_at": reply.data.expires_at, "name": title}
		_update_source()
		_draft_changed()
		popup.shutdown())
	popup.setup(self, takes, library)

func _import_sound(sound: Dictionary) -> void:
	var id := Storage.identity(sound)
	if imports.has(id): return
	var target := directory.text
	var found: Dictionary = storage.existing(target, sound)
	if not found.is_empty():
		EditorInterface.get_file_system_dock().navigate_to_path(found.resource_path)
		_say(Text.text("msg_this_sound_is_already_in_the_project"))
		return
	imports[id] = "Preparing…"
	_update_player()
	var token := epoch
	var current: Dictionary = await _fresh_sound(sound)
	if not alive or token != epoch:
		imports.erase(id)
		_update_player()
		return
	if current.has("error"):
		imports.erase(id)
		_update_player()
		_say(current.error)
		return
	if not current.has("order_id"):
		var md: Dictionary = current.get("format_metadata", {}) if current.get("format_metadata") is Dictionary else {}
		current.sha256 = md.get("wav", {}).get("sha256", "") if md.get("wav") is Dictionary else ""
	imports[id] = Text.text("download")
	_update_player()
	_say(Text.text("download"))
	var url := str(current.get("url", "")) if current.has("order_id") else str(current.get("wav_url", ""))
	if url.is_empty():
		imports.erase(id)
		_update_player()
		_say(Text.text("msg_this_take_is_not_downloadable_refresh_your_allowance"))
		return
	var reply: Dictionary = await api.download(url)
	if not alive or token != epoch:
		imports.erase(id)
		_update_player()
		return
	if not reply.ok:
		imports.erase(id)
		_update_player()
		_say(Text.error(reply))
		return
	var staged: Dictionary = storage.stage(target, current, reply.bytes)
	if staged.has("error"):
		imports.erase(id)
		_update_player()
		_say(staged.error)
		return
	imports[id] = Text.text("importing")
	_update_player()
	_say(Text.text("importing"))
	EditorInterface.get_resource_filesystem().scan()
	var deadline := Time.get_ticks_msec() + 15000
	var imported := false
	var actual_duration := 0.0
	while alive and Time.get_ticks_msec() < deadline:
		if not EditorInterface.get_resource_filesystem().is_scanning() and ResourceLoader.exists(staged.path):
			var resource = ResourceLoader.load(staged.path)
			imported = resource is AudioStream and resource.get_length() > 0
			if imported: actual_duration = resource.get_length()
			break
		await get_tree().create_timer(0.15).timeout
	imports.erase(id)
	_update_player()
	if not alive: return
	if not imported:
		_say(Text.text("msg_wav_downloaded_but_godot_could_not_import_it_no_manifest_e") + staged.path)
		return
	current.duration_ms = actual_duration * 1000.0
	var committed: Dictionary = storage.commit_import(target, current, staged)
	if committed.has("error"):
		_say(committed.error)
		return
	if not imported_directories.has(target): imported_directories.append(target)
	storage.settings.directories = imported_directories
	storage.save_settings()
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.get_file_system_dock().navigate_to_path(staged.path)
	_say(Text.text("msg_imported") + staged.path + (" • " + committed.warning if not committed.get("warning", "").is_empty() else ""))
	_render_project()
	_render_tasks()
	_update_player()

func _choose_directory() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.current_dir = directory.text if DirAccess.dir_exists_absolute(directory.text) else "res://"
	add_child(dialog)
	dialog.dir_selected.connect(func(path):
		if Storage.safe_directory(path):
			directory.text = path.trim_suffix("/") + "/"
			storage.settings.directory = directory.text
			storage.save_settings()
			_render_project()
		else: _say(Text.text("msg_choose_a_project_directory_outside_addons"))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.6)

func _render_project() -> void:
	if not is_instance_valid(project_rows): return
	_clear(project_rows)
	var directories := imported_directories.duplicate()
	if not directories.has(directory.text): directories.append(directory.text)
	var total := 0
	for target in directories:
		var m: Dictionary = storage.manifest(target)
		var files = m.get("files", {})
		if not files is Dictionary: continue
		for entry in files.values():
			if not entry is Dictionary or not entry.has("sfxmint_id"): continue
			total += 1
			var path := str(entry.get("resource_path", str(target).path_join(entry.file)))
			var row := _row(project_rows)
			_label(row, str(entry.get("title", "Sound")) + "\n" + path)
			if FileAccess.file_exists(path):
				var local: Dictionary = entry.duplicate(true)
				local.local_path = path
				if entry.has("take"): local.index = entry.take
				_button(row, "preview", func(): _select_sound(local, true))
				_button(row, "show", func(): EditorInterface.get_file_system_dock().navigate_to_path(path))
			else:
				_label(row, Text.text("missing"))
				_button(row, "relocate", func(): _relocate(target, entry))
				if not str(entry.get("slug", "")).is_empty():
					_button(row, "import", func(): _reimport_library(str(entry.slug)))
				elif entry.has("order_id"):
					_button(row, "import", func(): _import_sound({"order_id": entry.order_id, "index": entry.take, "account_id": account, "variant": entry.get("variant", "original"), "format": entry.get("format", "wav")}))
			var page = entry.get("page_url")
			if page is String and not page.is_empty():
				_button(row, "source", func(): _open_website(page))
	if total == 0:
		_label(project_rows, Text.text("msg_no_sfxmint_audio_imported_into_this_project_yet"))

func _reimport_library(slug: String) -> void:
	var reply: Dictionary = await api.api("/api/v1/sounds/" + slug.uri_encode())
	if alive:
		if reply.ok: _import_sound(reply.data)
		else: _say(Text.error(reply))

func _relocate(target: String, entry: Dictionary) -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.wav, *.ogg", "Audio")
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var error: String = storage.relocate(target, entry, path)
		_say(error if not error.is_empty() else "File location updated.")
		_render_project()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.6)

func _recent_orders() -> void:
	if account.is_empty():
		_say(Text.text("not_connected"))
		return
	var token := epoch
	var reply: Dictionary = await api.api("/api/v1/orders", HTTPClient.METHOD_GET, {}, true)
	if not alive or token != epoch: return
	if not reply.ok:
		_say(Text.error(reply))
		return
	var dialog := AcceptDialog.new()
	dialog.title = Text.text("msg_recent_account_orders_choose_explicitly_these_may_belong_t")
	dialog.min_size = Vector2i(680, 320)
	add_child(dialog)
	var rows := _scroll(dialog)
	for order in reply.data.get("orders", []):
		var row := _row(rows)
		_label(row, str(order.get("prompt", "")) + "\n" + str(order.get("id", "")) + " • " + Time.get_datetime_string_from_unix_time(int(order.get("created_at", 0)) / 1000))
		_button(row, "restore", func():
			if token != epoch: return
			for task in tasks:
				if task.id == order.id:
					_say(Text.text("msg_this_order_is_already_in_this_project"))
					return
			tasks.push_front({"id": order.id, "prompt": order.prompt, "status": order.status, "created_at": order.created_at, "kind": order.get("kind", "sound"), "asset_id": order.id, "round": 1})
			selected_asset = order.id
			selected_task = order.id
			storage.save_tasks(account, tasks)
			_render_tasks()
			_render_project()
			_say(Text.text("msg_order_added_resolve_the_pending_submission_only_after_chec"))
			dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(900, 420))

func _open_website(url: String) -> void:
	if url.begins_with("https://sfxmint.com/"):
		OS.shell_open(url)

func shutdown() -> void:
	_save_drafts()
	if is_instance_valid(source_popup): source_popup.shutdown()
	if is_instance_valid(dialogs): dialogs.shutdown()
	alive = false
	epoch += 1
	_stop_preview()
	if is_instance_valid(timer): timer.stop()
	if is_instance_valid(api): api.shutdown()
	if is_instance_valid(credentials): credentials.shutdown()
