## Bench view: draws the board, breadboard, parts and wires from the Bench model.
##
## The view owns *no* electrical state. It reads Bench and Solver and renders them; any
## user action is turned into a Bench mutation by bench_controller.gd. That split is why
## the whole simulation can be tested without a renderer.
class_name BenchView
extends Node3D

const PITCH_MM := 2.54
## A real breadboard is ~83 x 55 mm, which is fiddly to point at in VR. 0.003 renders it
## at ~15 x 26 cm — recognisably a breadboard, but with ~7 mm holes so rays land reliably.
const SCALE := 0.003

const COLOR_RAIL_RED := Color(0.75, 0.16, 0.16)
const COLOR_RAIL_BLUE := Color(0.16, 0.32, 0.75)
const COLOR_HOLE := Color(0.09, 0.09, 0.10)
const COLOR_LEAD := Color(0.78, 0.78, 0.80)
const COLOR_WIRE_IDLE := Color(0.95, 0.72, 0.20)
const COLOR_WIRE_FAULT := Color(0.95, 0.22, 0.22)
const COLOR_LED_ON := Color(1.0, 0.35, 0.25)
const COLOR_LED_OFF := Color(0.35, 0.12, 0.12)
const COLOR_LED_CATHODE := Color(0.72, 0.72, 0.74)

var bench: Bench
var solver: Solver
var board_root: Node3D
var part_root: Node3D
var wire_root: Node3D

## tie point id -> world position, so the controller can snap a placed part into place.
var tie_positions: Dictionary = {}
var part_nodes: Dictionary = {}
var wire_nodes: Dictionary = {}
var fault_elements: PackedStringArray = PackedStringArray()

func _ready() -> void:
	board_root = Node3D.new()
	board_root.name = "Board"
	add_child(board_root)
	part_root = Node3D.new()
	part_root.name = "Parts"
	add_child(part_root)
	wire_root = Node3D.new()
	wire_root.name = "Wires"
	add_child(wire_root)

## Board origin sits behind the breadboard so both are on the table in front of the user.
const BREADBOARD_OFFSET := Vector3(-0.12, 0, 0)
const BOARD_OFFSET := Vector3(0.14, 0, -0.02)

func build(p_bench: Bench, p_solver: Solver) -> void:
	bench = p_bench
	solver = p_solver
	_clear_children(board_root)
	tie_positions.clear()
	var bb := _build_breadboard()
	board_root.add_child(bb)
	board_root.add_child(_build_module())

func _mm_to_world(x_mm: float, z_mm: float) -> Vector3:
	return Vector3(x_mm * SCALE, 0, z_mm * SCALE)

## Breadboard body, rails, and every hole with a clickable area for the ray.
func _build_breadboard() -> Node3D:
	var root := Node3D.new()
	root.name = "Breadboard"
	root.position = BREADBOARD_OFFSET

	var rows := Breadboard.ROWS
	var width := (Breadboard.COLUMNS.size() * PITCH_MM) + 24.0
	var depth := (rows * PITCH_MM) + 10.0

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _mm_to_world(width, depth) + Vector3(0, 0.012, 0)
	body.mesh = box
	body.position = Vector3(0, 0.006, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.93, 0.93, 0.90)
	body_mat.roughness = 0.85
	body.material_override = body_mat
	root.add_child(body)

	var hole_mat := StandardMaterial3D.new()
	hole_mat.albedo_color = COLOR_HOLE
	for row in range(rows):
		for i in range(Breadboard.COLUMNS.size()):
			var col: String = Breadboard.COLUMNS[i]
			var pos := _mm_to_world(_column_x_mm(i), (row * PITCH_MM) + 6.0)
			var hole := _make_hole(hole_mat, pos.y + 0.012)
			var tie := bench.breadboard.tie_point(row, col)
			hole.set_meta("terminal", tie)
			root.add_child(hole)
			tie_positions[tie] = root.position + pos

	# Power rails either side, with their studs.
	for side_index in range(2):
		var x_mm := -14.0 if side_index == 0 else (Breadboard.COLUMNS.size() * PITCH_MM) + 1.0
		var side: String = Breadboard.RAIL_SIDES[side_index]
		for polarity_index in range(2):
			var polarity: String = ["+", "-"][polarity_index]
			var z_mm := 1.5 if polarity == "+" else 0.0
			var strip := MeshInstance3D.new()
			var strip_box := BoxMesh.new()
			strip_box.size = _mm_to_world(2.2, depth - 2.0) + Vector3(0, 0.002, 0)
			strip.mesh = strip_box
			strip.position = _mm_to_world(x_mm, depth * 0.5)
			var smat := StandardMaterial3D.new()
			smat.albedo_color = COLOR_RAIL_RED if polarity == "+" else COLOR_RAIL_BLUE
			smat.emission_enabled = true
			smat.emission = smat.albedo_color * 0.3
			strip.material_override = smat
			root.add_child(strip)

			for i in range(25):
				var pos := _mm_to_world(x_mm, 6.0 + (i * PITCH_MM))
				var stud := _make_hole(hole_mat, pos.y + 0.012)
				var stud_id := bench.breadboard.rail_stud(side, polarity, i)
				stud.set_meta("terminal", stud_id)
				root.add_child(stud)
				tie_positions[stud_id] = root.position + pos
			# z_mm reserved for future rail labelling spacing.
			z_mm += 0.0
	return root

