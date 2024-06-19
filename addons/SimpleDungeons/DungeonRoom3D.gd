@tool
class_name DungeonRoom3D
extends Node3D

signal dungeon_done_generating()

var dungeon_generator : DungeonGenerator3D :
	get:
		if is_inside_tree() and get_parent() is DungeonGenerator3D:
			return get_parent()
		else: return dungeon_generator

@export var size_in_voxels := Vector3i(1,1,1) :
	set(v):
		size_in_voxels = v.clamp(Vector3i(1,1,1),Vector3i(9999,9999,9999))
@export var voxel_scale := Vector3(10,10,10) :
	set(v):
		voxel_scale = v.clamp(Vector3(0.0001,0.0001,0.0001),Vector3(9999,9999,9999))

@export var min_count : int = 2
@export var max_count : int = 5

## Stair rooms are used in the floor connection stage and will have their min/max counts ignored.
## For the dungeon to generate, you must mark at least 1 room as a stair and have its doors span multiple floors.
@export var is_stair_room := false

## Preplaced rooms are immovable rooms you can place at a preset position in the dungeon
@export_group("Pre-placed room options")
## Editor button to align the room's position & scale with the dungeon's voxel grid.
## Will be called before generation to ensure room is aligned with grid.
@export var force_align_with_grid_button := false :
	set(_v):
		virtual_transform = self.transform
		snap_room_to_dungeon_grid()

func _validate_property(property: Dictionary):
	if property.name in ["force_align_with_grid_button"] and not get_parent() is DungeonGenerator3D:
		property.usage = PROPERTY_USAGE_NO_EDITOR

@export_group("Debug view")
@export var show_debug_in_editor : bool = true
@export var show_debug_in_game : bool = false
## For internal debug use only
@export var show_grid_aabb_with_doors : bool = false

var was_preplaced = false :
	get:
		if Engine.is_editor_hint():
			return is_inside_tree() and get_parent() is DungeonGenerator3D
		else: return was_preplaced

## Number of 90 degree rotations around the y axis
var room_rotations : int :
	set(v): virtual_transform.basis = Basis.from_euler(Vector3(0,wrapi(v, 0, 4) * deg_to_rad(90.0),0)).scaled(virtual_transform.basis.get_scale())
	get: return round(wrapi(round(virtual_transform.basis.get_euler().y / deg_to_rad(90.0)), 0, 4))

# For performance, we should not spawn/instantiate many dungeon rooms.
# This is because the dungeon generator may have to restart multiple times.
# We don't want to have to delete and restart all nodes/models/etc we instantiated
# Also, we cannot access the scene tree from other threads.
# So instead, we will create virtual DungeonRoom3Ds which reference the single original we create.
# Then, we can still encapsulate all the logic into this one class & improve performance.
var virtualized_from : DungeonRoom3D = null
# To be called instead of self on anything that requires transform or node access
# I think just in getting door nodes is the only part we need this.
var virtual_self : DungeonRoom3D = self :
	get: return virtualized_from if virtualized_from else self
# Cannot access the transform in threads at all so just saving it here and copying on unvirtualize.
var virtual_transform : Transform3D = Transform3D() :
	set(v):
		virtual_transform = v
		if is_inside_tree() and OS.get_main_thread_id() == OS.get_thread_caller_id():
			self.transform = v

var original_ready_func_called := false # For error checking. Ensure noone inherits this class w/o calling _ready.
func _ready():
	original_ready_func_called = true
	if not virtualized_from:
		add_debug_view_if_not_exist()
	# When spawning a room, make sure to set its transform to whatever its virtual/out of tree transform was set to.
	if virtual_transform != Transform3D():
		self.transform = virtual_transform
	elif self.transform != Transform3D():
		# For preplaced rooms:
		virtual_transform = self.transform
	# Mostly for debug and pre placed rooms:
	if get_parent() is Node3D:
		if get_parent() is DungeonGenerator3D:
			dungeon_generator = get_parent()
		if get_parent().get_parent() is DungeonGenerator3D:
			dungeon_generator = get_parent().get_parent()
	if Engine.is_editor_hint():
		return

func _process(delta):
	if Engine.is_editor_hint():
		return

