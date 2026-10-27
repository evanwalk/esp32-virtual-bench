## The error/warning engine.
##
## Rules run over the solved fact set and the bench, and emit Findings. Rules never
## mutate the circuit and never call the solver. Severity is fixed per rule, so a rule
## cannot be "sometimes fatal".
##
## Rule statements and their provenance live in docs/SPEC-PROVENANCE.md. Every rule id
## there is implemented here; the tests assert on ids, so renaming one is a test failure.
class_name Diagnostics
extends RefCounted

var bench: Bench
var solver: Solver
var _findings: Array[Finding] = []
var _nl: Netlist

func run(p_bench: Bench, p_solver: Solver) -> Array[Finding]:
	bench = p_bench
	solver = p_solver
	_nl = p_bench.netlist
	_nl.resolve()
	_findings.clear()

	_rail_shorts()
	_flash_pins_used()
	_input_only_driven()
	_five_volt_on_gpio()
	_strapping_boot()
	_adc2_with_wifi()
	_pin_overcurrent()
	_reg_overcurrent()
	_floating_inputs()
	_missing_ground()
	_led_reversed()
	_led_no_resistor()
	_series_resistor_band()

	var out := _findings.duplicate()
	out.sort_custom(func(a: Finding, b: Finding) -> bool: return Severity.rank(a.level) < Severity.rank(b.level))
	return out

func _add(f: Finding) -> void:
	_findings.append(f)

# --- rails ---------------------------------------------------------------------------

func _rail_shorts() -> void:
	var vin_node := _nl.node_of(bench.supply_terminal())
	var vdd_node := _nl.node_of("esp:3V3")
	var gnd_node := _nl.node_of(bench.ground_terminal())

	for polarity in [["5V", vin_node, "E_RAIL_SHORT_5V_GND", "0V"], ["3V3", vdd_node, "E_RAIL_SHORT_3V3_GND", "0V"]]:
		if polarity[1] == gnd_node and polarity[1] >= 0:
			var rail_node: int = polarity[1]
			_add(Finding.new(
				polarity[2], Severity.Level.ERROR,
				"%s rail is shorted to GND" % polarity[0],
				"The %s supply node and the GND node resolve to the same copper, so current has no load to fall across." % polarity[0],
				"Pull the bridging wire and re-check every jumper that touches the rail."
			).with_terminals(_nl.node_terminals(rail_node)).with_elements(solver_short_elements(rail_node, gnd_node)))

	if vin_node == vdd_node and vin_node >= 0 and gnd_node != vin_node:
		_add(Finding.new(
			"E_RAIL_SHORT_5V_3V3", Severity.Level.ERROR,
			"5V rail is bridged to the 3V3 rail",
			"The LDO has no reverse path, so 5V rides straight onto the 3V3 node and every 3.3V part on it.",
			"Move the jumper from the 5V rail to the 3V3 rail, or run the part from VIN deliberately."
		).with_terminals(_nl.node_terminals(vin_node)).with_elements(solver_short_elements(vin_node, vdd_node)))

## Elements sitting on the copper between two nodes (used to name the guilty wire).
func solver_short_elements(a: int, b: int) -> PackedStringArray:
	if a != b:
		return PackedStringArray()
	return _nl.elements_on_node(a)

func _flash_pins_used() -> void:
	for g in bench.board.gpio_numbers():
		if not bench.board.is_flash_pin(g):
			continue
		var node := _nl.node_of("esp:gpio%d" % g)
		if node < 0:
			continue
		# Anything more than the pin's own seat on the node means it is wired up.
		if _nl.node_terminals(node).size() > 1:
			_add(Finding.new(
				"E_FLASH_PIN_USED", Severity.Level.ERROR,
				"GPIO%d is a flash pin and cannot be used" % g,
				"GPIO 6-11 are bonded to the SPI flash die on the module; using one crashes the boot loader.",
				"Rewire to a free GPIO (4, 5, 13, 14, 16-19, 21-23, 25-27, 32, 33)."
			).with_terminals(_nl.node_terminals(node)))

