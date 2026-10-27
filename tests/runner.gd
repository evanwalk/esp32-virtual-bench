## Minimal test runner: no plugin, no framework, no download.
##
## Godot's `--headless --script` runs this directly. Exit code 0 = all pass, 1 = failure,
## so CI needs nothing but the binary that already builds the game.
extends SceneTree

var _pass := 0
var _fail := 0
var _fails: Array[String] = []
var _current := ""

func _initialize() -> void:
	var suites := _discover()
	for path in suites:
		var script: Script = load(path)
		var suite = script.new()
		suite.runner = self
		_current = path
		print("\n== %s" % path.get_file())
		suite.run()
	print("\n---------------------------------------------")
	print("PASS %d   FAIL %d" % [_pass, _fail])
	if _fail > 0:
		for f in _fails:
			print("  FAILED: %s" % f)
		print("RESULT: FAIL")
		quit(1)
	else:
		print("RESULT: PASS")
		quit(0)

func _discover() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://tests/suites")
	if dir == null:
		push_error("no tests/suites directory")
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("res://tests/suites/%s" % f)
	return out

func check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok   %s" % label)
	else:
		_fail += 1
		_fails.append("%s :: %s" % [_current, label])
		print("  FAIL %s" % label)

func eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (got %s, want %s)" % [label, actual, expected])

func has_rule(findings: Array, rule_id: String, label: String) -> void:
	var found := false
	for f in findings:
		if f.rule_id == rule_id:
			found = true
			break
	check(found, "%s [%s]" % [label, rule_id])

func lacks_rule(findings: Array, rule_id: String, label: String) -> void:
	var found := false
	for f in findings:
		if f.rule_id == rule_id:
			found = true
			break
	check(not found, "%s [no %s]" % [label, rule_id])

func has_error(findings: Array, rule_id: String, label: String) -> void:
	for f in findings:
		if f.rule_id == rule_id:
			check(f.level == Severity.Level.ERROR, "%s is ERROR" % label)
			return
	check(false, "%s missing entirely" % label)
