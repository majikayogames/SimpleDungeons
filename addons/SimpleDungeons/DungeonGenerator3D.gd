@tool
class_name DungeonGenerator3D
extends Node3D

signal done_generating()
signal generating_failed()

# This can be set to a callable to customize room spawning in a fine grained way.
# Function signature should be Callable(room_instances : Array[DungeonRoom3D], rng : RandomNumberGenerator) -> Array[DungeonRoom3D]
var custom_get_rooms_function = null

# For any vars which may be accessed from multiple threads
var t_mutex := Mutex.new()

enum BuildStage { NOT_STARTED = -2, PREPARING = -1, PLACE_ROOMS = 0, PLACE_STAIRS = 1, SEPARATE_ROOMS = 2, CONNECT_ROOMS = 3, FINALIZING = 4, DONE = 5 }
var stage : BuildStage = BuildStage.NOT_STARTED :
	set(v): t_mutex.lock(); stage = v; t_mutex.unlock();
	get: t_mutex.lock(); var v = stage; t_mutex.unlock(); return v;

## Add all the rooms for the dungeon generator to use in this array.
## Each one must inherit DungeonRoom.
## Not necessary to place the corridor room here. Place that in the corridor_room_scene property.
@export var room_scenes : Array[PackedScene] = []
## The corridor room is a special room scene which must be a 1x1x1 (in voxels) scene inheriting DungeonRoom which is used to connect all the placed rooms.
@export var corridor_room_scene : PackedScene

## Dungeon grid size measured in voxel units, voxel size is chosen in the voxel_scale property.
@export var dungeon_size := Vector3i(10,10,10) :
	set(v):
		dungeon_size = v.clamp(Vector3i(1,1,1),Vector3i(9999,9999,9999))

## Voxel scale/size in world units. Controls the standardized 1x1x1 room size of the dungeon.
## This should match the voxel scale on each of your rooms.voxel_scale
## If the voxel scale is different, the rooms will be scaled (perhaps non uniformly) to match the DungeonGenerator's voxel scale.
@export var voxel_scale := Vector3(10,10,10) :
	set(v):
		voxel_scale = v.clamp(Vector3(0.0001,0.0001,0.0001),Vector3(9999,9999,9999))

## Seed to use when generating the dungeon. Blank for random. You can call .generate(seed : int) to override.
## I'm setting this as a string because it didn't seem like you could set very large ints from editor if set to int.
@export var generate_seed : String = "" :
	set(v):
		var stripped_value = v.strip_edges().replace(r"[^0-9-]", "")
		if stripped_value.begins_with("-"):
			stripped_value = "-" + stripped_value.replace("-", "")
		else:
			stripped_value = stripped_value.replace("-", "")
		generate_seed = stripped_value
			
@export var generate_on_ready : bool = true
## Depending on the dungeon kit used and the separation/connecting algorithm, it's possible that
## a dungeon may not be able to correctly generate and have all rooms reachable/not overlapping.
## In that case, the algorithm can simply restart from the beginning and try again.
@export var max_retries : int = 1
## Max total iterations in generate loop running one pass for the current stage.
## Generation stages: PLACE_ROOMS, PLACE_STAIRS, SEPARATE_ROOMS, CONNECT_ROOMS
@export var max_safe_iterations : int = 250

## Run generation of dungeon on a separate thread.
## It is safe to access vars .stage, .is_currently_generating, and .failed_to_generate but otherwise you should use .call_deferred_thread_group() to call any functions.
## Does not work in editor - was causing crashes so I disabled it.
@export var generate_threaded := false

## Generate the dungeon in editor. If you added any custom rooms which extend DungeonRoom,
## they also need the @tool directive for this to work.
@export var editor_button_generate_dungeon : bool = false :
	set(value):
		generate()

## Abort the generation started in editor
@export var abort_editor_button : bool = false :
	set(value):
		abort_generation()

@export_group("AStar room connection options")
enum AStarHeuristics { NONE_DIJKSTRAS = 0, MANHATTAN = 1, EUCLIDEAN = 2 }
## What heuristic to use for the AStar room connection algorithm.
## Euclidan - Standard, tends towards straight corridors connecting rooms.
## Manhattan - May lead to zigzagging corridors between rooms.
## Dijkstra's - No heuristic, this turns AStar into Dijkstra's algorithm. Guaranteed to find the shortest possible path but may lead to zigzagging corridors.
@export var astar_heuristic : AStarHeuristics = AStarHeuristics.EUCLIDEAN
## Increasing the heuristic scale may make the path less optimal but can help reduce zigzagging corridors.
## A heuristic of 3.0 (with either manhattan or euclidean, Dijkstra's already means 0 heuristic scale) may help reduce zigzagging corridors.
@export var heuristic_scale : float = 1.0
## By making the corridors cost less to walk through, the algorithm will tend towards merging into single corridors,
## thus making hallways more compact.
@export var corridor_cost_multiplier : float = 0.25
## Similar to corridor cost, setting this lower makes it so the algorithm will walk through a rooms to connect 2 rooms/doors, thus saving corridors placements.
## You could also set it greater than 1 to make the algorithm less likely to walk through existing (non-corridor) rooms.
@export var room_cost_multiplier : float = 0.25
## After connecting all rooms, some doors may not have been connected.
## By setting the cost for astar to walk through rooms higher at this stage, it encourages more interesting room connections,
## rather than just putting 1x1x1 corridor caps at doors.
@export var room_cost_at_end_for_required_doors : float = 2.0

@export_group("Debug options")
@export var show_debug_in_editor : bool = true
@export var show_debug_in_game : bool = false
## Whether to place the dungeon rooms so far even if the generation failed.
@export var place_even_if_fail : bool = false
@export var visualize_generation_progress : bool = false
# By default hide debug after gen. Othewise will lag.
@export var hide_debug_visuals_for_all_generated_rooms : bool = true
@export var cycle_debug_draw_when_press_n : bool = false
## A timer will be called with this wait time for the next iteration of the generation loop
@export_range(0, 1000, 1, "or_greater", "suffix:ms") var visualize_generation_wait_between_iterations : int = 100

