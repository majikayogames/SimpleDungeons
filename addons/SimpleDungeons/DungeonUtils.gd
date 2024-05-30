class_name DungeonUtils
extends Node

enum Direction { LEFT = 0, RIGHT = 1, FRONT = 2, BACK = 3 }
const NEGATE_DIRECTION = {
	Direction.LEFT: Direction.RIGHT, Direction.RIGHT: Direction.LEFT,
	Direction.FRONT: Direction.BACK, Direction.BACK: Direction.FRONT
}
const DIRECTION_VECTORS = {
	Direction.LEFT: Vector3(-1,0,0), Direction.RIGHT: Vector3(1,0,0),
	Direction.FRONT: Vector3(0,0,1), Direction.BACK: Vector3(0,0,-1),
}
static func vec3_to_direction(vec : Vector3) -> Direction:
	var closest = Direction.LEFT
	var closest_dot = -INF
	for dir in DIRECTION_VECTORS.keys():
		var dir_vec = DIRECTION_VECTORS[dir]
		if dir_vec.dot(vec.normalized()) > closest_dot:
			closest_dot = dir_vec.dot(vec.normalized())
			closest = dir
	return closest

#static func rotate_vec3i(vec : Vector3i, angle : float, axis : Vector3 = Vector3.UP) -> Vector3i:
	#for i in wrapi(cc_90_turns, 0, 4): vec = Vector3i(-vec.z, vec.y, vec.x)
#	return vec

static func _make_set(arr: Array) -> Array:
	var unique_elements = []
	for element in arr:
		if element not in unique_elements:
			unique_elements.append(element)
	return unique_elements

static func _flatten(arr: Array, depth: int = 1) -> Array:
	var result = Array()
	for element in arr:
		if element is Array and depth > 0:
			result += _flatten(element, depth - 1)
		else:
			result.append(element)
	return result


static func _vec3i_min(a : Vector3i, b : Vector3i) -> Vector3i:
	return Vector3i(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))

static func _vec3i_max(a : Vector3i, b : Vector3i) -> Vector3i:
	return Vector3i(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))

class DungeonFloorAStarGrid2D extends AStarGrid2D:
	var corridors = [] as Array[Vector2i]
	
	func _init(dungeon_size : Vector3i, all_dungeon_rooms : Array, floor : int):
		self.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		self.region = Rect2i(0, 0, dungeon_size.x, dungeon_size.z)
		self.update()
		for x in dungeon_size.x:
			for z in dungeon_size.z:
				if all_dungeon_rooms.any(func(_r): return _r.get_aabb_in_grid().has_point(Vector3(x + 0.5,floor + 0.5,z + 0.5))):
					set_point_solid(Vector2i(x,z))
	#
	func _compute_cost(from : Vector2i, to : Vector2i):
		return 0 if corridors.has(to) else self.cell_size.x
	
	func _estimate_cost(from : Vector2i, to : Vector2i):
		return 0 # Make it Dijkstra's algorithm
	
	func add_corridor(xz : Vector2i):
		corridors.push_back(xz)
