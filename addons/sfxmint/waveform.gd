@tool
extends Control
# Only measured data is drawn. Unloaded/unsupported data remains an explicit empty state.
var peaks := PackedFloat32Array()
var fraction := 0.0
var active := false

func _ready() -> void:
	custom_minimum_size = Vector2(80, 28)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_peaks(values: Variant) -> void:
	peaks.clear()
	if values is Array or values is PackedFloat32Array:
		for v in values: peaks.append(clampf(float(v), 0.0, 1.0))
	queue_redraw()

func _draw() -> void:
	var muted := Color(get_theme_color("font_color", "Label"), 0.5)
	var accent := get_theme_color("accent_color", "Editor") if has_theme_color("accent_color", "Editor") else get_theme_color("font_focus_color", "Button")
	if peaks.is_empty():
		draw_line(Vector2(0, size.y / 2), Vector2(size.x, size.y / 2), muted, 1)
		return
	var count := mini(peaks.size(), maxi(1, int(size.x / 4)))
	for i in range(count):
		var amplitude := 0.0
		for j in range(i * peaks.size() / count, maxi(i * peaks.size() / count + 1, (i + 1) * peaks.size() / count)):
			amplitude = maxf(amplitude, peaks[j])
		var h := maxf(2, amplitude * size.y)
		var x := (i + 0.5) * size.x / count
		draw_line(Vector2(x, (size.y - h) / 2), Vector2(x, (size.y + h) / 2), accent if active and float(i) / count <= fraction else muted, 2)

static func measure_wav(stream: AudioStreamWAV, bins := 180) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	var data := stream.data
	if stream.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]: return output
	var width := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var count := data.size() / width
	if count == 0: return output
	for i in range(bins):
		var high := 0.0
		var begin := i * count / bins
		var end := (i + 1) * count / bins
		# Bound work for long ambience; measure actual samples, never generated artwork.
		var step := maxi(1, (end - begin) / 256)
		for sample in range(begin, end, step):
			var amplitude := absf(float(data.decode_s16(sample * 2)) / 32768.0) if width == 2 else absf(float(data[sample] - 128) / 128.0)
			high = maxf(high, amplitude)
		output.append(high)
	return output

static func measure(stream: AudioStream, bins := 180) -> PackedFloat32Array:
	if stream is AudioStreamWAV:
		var direct := measure_wav(stream, bins)
		if not direct.is_empty(): return direct
	# A separate decoder leaves the audible playback untouched. Sample bounded windows
	# across the real compressed file rather than allocating the entire decoded track.
	var decoder := stream.instantiate_playback()
	var output := PackedFloat32Array()
	if decoder == null or stream.get_length() <= 0: return output
	decoder.start()
	for i in range(bins):
		decoder.seek(float(i) * stream.get_length() / bins)
		var samples := decoder.mix_audio(1.0, 256)
		var peak := 0.0
		for sample in samples: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		output.append(clampf(peak, 0.0, 1.0))
	decoder.stop()
	return output
