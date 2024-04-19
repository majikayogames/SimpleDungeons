@tool
class_name DungeonGenerator
extends Node3D

enum BuildStage { PLACE_ROOMS = 0, PLACE_STAIRS = 1, SEPARATE_ROOMS = 2, CONNECT_ROOMS = 3, SPAWN_ROOMS = 4, DONE = 5 }
var stage : BuildStage = BuildStage.DONE

@export var dungeon_kit_scene : PackedScene :
	set(value):
		if dungeon_kit_scene != value:
			dungeon_kit_scene = value
			dungeon_kit_inst = dungeon_kit_scene.instantiate()

## Dungeon grid size measured in the standardized room size chosen on the DungeonKit.
@export var dungeon_size := Vector3i(10,10,10)

## Seed to use when generating the dungeon. 0 for random. You can call generate(seed) to override.
@export var generate_seed = 0
@export var generate_on_ready : bool = true
@export var generate_threaded : bool = false
## Depending on the dungeon kit used and the separation/connecting algorithm, it's possible that
## a dungeon may not be able to correctly generate and have all rooms reachable/not overlapping.
## In that case, the algorithm can simply restart from the beginning and try again.
@export var max_retries : int = 5
@export var max_safe_iterations : int = 250

@export var show_debug_grid_in_editor : bool = true
@export var show_debug_grid_in_game : bool = false

## Generate the dungeon in editor. If you added any custom rooms which extend DungeonRoom,
## they also need the @tool directive for this to work.
@export var editor_button_generate_dungeon : bool = false :
	set(value):
		dungeon_kit_inst = dungeon_kit_scene.instantiate() # may need update if editing and re-generating
		generate()

var dungeon_kit_inst : DungeonKit
var _editor_aabb_cube_visual : Node3D

var iterations = 0
var retry_attempts = 0

var _rooms_container : Node3D
func create_or_recreate_rooms_container():
	if get_node_or_null("RoomsContainer"):
		var rc = get_node_or_null("RoomsContainer")
		remove_child(rc)
		rc.queue_free()
		_rooms_container = null
	if _rooms_container != null:
		_rooms_container.queue_free()
	_rooms_container = Node3D.new()
	_rooms_container.position = Vector3(dungeon_size) * dungeon_kit_inst.grid_voxel_size / -2
	_rooms_container.name = "RoomsContainer"
	_rooms = [] as Array[DungeonRoom]
	_room_counts = {}
	_floors_graphs = []
	_stairs_graph = null
	_rooms_on_each_floor = []
	_doors_on_each_floor = []
	for room in dungeon_kit_inst.get_rooms():
		_room_counts[room] = 0

var _rooms = [] as Array[DungeonRoom]
var _room_counts = {}
var _stairs_graph : DungeonUtils.TreeGraph
var _floors_graphs : Array
var _rooms_on_each_floor : Array
var _doors_on_each_floor : Array
var _grid_to_room_arr_3d : Array
func get_room_at_pos(pos : Vector3i) -> DungeonRoom:
	if pos.x < 0 or pos.y < 0 or pos.z < 0: return null
	if pos.x >= dungeon_size.x or pos.y >= dungeon_size.y or pos.z >= dungeon_size.z: return null
	return _grid_to_room_arr_3d[pos.x][pos.y][pos.z]
var _astar_grids : Array
var _rng = RandomNumberGenerator.new()

var _is_generating := false
func generate(seed_override = null):
	if not does_pass_safety_checks():
		printerr("Unable to generate dungeon.")
		return false
	if seed_override != null:
		_rng.seed = seed_override
	elif generate_seed != 0:
		_rng.seed = generate_seed
	else:
		_rng.randomize()
	print("Using dungeon generation seed: ", _rng.get_seed())
	iterations = 0
	retry_attempts = 0
	start_generate_loop()

