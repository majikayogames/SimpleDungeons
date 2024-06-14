class_name DungeonAStar3D
extends AStar3D

var doors_list = []
var pt_id_to_vec3i = {}
var vec3i_to_pt_id = {}
var dungeon_generator : DungeonGenerator3D
var rooms_check_dict : Dictionary # Vector3i : DungeonRoom3D (Non-Corridor) instance
var corridors_check_dict : Dictionary # Vector3i : DungeonRoom3D (Corridor) instance

var cap_required_doors_phase := false

func can_walk_from_to(dungeon_generator : DungeonGenerator3D, pos_a : Vector3i, pos_b : Vector3i) -> bool:
	if not dungeon_generator.get_grid_aabbi().contains_point(pos_a): return false
	if not dungeon_generator.get_grid_aabbi().contains_point(pos_b): return false
	var room_a = rooms_check_dict[pos_a] if rooms_check_dict.has(pos_a) else null
	var room_b = rooms_check_dict[pos_b] if rooms_check_dict.has(pos_b) else null
	if room_a == null and room_b == null: return pos_a.y == pos_b.y # Outside rooms, only move horizontal
	if room_a == room_b: return true # Inside rooms, move anywhere, up and down, i.e. stairs
	# Ensure walking through doorways if not a simple case:
	var fits_room_a_door = room_a == null or room_a.get_doors_cached().filter(func(d): return d.grid_pos == pos_a and d.exit_pos_grid == pos_b).size() == 1
	var fits_room_b_door = room_b == null or room_b.get_doors_cached().filter(func(d): return d.grid_pos == pos_b and d.exit_pos_grid == pos_a).size() == 1
	return fits_room_a_door and fits_room_b_door

func _init(dungeon_generator : DungeonGenerator3D, rooms_check_dict : Dictionary, corridors_check_dict : Dictionary):
	self.dungeon_generator = dungeon_generator
	self.rooms_check_dict = rooms_check_dict
	self.corridors_check_dict = corridors_check_dict
	
	# Add points to the AStar3D grid
	var point_id = 0
	for x in range(dungeon_generator.dungeon_size.x):
		for y in range(dungeon_generator.dungeon_size.y):
			for z in range(dungeon_generator.dungeon_size.z):
				add_point(point_id, Vector3(x,y,z))
				pt_id_to_vec3i[point_id] = Vector3i(x,y,z)
				vec3i_to_pt_id[Vector3i(x,y,z)] = point_id
				point_id += 1
	
	var xyz_dirs := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1), Vector3i(0,1,0), Vector3i(0,-1,0)] as Array[Vector3i]
	# Connect points - allow walking in & out of all doors but don't connect where walls are.
	for x in range(dungeon_generator.dungeon_size.x):
		for y in range(dungeon_generator.dungeon_size.y):
			for z in range(dungeon_generator.dungeon_size.z):
				var cur_pt_id = get_closest_point(Vector3(x,y,z))
				# Allow walk in/out of room, up & down too for stairs
				for dir in xyz_dirs:
					if can_walk_from_to(dungeon_generator, Vector3i(x,y,z), Vector3i(x,y,z) + dir):
						connect_points(cur_pt_id, get_closest_point(Vector3(x,y,z) + Vector3(dir)))

func _estimate_cost(from_id : int, to_id : int) -> float:
	if dungeon_generator.astar_heuristic == DungeonGenerator3D.AStarHeuristics.NONE_DIJKSTRAS:
		return 0.0
	elif dungeon_generator.astar_heuristic == DungeonGenerator3D.AStarHeuristics.MANHATTAN:
		var diff := get_point_position(to_id) - get_point_position(from_id)
		return (abs(diff.x) + abs(diff.y) + abs(diff.z)) * dungeon_generator.heuristic_scale
	elif dungeon_generator.astar_heuristic == DungeonGenerator3D.AStarHeuristics.EUCLIDEAN:
		var diff := get_point_position(to_id) - get_point_position(from_id)
		return diff.length() * dungeon_generator.heuristic_scale
	return 0.0

func _compute_cost(from_id : int, to_id : int) -> float:
	var diff := get_point_position(to_id) - get_point_position(from_id)
	var cost := diff.length()
	if rooms_check_dict.has(Vector3i(get_point_position(to_id).round())):
		if not cap_required_doors_phase:
			cost *= dungeon_generator.room_cost_multiplier
		else:
			cost *= dungeon_generator.room_cost_at_end_for_required_doors
	if corridors_check_dict.has(Vector3i(get_point_position(to_id).round())):
		cost *= dungeon_generator.corridor_cost_multiplier
	return cost

func get_vec3i_path(from : Vector3i, to : Vector3i) -> Array[Vector3i]:
	var path = get_id_path(vec3i_to_pt_id[from], vec3i_to_pt_id[to])
	var path_vec3i = Array(path).map(func(pt_id : int): return pt_id_to_vec3i[pt_id])
	var typefix : Array[Vector3i] = [] as Array[Vector3i]
	typefix.assign(path_vec3i)
	return typefix