###########################
## INIT/PROCESS/BUILTINS ##
###########################

func _init():
	RenderingServer.set_debug_generate_wireframes(true)

func _input(event):
	if cycle_debug_draw_when_press_n and event is InputEventKey and Input.is_key_pressed(KEY_N):
		var vp = get_viewport()
		vp.debug_draw = (vp.debug_draw + 1 ) % 4

var _debug_view = null
func add_debug_view_if_not_exist():
	if not _debug_view:
		_debug_view = preload("res://addons/SimpleDungeons/debug_visuals/DungeonGenerator3DDebugView.gd").new()
		add_child(_debug_view)

func _ready():
	add_debug_view_if_not_exist()
	if Engine.is_editor_hint():
		return
	if generate_on_ready:
		generate()

func _process(delta):
	if Engine.is_editor_hint():
		# Debug view doesn't get added in Editor sometimes, like if you manually drag script on.
		for c in get_children():
			if c is DungeonRoom3D and not c.virtualized_from:
				c.add_debug_view_if_not_exist()
		return
	if _visualization_in_progress and Time.get_ticks_msec() - _last_iteration_end_time > visualize_generation_wait_between_iterations:
		_run_generate_loop(false)

###################################
## GENERATION ENTRY POINT & LOOP ##
###################################

# Mostly setting up proper error handling, threads, visualization here.
# Most of the interesting stuff is in the build logic portion of the code below.

var room_instances : Array[DungeonRoom3D]
var corridor_room_instance : DungeonRoom3D
var iterations := 0
var retry_attempts := 0
var rooms_container : Node3D
var rng := RandomNumberGenerator.new()

var running_thread : Thread
var failed_to_generate := false :
	set(v): t_mutex.lock(); failed_to_generate = v; t_mutex.unlock();
	get: t_mutex.lock(); var v = failed_to_generate; t_mutex.unlock(); return v;
var full_abort_triggered := false :
	set(v): t_mutex.lock(); full_abort_triggered = v; t_mutex.unlock();
	get: t_mutex.lock(); var v = full_abort_triggered; t_mutex.unlock(); return v;
var is_currently_generating : bool :
	get: return not (stage == BuildStage.NOT_STARTED or stage == BuildStage.DONE) and not failed_to_generate

var _is_generating_threaded = false
var _visualization_in_progress = false
var _last_iteration_end_time : int = Time.get_ticks_msec()

func generate(seed : int = int(generate_seed) if generate_seed.is_valid_int() else randi()) -> void:
	if is_currently_generating:
		_printerr("SimpleDungeons Error: Dungeon currently generating, cannot generate.")
		return
	
	stage = BuildStage.NOT_STARTED
	
	if not validate_dungeon():
		_printerr("SimpleDungeons Error: Cannot generate.")
		return
	
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	print("DungeonGenerator3D generate(): Using seed ", seed)
	
	cleanup_and_reset_dungeon_generator()
	create_or_recreate_rooms_container()
	get_preplaced_rooms() # Ensure cached because can't call get_children on threads
	
	for room in get_preplaced_rooms():
		room.snap_room_to_dungeon_grid()
		if not room.validate_room():
			_fail_generation("Could not validate preplaced rooms.")
			return
		room.ensure_doors_and_or_transform_cached_for_threads_and_virtualized_rooms()
	
	stage = BuildStage.PREPARING
	if not setup_room_instances_and_validate_before_generate():
		_fail_generation("DungeonGenerator3D generation failed while setting up rooms.")
		return
	
	_is_generating_threaded = generate_threaded and not visualize_generation_progress
	_visualization_in_progress = visualize_generation_progress
	
	if _is_generating_threaded and Engine.is_editor_hint():
		_is_generating_threaded = false
		_printwarning("Disabling threaded generation because in editor. Kept running into crashes with editor threads, looked like Godot bugs, so disabling for now. You can still use visualize generation in editor. Threaded generation in game seems to work fine.")
	
	if _is_generating_threaded:
		running_thread = Thread.new()
		running_thread.start(_run_generate_loop)
	else:
		_run_generate_loop()

func _run_generate_loop(first_call : bool = true) -> void:
	if first_call:
		retry_attempts = 0
		iterations = 0
		failed_to_generate = false
		stage = BuildStage.PLACE_ROOMS
	while retry_attempts <= max_retries and not full_abort_triggered:
		while iterations < max_safe_iterations and not failed_to_generate and stage != BuildStage.FINALIZING:
			var start_stage := stage
			_run_one_loop_iteration_and_increment_iterations()
			_last_iteration_end_time = Time.get_ticks_msec()
			if _visualization_in_progress and stage != BuildStage.FINALIZING and not failed_to_generate:
				return # Will be called again from _process
		if stage == BuildStage.FINALIZING:
			break
		# If the dungeon failed to generate after looping through all stages until max_safe_iterations, retry.
		retry_attempts += 1
		if retry_attempts > max_retries:
			_fail_generation("Reached max generation retries. Failed to generate. Failed at stage "+BuildStage.find_key(stage))
			break
		else:
			clear_rooms_container_and_setup_for_next_iteration()
			iterations = 0
			failed_to_generate = false
			stage = BuildStage.PLACE_ROOMS
			if _visualization_in_progress:
				return # Will be called again from _process
			_printwarning("Generation failed on attempt "+str(retry_attempts)+" at stage "+BuildStage.find_key(stage)+". Retrying generation.")
	
	_visualization_in_progress = false
	if _is_generating_threaded:
		if not failed_to_generate: _dungeon_finished_generating.call_deferred()
		else: _dungeon_failed_generating.call_deferred()
	else:
		if not failed_to_generate: _dungeon_finished_generating()
		else: _dungeon_failed_generating()