func start_generate_loop():
	stage = BuildStage.PLACE_ROOMS
	create_or_recreate_rooms_container()
	var success_placing = place_rooms_and_stairs()
	if success_placing:
		print("Success placing")
	else:
		print("Failed placing")
		stage = BuildStage.PLACE_ROOMS
		if retry_attempts < max_retries:
			iterations = 0
			retry_attempts += 1
			start_generate_loop.call_deferred()
		else:
			print("Failed to generate dungeon.")
		return
	
	if generate_threaded and not Engine.is_editor_hint():
		var t = Thread.new()
		t.start(_generate_loop)
	else:
		_generate_loop()

func _generate_loop():
	while stage != BuildStage.DONE and iterations < max_safe_iterations:
		var success = continue_generating()
		if not success:
			if retry_attempts < max_retries:
				iterations = 0
				retry_attempts += 1
				start_generate_loop.call_deferred()
			else:
				print("Failed to generate dungeon.")
			return

######################
## INIT AND PROCESS ##
######################

func _init():
	RenderingServer.set_debug_generate_wireframes(true)
func _input(event):
	if event is InputEventKey and Input.is_key_pressed(KEY_N):
		var vp = get_viewport()
		vp.debug_draw = (vp.debug_draw + 1 ) % 4

# Called when the node enters the scene tree for the first time.
func _ready():
	if show_debug_grid_in_game or Engine.is_editor_hint():
		_editor_aabb_cube_visual = preload("res://addons/SimpleDungeons/WireframeCube.tscn").instantiate()
		add_child(_editor_aabb_cube_visual)
	if Engine.is_editor_hint():
		return
	
	if generate_on_ready:
		generate.call_deferred(generate_seed if generate_seed != 0 else null)

func _process(delta):
	if _editor_aabb_cube_visual:
		_editor_aabb_cube_visual.visible = show_debug_grid_in_editor if Engine.is_editor_hint() else show_debug_grid_in_game
		if dungeon_kit_inst:
			_editor_aabb_cube_visual.scale = Vector3(dungeon_size) * dungeon_kit_inst.grid_voxel_size
			_editor_aabb_cube_visual.grid_size = dungeon_size
	if Engine.is_editor_hint():
		return

func place_rooms_and_stairs() -> bool:
	stage = BuildStage.PLACE_ROOMS
	while not placed_minimum_rooms():
		var room = get_random_room()
		var rand_pos = get_rand_pos_for_room(room)
		duplicate_and_place_room(room, rand_pos)
	stage += 1
	while not all_floors_connected():
		var connect_result = try_connect_floors_with_stair()
		if not connect_result:
			return false
	build_rooms_on_each_floor_arr()
	stage += 1
	return true

func claim_node_ownership_recur(node, owner = null):
	if owner == null:
		if Engine.is_editor_hint():
			# Hack to prevent errors at runtime or on export where EditorInterface does not exist.
			var script := GDScript.new()
			script.set_source_code("func eval(): return EditorInterface.get_edited_scene_root()" )
			script.reload()
			owner = script.new().eval()
		else:
			owner = self
	node.owner = owner
	for child in node.get_children():
		claim_node_ownership_recur(child, owner)

###################
## GENERATE LOOP ##
###################
func continue_generating():
	iterations += 1
	if stage < BuildStage.DONE and iterations < max_safe_iterations:
		if stage == BuildStage.SEPARATE_ROOMS:
			var any_overlap = try_push_apart_rooms()
			if not any_overlap:
				print("Suceeded in separating all rooms.")
				stage += 1
			else:
				print("Separating...")
		elif stage == BuildStage.CONNECT_ROOMS:
			if not all_rooms_connected_on_all_floors():
				var connect_result := connect_a_room()
				if not connect_result:
					printerr("Failed connect")
					return false
			else:
				print("Finished connection stage successfully")
				#add_child.call_deferred(_rooms_container)
				stage += 1
				#stage += 1
		elif stage == BuildStage.SPAWN_ROOMS:
			_place_corridors.call_deferred()
			add_child.call_deferred(_rooms_container)
			_position_rooms.call_deferred()
			_populate_grid_to_rooms_arr.call_deferred()
			_emit_placed_room_signals.call_deferred()
			claim_node_ownership_recur.call_deferred(_rooms_container)
			stage += 1
	
	if iterations >= max_safe_iterations and stage != BuildStage.DONE:
		print("Hit max safe iter")
		_place_corridors.call_deferred()
		add_child.call_deferred(_rooms_container)
		_position_rooms.call_deferred()
		_populate_grid_to_rooms_arr.call_deferred()
		_emit_placed_room_signals.call_deferred()
		claim_node_ownership_recur.call_deferred(_rooms_container)
		return false
	
	return true