const _dungeon_room_export_props_names = ["size_in_voxels", "voxel_scale", "min_count", "max_count", "is_stair_room", "show_debug_in_editor", "show_debug_in_game", "show_grid_aabb_with_doors"]
func copy_all_props(from : DungeonRoom3D, to : DungeonRoom3D) -> void:
	for prop in _dungeon_room_export_props_names:
		if from.get(prop) != to.get(prop):
			to.set(prop, from.get(prop))
	to.name = from.name
	to.dungeon_generator = from.dungeon_generator

func get_original_packed_scene() -> PackedScene:
	# Try to find the room packed scene in the DungeonGenerator3D so we don't have to load()
	if dungeon_generator:
		if dungeon_generator.corridor_room_scene.resource_path == virtual_self.scene_file_path:
			return dungeon_generator.corridor_room_scene
		for scene in dungeon_generator.room_scenes:
			if scene.resource_path == virtual_self.scene_file_path:
				return scene
	# Fall back to just getting it from the scene path just incase
	if virtual_self.scene_file_path:
		return load(virtual_self.scene_file_path)
	printerr(self.name+" Could not find DungeonRoom3D's original packed scene. This shouldn't happen. Are you manually spawning rooms?")
	return null

func create_clone_and_make_virtual_unless_visualizing() -> DungeonRoom3D:
	var make_clone_virtual : bool = true
	if dungeon_generator and dungeon_generator.visualize_generation_progress:
		make_clone_virtual = false
	var _clone
	if make_clone_virtual:
		#if not self.virtual_self._doors_cache:
		#	printerr("Cloning dungeon room without doors cached!!! Make sure to call .get_doors() at least once for all rooms.")
		_clone = DungeonRoom3D.new()
		_clone.virtualized_from = self.virtual_self
		# Can't access door nodes on threads, also if it's a clone, won't have any door nodes to check door pos/dir.
		#_clone._doors_cache = []
		for d in _doors_cache:
			_clone._doors_cache.push_back(Door.new(d.local_pos, d.dir, d.optional, _clone, d.door_node))
	else: _clone = get_original_packed_scene().instantiate()
	copy_all_props(virtual_self, _clone)
	_clone.dungeon_generator = self.dungeon_generator
	var name = virtual_self.name
	if dungeon_generator:
		name = name + "_" + str(len(dungeon_generator._rooms_placed))
	_clone.name = name
	return _clone

# Spawn the real room into the DungeonGenerator
func unvirtualize_and_free_clone_if_needed(into_parent : Node3D) -> DungeonRoom3D:
	if not virtualized_from:
		#if self.get_parent() != into_parent:
			#if self.get_parent() != null:
				#self.get_parent().remove_child(self)
			#into_parent.add_child(self)
		return self
	# Can't do this threaded anyway for virtualized so it's implied there will be no parent
	#var parent = self.get_parent()
	#parent.remove_child(self)
	self.queue_free()
	var inst : DungeonRoom3D = get_original_packed_scene().instantiate()
	copy_all_props(self, inst)
	inst.transform = self.virtual_transform
	into_parent.add_child(inst)
	inst.owner = into_parent.owner
	return inst

var _debug_view = null
func add_debug_view_if_not_exist():
	if not _debug_view:
		_debug_view = preload("res://addons/SimpleDungeons/debug_visuals/DungeonRoom3DDebugView.gd").new()
		add_child(_debug_view)

###########
## DOORS ##
###########

