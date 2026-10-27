## The simulation core: node voltages and branch currents.
##
## Works exclusively on the resolved Netlist, never on scene objects. Voltages are
## integers in microvolts so a dropped hop does not drift.
##
## Method: modified nodal analysis by Gauss-Seidel. Every conductive element is a
## conductance (resistor, wire, closed button, forward LED junction + forward drop);
## source nodes are clamped Dirichlet boundaries. Iterating the conductance-weighted
## average gives correct series chains and dividers, which single-hop relaxation does
## not: a resistor in series with an LED must actually reduce the LED current.
##
## The solve deliberately runs with the power switch *open* as well, because diagnosing
## a broken circuit before the switch closes is the whole point of the app.
##
## The solver never raises diagnostics. It resolves electrical state and reports facts
## (`outcome`, node voltages, element currents); sim/diagnostics.gd judges them.
class_name Solver
extends RefCounted

enum Outcome { UNPOWERED, POWERED, SOURCE_CONFLICT, REG_OVERLOAD }

const MAX_SWEEPS := 400
const CONVERGE_EPS_UV := 50
const WIRE_OHM := 0.01
const OPEN_BUTTON_OHM := 1.0e12
const LED_JUNCTION_OHM := 20.0

## Facts a rules pass reads. Filled by solve().
var bench: Bench
var node_v: Dictionary = {}          ## node -> uV, for reachable nodes only
var node_source: Dictionary = {}     ## node -> "vin" | "vdd" | "gnd" | "gpio"
var element_current_ua: Dictionary = {}  ## element id -> uA magnitude
var reg_return_ua := 0
var vin_return_ua := 0
var outcome: int = Outcome.UNPOWERED
var supply_node := -1
var ground_node := -1
var vdd_node := -1
var conducting_elements: PackedStringArray = PackedStringArray()
var reversed_leds: PackedStringArray = PackedStringArray()

var _nl: Netlist
var _prim: Array[Dictionary] = []
var _clamped: Dictionary = {}
var _adjacency: Dictionary = {}

func solve(p_bench: Bench) -> void:
	bench = p_bench
	_nl = p_bench.netlist
	_nl.resolve()
	_reset_facts()
	_collect_primitives()

	ground_node = _nl.node_of(p_bench.ground_terminal())
	supply_node = _nl.node_of(p_bench.supply_terminal())
	vdd_node = _nl.node_of("esp:3V3")

	var gnd_gone := ground_node < 0
	var short_vin_gnd := ground_node == supply_node
	var short_vdd_gnd := ground_node == vdd_node
	var short_vin_vdd := supply_node == vdd_node

	# GND is always the reference, even with the switch open: a fault has to be legible
	# on a cold board.
	_clamp(ground_node, 0, "gnd")
	if short_vin_gnd:
		# 5V tied to GND: the supply wins the shared node and burns into ground.
		_clamp(ground_node, BoardSpec.VIN_UV, "vin")
		outcome = Outcome.SOURCE_CONFLICT
	elif short_vdd_gnd:
		# 3V3 tied to GND: the LDO output collapses onto the reference.
		outcome = Outcome.SOURCE_CONFLICT
	elif short_vin_vdd:
		_clamp(supply_node, BoardSpec.VIN_UV, "vin")
		outcome = Outcome.SOURCE_CONFLICT
	else:
		_clamp(supply_node, BoardSpec.VIN_UV, "vin")
		_clamp(vdd_node, BoardSpec.VDD_UV, "vdd")

	# Driven pins are sources too; they are what makes a wrong circuit draw current.
	for g in bench.pin_levels:
		if not bench.is_driving(g):
			continue
		var node := _nl.node_of("esp:gpio%d" % g)
		if node >= 0 and not _clamped.has(node):
			_clamp(node, board_clamped_level(bench.drive_level(g)), "gpio")

	_build_adjacency()
	_seed_and_sweep()
	_label_sources()
	_measure_currents()
	_classify()

func _reset_facts() -> void:
	node_v.clear()
	node_source.clear()
	element_current_ua.clear()
	conducting_elements = PackedStringArray()
	reversed_leds = PackedStringArray()
	reg_return_ua = 0
	vin_return_ua = 0
	outcome = Outcome.UNPOWERED
	_prim.clear()
	_clamped.clear()
	_adjacency.clear()

