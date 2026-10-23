@tool
extends Node

const DEFAULT_ORIGIN = "https://sfxmint.com"
const MAX_BYTES = 128 * 1024 * 1024
var origin := DEFAULT_ORIGIN
var key := ""
var alive := true
var timeout := 45.0
var requests: Array[HTTPRequest] = []

func _init() -> void:
	# Only the development harness uses a loopback server. No editable remote endpoint.
	var test_origin := OS.get_environment("SFXMINT_TEST_ORIGIN").trim_suffix("/")
	if test_origin.begins_with("http://127.0.0.1:") and test_origin.get_slice(":", 2).is_valid_int():
		origin = test_origin

func api(path: String, method := HTTPClient.METHOD_GET, body: Dictionary = {}, authenticated := false, candidate_key := "") -> Dictionary:
	if not path.begins_with("/api/v1/") or path.contains(".."):
		return {"ok": false, "error": "invalid_path", "status": 0}
	var url := origin + path + ("&" if path.contains("?") else "?") + "via=godot"
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: SFXMint-Godot/0.2"])
	if authenticated:
		var secret := candidate_key if not candidate_key.is_empty() else key
		if secret.is_empty():
			return {"ok": false, "error": "api_key_required", "status": 401}
		headers.append("Authorization: Bearer " + secret)
	var payload := ""
	if method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var result: Dictionary = await _request(url, headers, method, payload)
	return _json_result(result)

func upload_audio(bytes: PackedByteArray, source: String) -> Dictionary:
	if key.is_empty(): return {"ok": false, "error": "api_key_required", "status": 401}
	if source not in ["upload", "record"]: return {"ok": false, "error": "invalid_source", "status": 400}
	var headers := PackedStringArray(["Content-Type: audio/wav", "Authorization: Bearer " + key, "User-Agent: SFXMint-Godot/0.2"])
	return _json_result(await _request(origin + "/api/v1/uploads?via=godot&rights=1&source=" + source, headers, HTTPClient.METHOD_POST, bytes))

func _json_result(result: Dictionary) -> Dictionary:
	if not result.has("bytes"):
		return result
	var parsed = JSON.parse_string(result.bytes.get_string_from_utf8())
	result.erase("bytes")
	if not parsed is Dictionary:
		result.ok = false
		result.error = "invalid_response"
		return result
	result.data = parsed
	if not result.ok:
		result.error = str(parsed.get("error", "request_failed"))
	return result

func download(url: String) -> Dictionary:
	if url.begins_with("/") and not url.begins_with("//"):
		url = origin + url
	# Signed audio URLs contain their authorization; NEVER attach the account key.
	if not url.begins_with("https://") and not url.begins_with(origin + "/"):
		return {"ok": false, "error": "unsafe_download_url", "status": 0}
	return await _request(url, PackedStringArray(["User-Agent: SFXMint-Godot/0.2"]), HTTPClient.METHOD_GET, "")

func _request(url: String, headers: PackedStringArray, method: int, body: Variant) -> Dictionary:
	if not alive:
		return {"ok": false, "error": "closed", "status": 0}
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.body_size_limit = MAX_BYTES
	# Do not forward auth or signed URL parameters across redirects.
	http.max_redirects = 0
	add_child(http)
	requests.append(http)
	var err := http.request_raw(url, headers, method, body) if body is PackedByteArray else http.request(url, headers, method, body)
	if err != OK:
		requests.erase(http)
		http.queue_free()
		return {"ok": false, "error": "connection_failed", "status": 0}
	var response: Array = await http.request_completed
	requests.erase(http)
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "connection_interrupted", "status": 0}
	return {"ok": int(response[1]) >= 200 and int(response[1]) < 300, "status": int(response[1]), "bytes": response[3]}

func shutdown() -> void:
	alive = false
	key = ""
	for http in requests.duplicate():
		if is_instance_valid(http):
			http.cancel_request()
			http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
	requests.clear()