func _column_x_mm(i: int) -> float:
	# Centre channel: a small gap between column e and f.
	var base := (i + 1) * PITCH_MM
	if i >= 5:
		base += 2.0
	return base

func _make_hole(mat: StandardMaterial3D, y: float) -> Area3D:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PITCH_MM * SCALE, 0.008, PITCH_MM * SCALE)
	shape.shape = box
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0012
	cyl.bottom_radius = 0.0012
	cyl.height = 0.002
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position.y = 0.001
	area.add_child(mesh)
	area.position.y = y
	return area

## The ESP32 module: a dark PCB with a metal can, plus an Area3D per pin.
func _build_module() -> Node3D:
	var root := Node3D.new()
	root.name = "ESP32"
	root.position = BOARD_OFFSET

	var pcb := MeshInstance3D.new()
	var pcb_box := BoxMesh.new()
	pcb_box.size = _mm_to_world(46.0, 28.0) + Vector3(0, 0.010, 0)
	pcb.mesh = pcb_box
	pcb.position = Vector3(0, 0.005, 0)
	var pcb_mat := StandardMaterial3D.new()
	pcb_mat.albedo_color = Color(0.07, 0.09, 0.12)
	pcb.material_override = pcb_mat
	root.add_child(pcb)

	var can := MeshInstance3D.new()
	var can_box := BoxMesh.new()
	can_box.size = Vector3(0.17, 0.012, 0.10)
	can.mesh = can_box
	can.position = Vector3(0, 0.016, -0.01)
	var can_mat := StandardMaterial3D.new()
	can_mat.albedo_color = Color(0.62, 0.64, 0.68)
	can_mat.metallic = 0.9
	can_mat.roughness = 0.35
	can.material_override = can_mat
	root.add_child(can)

	# Two pin rows down the long edges, alternating like a real 38-pin module.
	var pin_mat := StandardMaterial3D.new()
	pin_mat.albedo_color = Color(0.85, 0.72, 0.25)
	pin_mat.metallic = 0.7
	var left := 0
	var right := 0
	var gpios: Array = bench.board.usable_gpios()
	for i in range(gpios.size()):
		var g: int = gpios[i]
		var side_right := i % 2 == 1
		var index := right if side_right else left
		if side_right:
			right += 1
		else:
			left += 1
		var x := 0.211 if side_right else -0.211
		var z := -0.13 + (index * 0.0165)
		var pin := _make_pin(pin_mat)
		pin.position = Vector3(x, 0.013, z)
		pin.set_meta("terminal", "esp:gpio%d" % g)
		pin.set_meta("gpio", g)
		root.add_child(pin)
		tie_positions["esp:gpio%d" % g] = root.position + pin.position

	for supply in ["3V3", "VIN"]:
		var p := _make_pin(pin_mat)
		p.position = Vector3(-0.211, 0.013, 0.145 if supply == "3V3" else 0.162)
		p.set_meta("terminal", "esp:%s" % supply)
		root.add_child(p)
		tie_positions["esp:%s" % supply] = root.position + p.position
	for i in range(3):
		var p := _make_pin(pin_mat)
		p.position = Vector3(0.211, 0.013, 0.145 + (i * 0.017))
		p.set_meta("terminal", "esp:GND%d" % i)
		root.add_child(p)
		tie_positions["esp:GND%d" % i] = root.position + p.position
	return root