################
## GENERATION ##
################

func all_floors_connected() -> bool:
	if _stairs_graph == null:
		# Build initial stair graph
		_stairs_graph = DungeonUtils.TreeGraph.new(range(dungeon_size.y))
		print(_stairs_graph._nodes)
		print(_stairs_graph._roots)
		for room_on_grid in _rooms:
			var doors = room_on_grid.get_doors()
			for door in doors:
				# Connect all each rooms door y pos to every other room's door y pos
				_stairs_graph.connect_nodes(door.grid_pos.y, doors[0].grid_pos.y)
	return _stairs_graph.is_fully_connected()

func _get_room_count(room : DungeonRoom):
	return len(_rooms.filter(func(_r : DungeonRoom): return _r == room))

func _get_rooms_under_min_count() -> Array:
	return _room_counts.keys().filter(func(room): return room.min_count > _room_counts[room])

## Returns a list of rooms whose doors span multiple floors
func _get_stair_rooms() -> Array[DungeonRoom]:
	var stair_rooms = [] as Array[DungeonRoom]
	for room in dungeon_kit_inst.get_rooms():
		if len(DungeonUtils._make_set(room.get_doors().map(func(d): return d.local_pos.y))) > 1:
			stair_rooms.push_back(room)
	return stair_rooms

func _position_rooms():
	for room in _rooms:
		room.set_room_transform_to_grid_pos()

func get_rand_pos_for_room(room : DungeonRoom) -> Vector3i:
	var max_pos = dungeon_size - room.size_in_grid
	var rand_pos = Vector3(
		_rng.randi_range(0, max_pos.x),
		_rng.randi_range(0, max_pos.y),
		_rng.randi_range(0, max_pos.z)
	)
	return rand_pos
	
func constrain_to_bounds(room : DungeonRoom) -> void:
	var min_pos = room.grid_pos
	var max_pos = room.grid_pos + room.size_in_grid - Vector3i(1,1,1)
	for exit_pos_grid in room.get_doors().map(func(d): return d.exit_pos_grid):
		min_pos = DungeonUtils._vec3i_min(min_pos, exit_pos_grid)
		max_pos = DungeonUtils._vec3i_max(max_pos, exit_pos_grid)
	# Constrain to left/top bounds, including doors
	var out_of_bounds_lt = DungeonUtils._vec3i_min(min_pos, Vector3i(0,0,0))
	room.grid_pos -= out_of_bounds_lt
	# Constrain to right/bottom bounds, including doors
	var out_of_bounds_rb = DungeonUtils._vec3i_max(max_pos - (dungeon_size - Vector3i(1,1,1)), Vector3i(0,0,0))
	room.grid_pos -= out_of_bounds_rb

func placed_minimum_rooms() -> bool:
	return len(_get_rooms_under_min_count()) == 0

func get_random_room() -> DungeonRoom:
	var rooms_to_place := _get_rooms_under_min_count().filter(func(room): return _room_counts[room] < room.max_count)
	return rooms_to_place[_rng.randi_range(0, len(rooms_to_place) - 1)]

func duplicate_and_place_room(room : DungeonRoom, grid_pos : Vector3i, constrain : bool = true) -> DungeonRoom:
	var dupe = room.make_duplicate()
	_rooms_container.add_child(dupe)
	dupe.grid_pos = grid_pos
	_rooms.push_back(dupe)
	_room_counts[room] = _room_counts[room] + 1
	dupe.dungeon_generator = self
	#wprint("dupe.grid_pos")
	#print(dupe.grid_pos)
	if constrain:
		constrain_to_bounds(dupe)
	return dupe
	
