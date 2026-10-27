## Component specs: the parts that can sit on the bench.
##
## Each spec declares its terminals and its internal conduction (the copper *inside*
## the part). A resistor conducts; an LED conducts one way with a forward drop; a button
## conducts only while held. The bench layer asks a spec what it does; the spec decides.
class_name ComponentSpec
extends RefCounted

enum Kind { LED, RESISTOR, BUTTON, JUMPER }

const LED_FORWARD_DROP_UV := {
	"red": 1_800_000,
	"green": 2_800_000,
	"blue": 3_000_000,
}
const LED_MAX_MA := 20
const LED_REVERSE_BREAKDOWN_UV := 5_000_000

var kind: int
var id: String
## Ordered terminal suffix ids, e.g. ["A", "K"] for an LED.
var terminal_suffixes: PackedStringArray = PackedStringArray()
## Ohms; 0 for a jumper.
var resistance_ohm: float = 0.0
var forward_drop_uv: int = 0
var colour := ""

func _init(p_kind: int, p_id: String) -> void:
	kind = p_kind
	id = p_id
	match kind:
		Kind.LED:
			terminal_suffixes = PackedStringArray(["A", "K"])
		Kind.RESISTOR, Kind.BUTTON:
			terminal_suffixes = PackedStringArray(["1", "2"])
		Kind.JUMPER:
			terminal_suffixes = PackedStringArray(["A", "B"])

func terminal_id(suffix: String) -> String:
	return "%s:%s" % [id, suffix]

func all_terminals() -> PackedStringArray:
	var out := PackedStringArray()
	for s in terminal_suffixes:
		out.append(terminal_id(s))
	return out

## Conduction between the two leads. `state` carries live values (button held, etc).
func conducts(state: Dictionary = {}) -> bool:
	match kind:
		Kind.JUMPER, Kind.RESISTOR:
			return true
		Kind.BUTTON:
			return state.get("held", false)
		Kind.LED:
			# The diode only conducts forward; direction is decided by the solver from
			# resolved node voltages, so the spec itself is unconditionally conductive.
			return true
	return false

## Ohms contributed between the leads for the current model.
func series_ohms(state: Dictionary = {}) -> float:
	match kind:
		Kind.LED:
			return 0.0
		Kind.BUTTON:
			return 10.0 if state.get("held", false) else INF
		Kind.RESISTOR:
			return resistance_ohm
		Kind.JUMPER:
			return 0.01
	return INF

static func led(p_id: String, colour_name: String) -> ComponentSpec:
	var spec := ComponentSpec.new(Kind.LED, p_id)
	spec.colour = colour_name
	spec.forward_drop_uv = LED_FORWARD_DROP_UV.get(colour_name, 1_800_000)
	return spec

static func resistor(p_id: String, ohms: float) -> ComponentSpec:
	var spec := ComponentSpec.new(Kind.RESISTOR, p_id)
	spec.resistance_ohm = ohms
	return spec

static func button(p_id: String) -> ComponentSpec:
	return ComponentSpec.new(Kind.BUTTON, p_id)

static func jumper(p_id: String) -> ComponentSpec:
	return ComponentSpec.new(Kind.JUMPER, p_id)