func _make_pin(mat: StandardMaterial3D) -> Area3D:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.012, 0.02, 0.012)
	shape.shape = box
	area.add_child(shape)
	var mesh := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.008, 0.018, 0.008)
	mesh.mesh = m
	mesh.material_override = mat
	area.add_child(mesh)
	return area

# --- parts and wires ------------------------------------------------------------------

func refresh_parts() -> void:
	_clear_children(part_root)
	part_nodes.clear()
	for part_id in bench.parts:
		var node := _build_part(bench.parts[part_id])
		if node == null:
			continue
		part_nodes[part_id] = node
		part_root.add_child(node)

func _build_part(spec: ComponentSpec) -> Node3D:
	match spec.kind:
		ComponentSpec.Kind.RESISTOR: return _build_resistor(spec)
		ComponentSpec.Kind.LED: return _build_led(spec)
		ComponentSpec.Kind.BUTTON: return _build_button(spec)
	return null

## Position/orient a part between its two seated leads.
func _place_between(body: Node3D, spec: ComponentSpec, height: float) -> void:
	var a := _seat_world(spec, spec.terminal_suffixes[0])
	var b := _seat_world(spec, spec.terminal_suffixes[1])
	if a == Vector3.INF or b == Vector3.INF:
		return
	var mid := (a + b) * 0.5
	body.position = mid + Vector3(0, height, 0)
	if a.distance_to(b) > 0.0001:
		body.look_at_from_position(body.position, b + Vector3(0, body.position.y - b.y, 0), Vector3.UP)

func _seat_world(spec: ComponentSpec, suffix: String) -> Vector3:
	var lead: String = bench.placements.get(spec.id, {}).get(suffix, "")
	if lead == "" or not tie_positions.has(lead):
		return Vector3.INF
	return tie_positions[lead]

func _build_resistor(spec: ComponentSpec) -> Node3D:
	var body := Node3D.new()
	body.name = spec.id
	body.set_meta("part", spec.id)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.007, 0.007, 0.028)
	shape.shape = box
	area.add_child(shape)
	body.add_child(area)

	var can := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0024
	cyl.bottom_radius = 0.0024
	cyl.height = 0.022
	cyl.radial_segments = 10
	can.mesh = cyl
	can.rotation_degrees = Vector3(90, 0, 0)
	can.material_override = _mat(Color(0.82, 0.75, 0.55))
	body.add_child(can)
	body.add_child(_stub_lead())
	_place_between(body, spec, 0.010)
	return body

func _build_led(spec: ComponentSpec) -> Node3D:
	var body := Node3D.new()
	body.name = spec.id
	body.set_meta("part", spec.id)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.007, 0.007, 0.020)
	shape.shape = box
	area.add_child(shape)
	body.add_child(area)

	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.0035
	sphere.height = 0.007
	dome.mesh = sphere
	var mat := _mat(COLOR_LED_OFF)
	mat.emission_enabled = true
	mat.emission = COLOR_LED_OFF
	mat.set_meta("led", spec.id)
	dome.material_override = mat
	dome.name = "Dome"
	body.add_child(dome)
	_place_between(body, spec, 0.010)
	return body

