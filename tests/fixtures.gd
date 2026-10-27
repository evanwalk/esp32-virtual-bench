## Shared fixtures: build benches by writing jumpers the way a user would.
##
## Layout note: a breadboard's left half-row (a-e) is one net, the right half-row (f-j)
## is another, and the centre channel splits them. A part that must drop voltage has to
## straddle the channel: one lead in a left hole, one in a right hole. Parts that only
## need to sit in the circuit stay on their own side.
class_name Fixtures
extends RefCounted

static func blank_bench() -> Bench:
	return Bench.new(BoardSpec.new())

## Correct blink circuit on GPIO2: pin -> 330R -> LED -> GND rail -> board GND.
static func good_blink(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	# Resistor straddles the centre channel at row 5: left leg is the pin net.
	bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
	# LED straddles at row 8: anode fed from the resistor side, cathode to ground row.
	bench.place_part(ComponentSpec.led("led1", "red"), {"A": "bb:8:c", "K": "bb:8:h"})
	bench.add_wire("esp:gpio2", "bb:5:b")
	bench.add_wire("bb:5:h", "bb:8:c")
	bench.add_wire("bb:8:h", "bb:rail:-:0")
	bench.add_wire("bb:rail:-:1", "esp:GND0")
	return bench

## 5V jumper straight onto a 3.3V GPIO.
static func five_volt_on_gpio(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "INPUT")
	bench.add_wire("esp:VIN", "bb:10:b")
	bench.add_wire("bb:10:b", "esp:gpio2")
	return bench

static func rail_short_5v_gnd(bench: Bench) -> Bench:
	bench.add_wire("esp:VIN", "bb:rail:+:0")
	bench.add_wire("bb:rail:+:1", "esp:GND0")
	return bench

static func rail_short_3v3_gnd(bench: Bench) -> Bench:
	bench.add_wire("esp:3V3", "bb:rail:+:0")
	bench.add_wire("bb:rail:+:2", "esp:GND0")
	return bench

static func rail_short_5v_3v3(bench: Bench) -> Bench:
	bench.add_wire("esp:VIN", "esp:3V3")
	return bench

## LED backwards: cathode toward the drive, anode to ground.
static func led_reversed(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
	bench.place_part(ComponentSpec.led("led1", "red"), {"K": "bb:8:c", "A": "bb:8:h"})
	bench.add_wire("esp:gpio2", "bb:5:b")
	bench.add_wire("bb:5:h", "bb:8:c")
	bench.add_wire("bb:8:h", "bb:rail:-:0")
	bench.add_wire("bb:rail:-:1", "esp:GND0")
	return bench

## LED with no series resistance: straight across pin and ground.
static func led_no_resistor(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	bench.place_part(ComponentSpec.led("led1", "red"), {"A": "bb:5:c", "K": "bb:5:h"})
	bench.add_wire("esp:gpio2", "bb:5:b")
	bench.add_wire("bb:5:h", "esp:GND0")
	return bench

## Complete-ish circuit with the ground run missing.
static func missing_ground(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
	bench.place_part(ComponentSpec.led("led1", "red"), {"A": "bb:8:c", "K": "bb:8:h"})
	bench.add_wire("esp:gpio2", "bb:5:b")
	bench.add_wire("bb:5:h", "bb:8:c")
	# The LED cathode leg ties to an unearthed rail strip, so the loop never closes.
	bench.add_wire("bb:8:h", "bb:rail:-:0")
	return bench

static func input_only_output(bench: Bench) -> Bench:
	bench.set_pin_mode(34, "OUTPUT")
	bench.set_pin_level_raw(34, BoardSpec.VDD_UV)
	return bench

static func flash_pin(bench: Bench) -> Bench:
	bench.set_pin_mode(6, "OUTPUT")
	bench.add_wire("esp:gpio6", "bb:1:b")
	return bench

static func strap_low(bench: Bench) -> Bench:
	bench.add_wire("esp:gpio0", "bb:1:b")
	bench.add_wire("bb:1:b", "esp:GND0")
	return bench

static func adc2_wifi(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "ADC")
	bench.add_wire("esp:gpio2", "bb:20:b")
	return bench

## Three unprotected LEDs in parallel on one pin: far past the pin's current rating.
static func pin_overcurrent(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	for i in range(3):
		var row := 10 + i
		bench.place_part(ComponentSpec.led("led%d" % i, "red"), {"A": "bb:%d:c" % row, "K": "bb:%d:h" % row})
		bench.add_wire("esp:gpio2", "bb:%d:b" % row)
		bench.add_wire("bb:%d:h" % row, "bb:rail:-:0")
	bench.add_wire("bb:rail:-:1", "esp:GND0")
	return bench

## Button between a driven pin and ground (button reads as a driven load).
static func button_to_ground(bench: Bench) -> Bench:
	bench.set_pin_mode(2, "OUTPUT")
	bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
	bench.place_part(ComponentSpec.button("b1"), {"1": "bb:5:c", "2": "bb:5:h"})
	bench.add_wire("esp:gpio2", "bb:5:b")
	bench.add_wire("bb:5:h", "esp:GND0")
	return bench