# --- pin capability ------------------------------------------------------------------

func _input_only_driven() -> void:
	for g in bench.board.gpio_numbers():
		if not bench.board.is_input_only(g):
			continue
		if bench.pin_mode(g) != "OUTPUT":
			continue
		_add(Finding.new(
			"E_INPUT_ONLY_DRIVEN", Severity.Level.ERROR,
			"GPIO%d is input-only but the firmware drives it" % g,
			"GPIO 34-39 have no output driver, so pinMode OUTPUT produces a pin that never moves.",
			"Move the output to a bidirectional pin, or change the sketch to read GPIO%d." % g
		).with_terminals(PackedStringArray(["esp:gpio%d" % g])))

func _five_volt_on_gpio() -> void:
	var vin_node := _nl.node_of(bench.supply_terminal())
	for g in bench.board.gpio_numbers():
		if bench.board.is_flash_pin(g):
			continue
		var node := _nl.node_of("esp:gpio%d" % g)
		if node < 0:
			continue
		var v := solver.node_voltage(node)
		if v > BoardSpec.GPIO_ABS_MAX_UV:
			_add(Finding.new(
				"E_5V_INTO_GPIO", Severity.Level.ERROR,
				"GPIO%d sees %.1fV, above the 3.6V absolute maximum" % [g, v / 1_000_000.0],
				"An ESP32 GPIO is a 3.3V pin. Above 3.6V the input clamp conducts and the pin degrades or dies.",
				"Feed the GPIO from the 3V3 rail, or add a divider so the node stays under 3.3V."
			).with_terminals(PackedStringArray(["esp:gpio%d" % g])).with_elements(_elements_feeding(node, vin_node)))

## Elements whose downstream side is this node — names the wire that brought the voltage.
func _elements_feeding(node: int, _vin: int) -> PackedStringArray:
	var out := PackedStringArray()
	for el in _nl.elements_on_node(node):
		if bench.wires.has(el):
			out.append(el)
	return out

func _strapping_boot() -> void:
	for g in bench.board.strap_expected:
		var node := _nl.node_of("esp:gpio%d" % g)
		if node < 0:
			continue
		if _nl.node_terminals(node).size() <= 1:
			continue
		var expected: int = bench.board.strap_expected[g]
		var v := solver.node_voltage(node)
		var gnd_node := _nl.node_of(bench.ground_terminal())
		var is_low := node == gnd_node or (v >= 0 and v < BoardSpec.LOGIC_LOW_MAX_UV)
		var is_high := v >= BoardSpec.LOGIC_HIGH_MIN_UV
		if expected == 1 and not is_high:
			_add(Finding.new(
				"E_STRAPPING_BOOT", Severity.Level.ERROR,
				"GPIO%d is a strapping pin held low at boot" % g,
				"GPIO%d must read high when the chip resets or the ROM chooses the wrong boot mode." % g,
				"Pull GPIO%d up to 3V3, or move the load to a non-strapping pin." % g
			).with_terminals(PackedStringArray(["esp:gpio%d" % g])))
		elif expected == 0 and is_high:
			_add(Finding.new(
				"E_STRAPPING_BOOT", Severity.Level.ERROR,
				"GPIO%d is a strapping pin held high at boot" % g,
				"GPIO%d high at reset puts the flash into the wrong voltage/boot mode." % g,
				"Pull GPIO%d down to GND, or avoid it." % g
			).with_terminals(PackedStringArray(["esp:gpio%d" % g])))

func _adc2_with_wifi() -> void:
	if not bench.wifi_active:
		return
	for g in bench.board.gpio_numbers():
		if bench.board.adc2_channel(g) < 0:
			continue
		if bench.pin_mode(g) != "ADC":
			continue
		_add(Finding.new(
			"E_ADC2_WIFI", Severity.Level.ERROR,
			"GPIO%d reads ADC2 while WiFi is running" % g,
			"ADC2 is multiplexed with the radio; analogRead on it returns garbage or zero whenever WiFi is up.",
			"Move the analog input to an ADC1 pin (GPIO 32-39), or drop WiFi."
		).with_terminals(PackedStringArray(["esp:gpio%d" % g])))

