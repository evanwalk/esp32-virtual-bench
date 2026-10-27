extends RefCounted

var runner
var _pc: PowerController

func run() -> void:
	_ohm_law_series()
	_divider()
	_open_button()
	_pressed_button()
	_gpio_drive_clamped()
	_power_state_machine()
	_rail_short_collapses_3v3()

func _bench() -> Bench:
	return Fixtures.blank_bench()

func _solve(b: Bench) -> Solver:
	var s := Solver.new()
	s.solve(b)
	return s

func _ohm_law_series() -> void:
	var b := _bench()
	b.set_pin_mode(2, "OUTPUT")
	b.set_pin_level_raw(2, BoardSpec.VDD_UV)
	var r := ComponentSpec.resistor("r1", 1000.0)
	b.place_part(r, {"1": "bb:2:b", "2": "bb:2:f"})
	b.add_wire("esp:gpio2", "bb:2:b")
	b.add_wire("bb:2:j", "esp:GND0")
	var s := _solve(b)
	# 3.3V across 1000 ohm = 3300 uA.
	var ua := s.element_ua("r1")
	runner.check(ua > 3200 and ua < 3400, "Ohm's law holds through a series resistor (got %duA)" % ua)
	runner.eq(s.voltage_of("bb:2:f"), 0, "the far side sits at ground potential")

func _divider() -> void:
	var b := _bench()
	b.set_pin_mode(2, "OUTPUT")
	b.set_pin_level_raw(2, BoardSpec.VDD_UV)
	b.place_part(ComponentSpec.resistor("r1", 1000.0), {"1": "bb:2:b", "2": "bb:2:f"})
	b.place_part(ComponentSpec.resistor("r2", 1000.0), {"1": "bb:3:b", "2": "bb:3:f"})
	b.add_wire("esp:gpio2", "bb:2:b")
	b.add_wire("bb:2:f", "bb:3:b")
	b.add_wire("bb:3:f", "esp:GND0")
	var s := _solve(b)
	var mid := s.voltage_of("bb:2:f")
	runner.check(mid > 1_550_000 and mid < 1_750_000, "equal divider halves the drive (got %duV)" % mid)

func _open_button() -> void:
	var b := _bench()
	b.set_pin_mode(2, "OUTPUT")
	b.set_pin_level_raw(2, BoardSpec.VDD_UV)
	b.place_part(ComponentSpec.button("b1"), {"1": "bb:2:b", "2": "bb:2:f"})
	b.add_wire("esp:gpio2", "bb:2:b")
	b.add_wire("bb:2:j", "esp:GND0")
	var s := _solve(b)
	runner.eq(s.element_ua("b1"), 0, "an open button carries no current")

func _pressed_button() -> void:
	var b := _bench()
	b.set_pin_mode(2, "OUTPUT")
	b.set_pin_level_raw(2, BoardSpec.VDD_UV)
	b.place_part(ComponentSpec.button("b1"), {"1": "bb:2:b", "2": "bb:2:f"})
	b.add_wire("esp:gpio2", "bb:2:b")
	b.add_wire("bb:2:j", "esp:GND0")
	b.press_button("b1", true)
	var s := _solve(b)
	runner.check(s.element_ua("b1") > 0, "a pressed button carries current")
	# 3.3V over the 10 ohm model resistance is well past the pin's rating.
	runner.check(s.outcome != Solver.Outcome.UNPOWERED, "circuit is powered")

func _gpio_drive_clamped() -> void:
	# A pin held HIGH must not exceed VDD even with nothing drawing.
	var b := _bench()
	b.set_pin_mode(2, "OUTPUT")
	b.set_pin_level_raw(2, BoardSpec.VDD_UV)
	var s := _solve(b)
	runner.eq(s.voltage_of("esp:gpio2"), BoardSpec.VDD_UV, "a driven pin sits at 3.3V")

func _power_state_machine() -> void:
	var b := Fixtures.blank_bench()
	Fixtures.good_blink(b)
	var pc := PowerController.new(b)
	runner.eq(pc.state, PowerController.State.OFF, "starts OFF")
	runner.check(pc.request_power_on(), "clean circuit commits power")
	runner.eq(pc.state, PowerController.State.ON, "reaches ON")
	pc.request_power_off()
	runner.eq(pc.state, PowerController.State.OFF, "switch opens again")

func _rail_short_collapses_3v3() -> void:
	var b := _bench()
	Fixtures.rail_short_3v3_gnd(b)
	var s := _solve(b)
	runner.eq(s.outcome, Solver.Outcome.SOURCE_CONFLICT, "3V3-to-GND is a source conflict")
