## Bench controller: turns user intent into Bench mutations and drives the power gate.
##
## Every action here is a thin wrapper over the model — grab a part, snap its lead into a
## hole, run a wire, flip the switch, press a button. Nothing electrical is computed in
## this file, so the behaviour the user sees is exactly what the tested kernel says.
class_name BenchController
extends Node3D

const GRAB_DISTANCE := 2.6

var bench: Bench
var solver: Solver
var power: PowerController
var view: BenchView
var hud: Node

## Held part awaiting placement.
var held_part: ComponentSpec
var wire_anchor: String = ""
var fault_elements: PackedStringArray = PackedStringArray()
var _eval_timer := 0.0

func setup(p_bench: Bench, p_power: PowerController, p_view: BenchView, p_hud: Node) -> void:
	bench = p_bench
	solver = p_power.solver
	view = p_view
	hud = p_hud
	if view != null:
		view.fault_elements = fault_elements
	attach(p_power)

## Move the controller onto a new scenario's power/gate pair.
func attach(p_power: PowerController) -> void:
	if power != null and power.findings_updated.is_connected(_on_findings):
		power.findings_updated.disconnect(_on_findings)
	power = p_power
	solver = p_power.solver
	if not power.findings_updated.is_connected(_on_findings):
		power.findings_updated.connect(_on_findings)

func _process(delta: float) -> void:
	# Re-solve on a fixed cadence, not per frame: the solver is cheap but the HUD and the
	# highlight repaint are not, and a bench does not change 90 times a second.
	_eval_timer += delta
	if _eval_timer >= 0.12:
		_eval_timer = 0.0
		power.evaluate()
		view.apply_electrical_state()
		view.press_feedback()

func _on_findings(findings: Array) -> void:
	var faulty := PackedStringArray()
	for f in findings:
		if f.level == Severity.Level.INFO:
			continue
		for el in f.elements:
			if not faulty.has(el):
				faulty.append(el)
	fault_elements = faulty
	if view != null:
		view.fault_elements = faulty
		view.refresh_wires()
	if hud != null and hud.has_method("show_findings"):
		hud.show_findings(findings, power.status_line(), power.last_refusal)

# --- spawning -------------------------------------------------------------------------

func spawn_resistor(ohms: float) -> void:
	_spawn(ComponentSpec.resistor(_next_id("r"), ohms))

func spawn_led(colour: String) -> void:
	_spawn(ComponentSpec.led(_next_id("led"), colour))

func spawn_button() -> void:
	_spawn(ComponentSpec.button(_next_id("b")))

func _next_id(prefix: String) -> String:
	var n := 1
	while bench.parts.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]

func _spawn(spec: ComponentSpec) -> void:
	held_part = spec
	if hud != null and hud.has_method("set_prompt"):
		hud.set_prompt("Placing %s — pull the trigger on two adjacent holes across the centre channel" % spec.id)

# --- placement ------------------------------------------------------------------------

## Seat the held part, taking the first lead from `terminal` and the second by searching
## the neighbouring rows on the opposite half so a straddle is automatic.
func seat_held(terminal: String) -> bool:
	if held_part == null:
		return false
	var second := _partner_hole(terminal, held_part)
	if second == "":
		_set_prompt("No free hole opposite %s — parts need to straddle the centre channel" % terminal)
		return false
	if not bench.place_part(held_part, {held_part.terminal_suffixes[0]: terminal, held_part.terminal_suffixes[1]: second}):
		return false
	held_part = null
	view.refresh_parts()
	power.evaluate()
	return true

## Find a free hole on the far side of the channel from `terminal`.
func _partner_hole(terminal: String, spec: ComponentSpec) -> String:
	if not terminal.begins_with("bb:") or terminal.begins_with("bb:rail"):
		return ""
	var bits := terminal.split(":")
	if bits.size() != 3:
		return ""
	var row := int(bits[1])
	var col := bits[2]
	var left := Breadboard.HALVES["left"]
	var opposite: String = "f" if left.has(col) else "b"
	for delta in [0, 1, -1, 2, -2]:
		var r: int = row + int(delta)
		if r < 0 or r >= Breadboard.ROWS:
			continue
		var cand := bench.breadboard.tie_point(r, opposite)
		if bench.netlist.has_terminal(cand) and not _occupied(cand):
			return cand
	return ""

func _occupied(terminal: String) -> bool:
	for part_id in bench.placements:
		for suffix in bench.placements[part_id]:
			if bench.placements[part_id][suffix] == terminal:
				return true
	return false

# --- wiring ---------------------------------------------------------------------------

func toggle_wire(terminal: String) -> void:
	if wire_anchor == "":
		wire_anchor = terminal
		_set_prompt("Wire from %s — aim at the destination and pull the trigger again" % terminal)
		return
	if terminal == wire_anchor:
		wire_anchor = ""
		_set_prompt("Wire cancelled")
		return
	bench.add_wire(wire_anchor, terminal)
	wire_anchor = ""
	view.refresh_wires()
	power.evaluate()
	_set_prompt("Wired")

# --- physical controls ----------------------------------------------------------------

func toggle_power() -> void:
	if power.is_live() or power.state == PowerController.State.TRIPPED:
		power.request_power_off()
		power.reset_from_trip()
		return
	if power.request_power_on():
		_set_prompt("Power on")
	else:
		_set_prompt("Refused: " + power.last_refusal)
	view.apply_electrical_state()

func toggle_button(part_id: String) -> void:
	var held: bool = bench.button_state.get(part_id, false)
	bench.press_button(part_id, not held)
	view.press_feedback()
	power.evaluate()

func lift_at(part_id: String) -> void:
	bench.lift_part(part_id)
	view.refresh_parts()
	power.evaluate()

func remove_wire_at(wire_id: String) -> void:
	bench.remove_wire(wire_id)
	view.refresh_wires()
	power.evaluate()

func _set_prompt(text: String) -> void:
	if hud != null and hud.has_method("set_prompt"):
		hud.set_prompt(text)