# --- current ---------------------------------------------------------------------------

func _pin_overcurrent() -> void:
	for g in bench.board.gpio_numbers():
		if not bench.is_driving(g):
			continue
		var node := _nl.node_of("esp:gpio%d" % g)
		if node < 0:
			continue
		var ua := solver.node_power_ua(node)
		if ua > BoardSpec.GPIO_SOURCE_MA_SAFE * 1000:
			var severe := ua > BoardSpec.GPIO_ABS_MAX_MA * 1000
			_add(Finding.new(
				"E_OVERCURRENT_PIN", Severity.Level.ERROR if severe else Severity.Level.WARNING,
				"GPIO%d sources %.1fmA (safe limit %dmA)" % [g, ua / 1000.0, BoardSpec.GPIO_SOURCE_MA_SAFE],
				"A GPIO is not a supply. Beyond %dmA the output sags; beyond %dmA the driver is outside its rating." % [BoardSpec.GPIO_SOURCE_MA_SAFE, BoardSpec.GPIO_ABS_MAX_MA],
				"Add series resistance, or switch the load with a transistor and feed it from a rail."
			).with_terminals(PackedStringArray(["esp:gpio%d" % g])).with_elements(_elements_feeding(node, node)))

func _reg_overcurrent() -> void:
	var total_ma := solver.reg_return_ua / 1000.0
	if total_ma <= float(BoardSpec.REG_BUDGET_MA):
		return
	_add(Finding.new(
		"E_OVERCURRENT_REG", Severity.Level.ERROR,
		"Board 3V3 regulator is at %.0fmA, over its %dmA budget" % [total_ma, BoardSpec.REG_BUDGET_MA],
		"The on-module regulator and its thermal path cannot hold 3.3V at this draw; the rail browns out and the chip resets mid-run.",
		"Split the load onto the 5V rail, cut LED current, or power the heavy part externally."
	).with_terminals(PackedStringArray(["esp:3V3"])))

# --- connectivity ----------------------------------------------------------------------

func _floating_inputs() -> void:
	if not solver.is_live(_nl.node_of("esp:3V3")):
		return
	var vdd_node := _nl.node_of("esp:3V3")
	for g in bench.board.gpio_numbers():
		if bench.board.is_flash_pin(g):
			continue
		if not bench.board.can(g, BoardSpec.CAP_INPUT):
			continue
		# An output defines its own level; a pull-up defines one. Only bare inputs float.
		if bench.is_driving(g) or bench.has_pullup(g):
			continue
		var node := _nl.node_of("esp:gpio%d" % g)
		if node < 0 or node == vdd_node:
			continue
		# Only pins actually attached to something are worth flagging.
		if _nl.node_terminals(node).size() <= 1:
			continue
		var v := solver.node_voltage(node)
		_add(Finding.new(
			"W_FLOATING_INPUT", Severity.Level.WARNING,
			"GPIO%d is a floating input" % g,
			"Nothing sets a level on this net, so the pin reads noise and the firmware sees random HIGH/LOW.",
			"Set pinMode(GPIO%d, INPUT_PULLUP), or fit a resistor to 3V3 or GND." % g
		).with_terminals(_nl.node_terminals(node)))

func _missing_ground() -> void:
	if bench.parts.is_empty():
		return
	var gnd_node := _nl.node_of(bench.ground_terminal())
	if gnd_node < 0:
		return
	# Only a circuit actually wired to the board can be short of a return path.
	if not _touches_board():
		return
	if _has_ground_return():
		return
	_add(Finding.new(
		"E_NO_GROUND", Severity.Level.ERROR,
		"No ground return to the board",
		"Current needs a loop. Parts are wired to the board but nothing reaches GND, so no current can flow.",
		"Run a jumper from the breadboard GND rail to an ESP32 GND pin."
	).with_terminals(PackedStringArray([bench.ground_terminal()])))

