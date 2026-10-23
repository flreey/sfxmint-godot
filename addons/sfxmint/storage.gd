@tool
extends RefCounted

const NOTICE = "AI-generated audio. Each file carries its own license. File validation is not listening approval; audition in your game."
const BEGIN = "<!-- SFXMINT:BEGIN -->"
const END = "<!-- SFXMINT:END -->"
var root: String
var settings: Dictionary = {"directory": "res://audio/sfxmint/", "volume": 0.7, "format": "wav", "composer_expanded": true}

func _init(origin := "https://sfxmint.com", override_root := "") -> void:
	root = override_root if not override_root.is_empty() else OS.get_data_dir().path_join("sfxmint-godot").path_join((ProjectSettings.globalize_path("res://") + origin).sha256_text())
	DirAccess.make_dir_recursive_absolute(root)
	var saved := read_json(root.path_join("settings.json"))
	if safe_directory(str(saved.get("directory", ""))):
		settings.merge(saved, true)

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func atomic_text(path: String, text: String) -> Error:
	var temp := path + ".sfxmint-tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		return err
	return DirAccess.rename_absolute(temp, path)

func save_settings() -> Error:
	return atomic_text(root.path_join("settings.json"), JSON.stringify(settings, "\t"))

func tasks(account: String) -> Array:
	if account.is_empty():
		return []
	var value = read_json(root.path_join("tasks-" + account.sha256_text() + ".json")).get("tasks", [])
	return value if value is Array else []

func workspace(account: String) -> Dictionary:
	if account.is_empty(): return {}
	return read_json(root.path_join("workspace-" + account.sha256_text() + ".json"))

func save_workspace(account: String, drafts: Dictionary) -> Error:
	if account.is_empty(): return OK
	var safe := {}
	for id in drafts:
		if not drafts[id] is Dictionary: continue
		var value := {}
		for key in ["prompt", "composer_expanded", "kind", "duration_s", "variations", "enhance", "detail_labels", "details_on", "details_edited"]:
			if drafts[id].has(key): value[key] = drafts[id][key]
		# Starting audio is account-bound; no signed URL, key or raw audio is retained.
		var source = drafts[id].get("source", {})
		if source is Dictionary:
			value.source = {}
			for key in ["order", "take", "upload", "base", "name", "expires_at"]:
				if source.has(key): value.source[key] = source[key]
		safe[id] = value
	return atomic_text(root.path_join("workspace-" + account.sha256_text() + ".json"), JSON.stringify(safe, "\t"))

func save_tasks(account: String, entries: Array) -> Error:
	if account.is_empty():
		return ERR_INVALID_PARAMETER
	# Whitelist: never persist signed URLs, credentials or API response bodies.
	var safe: Array = []
	for entry in entries:
		var clean := {}
		for field in ["id", "prompt", "created_at", "status", "duration_s", "variations", "enhance", "kind", "asset_id", "round", "detail_labels", "details_on", "parent"]:
			if entry.has(field):
				clean[field] = entry[field]
		safe.append(clean)
	return atomic_text(root.path_join("tasks-" + account.sha256_text() + ".json"), JSON.stringify({"tasks": safe}, "\t"))