func try_connect_floors_with_stair() -> bool:
	var stair_rooms_to_place := _get_stair_rooms().filter(func(room): return room.max_count > _get_room_count(room))
	# Try each stair type available and check if it lets us move to any new floors
	for stair_room in stair_rooms_to_place:
		for floor_num in range(0, dungeon_size.y - stair_room.get_aabb_in_grid().size.y + 1):
			var exit_floors = DungeonUtils._make_set(stair_room.get_doors().map(func(d): return floor_num + d.local_pos.y))
			# If this stair connects two previously unconnected floors, place it in the level
			if exit_floors.any(func(start_floor): return exit_floors.any(func(end_floor): return not _stairs_graph.are_nodes_connected(start_floor, end_floor))):
				# Place stair and update stair graph to connect the floors
				var rand_pos = get_rand_pos_for_room(stair_room)
				rand_pos.y = floor_num
				duplicate_and_place_room(stair_room, rand_pos)
				exit_floors.map(func(start_floor): exit_floors.map(func(end_floor): _stairs_graph.connect_nodes(start_floor, end_floor)))
				return true
	return false

## Returns true if any of the rooms were overlapping.
func try_push_apart_rooms() -> bool:
	var any_overlap := false
	for i in range(0, len(_rooms)):
		for j in range(i + 1, len(_rooms)):
			if _rooms[i].overlaps_room(_rooms[j]):
				_rooms[i].push_away_from(_rooms[j])
				constrain_to_bounds(_rooms[i])
				constrain_to_bounds(_rooms[j])
				any_overlap = true
	return any_overlap

# Also used for separation phase
func build_rooms_on_each_floor_arr() -> void:
	_rooms_on_each_floor = range(dungeon_size.y).map(func(floor): return _rooms.filter(func(room): return room.get_doors().any(func(d): return d.grid_pos.y == floor)))

func all_rooms_connected_on_all_floors() -> bool:
	if len(_floors_graphs) == 0:
		# Loop through the floors, and check which of the rooms have a door which leads to that floor
		_floors_graphs = _rooms_on_each_floor.map(func(rooms_on_floor): return DungeonUtils.TreeGraph.new(rooms_on_floor))
		_astar_grids = range(dungeon_size.y).map(func(floor): return DungeonUtils.DungeonFloorAStarGrid2D.new(dungeon_size, _rooms, floor))
		_doors_on_each_floor = range(dungeon_size.y).map(func(floor_num): return (DungeonUtils._flatten(_rooms_on_each_floor[floor_num].map(func(room): return room.get_doors()))
			.filter(func(door):
				# Filter for doors on this floor, also filter out doors which already lead to rooms & connect tree there
				return door.grid_pos.y == floor_num and _grid_pos_in_bounds(door.exit_pos_grid) and 0 == len(_rooms_on_each_floor[floor_num].filter(func(room):
					if door.leads_to_room(room):
						_floors_graphs[floor_num].connect_nodes(door.room, room)
						return true
					else: return false)))))
	var floor_graphs_connected = _floors_graphs.all(func(graph): return graph.is_fully_connected())
	var all_non_optional_doors_connected = _doors_on_each_floor.all(func(doors): return doors.all(func(d): return d.optional or _astar_grids[d.grid_pos.y].corridors.has(Vector2i(d.exit_pos_grid.x, d.exit_pos_grid.z))))
	return floor_graphs_connected and all_non_optional_doors_connected

func _find(arr : Array, callable : Callable):
	var filtered = arr.filter(callable)
	return filtered[0] if len(filtered) > 0 else null

func _grid_pos_in_bounds(grid_pos : Vector3i) -> bool:
	if grid_pos.x < 0 or grid_pos.y < 0 or grid_pos.z < 0:
		return false
	if grid_pos.x >= dungeon_size.x or grid_pos.y >= dungeon_size.y or grid_pos.z >= dungeon_size.z:
		return false
	return true

