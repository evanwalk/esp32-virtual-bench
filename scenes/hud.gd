## World-anchored HUD: power switch, part palette, findings panel, and status.
##
## Lives on a quad in the scene (not a screen-space CanvasLayer) so it stays readable in
## VR at arm's length. Findings are colour-tiered and show reason + fix, which is the
## point of the app: the panel explains the fault, it does not just say "wrong".
extends Node3D

const PANEL_WIDTH := 1024
const PANEL_HEIGHT := 640
const MAX_ROWS := 6

const COLOR_ERROR := Color(1.0, 0.36, 0.31)
const COLOR_WARN := Color(1.0, 0.76, 0.28)
const COLOR_INFO := Color(0.55, 0.78, 1.0)
const COLOR_OK := Color(0.44, 0.92, 0.62)
const COLOR_DIM := Color(0.72, 0.75, 0.80)

var controller: BenchController
var label: Label3D
var switch_label: Label3D
var status_label: Label3D
var prompt_label: Label3D
var panel: MeshInstance3D
var switch_mesh: MeshInstance3D

func setup(p_controller: BenchController) -> void:
	controller = p_controller
	_build()

func _build() -> void:
	# Panel floats above the far edge of the bench, angled down at the user, so it never
	# covers the circuit being worked on but stays in view.
	position = Vector3(0, 1.15, -0.30)
	rotation_degrees = Vector3(-20, 0, 0)

	panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.58, 0.24)
	panel.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.06, 0.08, 0.94)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	panel.material_override = mat
	add_child(panel)

	status_label = _make_label(Vector2(-0.272, 0.098), 22, COLOR_DIM)
	status_label.text = "POWER OFF"
	add_child(status_label)

	label = _make_label(Vector2(-0.272, 0.062), 11, COLOR_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = 230.0
	label.text = "Bench empty. Spawn a part, then pull the trigger on two holes across the centre channel."
	add_child(label)

	prompt_label = _make_label(Vector2(-0.272, -0.082), 10, COLOR_INFO)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.width = 230.0
	add_child(prompt_label)

	switch_label = _make_label(Vector2(-0.272, -0.106), 11, COLOR_OK)
	switch_label.text = "[ switch ]"
	add_child(switch_label)

	_build_switch()
	_build_palette()

func _make_label(pos: Vector2, size_px: int, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.position = Vector3(pos.x, pos.y, 0.001)
	l.font_size = size_px
	l.pixel_size = 0.0022
	l.modulate = colour
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.text = ""
	return l

## The power switch is a real object you aim at and pull the trigger on.
func _build_switch() -> void:
	var body := Area3D.new()
	body.name = "PowerSwitch"
	body.set_meta("power_switch", true)
	body.position = Vector3(0.215, -0.082, 0.02)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.09, 0.05, 0.03)
	shape.shape = box
	body.add_child(shape)

	switch_mesh = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.04, 0.02)
	switch_mesh.mesh = mesh
	switch_mesh.material_override = _mat(Color(0.12, 0.14, 0.17))
	body.add_child(switch_mesh)
	add_child(body)

## Part palette: aim and trigger to spawn.
func _build_palette() -> void:
	var defs := [
		{"label": "LED", "action": "led"},
		{"label": "330R", "action": "r330"},
		{"label": "1k", "action": "r1k"},
		{"label": "BUTTON", "action": "button"},
	]
	var origin := Vector3(-0.238, -0.082, 0.02)
	for i in range(defs.size()):
		var d: Dictionary = defs[i]
		var area := Area3D.new()
		area.set_meta("spawn", d["action"])
		area.position = origin + Vector3(i * 0.062, 0, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.065, 0.035, 0.02)
		shape.shape = box
		area.add_child(shape)
		var chip := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.06, 0.03, 0.012)
		chip.mesh = cm
		chip.material_override = _mat(Color(0.16, 0.19, 0.24))
		area.add_child(chip)
		var text := _make_label(Vector2(0, 0), 10, COLOR_DIM)
		text.text = d["label"]
		text.position = Vector3(0, 0, 0.008)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		area.add_child(text)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m

# --- updates --------------------------------------------------------------------------

func show_findings(findings: Array, status: String, refusal: String) -> void:
	var lines: Array[String] = []
	for f in findings:
		if f.level == Severity.Level.INFO:
			continue
		if lines.size() >= MAX_ROWS:
			lines.append("  ... %d more" % (findings.size() - lines.size()))
			break
		lines.append("%s  %s\n    %s\n    FIX: %s" % [Severity.LABEL[f.level], f.message, f.reason, f.fix])
	if lines.is_empty():
		label.modulate = COLOR_OK
		label.text = "No faults detected."
	else:
		label.modulate = COLOR_WARN
		label.text = "\n".join(lines)
	if refusal != "":
		status_label.text = "REFUSED — see faults"
		status_label.modulate = COLOR_ERROR
	else:
		status_label.text = status
		status_label.modulate = COLOR_OK if status == "POWER ON" else COLOR_DIM
	var live := status == "POWER ON"
	(switch_mesh.material_override as StandardMaterial3D).albedo_color = (
		Color(0.10, 0.32, 0.16) if live else Color(0.12, 0.14, 0.17)
	)

func set_prompt(text: String) -> void:
	prompt_label.text = text
