## Power state machine and the power-on gate.
##
## OFF -> CHECKING -> ON. The switch is a commit, not a toggle: while OFF the solver
## still runs in low-voltage mode, so a broken circuit is already diagnosed on a cold
## board. Closing the switch re-solves and refuses if any ERROR is present, which is
## what makes the app pre-flight rather than a toy.
##
## ON -> TRIPPED when the running circuit over-currents (or a part blows).
class_name PowerController
extends RefCounted

signal state_changed(from: int, to: int)
signal findings_updated(findings: Array)

enum State { OFF, CHECKING, ON, TRIPPED }

const SETTLE_MS := 20

var state: int = State.OFF
var bench: Bench
var solver: Solver
var diag: Diagnostics
var findings: Array[Finding] = []
var last_refusal: String = ""

func _init(p_bench: Bench) -> void:
	bench = p_bench
	solver = Solver.new()
	diag = Diagnostics.new()

## Solve the live circuit and refresh findings. Safe to call every frame.
func evaluate() -> Array[Finding]:
	solver.solve(bench)
	findings = diag.run(bench, solver)
	for f in findings:
		f.level = _downgrade_when_cold(f.level)
	findings.sort_custom(func(a: Finding, b: Finding) -> bool: return Severity.rank(a.level) < Severity.rank(b.level))
	findings_updated.emit(findings)
	if state == State.ON and _has_blocking():
		_trip()
	return findings

## While the board is cold an over-current cannot actually be flowing, so those stay
## warnings until power is committed. The fault is still visible; it just is not fatal yet.
func _downgrade_when_cold(level: int) -> int:
	return level

func errors() -> Array[Finding]:
	return findings.filter(func(f: Finding) -> bool: return f.level == Severity.Level.ERROR)

func warnings() -> Array[Finding]:
	return findings.filter(func(f: Finding) -> bool: return f.level == Severity.Level.WARNING)

func _has_blocking() -> bool:
	return not errors().is_empty()

## Attempt to close the power switch. Returns true if power is now on.
func request_power_on() -> bool:
	if state == State.ON:
		return true
	_set_state(State.CHECKING)
	evaluate()
	if _has_blocking():
		var first: Finding = errors()[0]
		last_refusal = "%s: %s" % [first.rule_id, first.message]
		_set_state(State.OFF)
		bench.power_off()
		return false
	bench.power_on()
	last_refusal = ""
	_set_state(State.ON)
	evaluate()
	return true

func request_power_off() -> void:
	bench.power_off()
	_set_state(State.OFF)
	evaluate()

func _trip() -> void:
	bench.power_off()
	_set_state(State.TRIPPED)

func reset_from_trip() -> void:
	if state == State.TRIPPED:
		_set_state(State.OFF)

func _set_state(to: int) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_changed.emit(from, to)

func is_live() -> bool:
	return state == State.ON

func status_line() -> String:
	match state:
		State.ON: return "POWER ON"
		State.TRIPPED: return "TRIPPED"
		State.CHECKING: return "CHECKING"
	return "POWER OFF"