## A class that represent a door on a dungeon room
## TODO probably remove this 'dir' variable as it is just confusing now that we have rotations
class Door:
	var local_pos : Vector3i
	var grid_pos : Vector3i :
		get: return room.local_grid_pos_to_dungeon_grid_pos(local_pos)
	var exit_pos_local : Vector3i :
		get: return local_pos + Vector3i(DungeonUtils.DIRECTION_VECTORS[dir])
	var exit_pos_grid : Vector3i :
		get: return room.local_grid_pos_to_dungeon_grid_pos(exit_pos_local)
	var dir : DungeonUtils.Direction
	var optional : bool
	var room : DungeonRoom3D
	var door_node : Node3D
	func _init(local_pos : Vector3, dir : DungeonUtils.Direction, optional : bool, room : DungeonRoom3D, door_node : Node3D):
		self.local_pos = Vector3i(local_pos.round())
		self.dir = dir
		self.optional = optional
		self.room = room
		self.door_node = door_node
	func fits_other_door(other_room_door : Door) -> bool:
		return other_room_door.exit_pos_grid == grid_pos and other_room_door.grid_pos == exit_pos_grid
	func find_duplicates() -> Array:
		return room.get_doors().filter(func (d : Door): return d.exit_pos_local == exit_pos_local and d.local_pos == local_pos)
	func validate_door() -> bool:
		if not AABBi.new(Vector3i(), room.size_in_voxels).contains_point(local_pos):
			return false
		if AABBi.new(Vector3i(), room.size_in_voxels).contains_point(exit_pos_local):
			return false
		if find_duplicates().size() > 1:
			return false
		return true
	func get_room_leads_to() -> DungeonRoom3D:
		var other_room = room.dungeon_generator.get_room_at_pos(exit_pos_grid)
		if other_room == null: return null
		for door in other_room.get_doors():
			if fits_other_door(door):
				return other_room
		return null

func get_door_nodes() -> Array[Node3D]:
	var doors : Array[Node3D] = [] # .assign typecast workaround https://github.com/godotengine/godot/issues/72566
	doors.assign(virtual_self.find_children("DOOR*", "Node3D"))
	return doors

func get_door_by_node(node : Node) -> Door:
	for door in get_doors():
		if door.door_node == node:
			return door
	return null

# For calling on other threads/for virtualized rooms
func get_doors_cached() -> Array:
	return self._doors_cache

func ensure_doors_and_or_transform_cached_for_threads_and_virtualized_rooms() -> void:
	if is_inside_tree(): # transform cache only applies to preplaced rooms
		virtual_transform = self.transform
	get_doors()

# For some reason this mutex is required or I get crashes all over the place on threads.
# I never access _doors_cache from main thread so maybe it's overly sensitive thread guards.
var _thread_fix_mutex := Mutex.new()
var _doors_cache : Array = [] :
	set(v):
		_thread_fix_mutex.lock()
		_doors_cache = v
		_thread_fix_mutex.unlock()
	get:
		_thread_fix_mutex.lock()
		var tmp = _doors_cache
		_thread_fix_mutex.unlock()
		return tmp

func get_doors() -> Array:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or virtualized_from != null:
		# Ensure using get_doors_cached() when dealing with virtual rooms/threads.
		return _doors_cache
	var real_aabb_local = get_local_aabb()
	
	var room_doors = []
	for door in get_door_nodes():
		# Get door pos from min corner of aabb, then divide by the full aabb size.
		var door_pos_pct_across = (get_transform_rel_to(door, self).origin - real_aabb_local.position) / real_aabb_local.size
		# Snap door pos to the grid square it's in
		var door_pos_grid = (door_pos_pct_across * Vector3(size_in_voxels)).floor()
		door_pos_grid = door_pos_grid.clamp(Vector3(0,0,0), Vector3(size_in_voxels) - Vector3(1,1,1))
		var grid_center_pct_across = (door_pos_grid + Vector3(0.5,0.5,0.5)) / Vector3(size_in_voxels)
		# Find the door direction by the its vector from the grid square's center point
		var door_dir := DungeonUtils.vec3_to_direction(door_pos_pct_across - grid_center_pct_across)
		var door_obj := Door.new(door_pos_grid, door_dir, door.name.begins_with("DOOR?"), self, door)
		room_doors.push_back(door_obj)
	
	_doors_cache = room_doors
	return room_doors

#######################
## UTILITY FUNCTIONS ##
#######################

func push_away_from_and_stay_within_bounds(other_room : DungeonRoom3D) -> void:
	var diff := other_room.virtual_transform.origin - self.virtual_transform.origin
	var move := Vector3i(
		-1 if diff.x > 0 else 1,
		0,
		-1 if diff.z > 0 else 1)
	var dpos = get_grid_aabbi(true)
	var able_to_move = dpos.translated(move).push_within(dungeon_generator.get_grid_aabbi(), true).position - dpos.position
	if able_to_move.x != 0 or able_to_move.z != 0:
		set_position_by_grid_pos(get_grid_pos() + able_to_move)

