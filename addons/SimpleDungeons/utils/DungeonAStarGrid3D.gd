class_name DungeonAStar3D
extends AStar3D

var corridors = [] as Array[Vector3i]
var doors_list = []
# Dict with grid_pos:Array[grid_direction, grid_direction, ...] of which way you can walk in doors from grid positions
var positions_with_door_leading_in_to = {}
var pt_id_to_vec3i = {}
var vec3i_to_pt_id = {}

func _init(dungeon_generator : DungeonGenerator3D, rooms_placed : Array[DungeonRoom3D]):
	for room in rooms_placed:
		for door in room.get_doors():
			if not dungeon_generator.get_grid_aabbi().contains_point(door.exit_pos_grid): continue
			if not positions_with_door_leading_in_to.has(door.exit_pos_grid):
				positions_with_door_leading_in_to[door.exit_pos_grid] = []
			positions_with_door_leading_in_to[door.exit_pos_grid].push_back(door.grid_pos - door.exit_pos_grid)
	
	# Add points to the AStar3D grid
	var point_id = 0
	for x in range(dungeon_generator.dungeon_size.x):
		for y in range(dungeon_generator.dungeon_size.y):
			for z in range(dungeon_generator.dungeon_size.z):
				add_point(point_id, Vector3(x,y,z))
				pt_id_to_vec3i[point_id] = Vector3i(x,y,z)
				vec3i_to_pt_id[Vector3i(x,y,z)] = point_id
				point_id += 1
	
	var xz_dirs := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)] as Array[Vector3i]
	var xyz_dirs := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1), Vector3i(0,1,0), Vector3i(0,-1,0)] as Array[Vector3i]
	# Connect points - allow walking in & out of all doors but don't connect where walls are.
	for x in range(dungeon_generator.dungeon_size.x):
		for y in range(dungeon_generator.dungeon_size.y):
			for z in range(dungeon_generator.dungeon_size.z):
				var cur_pt_id = get_closest_point(Vector3(x,y,z))
				# Inside room - allow walk inside room & check for doors leading out
				var room := dungeon_generator.get_room_at_pos(Vector3i(x,y,z))
				if room:
					# Allow walk inside room, up & down too for stairs
					for dir in xyz_dirs:
						if room.get_grid_aabbi(false).contains_point(Vector3i(x,y,z) + dir):
							connect_points(cur_pt_id, get_closest_point(Vector3(x,y,z) + Vector3(dir)))
					# Allow walk out of all doors
					for door in room.get_doors_cached():
						if door.grid_pos == Vector3i(x,y,z) and dungeon_generator.get_grid_aabbi().contains_point(door.exit_pos_grid):
							connect_points(cur_pt_id, get_closest_point(Vector3(door.exit_pos_grid)))
				else: # Outside room - check for doors leading in
					# Walk freely if not landing in any rooms. Only horizontally, can only traverse up & down with stairs
					for dir in xz_dirs:
						if dungeon_generator.get_room_at_pos(Vector3i(x,y,z) + dir) == null and dungeon_generator.get_grid_aabbi().contains_point(Vector3i(x,y,z) + dir):
							connect_points(cur_pt_id, get_closest_point(Vector3(x,y,z) + Vector3(dir)))
					# Allow walk into room doors
					if positions_with_door_leading_in_to.has(Vector3i(x,y,z)):
						for in_dir in positions_with_door_leading_in_to[Vector3i(x,y,z)]:
							connect_points(cur_pt_id, get_closest_point(Vector3(x,y,z) + Vector3(in_dir)))


func get_vec3i_path(from : Vector3i, to : Vector3i) -> Array[Vector3i]:
	var path = get_id_path(vec3i_to_pt_id[from], vec3i_to_pt_id[to])
	var path_vec3i = Array(path).map(func(pt_id : int): return pt_id_to_vec3i[pt_id])
	var typefix : Array[Vector3i] = [] as Array[Vector3i]
	typefix.assign(path_vec3i)
	return typefix
