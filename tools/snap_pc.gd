extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main_ui: Control = packed.instantiate()
	root.add_child(main_ui)
	for i in range(15):
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png("C:/Users/Chris Eric/.gemini/antigravity/scratch/genesis-divine-sim/pc_snap.png")
		print("[SNAP] Saved pc_snap.png successfully! Size: ", img.get_size())
	quit(0)
