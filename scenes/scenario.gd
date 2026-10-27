## Scenarios: ready-made circuits, including the deliberately broken ones.
##
## Each scenario builds a Bench the same way a user would — parts seated, wires run — so
## a scenario proves the same path the interaction layer uses. Loaded by key so the HUD
## and the tests share one definition.
class_name Scenario
extends RefCounted

const NAMES := {
	"blink": "Blink LED on GPIO2 (correct)",
	"five_volt": "5V jumper onto GPIO2 (broken)",
	"rail_short": "5V rail shorted to GND (broken)",
	"led_backwards": "LED fitted backwards (broken)",
	"no_ground": "Missing ground return (broken)",
}

static func build(key: String) -> Bench:
	var bench := Bench.new(BoardSpec.new())
	match key:
		"blink":
			# GPIO2 -> 330R -> LED -> GND rail -> board GND.
			bench.set_pin_mode(2, "OUTPUT")
			bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
			bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
			bench.place_part(ComponentSpec.led("led1", "red"), {"A": "bb:8:c", "K": "bb:8:h"})
			bench.add_wire("esp:gpio2", "bb:5:b")
			bench.add_wire("bb:5:h", "bb:8:c")
			bench.add_wire("bb:8:h", "bb:rail:-:0")
			bench.add_wire("bb:rail:-:1", "esp:GND0")
		"five_volt":
			# 5V straight onto a 3.3V GPIO.
			bench.set_pin_mode(2, "INPUT")
			bench.add_wire("esp:VIN", "bb:10:b")
			bench.add_wire("bb:10:b", "esp:gpio2")
		"rail_short":
			bench.add_wire("esp:VIN", "bb:rail:+:0")
			bench.add_wire("bb:rail:+:1", "esp:GND0")
		"led_backwards":
			bench.set_pin_mode(2, "OUTPUT")
			bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
			bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
			bench.place_part(ComponentSpec.led("led1", "red"), {"K": "bb:8:c", "A": "bb:8:h"})
			bench.add_wire("esp:gpio2", "bb:5:b")
			bench.add_wire("bb:5:h", "bb:8:c")
			bench.add_wire("bb:8:h", "bb:rail:-:0")
			bench.add_wire("bb:rail:-:1", "esp:GND0")
		"no_ground":
			bench.set_pin_mode(2, "OUTPUT")
			bench.set_pin_level_raw(2, BoardSpec.VDD_UV)
			bench.place_part(ComponentSpec.resistor("r1", 330.0), {"1": "bb:5:c", "2": "bb:5:h"})
			bench.place_part(ComponentSpec.led("led1", "red"), {"A": "bb:8:c", "K": "bb:8:h"})
			bench.add_wire("esp:gpio2", "bb:5:b")
			bench.add_wire("bb:5:h", "bb:8:c")
			bench.add_wire("bb:8:h", "bb:rail:-:0")
	return bench
