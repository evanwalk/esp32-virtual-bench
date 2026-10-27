extends SceneTree

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.load_scenario("blink")
	main.power.request_power_on()
	await process_frame
	main.view.apply_electrical_state()
	await process_frame
	var cam: Camera3D = main.rig.flat_camera
	var led: Node3D = main.view.part_nodes["led1"]
	print("led world=", led.global_position, " screen=", cam.unproject_position(led.global_position))
	print("led_ua=", main.power.solver.element_ua("led1"))
	print("hud text=", main.hud.label.text.replace("\n", " | "))
	print("hud status=", main.hud.status_label.text)
	quit(0)
