@tool
class_name DungeonKit
extends Node3D

## The dungeon generates on a standardized grid, so all room you create must have
## have their AABBs sized in multiples of whatever cube/voxel size you choose here.
@export var grid_voxel_size : Vector3 = Vector3(10,10,10)
@export var editor_show_debug_door_locations : bool = false :
	set(value): create_debug_door_boxes()
@export var editor_clear_debug_door_locations : bool = false :
	set(value): hide_debug_door_boxes()
@export var show_debug_in_game : bool = false

func _ready():
	if show_debug_in_game:
		create_debug_door_boxes()

func hide_debug_door_boxes():
	for debug_box in find_children("DEBUG_BOX*", "", true, false):
		debug_box.queue_free()
	for debug_label in find_children("DEBUG_LABEL*", "", true, false):
		debug_label.queue_free()
	for debug_grid in find_children("DEBUG_GRID*", "", true, false):
		debug_grid.queue_free()

func create_debug_door_boxes():
	hide_debug_door_boxes()
	for room in get_rooms():
		if room.visible == false:
			continue
		var doors = room.get_doors()
		for door in doors:
			var box = CSGBox3D.new()
			var label = Label3D.new()
			var wireframe_grid = preload("res://addons/SimpleDungeons/WireframeCube.tscn").instantiate()
			room.add_child(wireframe_grid)
			room.add_child(label)
			label.text = str(door.local_pos)
			room.add_child(box)
			var corner = room.global_position + room.get_aabb_rel_to_room().position
			box.global_position = corner + (Vector3(door.local_pos) + Vector3(0.5,0.25,0.5)) * self.grid_voxel_size
			box.global_position += DungeonUtils.DIRECTION_VECTORS[door.dir] * self.grid_voxel_size / 2
			label.position = box.position + Vector3(0,1.5,0)
			var nudge_towards_center = DungeonUtils.DIRECTION_VECTORS[door.dir] * Vector3(-1, 0, -1) * 0.75
			if abs(nudge_towards_center.x) > abs(nudge_towards_center.z):
				box.size.x /= 5.0
			else:
				box.size.z /= 5.0
			box.size.y *= 1.5
			box.size *= 1.2
			box.global_position += nudge_towards_center
			label.global_position += nudge_towards_center
			box.name = "DEBUG_BOX_"+room.name
			label.name = "DEBUG_LABEL_"+room.name
			wireframe_grid.name = "DEBUG_GRID_"+room.name
			wireframe_grid.grid_size = room.size_in_grid
			print(room.name)
			print(room.size_in_grid)
			wireframe_grid.position = room.get_aabb_rel_to_room().position + room.get_aabb_rel_to_room().size / 2.0
			wireframe_grid.scale = Vector3(room.size_in_grid) * grid_voxel_size * 1.01
			box.material = StandardMaterial3D.new()
			box.material.albedo_color = Color(1, 1.0, 1.0, 0.5)
			box.material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			if door.optional:
				box.material.albedo_color = Color(1, 0.86666667461395, 0.10588235408068, 0.5)
				label.modulate = Color(1, 0.86666667461395, 0.10588235408068)
				label.text += " Optional"

func get_rooms() -> Array[DungeonRoom]:
	var rooms := [] as Array[DungeonRoom]
	for room in get_children().filter(func(c): return c is DungeonRoom):
		rooms.push_back(room)
		# Some glue to get the kit system to work. Can't set in _init without spawning into scene
		room.dungeon_kit = self
	return rooms