func _build_button(spec: ComponentSpec) -> Node3D:
	var body := Node3D.new()
	body.name = spec.id
	body.set_meta("part", spec.id)
	body.set_meta("button", true)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.012, 0.012, 0.012)
	shape.shape = box
	area.add_child(shape)
	body.add_child(area)

	var base := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.012, 0.004, 0.012)
	base.mesh = bmesh
	base.material_override = _mat(Color(0.13, 0.13, 0.15))
	body.add_child(base)

	var cap := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.005, 0.004, 0.005)
	cap.mesh = cmesh
	cap.position.y = 0.004
	cap.name = "Cap"
	cap.material_override = _mat(Color(0.85, 0.25, 0.25))
	body.add_child(cap)
	_place_between(body, spec, 0.008)
	return body

func _stub_lead() -> MeshInstance3D:
	var lead := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0006
	cyl.bottom_radius = 0.0006
	cyl.height = 0.008
	lead.mesh = cyl
	lead.rotation_degrees = Vector3(90, 0, 0)
	lead.material_override = _mat(COLOR_LEAD)
	return lead

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m

## Wires as sagging tubes between their two ends.
func refresh_wires() -> void:
	_clear_children(wire_root)
	wire_nodes.clear()
	for wire_id in bench.wires:
		var w: Dictionary = bench.wires[wire_id]
		var a: Vector3 = tie_positions.get(w["a"], Vector3.INF)
		var b: Vector3 = tie_positions.get(w["b"], Vector3.INF)
		if a == Vector3.INF or b == Vector3.INF:
			continue
		var faulty := fault_elements.has(wire_id)
		var node := _arc(wire_id, a + Vector3(0, 0.008, 0), b + Vector3(0, 0.008, 0), faulty)
		wire_root.add_child(node)
		wire_nodes[wire_id] = node

func _arc(wire_id: String, a: Vector3, b: Vector3, faulty: bool) -> Node3D:
	var root := Node3D.new()
	root.name = wire_id
	root.set_meta("wire", wire_id)
	var mat := _mat(COLOR_WIRE_FAULT if faulty else COLOR_WIRE_IDLE)
	var points := PackedVector3Array()
	var segments := 6
	var lift := 0.012
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		p.y += sin(t * PI) * lift
		points.append(p)
	for i in range(segments):
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0016
		cyl.bottom_radius = 0.0016
		cyl.height = points[i].distance_to(points[i + 1])
		seg.mesh = cyl
		seg.material_override = mat
		root.add_child(seg)
		var mid := (points[i] + points[i + 1]) * 0.5
		seg.position = mid
		var dir := (points[i + 1] - points[i]).normalized()
		if dir.length() > 0.0001:
			var up := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			seg.look_at_from_position(mid, mid + dir, up)
			seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	return root

# --- electrical feedback --------------------------------------------------------------

## Recolour from live solver state: which LEDs carry current, which wires are implicated.
func apply_electrical_state() -> void:
	for part_id in part_nodes:
		var node: Node3D = part_nodes[part_id]
		if not bench.parts.has(part_id):
			continue
		var spec: ComponentSpec = bench.parts[part_id]
		if spec.kind != ComponentSpec.Kind.LED:
			continue
		var dome := node.get_node_or_null("Dome") as MeshInstance3D
		if dome == null:
			continue
		var lit := solver != null and solver.element_ua(part_id) > 200
		var mat := dome.material_override as StandardMaterial3D
		mat.albedo_color = COLOR_LED_ON if lit else COLOR_LED_OFF
		mat.emission = Color(1.0, 0.42, 0.2) * (1.6 if lit else 0.15)

	var light_node := get_node_or_null("LedLight") as OmniLight3D
	var total := 0
	if solver != null:
		for part_id in bench.parts:
			if bench.parts[part_id].kind == ComponentSpec.Kind.LED:
				total += solver.element_ua(part_id)
	if light_node != null:
		light_node.light_energy = clampf(total / 8000.0, 0.0, 1.2)

func press_feedback() -> void:
	for part_id in part_nodes:
		var node: Node3D = part_nodes[part_id]
		if not node.has_meta("button"):
			continue
		var cap := node.get_node_or_null("Cap") as MeshInstance3D
		if cap != null:
			cap.position.y = 0.001 if bench.button_state.get(part_id, false) else 0.004

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