var _stage_just_changed = false
func _run_one_loop_iteration_and_increment_iterations() -> void:
	if iterations == 0:
		_stage_just_changed = true
	
	var cur_stage = stage
	# Each stage will increment stage once it is done.
	# Also, each stage can call _abort_generation_and_fail if it encounters any errors.
	if stage == BuildStage.PLACE_ROOMS:
		place_room_iteration(_stage_just_changed)
	elif stage == BuildStage.PLACE_STAIRS:
		place_stairs_iteration(_stage_just_changed)
	elif stage == BuildStage.SEPARATE_ROOMS:
		# This looked to be so extremely slow to run all the checks after each separate iteration, so just going to iterate here:
		separate_rooms_iteration(_stage_just_changed)
	elif stage == BuildStage.CONNECT_ROOMS:
		connect_rooms_iteration(_stage_just_changed)
	
	_stage_just_changed = stage != cur_stage
	iterations += 1

func _fail_generation(error : String = "Aborted generation") -> void:
	_printerr("SimpleDungeons Error: ", error)
	_printerr("SimpleDungeons Error: Failed to generate dungeon")
	failed_to_generate = true

func abort_generation():
	if not is_currently_generating:
		_printwarning("DungeonGenerator3D not currently generating.")
		return
	failed_to_generate = true
	full_abort_triggered = true
	_printerr("abort_generation() called")
	if running_thread and running_thread.is_alive() and OS.get_main_thread_id() == OS.get_thread_caller_id():
		running_thread.wait_to_finish()
	for room in room_instances:
		room.queue_free()
	for room in _rooms_placed:
		room.queue_free()
	rooms_container.queue_free()
	if rooms_container.is_inside_tree():
		rooms_container.get_parent().remove_child(rooms_container)

func _finalize_rooms(ready_callback = null) -> void:
	if not rooms_container.is_inside_tree():
		add_child(rooms_container)
	rooms_container.owner = self.owner
	for room in _rooms_placed.slice(0):
		_rooms_placed.erase(room)
		var unvirtualized = room.unvirtualize_and_free_clone_if_needed(rooms_container)
		unvirtualized.owner = self.owner
		_rooms_placed.push_back(unvirtualized)
	for room in room_instances:
		if room and is_instance_valid(room):
			room.queue_free()
	room_instances = []
	if corridor_room_instance and is_instance_valid(corridor_room_instance):
		corridor_room_instance.queue_free()
	corridor_room_instance = null
	if ready_callback is Callable:
		if rooms_container.is_node_ready():
			ready_callback.call_deferred()
		else:
			rooms_container.ready.connect(ready_callback)
		

func _dungeon_finished_generating() -> void:
	_finalize_rooms(_emit_done_signals)

func _dungeon_failed_generating() -> void:
	if place_even_if_fail:
		_finalize_rooms()
	elif not visualize_generation_progress:
		rooms_container.queue_free()
		for room in _rooms_placed:
			room.queue_free()
	for room in room_instances:
		room.queue_free()
	_emit_failed_signal.call_deferred() # Ensure rooms container placed/might be on thread.

# Emit done signals for dungeon & place_room for all DungeonRooms.
func _emit_done_signals():
	stage = BuildStage.DONE
	# Also need to call emit signal for each of place_rooms
	for room in _rooms_placed:
		if not room.original_ready_func_called:
			_printwarning("_ready not called on "+room.name+". Room placement, finalization, and doors will be broken. Make sure to call super._ready() at the top of your _ready func when inheriting DungeonRoom3D.")
		room.dungeon_done_generating.emit()
	for preplaced_room in find_children("*", "DungeonRoom3D", false):
		preplaced_room.dungeon_done_generating.emit()
	print("DungeonGenerator3D finished generating.")
	for room in room_instances:
		room.queue_free()
	done_generating.emit()

func _emit_failed_signal(): # So I can call_deferred
	if running_thread:
		running_thread.wait_to_finish()
	generating_failed.emit()

#########################
## DUNGEON BUILD LOGIC ##
#########################

# Placing rooms: A random room is selected from room_scenes until the min_count of all is matched

var _rooms_placed : Array[DungeonRoom3D]
var _custom_rand_rooms : Array[DungeonRoom3D]
var _use_custom_rand_rooms := false
func place_room_iteration(first_call_in_loop : bool) -> void:
	if first_call_in_loop:
		_rooms_placed = []
		_custom_rand_rooms = []
		_use_custom_rand_rooms = false
		if custom_get_rooms_function is Callable:
			_use_custom_rand_rooms = true
			_custom_rand_rooms = custom_get_rooms_function.call(room_instances, rng)
			if not _custom_rand_rooms is Array or len(_custom_rand_rooms) == 0:
				_fail_generation("custom_get_rooms_function takes should return a non-empty Array of DungeonRoom3Ds.")
				_printwarning("custom_get_rooms_function takes (room_instances : Array[DungeonRoom3D], rng_seeded : RandomNumberGenerator) as the arguments and should use .create_clone_and_make_virtual_unless_visualizing() to clone and then position with .set_position_by_grid_pos(Vector3i) or .rotation = 0 through 3 for number of 90 degree y rotations for the room.")
				return
			for room in _custom_rand_rooms:
				if not room is DungeonRoom3D:
					_fail_generation("custom_get_rooms_function supplied an object that is not a DungeonRoom3D. Ensure all rooms supplied inherit DungeonRoom3D, and use the @tool annotation if generating in editor.")
					return
				if room_instances.find(room) != -1:
					_fail_generation("custom_get_rooms_function supplied a room instance without cloning it. Always use DungeonRoom3D.create_clone_and_make_virtual_unless_visualizing() to create room instances.")
					return
	
	var rand_room : DungeonRoom3D
	if _use_custom_rand_rooms:
		rand_room = _custom_rand_rooms.pop_front()
	else:
		if get_rooms_less_than_max_count(false).size() > 0:
			rand_room = get_randomly_positioned_room()
	
	if rand_room:
		place_room(rand_room)
	
	if _use_custom_rand_rooms:
		if _custom_rand_rooms.size() == 0:
			stage += 1
	else:
		if get_rooms_less_than_min_count(false).size() == 0:
			if _rooms_placed.size() == 0:
				_fail_generation("Unable to place any rooms. Ensure min_count and max_count are set correctly on rooms.")
			else:
				stage += 1

