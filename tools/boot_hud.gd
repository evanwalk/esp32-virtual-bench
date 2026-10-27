extends SceneTree

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	print("status=", main.hud.status_label.text)
	print("findings=", main.hud.label.text.replace("\n", " | "))
	print("prompt=", main.hud.prompt_label.text)
	quit(0)
