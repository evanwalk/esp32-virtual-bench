extends SceneTree

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	print("parts at boot=", main.bench.parts.keys())
	print("wires at boot=", main.bench.wires.size())
	quit(0)