func overlaps_room(other_room : DungeonRoom3D) -> bool:
	var aabbis = { self: self.get_grid_aabbi(false), other_room: other_room.get_grid_aabbi(false) }
	if aabbis[self].intersects(aabbis[other_room]): return true
	# Separate with a margin for doors, but allow if 2 opposing doors fit together
	var door_intersects = (func(door : Door, room : DungeonRoom3D):
		# Optional doors can intersect but not if stair room
		if door.optional and not door.room.is_stair_room: return false
		if not aabbis[room].contains_point(door.exit_pos_grid): return false
		return not room.get_doors().any(func(_d): return _d.fits_other_door(door)))
	if other_room.get_doors().any(door_intersects.bind(self)): return true
	if get_doors().any(door_intersects.bind(other_room)): return true
	return false

func snap_room_to_dungeon_grid() -> void:
	if not dungeon_generator:
		return
	snap_rotation_and_scale_to_dungeon_grid()
	set_position_by_grid_pos()
	constrain_room_to_bounds_with_doors()

func constrain_room_to_bounds_with_doors():
	# For stair rooms, also ensure optional doors can be reached. So stairs don't get their path blocked against wall
	var aabbi_with_doors := get_grid_aabbi(true)
	var aabbi_with_doors_constrained := aabbi_with_doors.push_within(dungeon_generator.get_grid_aabbi(), false)
	set_position_by_grid_pos(get_grid_pos() + (aabbi_with_doors_constrained.position - aabbi_with_doors.position))

## Room must be scaled so voxel scale matches the DungeonGenerator3D's voxel scale.
func snap_rotation_and_scale_to_dungeon_grid() -> void:
	virtual_transform = Transform3D(Basis().rotated(Vector3(0,1,0), self.room_rotations * deg_to_rad(90.0)).scaled(dungeon_generator.voxel_scale / voxel_scale), virtual_transform.origin)

## Returns room pos from corner (min) of AABB on dungeon grid 
func get_grid_pos() -> Vector3i:
	return get_grid_aabbi(false).position

## Set position of room from corner (min) of AABB on dungeon grid
func set_position_by_grid_pos(new_grid_pos : Vector3i = get_grid_pos()) -> void:
	if not dungeon_generator: printerr("set_position_by_grid_pos: No dungeon_generator set on DungeonRoom3D")
	var cur_aabb := xform_aabb(get_local_aabb(), get_xform_to(SPACE.LOCAL_SPACE, SPACE.DUNGEON_GRID))
	cur_aabb.position = Vector3(new_grid_pos)
	cur_aabb = xform_aabb(cur_aabb, get_xform_to(SPACE.DUNGEON_GRID, SPACE.DUNGEON_SPACE))
	virtual_transform.origin = cur_aabb.get_center()

# Probably a good idea to have this in. Hopping between local/dungeon space, grid, and editor positions
enum SPACE { LOCAL_GRID = 0, LOCAL_SPACE = 1, DUNGEON_SPACE = 2, DUNGEON_GRID = 3 }
func get_xform_to(from : SPACE, to : SPACE) -> Transform3D:
	var t = Transform3D()
	var inv := to < from
	if inv:
		var tmp = to; to = from; from = tmp
	
	if from <= SPACE.LOCAL_GRID and to >= SPACE.LOCAL_SPACE:
		t = Transform3D(Basis().scaled(voxel_scale), self.get_local_aabb().position) * t
	if from <= SPACE.LOCAL_SPACE and to >= SPACE.DUNGEON_SPACE:
		t = virtual_transform * t
	if from <= SPACE.DUNGEON_SPACE and to >= SPACE.DUNGEON_GRID and dungeon_generator:
		t = Transform3D(Basis().scaled(dungeon_generator.voxel_scale.inverse()), Vector3(dungeon_generator.dungeon_size)/2.0) * t
	
	return t.affine_inverse() if inv else t

## Different behavior than Godot's transform * AABB. This properly scales too. Regular just does position & rotation.
func xform_aabb(aabb : AABB, xform : Transform3D) -> AABB:
	var pos := xform * aabb.position
	var end := xform * aabb.end
	return AABB(pos, end - pos).abs()

func xform_aabbi(aabbi : AABBi, xform : Transform3D) -> AABBi:
	return AABBi.from_AABB_rounded(xform_aabb(aabbi.to_AABB(), xform))

