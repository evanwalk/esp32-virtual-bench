## One diagnostic finding.
##
## A finding is deliberately verbose: it names the rule, the offending netlist
## elements, the electrical reason, and the concrete fix. A learner reading only the
## HUD should be able to correct the circuit without reading source.
class_name Finding
extends RefCounted

var rule_id: String
var level: int
var message: String
var reason: String
var fix: String
## Terminal ids the finding is about; the VR layer highlights these.
var terminals: PackedStringArray = PackedStringArray()
## Element ids (wires, components) that created the fault.
var elements: PackedStringArray = PackedStringArray()

func _init(p_rule_id: String, p_level: int, p_message: String, p_reason: String, p_fix: String) -> void:
	rule_id = p_rule_id
	level = p_level
	message = p_message
	reason = p_reason
	fix = p_fix

func is_error() -> bool:
	return level == Severity.Level.ERROR

func with_terminals(ids: PackedStringArray) -> Finding:
	terminals = ids
	return self

func with_elements(ids: PackedStringArray) -> Finding:
	elements = ids
	return self

func to_line() -> String:
	return "%s %s: %s | reason: %s | fix: %s" % [
		Severity.LABEL[level], rule_id, message, reason, fix,
	]

func to_dict() -> Dictionary:
	return {
		"rule_id": rule_id,
		"level": level,
		"message": message,
		"reason": reason,
		"fix": fix,
		"terminals": Array(terminals),
		"elements": Array(elements),
	}
