@tool
extends EditorPlugin
const API = preload("res://addons/sfxmint/api.gd")
const Store = preload("res://addons/sfxmint/storage.gd")
var failures := 0
func _enter_tree() -> void:
	if "--export-pack" not in OS.get_cmdline_args():
		run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
func run() -> void:
	await get_tree().process_frame
	var candidates := EditorInterface.get_base_control().find_children("SFXMintPanel", "", true, false)
	if candidates.size() != 1:
		push_error("Expected one native plugin dock")
		get_tree().quit(1)
		return
	var panel = candidates[0]
	panel.timer.stop()
	var invalid_credential: Dictionary = await panel.credentials.call_store("invalid")
	check(invalid_credential.get("error") == "invalid_request", "native credential helper pipe validates without opening a saved key")
	panel.storage = Store.new(API.DEFAULT_ORIGIN, OS.get_cache_dir().path_join("sfxmint-editor-smoke-" + str(OS.get_process_id())))
	await panel.api._request(panel.api.origin + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST, "")
	panel.query.text = "coin"
	await panel._search()
	var reply: Dictionary = await panel.api.api("/api/v1/search?q=coin")
	var sound: Dictionary = reply.data.candidates[0]
	# Real HTTP waits keep the native player controls in their in-flight state.
	panel._select_sound(sound)
	await panel._preview(sound)
	check(panel.player.stream != null, "initial preview loaded before switching candidates")
	var slow := sound.duplicate(true)
	slow.slug = "slow-preview"
	slow.mp3_url = panel.api.origin + "/audio.wav?seconds=3&delay_ms=600"
	panel._select_sound(slow)
	panel._preview(slow)
	check(panel.preview_loading and panel.player.stream == null and not panel.player.playing, "switching clears old audio before the new download")
	check(panel.play_button.disabled and panel.player_label.text == "Downloading preview…" and not panel.seek.editable, "preview download is visible and playback controls wait for the selected file")
	panel._preview(slow)
	check(not panel.player.playing and panel.player.stream == null, "rapid repeat play cannot replay the previous sound")
	var preview_deadline := Time.get_ticks_msec() + 5000
	while panel.preview_loading and Time.get_ticks_msec() < preview_deadline: await get_tree().process_frame
	check(panel.player.stream != null and abs(panel.player.stream.get_length() - 3) < 0.01 and panel.player.playing, "download completion plays the selected three-second file")
	panel._select_sound(sound)
	panel._preview(slow)
	panel._select_sound(sound)
	await panel._preview(sound)
	await get_tree().create_timer(0.8).timeout
	check(panel.preview_id == Store.identity(sound) and abs(panel.player.stream.get_length() - 1) < 0.01, "late download cannot replace a newer selection")
	var missing := sound.duplicate(true)
	missing.slug = "missing-preview"
	missing.mp3_url = panel.api.origin + "/missing-audio.wav"
	panel._select_sound(missing)
	await panel._preview(missing)
	check(not panel.preview_loading and panel.player.stream == null and not panel.play_button.disabled, "failed download clears loading and allows retry without old audio")
	panel._select_sound(sound)
	sound.wav_url += "?delay_ms=600"
	panel._import_sound(sound)
	check(panel.import_button.disabled and panel.import_button.text == "Downloading…", "import button visibly reports the download")
	var import_deadline := Time.get_ticks_msec() + 10000
	while panel.imports.has(Store.identity(sound)) and Time.get_ticks_msec() < import_deadline: await get_tree().process_frame
	check(not panel.import_button.disabled and panel.import_button.text == "Show in FileSystem", "finished import restores its destination action")
	var manifest: Dictionary = panel.storage.manifest(panel.directory.text)
	check(manifest.get("files", {}).size() == 1, "native editor imports before recording manifest")
	if manifest.get("files", {}).size() == 1:
		var file: Dictionary = manifest.files.values()[0]
		check(ResourceLoader.load(file.resource_path) is AudioStream, "imported WAV resolves as AudioStream")
		await panel._import_sound(sound)
		check(panel.storage.manifest(panel.directory.text).files.size() == 1, "duplicate import locates instead of duplicating")

	var control: Dictionary = await panel.api._request(panel.api.origin + "/__control", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, '{"invalid_wav":true}')
	check(control.ok, "controlled malformed WAV enabled")
	var invalid := sound.duplicate(true)
	invalid.slug = "invalid-test"
	invalid.title = "Invalid WAV fixture"
	invalid.format_metadata = {}
	await panel._import_sound(invalid)
	check(panel.storage.manifest(panel.directory.text).files.size() == 1, "resource recognition failure adds no manifest entry")
	await panel.api._request(panel.api.origin + "/__control", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, '{"invalid_wav":false}')
	panel.key_input.text = "sfx_live_" + "1".repeat(40)
	await panel._connect_key(panel.key_input.text, false)
	panel.prompt.text = "Editor generation fixture"
	panel.generate_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 10000
	while panel.submitting and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(panel.tasks.size() == 1 and not panel.submitting, "native Generate signal creates one task")
	if panel.tasks.size() == 1:
		var task: Dictionary = panel.tasks[0]
		await panel._poll(task)
		await panel._poll(task)
		var files: Array = panel.details.get(task.id, {}).get("files", [])
		check(files.size() == 4, "native editor renders four generated candidates")
		if files.size() >= 2:
			await panel._preview(panel._take_sound(task, files[0]))
			var first_stream = panel.player.stream
			await panel._preview(panel._take_sound(task, files[1]))
			check(first_stream is AudioStream and panel.player.playing, "native editor compares generated candidate streams")
			panel._stop_preview()
			await panel._import_sound(panel._take_sound(task, files[1]))
			check(panel.storage.manifest(panel.directory.text).files.size() == 2, "native editor imports generated take and provenance")
	var original_key: String = panel.api.key
	await panel._connect_key("sfx_live_" + "3".repeat(40), false)
	check(panel.api.key == original_key and panel.account == "test-account-a", "invalid replacement preserves active identity")
	panel._save_drafts()
	panel.drafts = panel.storage.workspace(panel.account)
	panel.drafts[panel.selected_asset]["composer_expanded"] = false
	panel._restore_draft()
	check(panel.composer.visible and panel.prompt.editable, "legacy collapsed draft restores directly editable description")
	panel._new_asset()
	check(panel.composer.visible, "new creation starts with expanded composer")
	panel._set_kind("ambience")
	panel.prompt.text = "Wind in the trees"
	await panel._suggest_details()
	check(panel.detail_labels == ["birds", "wind"], "ambience detail suggestions populate removable labels")
	await panel._generate()
	var ambience: Dictionary = panel.tasks[0]
	await panel._poll(ambience)
	await panel._poll(ambience)
	var ambience_file: Dictionary = panel.details[ambience.id].files[0]
	var long_sound: Dictionary = panel._take_sound(ambience, ambience_file)
	check(long_sound.kind == "ambience" and long_sound.variant == "details" and not long_sound.loopable, "ambience defaults to available details without claiming seamless playback")
	await panel._preview(long_sound)
	check(abs(panel.player.stream.get_length() - 12) < 0.01, "selected long ambience auditions its actual 12-second file")
	panel._select_sound(long_sound)
	if panel.inspector.get_parent() != panel.inspector_popup:
		panel.inspector.reparent(panel.inspector_popup, false)
		panel.inspector.position = Vector2.ZERO
	panel._open_inspector()
	for frame in range(4): await get_tree().process_frame
	print("POPUP GEOMETRY: ", panel.inspector_popup.size, " content: ",panel.inspector.size," min: ",panel.inspector.get_combined_minimum_size())
	check(panel.inspector_popup.visible and panel.inspector_popup.size.y <= 600 * panel.ui_scale, "version popup fits a normal editor viewport")
	panel.inspector_popup.hide()
	panel._choose_variant("loop")
	await get_tree().create_timer(0.2).timeout
	check(panel.selected_sound.variant == "loop", "version control selects prepared loop")
	var loop_sound: Dictionary = await panel._fresh_sound(panel.selected_sound)
	check(loop_sound.variant == "loop" and loop_sound.url.contains("seconds=8") and loop_sound.sha256 == "", "refresh preserves variant and never reuses original hash")
	panel._stop_preview()
	await panel._preview(loop_sound)
	check(abs(panel.player.stream.get_length() - 8) < 0.01, "loop playback uses separate eight-second file")
	await panel._preview(loop_sound)
	check(panel.player.stream_paused, "same-player control pauses playback")
	await panel._preview(loop_sound)
	check(not panel.player.stream_paused, "same-player control resumes playback")
	await panel._import_sound(loop_sound)
	var loop_entry: Dictionary = panel.storage.existing(panel.directory.text, loop_sound)
	check(loop_entry.get("variant") == "loop" and abs(float(loop_entry.get("duration_ms",0))-8000)<10, "loop manifest stores selected variant and measured imported duration")
	var ogg: Dictionary = panel._take_sound(ambience, ambience_file, "original", "ogg")
	await panel._preview(ogg)
	check(panel.player.stream is AudioStreamOggVorbis, "offered OGG auditions as OggVorbis")
	await panel._import_sound(ogg)
	var ogg_entry: Dictionary = panel.storage.existing(panel.directory.text, ogg)
	check(ogg_entry.get("format") == "ogg" and str(ogg_entry.get("file", "")).ends_with(".ogg"), "OGG imports with independent format identity")
	await panel._favorite(ogg)
	check(panel.details[ambience.id].files[0].favorite, "favorite state is persisted by the server")
	panel._new_asset()
	panel._set_kind("music")
	panel.prompt.text = "Quiet exploration music"
	await panel._generate()
	var music: Dictionary = panel.tasks[0]
	await panel._poll(music)
	await panel._poll(music)
	var track: Dictionary = panel._take_sound(music, panel.details[music.id].files[0], "original")
	check(track.kind == "music" and track.duration_ms == 30000, "BGM retains explicit kind and 30-second original")
	var source_bytes: Dictionary = await panel.api.download("/audio.wav")
	var converted: PackedByteArray = panel.SourceUI.to_wav(panel.Sound.decode(source_bytes.bytes))
	check(converted.size() > 44 and abs(panel.Sound.decode(converted).get_length()-1)<0.01, "upload conversion creates valid bounded PCM WAV")
	var uploaded: Dictionary = await panel.api.upload_audio(converted,"upload")
	check(uploaded.ok and uploaded.data.has("expires_at"), "authenticated source upload returns expiry")
	panel._new_asset()
	panel.start_source = {"upload": uploaded.data.upload_id,"expires_at":uploaded.data.expires_at,"name":"fixture"}
	panel._update_source()
	panel.prompt.text = "Variation of my source"
	await panel._generate()
	var supplied: Dictionary = panel.tasks[0]
	await panel._poll(supplied)
	await panel._poll(supplied)
	var supplied_sound: Dictionary = panel._take_sound(supplied,panel.details[supplied.id].files[0])
	check(supplied_sound.license == "LicenseRef-User-Supplied", "uploaded source is never presented as CC0")
	await panel._import_sound(supplied_sound)
	check(panel.storage.manifest(panel.directory.text).license == "Per-file; see files", "mixed-rights manifest drops blanket CC0 claim")
	panel._start_from()
	check(is_instance_valid(panel.source_popup) and panel.source_popup.dialog.visible, "source chooser opens all native source tabs")
	panel.source_popup.shutdown()
	panel._open_connection()
	check(panel.dialogs.connection.visible and panel.key_input.secret, "connect dialog opens with masked empty input")
	panel.dialogs.cancel_connection()
	check(panel.account == "test-account-a", "canceling replacement leaves account connected")
	panel._open_settings()
	check(panel.dialogs.settings.visible, "native settings dialog opens")
	panel.dialogs.settings.hide()
	panel._save_project_settings("../outside", "wav")
	check(panel.dialogs.settings_message.text.contains("outside addons"), "invalid settings keep project destination intact")
	print("EDITOR SMOKE RESULT: %s failures" % failures)
	get_tree().quit(1 if failures else 0)
