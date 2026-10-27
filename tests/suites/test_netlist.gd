extends RefCounted

var runner

func run() -> void:
	_netlist_basics()
	_breadboard_ties()
	_placement()

func _netlist_basics() -> void:
	var nl := Netlist.new()
	nl.add_terminal("a", "tie")
	nl.add_terminal("b", "tie")
	nl.add_terminal("c", "tie")
	runner.check(nl.node_of("a") != nl.node_of("b"), "unjoined terminals are separate nodes")
	nl.join("a", "b", "w1")
	runner.eq(nl.node_of("a"), nl.node_of("b"), "a wire puts two terminals on one node")
	runner.check(nl.node_of("c") != nl.node_of("a"), "the wire does not drag in a third")
	nl.join("b", "c", "w2")
	runner.eq(nl.node_of("a"), nl.node_of("c"), "continuity chains transitively")
	nl.remove_element("w1")
	runner.check(nl.node_of("a") != nl.node_of("c"), "pulling a wire breaks the chain")
	runner.eq(nl.node_peers("a").size(), 0, "no peers once the wire is gone")

func _breadboard_ties() -> void:
	var bench := Bench.new(BoardSpec.new())
	var nl := bench.netlist
	# a-e are one half-row group; f is not.
	runner.eq(nl.node_of("bb:3:a"), nl.node_of("bb:3:e"), "a-e share a tie group")
	runner.check(nl.node_of("bb:3:a") != nl.node_of("bb:3:f"), "the centre channel splits the row")
	runner.check(nl.node_of("bb:3:a") != nl.node_of("bb:4:a"), "rows do not bleed into each other")
	runner.eq(nl.node_of("bb:rail:+:0"), nl.node_of("bb:rail:+:24"), "a rail is continuous along its side")
	runner.check(nl.node_of("bb:rail:+:0") != nl.node_of("bb:rail:-:0"), "the two rails are separate")
	runner.check(nl.node_of("bb:rail:+:0") != nl.node_of("bb:rail:+:r0"), "rail sides are separate")
	runner.eq(nl.node_of("esp:GND0"), nl.node_of("esp:GND2"), "all board GND pins are common")

func _placement() -> void:
	var bench := Bench.new(BoardSpec.new())
	var r := ComponentSpec.resistor("r1", 330.0)
	runner.check(bench.place_part(r, {"1": "bb:1:b", "2": "bb:2:b"}), "part seats into free holes")
	runner.eq(bench.netlist.node_of("r1:1"), bench.netlist.node_of("bb:1:b"), "lead 1 is bonded to its hole")
	runner.check(bench.place_part(r, {"1": "bb:3:b", "2": "bb:4:b"}) == false, "a part cannot seat twice")
	var b := ComponentSpec.button("b1")
	bench.place_part(b, {"1": "bb:6:b", "2": "bb:6:f"})
	runner.check(bench.netlist.node_of("b1:1") != bench.netlist.node_of("b1:2"), "button leads are distinct across the channel")
	var sw := ComponentSpec.button("b2")
	bench.place_part(sw, {"1": "bb:7:b", "2": "bb:7:d"})
	runner.eq(bench.netlist.node_of("b2:1"), bench.netlist.node_of("b2:2"), "leads in one half-row land on the same net")
	bench.lift_part("r1")
	runner.check(not bench.parts.has("r1"), "lifting removes the part")
	runner.check(not bench.netlist.has_terminal("r1:1"), "a lifted part leaves no dangling lead")