## Does any part lead share copper with a board pin (any supply, GND or GPIO)?
func _touches_board() -> bool:
	for part_id in bench.parts:
		for t in bench.parts[part_id].all_terminals():
			for peer in _nl.node_terminals(_nl.node_of(t)):
				if peer.begins_with("esp:"):
					return true
	return false

func _has_ground_return() -> bool:
	var gnd_node := _nl.node_of(bench.ground_terminal())
	for part_id in bench.parts:
		var spec: ComponentSpec = bench.parts[part_id]
		for t in spec.all_terminals():
			if _nl.node_of(t) == gnd_node:
				return true
	return false

# --- LED-specific ----------------------------------------------------------------------

func _led_reversed() -> void:
	for led_id in solver.reversed_leds:
		if not bench.parts.has(led_id):
			continue
		_add(Finding.new(
			"W_LED_REVERSED", Severity.Level.WARNING,
			"%s is fitted backwards" % led_id,
			"The anode is on the low side, so the junction is reverse-biased and the LED stays dark.",
			"Lift the LED, rotate it 180 degrees, and reseat it: long leg (anode) toward the drive."
		).with_terminals(bench.parts[led_id].all_terminals()).with_elements(PackedStringArray([led_id])))

func _led_no_resistor() -> void:
	for part_id in bench.parts:
		var spec: ComponentSpec = bench.parts[part_id]
		if spec.kind != ComponentSpec.Kind.LED:
			continue
		if _led_has_series_r(spec):
			continue
		_add(Finding.new(
			"W_LED_NO_RESISTOR", Severity.Level.ERROR,
			"%s has no series resistor" % part_id,
			"An LED across a rail is a diode with a near-vertical V-I curve; the current is set only by the source, so it runs away.",
			"Insert a resistor (220-470 ohm at 3V3, 1k at 5V) in series with %s." % part_id
		).with_terminals(spec.all_terminals()).with_elements(PackedStringArray([part_id])))

## An LED is protected if some node on either of its nets also carries a resistor.
## Part seats are named "<part>:seat:<suffix>", so map seat elements back to the part.
func _led_has_series_r(spec: ComponentSpec) -> bool:
	for suffix in spec.terminal_suffixes:
		var node := _nl.node_of(spec.terminal_id(suffix))
		for el in _nl.elements_on_node(node):
			var part_id := _part_of_element(el)
			if part_id != "" and bench.parts.has(part_id):
				if bench.parts[part_id].kind == ComponentSpec.Kind.RESISTOR:
					return true
	return false

func _part_of_element(element: String) -> String:
	var cut := element.find(":seat:")
	if cut > 0:
		return element.substr(0, cut)
	if bench.parts.has(element):
		return element
	return ""

func _series_resistor_band() -> void:
	# STUBBED: present so the id is live, not yet asserting a band.
	for part_id in bench.parts:
		var spec: ComponentSpec = bench.parts[part_id]
		if spec.kind != ComponentSpec.Kind.LED:
			continue
		var node := _nl.node_of(spec.terminal_id("A"))
		for el in _nl.elements_on_node(node):
			var r_part := _part_of_element(el)
			if r_part == "" or not bench.parts.has(r_part):
				continue
			var r_spec: ComponentSpec = bench.parts[r_part]
			if r_spec.kind != ComponentSpec.Kind.RESISTOR:
				continue
			if r_spec.resistance_ohm < 100.0:
				_add(Finding.new(
					"W_SERIES_R_TOLERANCE", Severity.Level.WARNING,
					"%s series resistor is only %d ohm" % [el, int(r_spec.resistance_ohm)],
					"Under 100 ohm at 3V3 the LED is likely over its 20mA rating.",
					"Use 220-470 ohm at 3V3, or 1k at 5V."
				).with_terminals(r_spec.all_terminals()).with_elements(PackedStringArray([el])))
			return