func board_clamped_level(uv: int) -> int:
	# A GPIO never drives above its own supply rail.
	return clampi(uv, 0, BoardSpec.VDD_UV)

func _clamp(node: int, uv: int, source: String) -> void:
	if node < 0:
		return
	node_v[node] = uv
	node_source[node] = source
	_clamped[node] = true

## Flatten parts and wires into conductances between nodes.
func _collect_primitives() -> void:
	for wire_id in bench.wires:
		var w: Dictionary = bench.wires[wire_id]
		var a := _nl.node_of(w["a"])
		var b := _nl.node_of(w["b"])
		if a >= 0 and b >= 0 and a != b:
			_prim.append({"a": a, "b": b, "kind": "wire", "g": 1.0 / WIRE_OHM, "r": WIRE_OHM, "drop": 0, "el": wire_id})
	for part_id in bench.parts:
		var spec: ComponentSpec = bench.parts[part_id]
		match spec.kind:
			ComponentSpec.Kind.RESISTOR:
				_add_lead_prim(spec, "1", "2", "resistor", 1.0 / maxf(spec.resistance_ohm, 0.001), spec.resistance_ohm, 0, part_id)
			ComponentSpec.Kind.BUTTON:
				var held: bool = bench.button_state.get(part_id, false)
				var r: float = 10.0 if held else OPEN_BUTTON_OHM
				_add_lead_prim(spec, "1", "2", "button", 1.0 / r, r, 0, part_id)
			ComponentSpec.Kind.LED:
				_add_lead_prim(spec, "A", "K", "led", 1.0 / LED_JUNCTION_OHM, LED_JUNCTION_OHM, spec.forward_drop_uv, part_id)

func _add_lead_prim(spec: ComponentSpec, from_suffix: String, to_suffix: String, kind: String, g: float, r: float, drop: int, el: String) -> void:
	var a := _nl.node_of(spec.terminal_id(from_suffix))
	var b := _nl.node_of(spec.terminal_id(to_suffix))
	if a < 0 or b < 0 or a == b:
		return
	# `drop` always runs from `a` toward `b`, i.e. a is the anode.
	_prim.append({"a": a, "b": b, "kind": kind, "g": g, "r": r, "drop": drop, "el": el})

func _build_adjacency() -> void:
	# A forward drop is not a plain conductance: it is a series voltage source that only
	# passes forward current, so each link records which role the node plays in the
	# junction and the sweep skips it while the diode is reverse-biased. Leaving both the
	# sign and the direction out makes a backwards LED still conduct.
	for p in _prim:
		var a: int = p["a"]
		var b: int = p["b"]
		var drop: int = p["drop"]
		if not _adjacency.has(a):
			_adjacency[a] = []
		if not _adjacency.has(b):
			_adjacency[b] = []
		_adjacency[a].append({"node": b, "g": p["g"], "offset": drop, "diode": p["kind"] == "led", "anode": true})
		_adjacency[b].append({"node": a, "g": p["g"], "offset": -drop, "diode": p["kind"] == "led", "anode": false})

## A junction passes current when its forward drop is met. Only diodes are direction
## sensitive; resistors and wires (drop 0) are always conductive, otherwise a zero-drop
## branch flickers in and out of the average and the sweep oscillates.
func _link_active(link: Dictionary, here: int, there: int) -> bool:
	if not link["diode"]:
		return true
	var drop: int = abs(link["offset"])
	var anode_v := here if link["anode"] else there
	var cathode_v := there if link["anode"] else here
	if anode_v - cathode_v > drop - 1_000:
		return true
	return cathode_v - anode_v > ComponentSpec.LED_REVERSE_BREAKDOWN_UV

## Seed unclamped nodes from the highest reachable clamp so Gauss-Seidel starts close,
## then sweep until stable. Unclamped nodes with no conductance are not reachable.
func _seed_and_sweep() -> void:
	for node in _adjacency:
		if _clamped.has(node):
			continue
		node_v.erase(node)
	# Seed *before* iterating, or the first sweep sees no values to improve and the
	# convergence check breaks out immediately with every node at its seed value.
	_propagate_to_unreached()

	for sweep in range(MAX_SWEEPS):
		var worst := 0
		for node in _adjacency:
			if _clamped.has(node) or not node_v.has(node):
				continue
			var gsum := 0.0
			var weighted := 0.0
			for link in _adjacency[node]:
				var other: int = link["node"]
				if not node_v.has(other):
					continue
				if not _link_active(link, node_v[node], node_v[other]):
					continue
				var g: float = link["g"]
				gsum += g
				# The offset carries the LED drop in the right direction for this side.
				weighted += g * float(node_v[other] + link["offset"])
			if gsum <= 0.0:
				continue
			var target := int(weighted / gsum)
			var delta: int = abs(target - node_v[node])
			if delta > worst:
				worst = delta
			node_v[node] = target
		_propagate_to_unreached()
		if worst <= CONVERGE_EPS_UV:
			break

