@tool
class_name DungeonRoom
extends Node3D

signal placed_room()

var dungeon_generator : DungeonGenerator
var dungeon_kit

@export var min_count : int = 2
@export var max_count : int = 5

var grid_pos := Vector3i()

var size_in_grid := Vector3i() :
	set(value): pass
	get: return Vector3i(get_aabb_in_grid().size.round())

## A class that represent a door on a dungeon room
class Door:
	var local_pos : Vector3i
	var grid_pos : Vector3i :
		get: return room.grid_pos + local_pos
	var exit_pos_local : Vector3i :
		get: return local_pos + Vector3i(DungeonUtils.DIRECTION_VECTORS[dir])
	var exit_pos_grid : Vector3i :
		get: return grid_pos + Vector3i(DungeonUtils.DIRECTION_VECTORS[dir])
	var dir : DungeonUtils.Direction
	var optional : bool
	var room : DungeonRoom
	var door_node : Node3D
	func _init(local_pos : Vector3, dir : DungeonUtils.Direction, optional : bool, room : DungeonRoom, door_node : Node3D):
		self.local_pos = Vector3i(local_pos.round())
		self.dir = dir
		self.optional = optional
		self.room = room
		self.door_node = door_node
	func fits_other_door(other_door : Door) -> bool:
		return other_door.exit_pos_grid == grid_pos and other_door.dir == DungeonUtils.NEGATE_DIRECTION[dir]
	func leads_to_room(other_room : DungeonRoom) -> bool:
		return other_room.get_aabb_in_grid().has_point(Vector3(exit_pos_grid) + Vector3(0.5, 0.5, 0.5))
	func get_room_leads_to() -> DungeonRoom:
		var other_room := room.dungeon_generator.get_room_at_pos(exit_pos_grid)
		if other_room == null: return null
		for door in other_room.get_doors():
			if fits_other_door(door):
				return other_room
		return null

func make_duplicate() -> DungeonRoom:
	var dupe = self.duplicate()
	dupe.dungeon_kit = dungeon_kit
	#var rng = RandomNumberGenerator.new()
	dupe.name = self.name + "_" + str(randi())
	return dupe

func set_pos_from_aabb_corner(pos : Vector3) -> void:
	self.position = pos - get_aabb_rel_to_room().position

# Can't use global_transform when it's not actually in the tree
func get_transform_rel_to(child_node : Node3D, parent_node : Node3D) -> Transform3D:
	var transform = Transform3D()
	while child_node != parent_node and child_node != null:
		transform = child_node.transform * transform
		child_node = child_node.get_parent()
	return transform

var _aabb_rel_to_room_cached = null
func get_aabb_rel_to_room() -> AABB:
	if _aabb_rel_to_room_cached == null:
		var aabb = get_children().filter(func(c): return c.name == "AABB")[0]
		var aabb_transform = get_transform_rel_to(aabb, self)
		var aabb_size = aabb_transform.basis * aabb.size
		_aabb_rel_to_room_cached = AABB(aabb_transform.origin - aabb_size / 2, aabb_size)
	return _aabb_rel_to_room_cached

func get_aabb_in_grid() -> AABB:
	var aabb = get_aabb_rel_to_room()
	# Not quite full size of grid to prevent rounding errors, not sure if necessary.
	return AABB(grid_pos, aabb.size / dungeon_kit.grid_voxel_size * 0.99)

func push_away_from(other_room : DungeonRoom) -> void:
	var diff := other_room.get_aabb_in_grid().get_center() - get_aabb_in_grid().get_center()
	grid_pos.x -= 1 if diff.x > 0 else -1
	grid_pos.z -= 1 if diff.z > 0 else -1
	other_room.grid_pos.x += 1 if diff.x > 0 else -1
	other_room.grid_pos.z += 1 if diff.z > 0 else -1

func overlaps_room(other_room : DungeonRoom) -> bool:
	var aabbs_overlap = get_aabb_in_grid().intersects(other_room.get_aabb_in_grid())
	# Separate with a margin for doors, but allow if 2 opposing doors fit together
	var door_intersects = (func(door : Door, room : DungeonRoom):
		if door.leads_to_room(room):
			return not room.get_doors().any(func(_d): return _d.fits_other_door(door))
		else: return false)
	var other_doors_intersect = other_room.get_doors().any(door_intersects.bind(self))
	var my_doors_intersect = get_doors().any(door_intersects.bind(other_room))
	return aabbs_overlap or other_doors_intersect or my_doors_intersect

func _find_door_nodes(node : Node = self, result_array = []):
	if node.name.begins_with("DOOR"):
		result_array.push_back(node)
	for child in node.get_children():
		_find_door_nodes(child, result_array)
	return result_array

func set_room_transform_to_grid_pos():
	var pos_in_space = Vector3(grid_pos) * dungeon_kit.grid_voxel_size
	set_pos_from_aabb_corner(pos_in_space)

func get_door_by_node(door_node : Node3D) -> Door:
	for door in get_doors():
		if door.door_node == door_node:
			return door
	return null

var _doors_cached = null
func get_doors() -> Array[Door]:
	if _doors_cached != null and not Engine.is_editor_hint():
		return _doors_cached
	var real_aabb_local = get_aabb_rel_to_room()
	#real_aabb_local.position = self.transform.inverse() * real_aabb_local.position
	#real_aabb_local.size = self.transform.basis.inverse() * real_aabb_local.size
	
	var potential_door_exit_positions = []
	var corresponding_door_pos_grid_for_exit_pos = []
	
	var room_doors = [] as Array[Door]
	for door in _find_door_nodes():
		# Get door pos from min corner of aabb, then divide by the full aabb size.
		var door_pos_pct_across = (get_transform_rel_to(door, self).origin - real_aabb_local.position) / real_aabb_local.size
		# Snap door pos to grid pos
		var door_pos_grid = (door_pos_pct_across * get_aabb_in_grid().size).floor()
		door_pos_grid = door_pos_grid.clamp(Vector3(0,0,0), Vector3(get_aabb_in_grid().size.x - 1, get_aabb_in_grid().size.y - 1, get_aabb_in_grid().size.z - 1))
		# Find the door direction by the its vector from the grid square's center point
		var grid_center_pct_across = (door_pos_grid + Vector3(0.5,0.5,0.5)) / get_aabb_in_grid().size
		var door_dir := DungeonUtils.vec3_to_direction(door_pos_pct_across - grid_center_pct_across)
		var door_obj := Door.new(door_pos_grid, door_dir, door.name.begins_with("DOOR?"), self, door)
		room_doors.push_back(door_obj)
	
	_doors_cached = room_doors
	return room_doors