# Placing stairs:

# Array [DungeonRoom3D, grid_pos_y] for where to place rooms
var _stair_rooms_and_placements = []
var _stair_rooms_placed_count = {}
func place_stairs_iteration(first_call_in_loop : bool) -> void:
	if first_call_in_loop:
		_stair_rooms_placed_count = {}
		for s in get_stair_rooms_from_instances():
			_stair_rooms_placed_count[s] = 0
		_stair_rooms_and_placements = _make_and_solve_floors_graph()
		if failed_to_generate:
			return # solve failed and called abort
	
	if _stair_rooms_and_placements.size() > 0:
		var stair_and_y_pos = _stair_rooms_and_placements.pop_back()
		_stair_rooms_placed_count[stair_and_y_pos[0]] += 1
		var room = stair_and_y_pos[0].create_clone_and_make_virtual_unless_visualizing()
		var y_pos = stair_and_y_pos[1]
		room.room_rotations = rng.randi_range(0,4)
		room.set_position_by_grid_pos(Vector3i(
			rng.randi_range(0, dungeon_size.x - room.get_grid_aabbi(true).size.x),
			y_pos,
			rng.randi_range(0, dungeon_size.z - room.get_grid_aabbi(true).size.z)))
		place_room(room)
	elif get_stair_rooms_from_instances().filter(func(s): return s.min_count > _stair_rooms_placed_count[s]).size() > 0:
		var stairs_less_than_min = get_stair_rooms_from_instances().filter(func(s): return s.min_count > _stair_rooms_placed_count[s])
		var room_original = stairs_less_than_min[rng.randi() % stairs_less_than_min.size()]
		_stair_rooms_placed_count[room_original] += 1
		var room = room_original.create_clone_and_make_virtual_unless_visualizing()
		room.room_rotations = rng.randi_range(0,4)
		room.set_position_by_grid_pos(Vector3i(
			rng.randi_range(0, dungeon_size.x - room.get_grid_aabbi(true).size.x),
			rng.randi_range(0, dungeon_size.y - room.get_grid_aabbi(true).size.y),
			rng.randi_range(0, dungeon_size.z - room.get_grid_aabbi(true).size.z)))
		place_room(room)
	else:
		stage += 1

# Encapsulate some checks for stair room instances & how they can connect two or more floors.
class StairRoomInfo:
	var inst : DungeonRoom3D
	var stair_gaps = [] # Has door(s) leading 1 floors up, 2 floors up, etc.
	var stair_gaps_dict = {} # Gap:local door y position. To check y offset to place room at when connecting floors.
	var lowest_door_local_y_pos : int
	var available_to_use : int # Make sure not to go above stair's max_count value
	
	# Helper funcs for the stair chains where it might fail
	var _saved_available_to_use : int = 0
	func save_available_to_use():
		_saved_available_to_use = available_to_use
	func restore_available_to_use():
		available_to_use =_saved_available_to_use
	
	func _init(room_instance : DungeonRoom3D):
		self.inst = room_instance
		available_to_use = room_instance.max_count
		
		var door_y_positions = []
		for door in room_instance.get_doors_cached():
			if not door.local_pos.y in door_y_positions:
				door_y_positions.push_back(door.local_pos.y)
		door_y_positions.sort()
		stair_gaps_dict = {}
		for i in range(0, len(door_y_positions)):
			for j in range(i+1, len(door_y_positions)):
				var gap = door_y_positions[j] - door_y_positions[i]
				if not stair_gaps_dict.has(gap): stair_gaps_dict[gap] = []
				stair_gaps_dict[gap].append(door_y_positions[i])
		stair_gaps = stair_gaps_dict.keys()
	
	# format: [[DungeonRoom3D, grid_pos_y], ...]. returns [] if no valid way to connect those floors
	func get_valid_connect_positions(floor_1 : int, floor_2 : int) -> Array:
		if available_to_use == 0: return []
		
		var bottom_floor : int = min(floor_1, floor_2)
		var top_floor : int = max(floor_1, floor_2)
		var gap : int = top_floor - bottom_floor
		if stair_gaps_dict.has(gap):
			# Find actual valid pos from door local y positions, where doors spanning gap will land on floor_1 and floor_2
			var valid_offsets = stair_gaps_dict[gap].filter(func(y_offset : int): return floor_1 - y_offset >= 0 and floor_1 - y_offset + inst.size_in_voxels.y <= inst.dungeon_generator.dungeon_size.y)
			return valid_offsets.map(func(y_offset : int): return [inst, floor_1 - y_offset])
		return []

