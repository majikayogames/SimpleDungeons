@tool
extends DungeonGenerator3D

func _ready():
	self.custom_get_rooms_function = custom_get_rand_rooms
	super._ready()

func _process(delta):
	super._process(delta)

func custom_get_rand_rooms(room_instances : Array[DungeonRoom3D], rng_seeded : RandomNumberGenerator) -> Array[DungeonRoom3D]:
	var num_blue_rooms : int = 30
	var num_red_rooms : int = 30
	var blue_room = room_instances.filter(func(r): return r.name == "BlueRoom")[0]
	var red_room = room_instances.filter(func(r): return r.name == "RedRoom")[0]
	var rooms : Array[DungeonRoom3D] = []
	while num_red_rooms > 0:
		var inst = red_room.create_clone_and_make_virtual_unless_visualizing()
		rooms.push_back(inst)
		# Set room_rotations before set_position_by_grid_pos as it is set by AABB positon. May change when rotated.
		inst.room_rotations = rng_seeded.randi()
		inst.set_position_by_grid_pos(
			Vector3i(
				(rng_seeded.randi() % dungeon_size.x) / 2,
				rng_seeded.randi() % dungeon_size.y,
				rng_seeded.randi() % dungeon_size.z))
		num_red_rooms -= 1
	while num_blue_rooms > 0:
		var inst = blue_room.create_clone_and_make_virtual_unless_visualizing()
		rooms.push_back(inst)
		# Set room_rotations before set_position_by_grid_pos as it is set by AABB positon. May change when rotated.
		inst.room_rotations = rng_seeded.randi()
		inst.set_position_by_grid_pos(
			Vector3i(
				(rng_seeded.randi() % dungeon_size.x) / 2 + dungeon_size.x / 2,
				rng_seeded.randi() % dungeon_size.y,
				rng_seeded.randi() % dungeon_size.z))
		num_blue_rooms -= 1
	return rooms
