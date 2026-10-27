## Entry point: builds the world, wires input, and hosts the scenario switch.
##
## Input is deliberately narrow — trigger to act, grip to cycle scenarios — because the
## whole point is that the circuit, not the controls, is the hard part.
extends Node3D

const SCENARIO_ORDER := ["blink", "five_volt", "rail_short", "led_backwards", "no_ground"]

var rig: Node3D
var view: BenchView
var hud: Node3D
var controller: BenchController
var power: PowerController
var bench: Bench
var scenario_index := 0
var table: Node3D
var light: OmniLight3D
var env: WorldEnvironment

func _ready() -> void:
	_build_environment()
	if OS.has_feature("editor") and "--shot" in OS.get_cmdline_user_args():
		pass
	rig = load("res://scenes/xr_rig.gd").new()
	rig.name = "XRRig"
	add_child(rig)

	view = BenchView.new()
	view.name = "BenchView"
	add_child(view)
	# Sit the bench geometry on the table surface.
	view.position = Vector3(0, 0.74, -0.20)

	hud = load("res://scenes/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

	controller = BenchController.new()
	controller.name = "BenchController"
	add_child(controller)

	light = OmniLight3D.new()
	light.name = "LedLight"
	light.position = Vector3(0, 0.25, -0.1)
	light.omni_range = 0.6
	light.light_color = Color(1.0, 0.55, 0.35)
	light.light_energy = 0.0
	add_child(light)

	hud.setup(controller)
	load_scenario(SCENARIO_ORDER[0])
	controller.setup(bench, power, view, hud)

func _build_environment() -> void:
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	var e := env.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.062, 0.078)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.72)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.name = "WorldEnvironment"
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.5, 0.9, 0.6)
	fill.light_energy = 0.7
	fill.omni_range = 3.0
	add_child(fill)

	table = Node3D.new()
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.04, 0.62)
	top.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.18, 0.20)
	mat.roughness = 0.92
	top.material_override = mat
	table.add_child(top)
	table.position = Vector3(0, 0.72, -0.20)
	add_child(table)

func load_scenario(key: String) -> void:
	if power != null and power.findings_updated.is_connected(_on_scenario_findings):
		power.findings_updated.disconnect(_on_scenario_findings)
	bench = Scenario.build(key)
	power = PowerController.new(bench)
	power.findings_updated.connect(_on_scenario_findings)
	view.build(bench, power.solver)
	view.refresh_parts()
	view.refresh_wires()
	view.apply_electrical_state()
	if controller != null:
		controller.bench = bench
		controller.power = power
		controller.solver = power.solver
		# Re-bind so live edits repaint this scenario, not the previous one.
		controller.attach(power)
	power.evaluate()
	if hud.has_method("set_prompt"):
		hud.set_prompt("Scenario: %s — grip to cycle, switch on the panel to power" % Scenario.NAMES[key])

## Refresh the HUD from a scenario swap (the controller only repaints the live bench).
func _on_scenario_findings(findings: Array) -> void:
	if hud.has_method("show_findings"):
		hud.show_findings(findings, power.status_line(), power.last_refusal)

func _next_scenario() -> void:
	scenario_index = (scenario_index + 1) % SCENARIO_ORDER.size()
	load_scenario(SCENARIO_ORDER[scenario_index])

## Hit result of whichever hand is pointing; falls back to the flat camera's centre ray.
func _aim_point() -> Node:
	var ray: RayCast3D = null
	if rig != null and rig.has_method("primary_ray"):
		ray = rig.primary_ray()
	if ray == null or not ray.is_colliding():
		return null
	return ray.get_collider()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("trigger"):
		_activate(_aim_point())
	elif event.is_action_pressed("cycle_scenario"):
		_next_scenario()

func _activate(target: Node) -> void:
	if target == null:
		if controller.held_part != null:
			controller.held_part = null
			hud.set_prompt("Placement cancelled")
		elif controller.wire_anchor != "":
			controller.wire_anchor = ""
			hud.set_prompt("Wire cancelled")
		return
	if target.has_meta("power_switch"):
		controller.toggle_power()
		return
	if target.has_meta("spawn"):
		match String(target.get_meta("spawn")):
			"led": controller.spawn_led("red")
			"r330": controller.spawn_resistor(330.0)
			"r1k": controller.spawn_resistor(1000.0)
			"button": controller.spawn_button()
		return
	if target.has_meta("wire"):
		controller.remove_wire_at(String(target.get_meta("wire")))
		return
	if target.has_meta("part") or (target.get_parent() != null and target.get_parent().has_meta("part")):
		var part_node := target if target.has_meta("part") else target.get_parent()
		var part_id := String(part_node.get_meta("part"))
		if bench.button_state.has(part_id):
			controller.toggle_button(part_id)
		else:
			controller.lift_at(part_id)
		return
	if target.has_meta("terminal"):
		var terminal := String(target.get_meta("terminal"))
		if controller.held_part != null:
			controller.seat_held(terminal)
		else:
			controller.toggle_wire(terminal)