# Returns empty array if couldn't find a chain of stair rooms to connect the two floors.
# The main case I want to solve here is just a simple chain of multiple 2 floor stairs to connect a more than 2 floor gap.
# There are a ton of edge cases, which I won't even check for.
# This is some heuristic algorithm I thought of which just tries to find a set of rooms which when chained together,
#  continually closes the gap between floors. Should work for basic cases and also some more advanced ones.
func _find_stair_chain_to_connect_floors(floor_1 : int, floor_2 : int, floor_graph : TreeGraph, stair_info_dict : Dictionary) -> Array:
	var stair_chain := []
	var bottom_floor : int = min(floor_1, floor_2)
	var top_floor : int = max(floor_1, floor_2)
	var cur_floor := bottom_floor
	for s in stair_info_dict.values():
		s.save_available_to_use()
	while cur_floor != top_floor:
		# Valid floor = any floor which is closer to top_floor than cur_floor.
		var valid_to_floors := range(dungeon_size.y).filter(func(floor : int): return abs(floor - top_floor) < abs(top_floor - cur_floor))
		var valid_stair_placements := {}
		for to_floor in valid_to_floors:
			for stair_info in stair_info_dict.values():
				var valid_connect = stair_info.get_valid_connect_positions(cur_floor, to_floor)
				if valid_connect.size() > 0:
					if not valid_stair_placements.has(to_floor): valid_stair_placements[to_floor] = []
					valid_stair_placements[to_floor].append_array(valid_connect)
		if valid_stair_placements.keys().size() == 0:
			for s in stair_info_dict.values():
				s.restore_available_to_use()
			return [] # None found
		var to_floor : int = valid_stair_placements.keys()[rng.randi() % valid_stair_placements.keys().size()]
		var choose = valid_stair_placements[to_floor][rng.randi() % valid_stair_placements[to_floor].size()]
		if not floor_graph.has_node(cur_floor) or not floor_graph.has_node(to_floor) or not floor_graph.are_nodes_connected(cur_floor, to_floor):
			stair_chain.push_back(choose) # No need unless not connected already
			stair_info_dict[choose[0]].available_to_use -= 1
		cur_floor = to_floor
	return stair_chain

# returns Array with elements in format [room : DungeonRoom3D, room_grid_pos_y : int]
func _make_and_solve_floors_graph() -> Array:
	# Set up a tree (union find) graph of all the floors with doors on them.
	# This keeps track of what floors are connected by rooms spanning multiple floors.
	var floors_tree_graph := TreeGraph.new()
	var add_room_to_floors_graph := (func(room : DungeonRoom3D, room_y_pos : int):
		for door in room.get_doors_cached():
			var door_exit_y = door.local_pos.y + room_y_pos
			if not door_exit_y in floors_tree_graph.get_all_nodes():
				floors_tree_graph.add_node(door_exit_y)
			floors_tree_graph.connect_nodes(door_exit_y, room.get_doors_cached()[0].local_pos.y + room_y_pos))
	var rooms = []
	rooms.append_array(_rooms_placed)
	rooms.append_array(get_preplaced_rooms())
	for room in rooms:
		add_room_to_floors_graph.call(room, room.get_grid_pos().y)
	
	if not floors_tree_graph.is_fully_connected() and get_stair_rooms_from_instances().size() == 0:
		_fail_generation("No stair rooms defined. Add a room with with is_stair_room set to true.")
		return []
	
	# Solve the stair graph. We'll use a heuristic algorithm.
	# Tried to think of something elegant to do this but it may be harder than I thought.
	# This should be fine for 99% of cases. For truly odd stair patterns in dungeons you can preplace stairs or mod yourself.
	
	var stair_info_dict : Dictionary = {}
	for room in get_stair_rooms_from_instances():
		stair_info_dict[room] = StairRoomInfo.new(room)
	
	var stairs_to_add : Array = [] # element format: [DungeonRoom3D, grid_pos_y]
	while not floors_tree_graph.is_fully_connected():
		# Simple case - look for when we can directly connect 2 floors with a stair
		var stair_able_to_connect_floors_directly = []
		for f1 in floors_tree_graph.get_all_nodes():
			for f2 in floors_tree_graph.get_all_nodes().filter(func(_f2): return _f2 > f1):
				if floors_tree_graph.are_nodes_connected(f1, f2): continue
				for s in stair_info_dict.values():
					# Just looking for 1 valid element [DungeonRoom3D, grid_pos_y]
					stair_able_to_connect_floors_directly.append_array(s.get_valid_connect_positions(f1, f2))
					if stair_able_to_connect_floors_directly.size() > 0:
						break
				if stair_able_to_connect_floors_directly.size() > 0: break
			if stair_able_to_connect_floors_directly.size() > 0: break
		if stair_able_to_connect_floors_directly.size() > 0:
			var stair_and_pos = stair_able_to_connect_floors_directly[rng.randi() % stair_able_to_connect_floors_directly.size()]
			stairs_to_add.push_back(stair_and_pos)
			add_room_to_floors_graph.call(stair_and_pos[0], stair_and_pos[1])
			stair_info_dict[stair_and_pos[0]].available_to_use -= 1
			continue
		# There are many cases where it's not possible to directly connect floors,
		#  but you could chain more than 1 stair room together to connect them.
		# So here we'll do a non exhaustive search which attempts to cover most of these cases.
		var stair_room_chain_to_connect_floors = []
		for f1 in floors_tree_graph.get_all_nodes():
			var nearest_floors_up = floors_tree_graph.get_all_nodes().filter(func(_f2): return _f2 > f1)
			nearest_floors_up.sort_custom(func(fa,fb): return abs(fb - f1) > abs(fa - f1))
			for f2 in nearest_floors_up:
				if floors_tree_graph.are_nodes_connected(f1, f2): continue
				stair_room_chain_to_connect_floors = _find_stair_chain_to_connect_floors(f1, f2, floors_tree_graph, stair_info_dict)
				if stair_room_chain_to_connect_floors.size() > 0:
					break
			if stair_room_chain_to_connect_floors.size() > 0: break
		if stair_room_chain_to_connect_floors.size() > 0:
			for room_and_pos in stair_room_chain_to_connect_floors:
				add_room_to_floors_graph.call(room_and_pos[0], room_and_pos[1])
				stairs_to_add.push_back(room_and_pos)
			continue
		
		_fail_generation("Failed to connect all floors together with stairs. Ensure you have at least 1 DungeonRoom3D with 'is_stair_room' set to true with 2 or more doors leading different floors. Simplest is a 2 floor room with 1 door on each floor.")
		_printerr("Stair algorithm failed. If your stairs are shaped very oddly it can fail, it's not an exhaustive search but should work for most cases. Also ensure stairs max_count is enough to connect all the floors in your dungeon.")
		for s in stair_info_dict.values():
			_printwarning("Room "+str(s.inst.name)+" max_count is "+str(s.inst.max_count)+". One potential reason this could fail is you need to increase the max_count on your stair room(s) so all floors can be connected.")
		return []
	
	return stairs_to_add

