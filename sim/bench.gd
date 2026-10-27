## The bench: everything currently on the table, plus the firmware's pin modes.
##
## Bench owns the mutable model — placed parts, wires, pin modes, power switch state —
## and rebuilds the Netlist from it. The VR layer manipulates a Bench and nothing else;
## the solver only ever sees the Netlist Bench produced.
class_name Bench
extends RefCounted

const PIN_VDD := "vdd"
const PIN_GND := "gnd"

var board: BoardSpec
var breadboard: Breadboard
var netlist := Netlist.new()

## gpio -> mode string ("INPUT", "OUTPUT", "INPUT_PULLUP", "ADC", ...)
var pin_modes: Dictionary = {}
## pin key -> driven voltage in uV when the pin is an output and the board is on.
var pin_levels: Dictionary = {}
## component id -> ComponentSpec
var parts: Dictionary = {}
## part id -> { lead: terminal id } placement map
var placements: Dictionary = {}
## button id -> held
var button_state: Dictionary = {}
## wire id -> {"a": Terminal, "b": Terminal}
var wires: Dictionary = {}

var power_switch_closed := false
var wifi_active := false
var _wire_seq := 0

func _init(p_board: BoardSpec) -> void:
	board = p_board
	breadboard = Breadboard.new()
	_rebuild_static()

## Install board pins and breadboard terminals, and tie the ground pins to each other
## the way the module's own copper does.
func _rebuild_static() -> void:
	breadboard.install(netlist)
	for g in board.gpio_numbers():
		netlist.add_terminal("esp:gpio%d" % g, Netlist.KIND_PIN, {"gpio": g})
	# Board power pins.
	for name in ["3V3", "3V3_2", "VIN", "5V"]:
		netlist.add_terminal("esp:%s" % name, Netlist.KIND_PIN, {"supply": name.to_lower()})
	for i in range(3):
		netlist.add_terminal("esp:GND%d" % i, Netlist.KIND_PIN, {"supply": "gnd"})
	# All board GND pins are common copper, all 3V3 pins are common copper.
	netlist.join_group(PackedStringArray(["esp:GND0", "esp:GND1", "esp:GND2"]), "esp:gndplane", "tie")
	netlist.join_group(PackedStringArray(["esp:3V3", "esp:3V3_2"]), "esp:3v3plane", "tie")
	netlist.join_group(PackedStringArray(["esp:VIN", "esp:5V"]), "esp:vinplane", "tie")

func reset(board_spec: BoardSpec) -> void:
	netlist = Netlist.new()
	parts.clear()
	placements.clear()
	button_state.clear()
	wires.clear()
	pin_modes.clear()
	pin_levels.clear()
	power_switch_closed = false
	wifi_active = false
	_wire_seq = 0
	board = board_spec
	_rebuild_static()

# --- pin modes -----------------------------------------------------------------------

func set_pin_mode(gpio: int, mode: String) -> void:
	pin_modes[gpio] = mode

func pin_mode(gpio: int) -> String:
	return pin_modes.get(gpio, "")

func set_pin_level_raw(gpio: int, uv: int) -> void:
	pin_levels[gpio] = uv

func is_driving(gpio: int) -> bool:
	return pin_mode(gpio) == "OUTPUT" and pin_levels.has(gpio)

func drive_level(gpio: int) -> int:
	return pin_levels.get(gpio, 0)

func is_high_z_input(gpio: int) -> bool:
	var m := pin_mode(gpio)
	return m == "INPUT" or m == "ADC" or m == ""

func has_pullup(gpio: int) -> bool:
	return pin_mode(gpio) == "INPUT_PULLUP"

# --- parts ---------------------------------------------------------------------------

func place_part(spec: ComponentSpec, lead_targets: Dictionary) -> bool:
	if parts.has(spec.id):
		return false
	for suffix in spec.terminal_suffixes:
		if not lead_targets.has(suffix):
			return false
		if not netlist.has_terminal(lead_targets[suffix]):
			return false
	parts[spec.id] = spec
	placements[spec.id] = lead_targets.duplicate()
	if spec.kind == ComponentSpec.Kind.BUTTON:
		button_state[spec.id] = false
	# The part's own leads become terminals, tied into the board by its seat only.
	# Leads stay electrically distinct so the solver can put the part's resistance or
	# its forward drop between them; a part must never collapse its own leads into one
	# node or series resistance would vanish.
	var leads := spec.all_terminals()
	for lead in leads:
		netlist.add_terminal(lead, Netlist.KIND_LEAD, {"part": spec.id})
	for suffix in spec.terminal_suffixes:
		netlist.join(spec.terminal_id(suffix), lead_targets[suffix], "%s:seat:%s" % [spec.id, suffix], "tie")
	return true

func lift_part(part_id: String) -> bool:
	if not parts.has(part_id):
		return false
	var spec: ComponentSpec = parts[part_id]
	for suffix in spec.terminal_suffixes:
		netlist.remove_element("%s:seat:%s" % [part_id, suffix])
	for lead in spec.all_terminals():
		netlist.remove_terminal(lead)
	parts.erase(part_id)
	placements.erase(part_id)
	button_state.erase(part_id)
	return true

func press_button(part_id: String, held: bool) -> void:
	if parts.has(part_id) and parts[part_id].kind == ComponentSpec.Kind.BUTTON:
		button_state[part_id] = held

# --- wires ---------------------------------------------------------------------------

func add_wire(a: String, b: String) -> String:
	if not netlist.has_terminal(a) or not netlist.has_terminal(b):
		return ""
	_wire_seq += 1
	var wire_id := "w%d" % _wire_seq
	wires[wire_id] = {"a": a, "b": b}
	netlist.join(a, b, wire_id, "wire")
	return wire_id

func remove_wire(wire_id: String) -> bool:
	if not wires.has(wire_id):
		return false
	netlist.remove_element(wire_id)
	wires.erase(wire_id)
	return true

# --- power ---------------------------------------------------------------------------

func power_on() -> void:
	power_switch_closed = true

func power_off() -> void:
	power_switch_closed = false

func set_wifi(active: bool) -> void:
	wifi_active = active

## Board supply terminals for the solver.
func supply_terminal() -> String:
	return "esp:VIN"

func ground_terminal() -> String:
	return "esp:GND0"