## Nodes never seeded (chains leaving a clamp) get their value from a neighbour.
func _propagate_to_unreached() -> void:
	var changed := true
	var guard := 0
	while changed and guard < MAX_SWEEPS:
		changed = false
		guard += 1
		for node in _adjacency:
			if _clamped.has(node) or node_v.has(node):
				continue
			for link in _adjacency[node]:
				var other: int = link["node"]
				if node_v.has(other):
					node_v[node] = int(node_v[other] + link["offset"])
					changed = true
					break

## Label each reachable node with the source feeding it (for current accounting).
func _label_sources() -> void:
	for node in _adjacency:
		if _clamped.has(node):
			continue
		var best := -1
		var best_source := ""
		for link in _adjacency[node]:
			var other: int = link["node"]
			if not node_source.has(other):
				continue
			if node_v.has(other) and node_v[other] > best:
				best = node_v[other]
				best_source = node_source[other]
		if best_source != "":
			node_source[node] = best_source

## Ohm's law per element that actually carries current.
func _measure_currents() -> void:
	for p in _prim:
		var a: int = p["a"]
		var b: int = p["b"]
		if not node_v.has(a) or not node_v.has(b):
			continue
		var diff: int = node_v[a] - node_v[b]
		var r: float = p["r"]
		if p["kind"] == "led":
			if diff > p["drop"]:
				var ua := int((diff - p["drop"]) / r)
				if ua > 0:
					element_current_ua[p["el"]] = ua
					conducting_elements.append(p["el"])
			elif diff < 0:
				# Reverse-biased: dark (the reversed-LED rule reads this list), and only
				# conducting at all once the junction passes reverse breakdown.
				reversed_leds.append(p["el"])
				if -diff > ComponentSpec.LED_REVERSE_BREAKDOWN_UV:
					var irev := int((-diff - ComponentSpec.LED_REVERSE_BREAKDOWN_UV) / r)
					if irev > 0:
						element_current_ua[p["el"]] = irev
						conducting_elements.append(p["el"])
			continue
		if r <= 0.0:
			continue
		var mag := int(abs(diff) / r)
		if mag > 0:
			element_current_ua[p["el"]] = mag
			conducting_elements.append(p["el"])

## Sum return current per source and grade the outcome.
func _classify() -> void:
	var total_reg := 0
	var total_vin := 0
	for p in _prim:
		var el: String = p["el"]
		if not element_current_ua.has(el):
			continue
		var src: String = node_source.get(p["a"], "")
		if p["kind"] == "led" and reversed_leds.has(el):
			continue
		# Current drawn off a GPIO is current the regulator has to supply.
		if src == "vdd" or src == "gpio":
			total_reg += element_current_ua[el]
		elif src == "vin":
			total_vin += element_current_ua[el]
	reg_return_ua = total_reg
	vin_return_ua = total_vin
	if outcome == Outcome.SOURCE_CONFLICT:
		return
	var total := total_reg + total_vin
	if total > BoardSpec.REG_BUDGET_MA * 1000:
		outcome = Outcome.REG_OVERLOAD
	elif total > 0:
		outcome = Outcome.POWERED

func resolve_nodes() -> void:
	_nl.resolve()

func node_voltage(node: int) -> int:
	return node_v.get(node, -1)

func voltage_of(terminal: String) -> int:
	return node_voltage(_nl.node_of(terminal))

func is_live(node: int) -> bool:
	return node_v.has(node)

func element_ua(element: String) -> int:
	return element_current_ua.get(element, 0)

## Total current leaving a node across its elements.
func node_power_ua(node: int) -> int:
	var total := 0
	for p in _prim:
		if p["a"] == node and element_current_ua.has(p["el"]):
			total += element_current_ua[p["el"]]
	return total