# Separating rooms:

var _aabbis_with_doors = {}
func separate_rooms_iteration(first_call_in_loop : bool) -> void:
	var rooms = get_all_placed_and_preplaced_rooms()
	if first_call_in_loop:
		_aabbis_with_doors = {}
		for room in rooms:
			_aabbis_with_doors[room] = room.get_grid_aabbi(true)
	
	var any_overlap := false
	for i in range(0, len(rooms)):
		for j in range(i + 1, len(rooms)):
			var fast_check = _aabbis_with_doors[rooms[i]].intersects(_aabbis_with_doors[rooms[j]])
			if fast_check and rooms[i].overlaps_room(rooms[j]):
				if not rooms[i] in get_preplaced_rooms():
					rooms[i].push_away_from_and_stay_within_bounds(rooms[j])
					_aabbis_with_doors[rooms[i]] = rooms[i].get_grid_aabbi(true)
				if not rooms[j] in get_preplaced_rooms():
					rooms[j].push_away_from_and_stay_within_bounds(rooms[i])
					_aabbis_with_doors[rooms[j]] = rooms[j].get_grid_aabbi(true)
				any_overlap = true
	
	if not any_overlap:
		stage += 1

# Connecting rooms:

var _astar3d : DungeonAStar3D
var _quick_room_check_dict : Dictionary
var _quick_corridors_check_dict : Dictionary
var _non_corridor_rooms : Array
var _rooms_to_connect : Array
var _all_doors_dict : Dictionary
var _required_doors_dict : Dictionary
var _last_rooms_to_connect_counts := []
func connect_rooms_iteration(first_call_in_loop : bool) -> void:
	if first_call_in_loop:
		_rooms_to_connect = []
		_last_rooms_to_connect_counts = []
		_non_corridor_rooms = []
		_quick_room_check_dict = {}
		_quick_corridors_check_dict = {}
		_all_doors_dict = {}
		_required_doors_dict = {}
		for room in get_all_placed_and_preplaced_rooms():
			var doors = room.get_doors_cached()
			if room.get_doors_cached().size() > 0:
				_rooms_to_connect.push_back(room)
				_non_corridor_rooms.push_back(room)
			for door in doors:
				if get_grid_aabbi().contains_point(door.exit_pos_grid):
					_all_doors_dict[door.exit_pos_grid] = door
					if not door.optional:
						_required_doors_dict[door.exit_pos_grid] = door
			var aabbi = room.get_grid_aabbi(false)
			for x in aabbi.size.x: for y in aabbi.size.y: for z in aabbi.size.z:
				_quick_room_check_dict[aabbi.position + Vector3i(x,y,z)] = room
		# Init after corridors/room dict setup
		_astar3d = DungeonAStar3D.new(self, _quick_room_check_dict, _quick_corridors_check_dict)
		# Sort rooms by door y positions. Likely to make astar connections more stable
		_rooms_to_connect.sort_custom(func(a,b): return b.get_doors_cached()[0].exit_pos_grid.y > a.get_doors_cached()[0].exit_pos_grid.y)
	
	# Can exit early if _rooms_to_connect stops going down, aka we tried shuffling and couldn't find a connection
	# Don't think this is necessary actually, I just exit below instead if it fails ever.
	#_last_rooms_to_connect_counts.push_front(len(_rooms_to_connect))
	#_last_rooms_to_connect_counts = _last_rooms_to_connect_counts.filter(func(c): return c == _last_rooms_to_connect_counts[0])
	#if len(_last_rooms_to_connect_counts) > (len(_rooms_to_connect) * 4) and _last_rooms_to_connect_counts[0] == len(_rooms_to_connect):
		#_fail_generation("Unable to connect all rooms")
		#return
	
	# First, just pathfind through all the rooms, one to the next, until all rooms are connected
	if len(_rooms_to_connect) >= 2:
		var room_0_pos = _rooms_to_connect[0].get_grid_aabbi(false).position
		var room_1_pos = _rooms_to_connect[1].get_grid_aabbi(false).position
		var connect_path := _astar3d.get_vec3i_path(room_0_pos, room_1_pos)
		var room_a := _rooms_to_connect.pop_front()
		if len(connect_path) == 0:
			#print("Failed somehow")
			#_rooms_to_connect.insert(rng.randi_range(1, len(_rooms_to_connect)), room_a)
			_fail_generation("Failed to fully connect dungeon rooms with corridors.")
			return
		#print("Connecting ", room_a.name, " to ", _rooms_to_connect[0].name, ". Result: ", connect_path)
		for corridor_pos in connect_path:
			if not _quick_room_check_dict.has(corridor_pos) and not _quick_corridors_check_dict.has(corridor_pos):
				var room := corridor_room_instance.create_clone_and_make_virtual_unless_visualizing()
				room.set_position_by_grid_pos(corridor_pos)
				place_room(room)
				_quick_corridors_check_dict[corridor_pos] = room
		return
	
	# Next, not all the doors may be connected, so we have to do some strategy to nicely connect the required doors remaining.
	for required_door in _required_doors_dict.values().slice(0): # Slice necessary? Not sure.
		# No need to connect doors which already have a corridor
		if _quick_room_check_dict.has(required_door.exit_pos_grid) or _quick_corridors_check_dict.has(required_door.exit_pos_grid):
			_required_doors_dict.erase(required_door)
			continue
		# Get other room doors which are closest to the required door
		var closest_other_room_doors = _all_doors_dict.values().slice(0)#filter(func(d): return d.room != required_door.room)
		closest_other_room_doors.sort_custom(func(a,b):
			# Make sure doors not on same floor sorted far after
			# Also make sure doors of same room sorted far after
			var b_dist = Vector3(b.exit_pos_grid - required_door.exit_pos_grid).length()
			var a_dist = Vector3(a.exit_pos_grid - required_door.exit_pos_grid).length()
			if a.exit_pos_grid.y != required_door.exit_pos_grid.y or a.room == required_door.room:
				a_dist += dungeon_size.x + dungeon_size.y + dungeon_size.z
			if b.exit_pos_grid.y != required_door.exit_pos_grid.y or b.room == required_door.room:
				b_dist += dungeon_size.x + dungeon_size.y + dungeon_size.z
			return b_dist > a_dist)
		
		_astar3d.cap_required_doors_phase = true
		var connect_path := _astar3d.get_vec3i_path(required_door.exit_pos_grid, closest_other_room_doors[0].exit_pos_grid)
		for corridor_pos in connect_path:
			if not _quick_room_check_dict.has(corridor_pos) and not _quick_corridors_check_dict.has(corridor_pos):
				var room := corridor_room_instance.create_clone_and_make_virtual_unless_visualizing()
				room.set_position_by_grid_pos(corridor_pos)
				place_room(room)
				_quick_corridors_check_dict[corridor_pos] = room
		_required_doors_dict.erase(required_door)
		return
	
	stage = BuildStage.FINALIZING

