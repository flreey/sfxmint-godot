@tool
extends EditorPlugin

const SoundPanel = preload("panel.gd")
const ExportGuard = preload("export_guard.gd")
var panel: Control
var dock: EditorDock
var guard: EditorExportPlugin

func _enter_tree() -> void:
	guard = ExportGuard.new()
	add_export_plugin(guard)
	panel = SoundPanel.new()
	dock = EditorDock.new()
	dock.title = "SFXMint"
	dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL
	dock.add_child(panel)
	add_dock(dock)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.shutdown()
	if is_instance_valid(dock):
		remove_dock(dock)
		dock.queue_free()
	if guard:
		remove_export_plugin(guard)