# Seed 475 is broken
## Returns true if we were able to connect a room.
func connect_a_room() -> bool:
	for floor_num in range(dungeon_size.y):
		#if floor_num > 0 and stage < BuildStage.DONE:
			#stage += 1
		var rooms : Array[DungeonRoom] = _rooms_on_each_floor[floor_num]
		var graph : DungeonUtils.TreeGraph = _floors_graphs[floor_num]
		var astar_grid : DungeonUtils.DungeonFloorAStarGrid2D = _astar_grids[floor_num]
		var doors_on_this_floor = _doors_on_each_floor[floor_num]
		#print(doors_on_this_floor.map(func(d): return d.exit_pos_grid))
		# Find a door we still need to connect, not connected to the root of the graph.
		var door_a = _find(doors_on_this_floor, func(door):
			return not graph.are_nodes_connected(door.room, rooms[0]))
		# Tree graph is fully connected. Next goal is to connect non-optional doors.
		if not door_a: door_a = _find(doors_on_this_floor, func(door): return not door.optional and not astar_grid.corridors.has(Vector2i(door.exit_pos_grid.x, door.exit_pos_grid.z)))
		# If a is null by this point, that means all rooms are connected, and all non-optional doors are connected.
		if door_a:
			var door_b = _find(doors_on_this_floor, func(d): return d.room != door_a.room and (graph.is_fully_connected() or not graph.are_nodes_connected(d.room, door_a.room)))
			var corridors_to_add = []
			if door_b:
				corridors_to_add = astar_grid.get_id_path(Vector2i(door_a.exit_pos_grid.x, door_a.exit_pos_grid.z), Vector2i(door_b.exit_pos_grid.x, door_b.exit_pos_grid.z))
			if len(corridors_to_add) == 0:
				# Path find failed or no door_b. Just add 1 corridor at door_a
				print("Failed to find path for required door. Adding end cap")
				corridors_to_add.push_back(Vector2i(door_a.exit_pos_grid.x, door_a.exit_pos_grid.z))
			else: # Found path
				graph.connect_nodes(door_a.room, door_b.room)
			# Don't add corridors twice
			corridors_to_add = corridors_to_add.filter(func(c): return not astar_grid.corridors.has(c))
			#print("connecting ", door_a.room.name, ":", door_a.door_node.name, " to ... ", door_b.room.name if door_b else null, ":", door_b.door_node.name if door_b else null)
			#print(rooms)
			#print(doors_on_this_floor.map(func(_d): return _d.room))
			for pos in corridors_to_add:
				astar_grid.corridors.push_back(pos)
			return true
	return false

# To be called on main thread
func _place_corridors():
	var corridor_room = _find(dungeon_kit_inst.get_rooms(), func(room):
		return room.size_in_grid == Vector3i(1,1,1) and len(room.get_doors()) == 4)
	for floor_num in len(_astar_grids):
		var astar_grid = _astar_grids[floor_num]
		for pos in astar_grid.corridors:
			var dupe = duplicate_and_place_room(corridor_room, Vector3i(pos.x, floor_num, pos.y), false)
			dupe.name = str(Vector3i(pos.x, floor_num, pos.y))
		
func _populate_grid_to_rooms_arr():
	# Create _grid_to_room_arr_3d for quick checking later, like for where doors lead
	_grid_to_room_arr_3d = []
	_grid_to_room_arr_3d.resize(dungeon_size.x)
	for x in dungeon_size.x:
		_grid_to_room_arr_3d[x] = []
		_grid_to_room_arr_3d[x].resize(dungeon_size.y)
		for y in dungeon_size.y:
			_grid_to_room_arr_3d[x][y] = []
			_grid_to_room_arr_3d[x][y].resize(dungeon_size.z)
			for z in dungeon_size.z:
				_grid_to_room_arr_3d[x][y][z] = null
	for room in _rooms:
		for x in range(room.grid_pos.x, room.grid_pos.x + room.size_in_grid.x):
			for y in range(room.grid_pos.y, room.grid_pos.y + room.size_in_grid.y):
				for z in range(room.grid_pos.z, room.grid_pos.z + room.size_in_grid.z):
					_grid_to_room_arr_3d[x][y][z] = room

