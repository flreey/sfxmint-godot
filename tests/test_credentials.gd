extends SceneTree
const Credentials = preload("../addons/sfxmint/credentials.gd")
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var helper := Credentials.new()
	root.add_child(helper)
	# These fail validation before opening any real credential entry.
	var invalid: Dictionary = await helper.call_store("invalid")
	var bad_key: Dictionary = await helper.call_store("set", "not-a-key")
	var expected := "invalid_request" if Engine.is_editor_hint() else "editor_only"
	var passed: bool = invalid.get("error") == expected and bad_key.get("error") == expected
	print("Credential mode: " + ("editor pipes" if Engine.is_editor_hint() else "runtime blocked"))
	print("CREDENTIAL PIPE RESULT: " + ("PASS" if passed else "FAIL"))
	helper.shutdown()
	helper.queue_free()
	await process_frame
	quit(0 if passed else 1)
