extends RefCounted

var runner
var _pc: PowerController

func run() -> void:
	_clean_blink_has_no_errors()
	_clean_blink_powers_on()
	_five_volt_on_gpio_blocks_power()
	_five_volt_reported_before_power_on()
	_rail_short_5v_gnd()
	_rail_short_3v3_gnd()
	_rail_short_5v_3v3()
	_input_only_driven()
	_flash_pin()
	_strapping_low()
	_adc2_with_wifi()
	_adc2_without_wifi()
	_pin_overcurrent()
	_led_reversed()
	_led_reversed_stops_current()
	_led_no_resistor()
	_missing_ground()
	_floating_input()
	_pullup_clears_floating()

func _eval(bench: Bench) -> Array:
	_pc = PowerController.new(bench)
	var f := _pc.evaluate()
	bench.power_off()
	return f

func _clean_blink_has_no_errors() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.good_blink(b)
	var f := _eval(b)
	runner.eq(_pc.errors().size(), 0, "clean blink circuit has zero errors (no false positives)")
	runner.lacks_rule(f, "E_RAIL_SHORT_5V_GND", "clean blink rails")
	runner.lacks_rule(f, "E_5V_INTO_GPIO", "clean blink GPIO2")
	runner.lacks_rule(f, "W_LED_NO_RESISTOR", "clean blink is resistor-protected")

func _clean_blink_powers_on() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.good_blink(b)
	var pc := PowerController.new(b)
	runner.check(pc.request_power_on(), "correct circuit powers on")
	runner.check(pc.is_live(), "power state is ON")
	# LED should carry a sane current, roughly (3.3 - 1.8) / 330 ohm.
	var ua := pc.solver.element_ua("led1")
	runner.check(ua > 2_000 and ua < 10_000, "LED current is sane (%.1fmA)" % (ua / 1000.0))
	runner.eq(pc.errors().size(), 0, "no errors while running")

func _five_volt_on_gpio_blocks_power() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.five_volt_on_gpio(b)
	var pc := PowerController.new(b)
	runner.check(not pc.request_power_on(), "5V on a 3.3V GPIO refuses power-on")
	runner.check(not pc.is_live(), "power stays off")
	runner.check(pc.last_refusal.contains("E_5V_INTO_GPIO"), "refusal names the rule")
	runner.check(pc.last_refusal.length() > 0, "refusal is explained")

func _five_volt_reported_before_power_on() -> void:
	# The acceptance criterion: flagged on a cold board, before any power commit.
	var b := Fixtures.blank_bench()
	Fixtures.five_volt_on_gpio(b)
	var pc := PowerController.new(b)
	var f := pc.evaluate()
	runner.has_error(f, "E_5V_INTO_GPIO", "5V onto 3.3V GPIO")
	runner.eq(pc.state, PowerController.State.OFF, "board is still cold")
	for x in f:
		if x.rule_id == "E_5V_INTO_GPIO":
			check_finding_quality(x)

func check_finding_quality(f: Finding) -> void:
	runner.check(f.reason.length() > 20, "finding carries a real reason")
	runner.check(f.fix.length() > 10, "finding carries a concrete fix")
	runner.check(f.terminals.size() > 0, "finding names the offending terminals")

func _rail_short_5v_gnd() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.rail_short_5v_gnd(b)
	var f := _eval(b)
	runner.has_error(f, "E_RAIL_SHORT_5V_GND", "5V rail shorted to GND")
	runner.eq(_pc.solver.outcome, Solver.Outcome.SOURCE_CONFLICT, "solver reports a source conflict")

func _rail_short_3v3_gnd() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.rail_short_3v3_gnd(b)
	var f := _eval(b)
	runner.has_error(f, "E_RAIL_SHORT_3V3_GND", "3V3 rail shorted to GND")

func _rail_short_5v_3v3() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.rail_short_5v_3v3(b)
	var f := _eval(b)
	runner.has_error(f, "E_RAIL_SHORT_5V_3V3", "5V bridged to 3V3")

func _input_only_driven() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.input_only_output(b)
	var f := _eval(b)
	runner.has_error(f, "E_INPUT_ONLY_DRIVEN", "output on an input-only pin")

func _flash_pin() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.flash_pin(b)
	var f := _eval(b)
	runner.has_error(f, "E_FLASH_PIN_USED", "wiring on a flash pin")

func _strapping_low() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.strap_low(b)
	var f := _eval(b)
	runner.has_error(f, "E_STRAPPING_BOOT", "strapping pin held low at boot")

func _adc2_with_wifi() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.adc2_wifi(b)
	b.set_wifi(true)
	var f := _eval(b)
	runner.has_error(f, "E_ADC2_WIFI", "ADC2 pin used with WiFi active")

func _adc2_without_wifi() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.adc2_wifi(b)
	b.set_wifi(false)
	var f := _eval(b)
	runner.lacks_rule(f, "E_ADC2_WIFI", "ADC2 pin with WiFi off")

func _pin_overcurrent() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.pin_overcurrent(b)
	var f := _eval(b)
	runner.has_rule(f, "E_OVERCURRENT_PIN", "three unprotected LEDs on one pin")

func _led_reversed() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.led_reversed(b)
	var f := _eval(b)
	runner.has_rule(f, "W_LED_REVERSED", "LED fitted backwards")
	for x in f:
		if x.rule_id == "W_LED_REVERSED":
			runner.eq(x.level, Severity.Level.WARNING, "reversed LED is a warning, not fatal")

func _led_reversed_stops_current() -> void:
	# A backwards LED must actually read dark, not merely be flagged.
	var b := Fixtures.blank_bench()
	Fixtures.led_reversed(b)
	var s := Solver.new()
	s.solve(b)
	runner.eq(s.element_ua("led1"), 0, "a reversed LED carries no forward current")

func _led_no_resistor() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.led_no_resistor(b)
	var f := _eval(b)
	runner.has_rule(f, "W_LED_NO_RESISTOR", "LED with no series resistor")

func _missing_ground() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.missing_ground(b)
	var f := _eval(b)
	runner.has_error(f, "E_NO_GROUND", "load with no ground return")

func _floating_input() -> void:
	var b := Fixtures.blank_bench()
	# An input pin wired to a part that sets no level.
	b.place_part(ComponentSpec.button("b1"), {"1": "bb:28:b", "2": "bb:28:f"})
	b.add_wire("esp:gpio4", "bb:28:c")
	var f := _eval(b)
	runner.has_rule(f, "W_FLOATING_INPUT", "bare input pin")
	for x in f:
		if x.rule_id == "W_FLOATING_INPUT":
			runner.eq(x.level, Severity.Level.WARNING, "floating input is a warning")

func _pullup_clears_floating() -> void:
	var b := Fixtures.blank_bench()
	b.set_pin_mode(4, "INPUT_PULLUP")
	b.place_part(ComponentSpec.button("b1"), {"1": "bb:30:b", "2": "bb:30:f"})
	b.add_wire("esp:gpio4", "bb:30:c")
	var f := _eval(b)
	runner.lacks_rule(f, "W_FLOATING_INPUT", "INPUT_PULLUP defines a level")
