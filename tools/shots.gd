## Screenshot harness: renders each scenario under Xvfb and writes PNGs.
##
## Proves the app actually draws (and lets layout be eyeballed) without a headset. Each
## capture waits real frames after loading a scenario, otherwise every shot captures the
## previous scene and they all come out identical.
##
##   xvfb-run -a godot --rendering-driver opengl3 --xr-mode off --script res://tests/shots.gd
extends SceneTree

const OUT := "/tmp/shots"
const SCENARIOS := ["blink", "five_volt", "rail_short", "led_backwards"]
const SETTLE := 12

var main: Node3D
var index := 0
var wait := 20
var _armed := false

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	wait -= 1
	if wait > 0:
		return false
	if index >= SCENARIOS.size():
		print("SHOTS_DONE")
		return true

	var key: String = SCENARIOS[index]
	if not _armed:
		main.load_scenario(key)
		if key == "blink":
			main.power.request_power_on()
		main.hud.show_findings(main.power.findings, main.power.status_line(), main.power.last_refusal)
		main.view.apply_electrical_state()
		_armed = true
		wait = SETTLE
		return false

	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, key])
	print("SHOT %s" % key)
	_armed = false
	index += 1
	wait = 4
	return false