func _emit_placed_room_signals():
	for room in _rooms:
		room.placed_room.emit()
		
## Returns false if it fails any safety checks that would make the dungeon impossible to generate
func does_pass_safety_checks() -> bool:
	if not dungeon_kit_inst:
		printerr("SimpleDungeons Error: Must have a dungeon kit set to generate the dungeon.")
		return false
	var found_corridor = false
	var found_stair_room = false
	var min_total_room_volume : int = 0
	if len(dungeon_kit_inst.get_rooms()) == 0:
		printerr("SimpleDungeons Error: No rooms found. Make sure each room has a DungeonRoom script on it. (Or a script which inherits from DungeonRoom to add custom functionality)")
		return false
	for room in dungeon_kit_inst.get_rooms():
		if not room.get_node_or_null("AABB"):
			printerr("SimpleDungeons Error: Room ", room.name, " has no AABB. You must add a (can be invisible) CSGBox3D node as a direct child of each DungeonRoom to mark the room dimensions.")
			return false
		if not Vector3(room.get_aabb_rel_to_room().size).posmodv(dungeon_kit_inst.grid_voxel_size).length() < 0.5:
			printerr("SimpleDungeons Warning: Room AABB sizes should be standardized to the chosen grid_voxel_size on the DungeonKit.")
			printerr("Room ", room.name, " has an AABB which does not match the chosen grid_voxel_size. This may cause incorrect room placement.")
		if room.size_in_grid.x <= 0 or room.size_in_grid.y <= 0 or room.size_in_grid.z <= 0:
			printerr("SimpleDungeons Error: Room ", room.name, " has as <= 0 size on one of the X Y or Z axes.")
			return false
		if room.size_in_grid.x > dungeon_size.x or room.size_in_grid.y > dungeon_size.y or room.size_in_grid.z > dungeon_size.z:
			printerr("SimpleDungeons Error: Room ", room.name, " does not fit. Its AABB is larger than the set dungeon_size on one of the X Y or Z axes.")
			printerr("Room size: ", room.size_in_grid, " Dungeon size: ", dungeon_size)
			return false
		if room.size_in_grid == Vector3i(1,1,1) and len(room.get_doors().filter(func(_d : DungeonRoom.Door): return _d.optional)) == 4:
			found_corridor = true
		if len(room.get_doors()) == 0:
			printerr("SimpleDungeons Error: All rooms must have at least 1 door")
			return false
		for door in room.get_doors():
			if room.get_aabb_in_grid().has_point(Vector3(door.exit_pos_grid) + Vector3(0.5, 0.5, 0.5)):
				printerr("SimpleDungeons Error: Room ", room.name, " has invalid door placements.. Use the DungeonKit debug view in editor checkbox and fix doors on this room by making sure they all align with the grid.")
				return false
		min_total_room_volume += (room.size_in_grid.x * room.size_in_grid.y * room.size_in_grid.z) * room.min_count
	if not found_corridor:
		printerr("SimpleDungeons Error: Needs at least 1 1x1x1 (in grid squares/voxels) corridor room with 4 optional doors.")
		printerr("You can mark a door as optional by prefixing with DOOR? while required doors are prefixed with just DOOR")
		return false
	if min_total_room_volume > (dungeon_size.x * dungeon_size.y * dungeon_size.z):
		printerr("SimpleDungeons Error: Total minimum number of rooms must be less than the total volume of the dungeon. Decrease the number of rooms to spawn or increase the dungeon size.")
		return false
	if dungeon_size.y > 1 and len(_get_stair_rooms()) == 0:
		printerr("SimpleDungeons Error: No stair rooms found and dungeon_size.y > 1. Multi-level dungeons must have a stair room (any room with doors leading to multiple floors).")
		return false
	return true
