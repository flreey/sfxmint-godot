@tool
extends RefCounted
# The selected file variant is the single source of truth for audition and import.

static func string(value: Variant) -> String:
	return value if value is String else ""

static func kind_label(kind: String) -> String:
	return {"sound": "Sound", "ambience": "Ambience", "music": "BGM"}.get(kind, "Sound")

static func clock(seconds: float) -> String:
	if seconds >= 60:
		return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	return ("%.1f" % seconds).trim_suffix(".0") + " s"

static func with_format(url: String, format: String) -> String:
	if url.is_empty() or format == "wav": return url
	return url + ("&" if url.contains("?") else "?") + "format=" + format

static func variants(file: Dictionary) -> Array:
	var choices: Array = []
	var detail = file.get("details")
	if detail is Dictionary and not string(file.get("details_play_url")).is_empty():
		choices.append({"id": "details", "label": "With details", "seconds": float(detail.get("seconds", 0))})
	var cut = file.get("loop_cut")
	# A full preview is not a preview of a prepared loop. Do not silently substitute it.
	if cut is Dictionary and not string(file.get("loop_url")).is_empty():
		choices.append({"id": "loop", "label": "Plain loop", "seconds": float(cut.get("seconds", 0))})
	choices.append({"id": "original", "label": "Original", "seconds": float(file.get("duration_s", 0))})
	return choices

static func from_take(task: Dictionary, file: Dictionary, detail: Dictionary, account: String, variant := "", format := "wav") -> Dictionary:
	var choices := variants(file)
	if variant.is_empty(): variant = choices[0].id
	var chosen: Dictionary = {}
	for choice in choices:
		if choice.id == variant: chosen = choice
	if chosen.is_empty(): return {"error": "This file version is no longer available. Choose another version."}
	if format not in ["wav", "ogg"] or (format == "ogg" and not file.get("ogg", false)):
		return {"error": "This format is not available for this take. Choose WAV."}
	var original_url := string(file.get("url"))
	var url := string(file.get({"original": "url", "loop": "loop_url", "details": "details_url"}[variant]))
	var preview := string(file.get({"original": "preview_url", "loop": "loop_url", "details": "details_play_url"}[variant]))
	# Entitled playback uses the very same version/format that will be imported.
	url = with_format(url, format)
	if not url.is_empty(): preview = url
	var order: Dictionary = detail.get("order", task)
	var kind := string(order.get("kind", task.get("kind", "sound")))
	var license_text := string(detail.get("license"))
	var license_id := string(detail.get("license_id"))
	if license_id.is_empty():
		if license_text.contains("License: CC0 1.0") or license_text.begins_with("CC0-1.0"):
			license_id = "CC0-1.0"
		elif license_text.contains("no CC0 dedication"):
			license_id = "LicenseRef-User-Supplied"
		else:
			license_id = "See license text" if not license_text.is_empty() else "Unknown"
	var take_label := "Take" if kind == "sound" else "Track"
	return {
		"order_id": task.id, "index": int(file.index), "account_id": account,
		"kind": kind, "variant": variant, "variant_label": chosen.label, "format": format,
		"title": "%s — %s %d" % [order.get("prompt", task.get("prompt", "Sound")), take_label, int(file.index)],
		"label": string(file.get("label")), "duration_ms": chosen.seconds * 1000.0,
		"preview_url": preview, "url": url,
		# The server hash describes only the original WAV, never its derived files.
		"sha256": string(file.get("sha256")) if variant == "original" and format == "wav" else "",
		"license": license_id, "license_text": license_text,
		"loopable": variant == "loop" or (variant == "original" and file.get("loop", false)),
		"loop_cut": file.get("loop_cut") if variant == "loop" else null,
		"detail_labels": file.get("details", {}).get("labels", []) if file.get("details") is Dictionary and variant == "details" else [],
		"favorite": bool(file.get("favorite", false)), "locked": original_url.is_empty(),
		"variants": choices, "ogg": bool(file.get("ogg", false)),
		"peaks": file.get("peaks", []) if variant == "original" else [],
	}

static func decode(bytes: PackedByteArray) -> AudioStream:
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	if magic == "RIFF": return AudioStreamWAV.load_from_buffer(bytes)
	if magic == "OggS": return AudioStreamOggVorbis.load_from_buffer(bytes)
	return AudioStreamMP3.load_from_buffer(bytes)
