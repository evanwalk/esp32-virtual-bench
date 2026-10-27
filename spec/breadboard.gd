## Breadboard geometry and its internal tie groups.
##
## A breadboard is not a bag of holes: it has fixed internal copper. Each half-row
## (a-e and f-j) is one tie group; each power rail is one continuous strip. Placing a
## part or a jumper creates a Join through the board, exactly as the real spring clip
## does. This is where most beginners' circuits go wrong, so it is modelled, not faked.
class_name Breadboard
extends RefCounted

const ROWS := 30
const COLUMNS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
const HALVES := {"left": ["a", "b", "c", "d", "e"], "right": ["f", "g", "h", "i", "j"]}
const RAIL_SIDES := ["left", "right"]

var id := "bb1"

func tie_point(row: int, column: String) -> String:
	return "bb:%d:%s" % [row, column]

func rail_stud(side: String, polarity: String, index: int) -> String:
	if side == "left":
		return "bb:rail:%s:%d" % [polarity, index]
	return "bb:rail:%s:r%d" % [polarity, index]

## Declare every terminal and the board's own tie groups into a netlist.
func install(netlist: Netlist) -> void:
	for row in range(ROWS):
		for col in COLUMNS:
			netlist.add_terminal(tie_point(row, col), Netlist.KIND_TIE, {"row": row, "column": col})
	# Row halves conduct to each other. This is the physical board.
	for row in range(ROWS):
		for half in HALVES:
			var group := PackedStringArray()
			for col in HALVES[half]:
				group.append(tie_point(row, col))
			netlist.join_group(group, "bb:row:%d:%s" % [row, half], "tie")
	# Power rails: 25 studs per polarity per side, continuous.
	for side in RAIL_SIDES:
		for polarity in ["+", "-"]:
			var group := PackedStringArray()
			for i in range(25):
				var stud := rail_stud(side, polarity, i)
				netlist.add_terminal(stud, Netlist.KIND_RAIL, {"side": side, "polarity": polarity})
				group.append(stud)
			netlist.join_group(group, "bb:rail:%s:%s" % [side, polarity], "tie")

## Is this a rail stud carrying positive supply?
func is_positive_rail(terminal: String) -> bool:
	return terminal.begins_with("bb:rail:+:")

func is_negative_rail(terminal: String) -> bool:
	return terminal.begins_with("bb:rail:-:")

func is_rail(terminal: String) -> bool:
	return terminal.begins_with("bb:rail:")
