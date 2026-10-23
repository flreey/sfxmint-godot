extends SceneTree

const API = preload("../addons/sfxmint/api.gd")
const Store = preload("../addons/sfxmint/storage.gd")
const SoundPanel = preload("../addons/sfxmint/panel.gd")
var failures := 0
var checks := 0
var api: Node
var panel: Control
var store: RefCounted
var target := "res://tests/artifacts/imports/"

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func control(value: Dictionary) -> void:
	await api._request(api.origin + "/__control", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(value))

func run() -> void:
	if OS.get_environment("SFXMINT_TEST_ORIGIN") != "http://127.0.0.1:8797":
		push_error("Tests require the isolated local Worker on port 8797.")
		quit(2)
		return
	api = API.new()
	root.add_child(api)
	await api._request(api.origin + "/__reset", PackedStringArray(), HTTPClient.METHOD_POST, "")
	var search: Dictionary = await api.api("/api/v1/search?q=coin")
	check(search.ok and search.data.candidates.size() == 1, "anonymous search")
	var sound: Dictionary = search.data.candidates[0]
	var audio: Dictionary = await api.download(sound.wav_url)
	check(audio.ok and AudioStreamWAV.load_from_buffer(audio.bytes) is AudioStreamWAV, "WAV downloads and decodes")
	store = Store.new(api.origin, OS.get_cache_dir().path_join("sfxmint-godot-tests-" + str(OS.get_process_id())))
	target = target.path_join(str(OS.get_process_id())) + "/"
	var source := sound.duplicate(true)
	source.sha256 = sound.format_metadata.wav.sha256
	var bad := source.duplicate(true)
	bad.sha256 = "bad"
	check(store.stage(target, bad, audio.bytes).has("error"), "checksum mismatch rejected")
	check(store.stage("res://addons", source, audio.bytes).has("error"), "plugin directory rejected")
	check(store.stage("/tmp/", source, audio.bytes).has("error"), "outside project rejected")
	check(store.stage(target, sound, PackedByteArray([1,2,3])).has("error"), "invalid resource rejected")
	var staged: Dictionary = store.stage(target, source, audio.bytes)
	check(staged.has("path"), "temporary WAV staged")
	check(store.manifest(target).is_empty(), "staging does not claim successful import")
	var conflict: Dictionary = store.stage(target, source, audio.bytes)
	check(conflict.path != staged.path, "same filename never overwritten")
	Store.atomic_text(target.path_join("SOUNDS.md"), "# My sounds\nKeep my notes.\n")
	var committed: Dictionary = store.commit_import(target, source, staged)
	check(committed.has("entry"), "successful import manifest")
	check(FileAccess.get_file_as_string(target.path_join("SOUNDS.md")).contains("Keep my notes."), "user markdown preserved")
	check(store.existing(target, source).resource_path == staged.path, "duplicate locates existing file")
	var moved := target.path_join("moved.wav")
	DirAccess.rename_absolute(staged.path, moved)
	check(store.existing(target, source).is_empty(), "missing file detected")
	check(store.relocate(target, committed.entry, moved).is_empty(), "same hash relocation")
	check(store.existing(target, source).resource_path == moved, "relocation persisted")
	Store.atomic_text(target.path_join("sounds.json"), "{broken")
	check(store.stage(target, source, audio.bytes).has("error"), "incompatible manifest protected")
	check(store.commit_import(target, source, conflict).has("error"), "concurrent corrupt manifest protected")
	check(FileAccess.get_file_as_string(target.path_join("sounds.json")) == "{broken", "corrupt manifest retained exactly")
	var file_block := target.path_join("not-a-directory")
	Store.atomic_text(file_block, "blocked")
	check(store.stage(file_block.path_join("nested"), source, audio.bytes).has("error"), "unwritable destination fails safely")
	var task := {"id":"ord_test", "prompt":"coin", "status":"generating", "created_at":1, "secret":"not-persisted", "url":"https://example.com/?token=private"}
	check(store.save_tasks("a", [task]) == OK, "task saved")
	var restarted := Store.new(api.origin, store.root)
	check(restarted.tasks("a").size() == 1 and restarted.tasks("b").is_empty(), "restart recovery and account isolation")
	check(not JSON.stringify(restarted.tasks("a")).contains("private") and not restarted.tasks("a")[0].has("secret"), "task whitelist excludes secrets and signed URLs")
	panel = SoundPanel.new()
	root.add_child(panel)
	await process_frame
	panel.timer.stop()
	panel.storage = store
	panel.api.timeout = 0.25
	await panel._connect_key("sfx_live_" + "1".repeat(40), true)
	check(panel.account == "test-account-a" and panel.api.key.length() == 49, "API key handshake")
	check(panel.status.text.contains("session only"), "unavailable secure store falls back to session")
	panel.prompt.text = "coin pickup"
	await control({"delay_ms": 1000})
	panel._generate()
	await process_frame
	await panel._generate()
	await create_timer(0.6).timeout
	check(panel.tasks.size() == 1 and panel.tasks[0].status == "uncertain", "POST timeout stays uncertain and duplicate click is blocked")
	await create_timer(0.7).timeout
	var recent: Dictionary = await panel.api.api("/api/v1/orders", HTTPClient.METHOD_GET, {}, true)
	check(recent.data.orders.size() == 1, "timeout did not automatically resubmit")
	var oid: String = recent.data.orders[0].id
	panel.tasks = [{"id":oid,"prompt":"coin pickup","status":"generating","created_at":recent.data.orders[0].created_at}]
	store.save_tasks(panel.account, panel.tasks)
	await control({"delay_ms":0, "get_status":503})
	await panel._poll(panel.tasks[0])
	check(panel.poll_errors.get(oid) == 1 and panel.poll_due[oid] > Time.get_unix_time_from_system(), "offline query uses delayed backoff")
	await control({"get_status":200,"partial":true})
	await panel._poll(panel.tasks[0])
	await panel._poll(panel.tasks[0])
	check(panel.tasks[0].status == "delivered" and panel.details[oid].files[3].status == "failed", "partial generation preserves ready takes")
	var take: Dictionary = panel._take_sound(panel.tasks[0], panel.details[oid].files[0])
	await create_timer(3.2).timeout
	var stale: Dictionary = await api.download(take.url)
	check(stale.status == 403, "fixture signed URL actually expired")
	await panel._preview(take)
	check(panel.player.playing, "preview refreshes expired URL and plays")
	panel._stop_preview()
	check(not panel.player.playing, "single preview can be stopped")
	await control({"post_status":402})
	await panel._generate()
	check(panel.plans_row.visible and panel.prompt.text == "coin pickup", "quota error keeps description and purchase action")
	var count: int = panel.tasks.size()
	await panel._refresh_account()
	check(panel.tasks.size() == count, "refresh never submits generation")
	await panel._connect_key("sfx_live_" + "2".repeat(40), false)
	check(panel.tasks.is_empty() and panel.account == "test-account-b", "switching account clears visible tasks")
	var foreign: Dictionary = await panel.api.api("/api/v1/orders/" + oid, HTTPClient.METHOD_GET, {}, true)
	check(foreign.status == 404, "foreign account cannot read order")
	await panel._connect_key("sfx_live_" + "1".repeat(40), false)
	check(panel.tasks.size() == 1 and panel.tasks[0].id == oid, "reconnection restores original account tasks")
	panel._disconnect()
	check(panel.api.key.is_empty() and panel.account.is_empty() and panel.tasks.is_empty(), "disconnect clears in-memory identity")
	panel.shutdown()
	panel.queue_free()
	api.shutdown()
	api.queue_free()
	await process_frame
	print("SFXMINT TEST RESULT: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)