static func safe_directory(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..") and path.trim_suffix("/") != "res://addons" and not path.begins_with("res://addons/") and not path.contains(".godot") and not path.contains("\\")

static func safe_name(value: String) -> String:
	var out := ""
	for c in value.to_lower():
		if "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(c):
			out += c
		elif not out.ends_with("-"):
			out += "-"
	return out.left(64).strip_edges().trim_suffix("-") if not out.is_empty() else "sound"

static func identity(sound: Dictionary) -> String:
	var id := "order:" + str(sound.order_id) + ":" + str(sound.index) if sound.has("order_id") else "library:" + str(sound.get("slug", ""))
	var variant := str(sound.get("variant", "original"))
	var format := str(sound.get("format", "wav"))
	# Preserve identity of already imported v0.1 original WAVs.
	return id if variant == "original" and format == "wav" else id + ":" + variant + ":" + format

func manifest(directory: String) -> Dictionary:
	return read_json(directory.path_join("sounds.json"))

func existing(directory: String, sound: Dictionary) -> Dictionary:
	var files = manifest(directory).get("files", {})
	if not files is Dictionary:
		return {}
	for value in files.values():
		if value is Dictionary and value.get("sfxmint_id", "") == identity(sound):
			var path := str(value.get("resource_path", directory.path_join(str(value.get("file", "")))))
			if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == value.get("sha256", ""):
				return value
	return {}

func stage(directory: String, sound: Dictionary, bytes: PackedByteArray) -> Dictionary:
	if not safe_directory(directory):
		return {"error": "Choose a project directory outside addons/."}
	var path := directory.path_join("sounds.json")
	var m := manifest(directory)
	if FileAccess.file_exists(path) and (m.is_empty() or not m.get("files") is Dictionary):
		return {"error": "Existing sounds.json is not a compatible manifest; choose another directory."}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var digest := hash.finish().hex_encode()
	var expected := str(sound.get("sha256", ""))
	if not expected.is_empty() and digest != expected:
		return {"error": "Checksum mismatch. No file was imported."}
	var format := str(sound.get("format", "wav"))
	if format == "wav":
		if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
			return {"error": "The response is not a WAV audio file."}
		if bytes.decode_u32(4) + 8 > bytes.size():
			return {"error": "The WAV download is incomplete. No file was imported."}
	elif format == "ogg":
		if bytes.size() < 27 or bytes.slice(0, 4).get_string_from_ascii() != "OggS" or AudioStreamOggVorbis.load_from_buffer(bytes) == null:
			return {"error": "The response is not a valid OGG audio file."}
	else:
		return {"error": "Unsupported import format."}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return {"error": "Cannot create the import directory."}
	var basename := safe_name(str(sound.get("title", sound.get("slug", "sound"))))
	if sound.get("variant", "original") != "original": basename += "-" + safe_name(str(sound.variant))
	var file_name := basename + "-" + digest.left(8) + "." + format
	var n := 2
	while FileAccess.file_exists(directory.path_join(file_name)):
		file_name = basename + "-" + digest.left(8) + "-" + str(n) + "." + format
		n += 1
	var target := directory.path_join(file_name)
	var temp := root.path_join("import-" + digest + ".tmp")
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return {"error": "Cannot write the temporary download."}
	f.store_buffer(bytes)
	f.close()
	# Copy can cross disks; destination is newly chosen and never overwrites a user file.
	var err := DirAccess.copy_absolute(temp, ProjectSettings.globalize_path(target))
	DirAccess.remove_absolute(temp)
	if err != OK:
		return {"error": "Cannot write the audio into the project."}
	return {"path": target, "sha256": digest, "bytes": bytes.size()}

func commit_import(directory: String, sound: Dictionary, staged: Dictionary) -> Dictionary:
	var m := manifest(directory)
	if FileAccess.file_exists(directory.path_join("sounds.json")) and (m.is_empty() or not m.get("files") is Dictionary):
		return {"error": "Manifest changed during import; audio retained, manifest not overwritten."}
	if m.is_empty():
		m = {"version": 2, "generated_by": "sfxmint-godot/0.2", "origin": "https://sfxmint.com", "base": "", "content_notice": NOTICE, "files": {}}
	if not m.get("files") is Dictionary:
		return {"error": "Manifest changed during import; audio retained, manifest not overwritten."}
	var entry := {
		"file": str(staged.path).get_file(), "resource_path": staged.path,
		"slug": sound.get("slug", ""), "title": sound.get("title", "Sound"), "label": null,
		"format": sound.get("format", "wav"), "duration_ms": sound.get("duration_ms"), "loopable": sound.get("loopable", false),
		"kind": sound.get("kind", "sound"), "variant": sound.get("variant", "original"),
		"sha256": staged.sha256, "bytes": staged.bytes,
		"source_url": sound.get("wav_url", "") if not sound.has("order_id") else "",
		"page_url": sound.get("page_url"), "license": sound.get("license", "CC0-1.0"),
		"content_check": {"status": "unverified"}, "unverified_requirements": sound.get("unverified_requirements", []),
		"sfxmint_id": identity(sound), "ai_generated": true,
	}
	if sound.has("order_id"):
		entry["order_id"] = sound.order_id
		entry["take"] = sound.index
		entry["license_text"] = sound.get("license_text", "")
	if sound.get("loop_cut") is Dictionary: entry["loop_cut"] = sound.loop_cut
	if sound.get("detail_labels") is Array: entry["detail_labels"] = sound.detail_labels
	var entry_key := str(staged.path).get_file().get_basename()
	while m.files.has(entry_key):
		entry_key += "_2"
	m.files[entry_key] = entry
	# A mixed manifest must not claim that user-supplied audio is public domain.
	m.version = 2
	m.license = "CC0-1.0" if m.files.values().all(func(item): return item is Dictionary and item.get("license") == "CC0-1.0") else "Per-file; see files"
	if m.license != "CC0-1.0": m.erase("license_url")
	if atomic_text(directory.path_join("sounds.json"), JSON.stringify(m, "\t")) != OK:
		return {"error": "Audio imported, but sounds.json could not be saved."}
	var doc_error := write_markdown(directory, m)
	return {"entry": entry, "warning": doc_error}

static func write_markdown(directory: String, m: Dictionary) -> String:
	var path := directory.path_join("SOUNDS.md")
	var old := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "# Project sounds\n"
	var section := BEGIN + "\n\n## SFXMint imports\n\n" + NOTICE + "\n\n| Sound | File | License |\n|---|---|---|\n"
	for item in m.files.values():
		if item is Dictionary and item.has("sfxmint_id"):
			section += "| %s | `%s` | %s |\n" % [str(item.title).replace("|", "\\|").replace("\n", " "), str(item.resource_path).replace("|", "\\|"), item.license]
	section += "\nSee sounds.json for hashes and source identifiers. Select and listen before wiring these files to game events.\n\n" + END
	var start := old.find(BEGIN)
	var end := old.find(END)
	if (start >= 0) != (end >= 0) or (start >= 0 and end < start):
		return "SOUNDS.md has incomplete managed markers; left unchanged."
	var updated := old.substr(0, start) + section + old.substr(end + END.length()) if start >= 0 else old + "\n" + section + "\n"
	return "SOUNDS.md could not be saved." if atomic_text(path, updated) != OK else ""

func relocate(directory: String, entry: Dictionary, new_path: String) -> String:
	if not new_path.begins_with("res://") or not FileAccess.file_exists(new_path) or FileAccess.get_sha256(new_path) != entry.get("sha256", ""):
		return "Choose the same audio file inside this project (checksum must match)."
	var m := manifest(directory)
	for value in m.get("files", {}).values():
		if value is Dictionary and value.get("sfxmint_id") == entry.get("sfxmint_id"):
			value.resource_path = new_path
			value.file = new_path.trim_prefix(directory.trim_suffix("/") + "/")
	if atomic_text(directory.path_join("sounds.json"), JSON.stringify(m, "\t")) != OK:
		return "Cannot update sounds.json."
	return write_markdown(directory, m)
