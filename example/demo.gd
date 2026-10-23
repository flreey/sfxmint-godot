extends Control
# A small game event demonstration. Only local imported resources are played.
var player: AudioStreamPlayer
var info: Label
var selected: OptionButton
var files: Array[String] = []
var coins := 0

func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 240)
	center.add_child(box)
	var title := Label.new()
	title.text = "SFXMint • Coin pickup demo"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	info = Label.new()
	info.text = "Import a sound with the SFXMint dock, then run this scene."
	box.add_child(info)
	selected = OptionButton.new()
	box.add_child(selected)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://audio/sfxmint/sounds.json")) if FileAccess.file_exists("res://audio/sfxmint/sounds.json") else {}
	if manifest is Dictionary:
		for item in manifest.get("files", {}).values():
			var path := str(item.get("resource_path", ""))
			if ResourceLoader.exists(path):
				files.append(path)
				selected.add_item(str(item.get("title", path)))
	var button := Button.new()
	button.text = "Pick up coin [Space]"
	button.custom_minimum_size.y = 64
	button.pressed.connect(_pickup)
	box.add_child(button)
	button.grab_focus()

func _pickup() -> void:
	coins += 1
	info.text = "Coins: %s — local audio; no network or plugin needed" % coins
	if not files.is_empty():
		player.stream = load(files[selected.selected])
		player.play()
