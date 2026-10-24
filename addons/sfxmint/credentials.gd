@tool
extends Node

var busy := false
var pid := -1
var alive := true

func executable() -> String:
	var platform := {"macOS": "macos", "Windows": "windows", "Linux": "linux"}.get(OS.get_name(), "") as String
	var arch := Engine.get_architecture_name()
	if platform.is_empty() or not arch in ["arm64", "x86_64"]:
		return ""
	var filename := "sfxmint-credentials-" + platform + "-" + arch + (".exe" if platform == "windows" else "")
	return ProjectSettings.globalize_path(get_script().resource_path.get_base_dir().path_join("bin").path_join(filename))

func available() -> bool:
	var path := executable()
	return not path.is_empty() and FileAccess.file_exists(path)

func call_store(operation: String, secret := "") -> Dictionary:
	if not Engine.is_editor_hint():
		return {"ok": false, "error": "editor_only"}
	if busy or not alive:
		return {"ok": false, "error": "credential_store_busy"}
	var path := executable()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "credential_helper_unavailable"}
	# Godot's ZIP installer may not preserve Unix executable permission bits.
	if OS.get_name() != "Windows" and FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER) != OK:
		return {"ok": false, "error": "credential_helper_unavailable"}
	busy = true
	var process := OS.execute_with_pipe(path, PackedStringArray(), false)
	if process.is_empty():
		busy = false
		return {"ok": false, "error": "credential_store_unavailable"}
	pid = process.pid
	var pipe: FileAccess = process.stdio
	pipe.store_string(JSON.stringify({"op": operation, "secret": secret}) + "\n")
	secret = ""
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 30000
	while alive and Time.get_ticks_msec() < deadline:
		var chunk := pipe.get_buffer(4096)
		if not chunk.is_empty():
			received.append_array(chunk)
			if received.size() > 8192:
				break
			if received.has(10):
				var parsed = JSON.parse_string(received.get_string_from_utf8())
				pipe.close()
				process.stderr.close()
				pid = -1
				busy = false
				return parsed if parsed is Dictionary else {"ok": false, "error": "invalid_helper_response"}
		if not OS.is_process_running(pid):
			break
		await get_tree().create_timer(0.05).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	pipe.close()
	process.stderr.close()
	busy = false
	return {"ok": false, "error": "credential_store_unavailable"}

func shutdown() -> void:
	alive = false
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
