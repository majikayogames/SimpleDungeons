@tool
class_name DungeonKit
extends Node3D

@export var room_size : Vector3 = Vector3(10,10,10)
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

func create_debug_door_boxes():
	hide_debug_door_boxes()
	for room in get_rooms():
		if room.visible == false:
			continue
		var doors = room.get_doors()
		#print(len(doors))
		for door in doors:
			#if door.pos == Vector3i(0,0,0):
				#continue
			#var box = Label3D.new()
			#box.text = str(door.pos.x, door.pos.y, door.pos.z)
			var box = CSGBox3D.new()
			var label = Label3D.new()
			room.add_child(label)
			label.text = str(door.local_pos)
			room.add_child(box)
			#print("door.local_pos")
			#print(door.local_pos)
			var corner = room.global_position + room.get_aabb_rel_to_room().position
			box.global_position = corner + (Vector3(door.local_pos) + Vector3(0.5,0.25,0.5)) * self.room_size
			box.global_position += DungeonUtils.DIRECTION_VECTORS[door.dir] * self.room_size / 2
			#print(box.position)
			label.position = box.position + Vector3(0,1.5,0)
			var nudge_towards_center = DungeonUtils.DIRECTION_VECTORS[door.dir] * Vector3(-1, 0, -1) * 0.75
			box.global_position += nudge_towards_center
			label.global_position += nudge_towards_center
			box.name = "DEBUG_BOX_"+room.name
			label.name = "DEBUG_LABEL_"+room.name
			if door.optional:
				box.material = StandardMaterial3D.new()
				box.material.albedo_color = Color(1, 0.86666667461395, 0.10588235408068)
				label.modulate = Color(1, 0.86666667461395, 0.10588235408068)
				label.text += " Optional"

func get_rooms() -> Array[DungeonRoom]:
	var rooms := [] as Array[DungeonRoom]
	for room in get_children().filter(func(c): return c is DungeonRoom):
		rooms.push_back(room)
		# Some glue to get the kit system to work. Can't set in _init without spawning into scene
		room.dungeon_kit = self
	return rooms
