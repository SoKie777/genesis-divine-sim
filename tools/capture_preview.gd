extends SceneTree
## Capture un aperçu haute résolution de l'interface et du monde isométrique 2.5D.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main_ui: Control = packed.instantiate()
	root.add_child(main_ui)
	await process_frame
	main_ui.sim.step_ticks(720)
	main_ui._modal_help.visible = false
	main_ui._select_dock_category("MIRACLES")
	main_ui._refresh_all_ui()
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var out_path: String = ProjectSettings.globalize_path("res://assets/sprites/preview_ingame.png")
		img.save_png(out_path)
		print("[PREVIEW] Saved to: ", out_path)
	quit(0)