####################################
## DUNGEON BUILD HELPER FUNCTIONS ##
####################################

func get_rooms_less_than_min_count(include_stairs : bool):
	return room_instances.filter(func(room : DungeonRoom3D):
		if not include_stairs and room.is_stair_room:
			return false
		var already_in_tree = _rooms_placed.filter(func(placed_room : DungeonRoom3D):
			return room.get_original_packed_scene() == placed_room.get_original_packed_scene())
		return len(already_in_tree) < room.min_count)

func get_rooms_less_than_max_count(include_stairs : bool):
	return room_instances.filter(func(room : DungeonRoom3D):
		if not include_stairs and room.is_stair_room:
			return false
		var already_in_tree = _rooms_placed.filter(func(placed_room : DungeonRoom3D):
			return room.get_original_packed_scene() == placed_room.get_original_packed_scene())
		return len(already_in_tree) < room.max_count)

func get_randomly_positioned_room() -> DungeonRoom3D:
	var room : DungeonRoom3D = get_rooms_less_than_max_count(false)[rng.randi() % get_rooms_less_than_max_count(false).size()]
	room = room.create_clone_and_make_virtual_unless_visualizing()
	var buf := dungeon_size - room.get_grid_aabbi(false).size
	var rand_pos : Vector3i = Vector3i(rng.randi_range(0, buf.x), rng.randi_range(0, buf.y), rng.randi_range(0, buf.z))
	room.room_rotations = rng.randi_range(0,3)
	room.set_position_by_grid_pos(rand_pos)
	return room

func place_room(room : DungeonRoom3D) -> void:
	room.dungeon_generator = self # Incase wasn't set yet
	_rooms_placed.push_back(room)
	if visualize_generation_progress:
		rooms_container.add_child(room)
	room.snap_room_to_dungeon_grid()

###################################
## INITIALIZE/CLEANUP GENERATION ##
###################################

func create_or_recreate_rooms_container() -> void:
	if rooms_container and is_instance_valid(rooms_container):
		if rooms_container.is_inside_tree():
			rooms_container.get_parent().remove_child(rooms_container)
		rooms_container.queue_free()
	if get_node_or_null("RoomsContainer"): # Incase it's still a child if rooms_container was null somehow
		var rc = get_node_or_null("RoomsContainer")
		remove_child(rc)
		rc.queue_free()
	rooms_container = Node3D.new()
	rooms_container.name = "RoomsContainer"
	if visualize_generation_progress:
		add_child(rooms_container)

func clear_rooms_container_and_setup_for_next_iteration():
	if visualize_generation_progress:
		for c in rooms_container.get_children():
			c.queue_free()
			rooms_container.remove_child(c)
	else:
		for room in _rooms_placed:
			room.queue_free()
	_rooms_placed = []

# Clears the room & corridor instances pool, unless they are in tree.
# For flexibility checking if in tree
# Room instances are used as a library to run checks on,
# but could allow placing them as last room of their kind to save some memory/an instantiate call.
func _clear_room_instances() -> void:
	for room in room_instances:
		if room and is_instance_valid(room):
			room.queue_free()
	if corridor_room_instance and is_instance_valid(corridor_room_instance):
		corridor_room_instance.queue_free()
	room_instances = []
	corridor_room_instance = null

func cleanup_and_reset_dungeon_generator() -> void:
	if is_currently_generating:
		_fail_generation("Dungeon reset while generating.")
	if running_thread:
		if running_thread.is_alive() or running_thread.is_started():
			running_thread.wait_to_finish()
		running_thread = null
	if get_node_or_null("RoomsContainer"):
		var rc = get_node_or_null("RoomsContainer")
		remove_child(rc)
		rc.queue_free()
	_clear_room_instances()
	failed_to_generate = false
	full_abort_triggered = false
	iterations = 0
	retry_attempts = 0
	stage = BuildStage.NOT_STARTED