func get_local_aabb() -> AABB:
	var size := Vector3(size_in_voxels) * voxel_scale
	return AABB(-size/2.0, size)

func get_grid_aabbi(include_doors : bool) -> AABBi:
	# For stair rooms, all doors are counted for AABB. Generally even if they are optional, want to guarantee able to walk out of them to connect floors
	var grid_aabbi = AABBi.from_AABB_rounded(xform_aabb(get_local_aabb(), get_xform_to(SPACE.LOCAL_SPACE, SPACE.DUNGEON_GRID)))
	if include_doors: # Include doors after to keep position the same
		for door in get_doors().filter(func(d : Door): return !d.optional or self.is_stair_room):
			grid_aabbi = grid_aabbi.expand_to_include(door.exit_pos_grid)
	return grid_aabbi

func local_grid_pos_to_dungeon_grid_pos(local_pos : Vector3i) -> Vector3i:
	# It will be rounded in wrong direction when rotated 180 going to dungeon space.
	# So use middle of local grid and .floor() instead of .round() at end.
	var transformed_middle := get_xform_to(SPACE.LOCAL_GRID, SPACE.DUNGEON_GRID) * (Vector3(local_pos) + Vector3(0.5,0.5,0.5))
	return Vector3i(transformed_middle.floor())

# Can't use global_transform when it's not actually in the scene tree.
# Just using this for doors.
func get_transform_rel_to(child_node : Node3D, parent_node : Node3D) -> Transform3D:
	var transform = Transform3D()
	while child_node != parent_node:
		transform = child_node.transform * transform
		if child_node.get_parent() is Node3D: child_node = child_node.get_parent()
		else: break
	return transform

################
## VALIDATION ##
################

# printerr() and push_warning() eat my outputs a lot. Regular prints are more reliable.
func _printerr(str : String, str2 : String = "", str3 : String = "", str4 : String = ""):
	print_rich("[color=#FF3531]"+(str+str2+str3+str4)+"[/color]")
func _printwarning(str : String, str2 : String = "", str3 : String = "", str4 : String = ""):
	print_rich("[color=#FFF831]"+(str+str2+str3+str4)+"[/color]")

# Returns true if no errors found before generating.
# Calls callbacks with warning/error string if any.
func validate_room(error_callback = null, warning_callback = null) -> bool:
	if not warning_callback is Callable: warning_callback = (func(str): _printwarning(str))
	if not error_callback is Callable: error_callback = (func(str): _printerr(str))
	var any_errors := {"err": false} # So lambda closure captures
	error_callback = func(str): any_errors["err"] = true; error_callback.call(str)
	
	var doors = get_doors()
	if doors.size() == 0:
		warning_callback.call("Room "+self.name+" has no doors defined. Room will be unreachable. Add doors by creating Node3Ds with names prefixed with DOOR or DOOR? for optional doors.")
	if not doors.all(func(d : Door): return d.validate_door()):
		error_callback.call("Room "+self.name+" has one or more invalid doors.")
	if doors.any(func(d : Door): return d.find_duplicates().size() > 1):
		error_callback.call("Room "+self.name+" has one or more overlapping/duplicate doors.")
	
	var unique_door_y = doors.reduce(func(acc : Dictionary, d : Door):
		acc[d.local_pos.y] = true
		return acc, {})
	if is_stair_room and unique_door_y.keys().size() < 2:
		error_callback.call("Room "+self.name+" is set as is_stair_room but does not have doors leading to 2 or more floors.")
	
	# Post instantiate/place checks:
	if not dungeon_generator:
		return not any_errors["err"]
	
	if not self.scale.is_equal_approx(Vector3(1,1,1)):
		warning_callback.call("Room "+self.name+"'s root node scale should be set to Vector3(1,1,1). Will be scaled during generation.")
	if voxel_scale != dungeon_generator.voxel_scale:
		warning_callback.call("Room "+self.name+"'s voxel scale does not match DungeonGenerator3D voxel size. Room will be scaled to match.")
	if size_in_voxels != size_in_voxels.clamp(Vector3i(0,0,0), dungeon_generator.dungeon_size):
		error_callback.call("Room "+self.name+" is too big for the DungeonGenerator3D!")
	
	return not any_errors["err"]
