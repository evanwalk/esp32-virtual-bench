## The circuit graph: terminals, conductive joins, and node resolution.
##
## Vertices are Terminals (breadboard tie points, rails, component leads, board pins).
## Edges are Joins created by exactly three things: a jumper wire, the breadboard's
## internal tie groups, and a component's own internal conduction. Every Join remembers
## which element made it, so diagnostics can point at *the wire* that made it wrong.
##
## Node resolution is union-find. Two terminals in one node are the same copper. The
## solver works on nodes, never on raw terminals, so a fault is found once no matter how
## many terminals the fault touches.
class_name Netlist
extends RefCounted

const KIND_PIN := "pin"
const KIND_RAIL := "rail"
const KIND_TIE := "tie"
const KIND_LEAD := "lead"

## id -> { kind: String, meta: Dictionary }
var _terminals: Dictionary = {}
## id -> [terminal ids]; one entry per node after resolve().
var _nodes: Array[PackedStringArray] = []
## terminal id -> node id
var _node_of: Dictionary = {}
## Join records: { terminals: PackedStringArray, element: String, kind: String }
var _joins: Array[Dictionary] = []
var _resolved := false

func add_terminal(id: String, kind: String, meta: Dictionary = {}) -> bool:
	if _terminals.has(id):
		return false
	_terminals[id] = {"kind": kind, "meta": meta}
	_resolved = false
	return true

func has_terminal(id: String) -> bool:
	return _terminals.has(id)

func remove_terminal(id: String) -> void:
	_terminals.erase(id)
	_node_of.erase(id)
	_resolved = false

func terminal_kind(id: String) -> String:
	return _terminals.get(id, {}).get("kind", "")

func terminal_meta(id: String) -> Dictionary:
	return _terminals.get(id, {}).get("meta", {})

func terminal_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _terminals:
		out.append(id)
	return out

## Join two terminals. `kind` is "wire", "tie", or "comp".
func join(a: String, b: String, element: String, kind: String = "wire") -> bool:
	if not _terminals.has(a) or not _terminals.has(b):
		return false
	for j in _joins:
		if j["element"] == element and j["kind"] == kind:
			j["terminals"].append(a)
			j["terminals"].append(b)
			_resolved = false
			return true
	_joins.append({"terminals": PackedStringArray([a, b]), "element": element, "kind": kind})
	_resolved = false
	return true

## Add a multi-terminal join at once (board tie groups, component bodies).
func join_group(terminals: PackedStringArray, element: String, kind: String) -> bool:
	if terminals.size() < 2:
		return false
	for t in terminals:
		if not _terminals.has(t):
			return false
	_joins.append({"terminals": terminals.duplicate(), "element": element, "kind": kind})
	_resolved = false
	return true

## Remove every join belonging to an element (wire pulled, component lifted).
func remove_element(element: String) -> void:
	for i in range(_joins.size() - 1, -1, -1):
		if _joins[i]["element"] == element:
			_joins.remove_at(i)
			_resolved = false

func joins() -> Array[Dictionary]:
	return _joins

func elements() -> PackedStringArray:
	var out := PackedStringArray()
	for j in _joins:
		if not out.has(j["element"]):
			out.append(j["element"])
	return out

## Union-find resolution. Idempotent; cached until the graph changes.
func resolve() -> void:
	if _resolved:
		return
	var parent := {}
	for id in _terminals:
		parent[id] = id
	for j in _joins:
		var terms: PackedStringArray = j["terminals"]
		if terms.size() < 2:
			continue
		var root := _find(parent, terms[0])
		for i in range(1, terms.size()):
			var other := _find(parent, terms[i])
			if other != root:
				parent[other] = root
	# Collapse to node ids and a terminal -> node map.
	_nodes.clear()
	_node_of.clear()
	var index := {}
	for id in _terminals:
		var root := _find(parent, id)
		if not index.has(root):
			index[root] = _nodes.size()
			_nodes.append(PackedStringArray())
		var node: int = index[root]
		_nodes[node].append(id)
		_node_of[id] = node
	_resolved = true

func _find(parent: Dictionary, id: String) -> String:
	var r := id
	while parent[r] != r:
		r = parent[r]
	# Path compression.
	while parent[id] != r:
		var next: String = parent[id]
		parent[id] = r
		id = next
	return r

func node_count() -> int:
	resolve()
	return _nodes.size()

func node_of(terminal: String) -> int:
	resolve()
	return _node_of.get(terminal, -1)

func node_terminals(node: int) -> PackedStringArray:
	resolve()
	if node < 0 or node >= _nodes.size():
		return PackedStringArray()
	return _nodes[node]

## All terminals on the same copper as `terminal`, excluding itself.
func node_peers(terminal: String) -> PackedStringArray:
	var out := PackedStringArray()
	var node := node_of(terminal)
	for t in node_terminals(node):
		if t != terminal:
			out.append(t)
	return out

## Elements that join two terminals directly on the same node.
func elements_on_node(node: int) -> PackedStringArray:
	resolve()
	var members := node_terminals(node)
	var out := PackedStringArray()
	for j in _joins:
		for t in j["terminals"]:
			if members.has(t):
				if not out.has(j["element"]):
					out.append(j["element"])
				break
	return out
