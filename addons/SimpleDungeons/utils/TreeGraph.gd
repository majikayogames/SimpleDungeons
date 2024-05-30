class_name TreeGraph

## TreeGraph: A utility class used to ensure all rooms and floors on the dungeon are connected.

var _nodes = []
var _roots = {}

func _init(nodes : Array = []):
	self._nodes = nodes
	# Initially, each node is its own root.
	for node in nodes:
		self._roots[node] = node

func add_node(node : Variant):
	self._nodes.append(node)
	self._roots[node] = node

func has_node(node : Variant):
	return node in _nodes

func get_all_nodes() -> Array:
	return _nodes

func find_root(node) -> Variant:
	if _roots[node] != node:
		# Compress the path and set all nodes along the way to the root
		_roots[node] = find_root(_roots[node])
	return _roots[node]

# Tricky. Messed this up at first. Always set the root to the lower (index) root to keep it stable
func connect_nodes(node_a, node_b) -> void:
	if find_root(node_a) != find_root(node_b):
		if _nodes.find(find_root(node_a)) < _nodes.find(find_root(node_b)):
			_roots[find_root(node_b)] = _roots[find_root(node_a)]
		else:
			_roots[find_root(node_a)] = _roots[find_root(node_b)]

func are_nodes_connected(node_a, node_b) -> bool:
	return find_root(node_a) == find_root(node_b)

func is_fully_connected() -> bool:
	return len(_nodes) == 0 or _nodes.all(func(node): return are_nodes_connected(node, _nodes[0]))