func setup_room_instances_and_validate_before_generate() -> bool:
	if not room_scenes:
		_printerr("SimpleDungeons Error: No DungeonRoom3D room scenes set.")
		return false
	var inst_arr : Array[DungeonRoom3D] = []
	for s in room_scenes:
		if not s: continue
		var inst = s.instantiate()
		if not inst is DungeonRoom3D:
			_printerr("SimpleDungeons Error: "+s.resource_path+" room scene does not inherit DungeonRoom3D. Also may need @tool annotation if generating in editor.")
			return false
		else:
			inst.dungeon_generator = self
			# Need to save door info before cloning/making virtual copies w/o actual nodes/meshes inside for performance
			inst.ensure_doors_and_or_transform_cached_for_threads_and_virtualized_rooms()
			inst_arr.append(inst as DungeonRoom3D)
	room_instances = inst_arr
	corridor_room_instance = corridor_room_scene.instantiate() if corridor_room_scene else null
	if corridor_room_instance:
		#corridor_room_instance.dungeon_generator = self
		corridor_room_instance.set("dungeon_generator", self)
		#corridor_room_instance.ensure_doors_and_or_transform_cached_for_threads_and_virtualized_rooms()
	return validate_dungeon()

####################
## UTIL FUNCTIONS ##
####################

# printerr() and push_warning() eat my outputs a lot. Regular prints are more reliable.
func _printerr(str : String, str2 : String = "", str3 : String = "", str4 : String = ""):
	print_rich("[color=#FF3531]"+(str+str2+str3+str4)+"[/color]")
func _printwarning(str : String, str2 : String = "", str3 : String = "", str4 : String = ""):
	print_rich("[color=#FFF831]"+(str+str2+str3+str4)+"[/color]")

func get_grid_aabbi() -> AABBi:
	return AABBi.new(Vector3i(0,0,0), dungeon_size)

func get_room_at_pos(grid_pos : Vector3i) -> DungeonRoom3D:
	if stage > BuildStage.CONNECT_ROOMS:
		 # Can use these vars for speedup if past the connect rooms stage where we set them
		var quick_check = _quick_room_check_dict.get(grid_pos)
		return quick_check if quick_check else _quick_corridors_check_dict.get(grid_pos)
	for room in get_all_placed_and_preplaced_rooms():
		if room.get_grid_aabbi(false).contains_point(grid_pos):
			return room
	return null
	
var _preplaced_rooms_cached : Array = []
func get_preplaced_rooms() -> Array:
	var rooms := []
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _preplaced_rooms_cached.slice(0)
	else:
		rooms.assign(get_children().filter(func(c): return c is DungeonRoom3D))
		_preplaced_rooms_cached = rooms.slice(0)
		return rooms

func get_all_placed_and_preplaced_rooms() -> Array:
	var rooms := get_preplaced_rooms()
	rooms.append_array(_rooms_placed)
	return rooms

# Any rooms with doors leading to more than 1 floor are considered stairs
func get_stair_rooms_from_instances() -> Array:
	var rooms := []
	rooms.assign(room_instances.filter(func(c):
		if not c is DungeonRoom3D: return false
		if not c.is_stair_room: return false
		var floors_dict = {}
		for door in c.get_doors_cached():
			floors_dict[door.local_pos.y] = true
		return floors_dict.keys().size() >= 2))
	return rooms

################
## VALIDATION ##
################

# Returns true if no errors found before generating.
# Calls callbacks with warning/error string if any.
# Upon generate, also calls validation checks on each of the rooms.
func validate_dungeon(error_callback = null, warning_callback = null) -> bool:
	# printerr and push_warning do not always work. Only print() seems to reliably output.
	if not warning_callback is Callable: warning_callback = (func(str): _printwarning("SimpleDungeons Warning: ", str))
	if not error_callback is Callable: error_callback = (func(str): _printerr("SimpleDungeons Error: ", str))
	var any_errors : = {"err": false} # So lambda closure captures
	error_callback = (func(str): any_errors["err"] = true; error_callback.call(str))
	
	if not corridor_room_scene:
		error_callback.call("No corridor room scene set. Add a 1x1x1 (in voxels) corridor room scene.")
	if room_scenes.size() == 0:
		error_callback.call("No rooms added. Add DungeonRoom scenes to the room_scenes property.")
	
	if not is_currently_generating:
		return not any_errors["err"]
	
	# Build stage checks:
	
	if not room_instances is Array or len(room_instances) == 0:
		error_callback.call("No rooms added. Cannot generate dungeon.")
	if room_instances is Array:
		for room in room_instances:
			if not room is DungeonRoom3D:
				error_callback.call("Room "+room.name+" does not inherit DungeonRoom3D! Also add @tool to dungeon room script if generating in editor.")
			else:
				if not room.has_method("validate_room"):
					error_callback.call("validate_room() method not found on room "+room.name+". Ensure it inherits DungeonRoom3D and has the @tool annotation if you're trying to generate in editor.")
				room.validate_room(error_callback, warning_callback)
	if not corridor_room_instance is DungeonRoom3D:
		var corridor_name = corridor_room_instance.name if corridor_room_instance else "null"
		error_callback.call("Corridor Room "+corridor_name+" does not inherit DungeonRoom3D!")
	if corridor_room_instance is DungeonRoom3D and corridor_room_instance.size_in_voxels != Vector3i(1,1,1):
		error_callback.call("Corridor Room must be 1x1x1 in voxels.")
	if corridor_room_instance and not corridor_room_instance.has_method("get_doors"):
		error_callback.call("get_doors() method not found on the corridor room. Ensure it inherits DungeonRoom3D and has the @tool annotation if you're trying to generate in editor.")
	if corridor_room_instance is DungeonRoom3D and (corridor_room_instance.get_doors().size() != 4 or corridor_room_instance.get_doors().any(func(d): return not d.optional)):
		error_callback.call("Corridor Room must have 4 optional doors")
	if corridor_room_instance is DungeonRoom3D:
		corridor_room_instance.validate_room(error_callback, warning_callback)
		if corridor_room_instance.size_in_voxels != Vector3i(1,1,1):
			error_callback.call("Corridor room scene must be 1x1x1 in voxels. It is used to connect the rooms with hallways.")
	
	return not any_errors["err"]
