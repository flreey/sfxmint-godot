@tool
extends Node
signal selected(source: Dictionary)
signal upload_requested(bytes: PackedByteArray, source: String, name: String)
signal closed
const Sound = preload("sound.gd")
var dialog: Window
var message: Label
var rights: CheckBox
var use_button: Button
var bytes := PackedByteArray()
var source_kind := "upload"
var source_name := ""
var microphone: AudioStreamPlayer
var effect: AudioEffectRecord
var bus_name := ""
var record_button: Button
var started := 0.0

func setup(host: Control, takes: Array, library: Array) -> void:
	dialog = Window.new()
	dialog.title = "Start from audio"
	dialog.size = Vector2i(Vector2(640, 440) * host.ui_scale)
	dialog.min_size = Vector2i(Vector2(540, 380) * host.ui_scale)
	if Engine.is_editor_hint(): dialog.theme = EditorInterface.get_editor_theme()
	dialog.transient = true
	dialog.exclusive = true
	dialog.visible = false
	host.add_child(dialog)
	dialog.close_requested.connect(shutdown)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	dialog.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	for group in [{"name": "Your takes", "items": takes}, {"name": "Library", "items": library}]:
		var scroll := ScrollContainer.new()
		scroll.name = group.name
		tabs.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		if group.items.is_empty(): label(rows, "No eligible sounds yet. Generate a Sound or search the Library first.")
		for item in group.items:
			var choice := Button.new()
			choice.text = str(item.get("name", "Sound"))
			choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
			choice.clip_text = true
			choice.pressed.connect(func(): selected.emit(item); shutdown())
			rows.add_child(choice)
	var upload := VBoxContainer.new()
	upload.name = "Upload"
	tabs.add_child(upload)
	label(upload, "Choose WAV, OGG or MP3, up to 10 seconds. Your source rights apply to the result.")
	var choose := Button.new()
	choose.text = "Choose audio file…"
	choose.pressed.connect(pick_file)
	upload.add_child(choose)
	var record := VBoxContainer.new()
	record.name = "Record"
	tabs.add_child(record)
	label(record, "Record up to 10 seconds from your input device. Enable Audio > Driver > Enable Input in Project Settings first.")
	record_button = Button.new()
	record_button.text = "Start recording"
	record_button.pressed.connect(toggle_recording)
	record.add_child(record_button)
	message = label(box, "")
	rights = CheckBox.new()
	rights.text = "I have the rights to use this uploaded or recorded audio."
	rights.toggled.connect(func(_value): use_button.disabled = bytes.is_empty() or not rights.button_pressed)
	box.add_child(rights)
	use_button = Button.new()
	use_button.text = "Use this audio"
	use_button.disabled = true
	use_button.pressed.connect(func():
		if bytes.is_empty() or not rights.button_pressed: return
		use_button.disabled = true
		upload_requested.emit(bytes, source_kind, source_name))
	box.add_child(use_button)
	dialog.popup_centered()

func label(parent: Node, text: String) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

func pick_file() -> void:
	var picker := EditorFileDialog.new()
	picker.access = EditorFileDialog.ACCESS_FILESYSTEM
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	picker.add_filter("*.wav, *.ogg, *.mp3", "Audio (up to 10 seconds)")
	dialog.add_child(picker)
	picker.file_selected.connect(func(path):
		picker.queue_free()
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 32 * 1024 * 1024:
			message.text = "Cannot read this audio, or the file exceeds 32 MB."
			return
		var stream := Sound.decode(file.get_buffer(file.get_length()))
		if stream == null or stream.get_length() <= 0 or stream.get_length() > 10.01:
			message.text = "Choose decodable audio between 0 and 10 seconds."
			return
		set_audio(to_wav(stream), "upload", path.get_file()))
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.65)

static func to_wav(stream: AudioStream) -> PackedByteArray:
	var playback := stream.instantiate_playback()
	if playback == null: return PackedByteArray()
	var mix_rate := float(AudioServer.get_mix_rate())
	var count := mini(int(stream.get_length() * mix_rate), int(10 * mix_rate))
	playback.start()
	var pcm := PackedByteArray()
	pcm.resize(count * 4)
	var offset := 0
	while offset < count:
		var frames := playback.mix_audio(1.0, mini(1024, count - offset))
		if frames.is_empty(): break
		for frame in frames:
			if offset >= count: break
			pcm.encode_s16(offset * 4, clampi(int(frame.x * 32767.0), -32768, 32767))
			pcm.encode_s16(offset * 4 + 2, clampi(int(frame.y * 32767.0), -32768, 32767))
			offset += 1
	playback.stop()
	pcm.resize(offset * 4)
	return wav_bytes(pcm, int(mix_rate), true)

static func wav_bytes(pcm: PackedByteArray, rate: int, stereo: bool) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(44)
	for item in [[0, "RIFF"], [8, "WAVE"], [12, "fmt "], [36, "data"]]:
		var tag: PackedByteArray = item[1].to_ascii_buffer()
		for i in range(4): data[item[0] + i] = tag[i]
	var channels := 2 if stereo else 1
	data.encode_u32(4, 36 + pcm.size())
	data.encode_u32(16, 16)
	data.encode_u16(20, 1)
	data.encode_u16(22, channels)
	data.encode_u32(24, rate)
	data.encode_u32(28, rate * channels * 2)
	data.encode_u16(32, channels * 2)
	data.encode_u16(34, 16)
	data.encode_u32(40, pcm.size())
	data.append_array(pcm)
	return data

func set_audio(value: PackedByteArray, kind: String, title: String) -> void:
	bytes = value
	source_kind = kind
	source_name = title
	rights.button_pressed = false
	use_button.disabled = true
	message.text = title + " — confirm your source rights below."

func toggle_recording() -> void:
	if is_instance_valid(microphone):
		stop_recording()
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		message.text = "Enable audio input in Project Settings and restart the editor before recording."
		return
	bus_name = "SFXMintCapture_" + str(get_instance_id())
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, bus_name)
	AudioServer.set_bus_mute(bus, true)
	effect = AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, effect)
	microphone = AudioStreamPlayer.new()
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = bus_name
	add_child(microphone)
	microphone.play()
	effect.set_recording_active(true)
	started = Time.get_ticks_msec() / 1000.0
	record_button.text = "Stop recording"

func _process(_delta: float) -> void:
	if is_instance_valid(microphone):
		var elapsed := Time.get_ticks_msec() / 1000.0 - started
		message.text = "Recording %.1f / 10 seconds…" % elapsed
		if elapsed >= 10: stop_recording()

func stop_recording() -> void:
	if not is_instance_valid(microphone): return
	effect.set_recording_active(false)
	var captured := effect.get_recording()
	microphone.stop()
	remove_child(microphone)
	microphone.queue_free()
	microphone = null
	var bus := AudioServer.get_bus_index(bus_name)
	if bus >= 0: AudioServer.remove_bus(bus)
	bus_name = ""
	record_button.text = "Start recording"
	if captured and captured.get_length() > 0:
		var pcm: PackedByteArray = captured.data.slice(0, int(captured.mix_rate * 10) * (4 if captured.stereo else 2))
		set_audio(wav_bytes(pcm, captured.mix_rate, captured.stereo), "record", "Microphone recording")
	else: message.text = "No audio captured. Check your microphone and system permission."

func shutdown() -> void:
	stop_recording()
	bytes.clear()
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()
	closed.emit()
	queue_free()
