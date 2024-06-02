@tool
extends DungeonRoom3D

# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	dungeon_done_generating.connect(remove_unused_doors_and_walls)

func remove_unused_doors_and_walls():
	if RandomNumberGenerator.new().randf_range(0,10) > 2.5: $Models/F_WALL/torch_001.queue_free()
	if RandomNumberGenerator.new().randf_range(0,10) > 2.5: $Models/B_WALL/torch_001.queue_free()
	if RandomNumberGenerator.new().randf_range(0,10) > 2.5: $Models/R_WALL/torch_001.queue_free()
	if RandomNumberGenerator.new().randf_range(0,10) > 2.5: $Models/L_WALL/torch_001.queue_free()
	
	if get_door_by_node($"CSGBox3D/DOOR?_F_CUT").get_room_leads_to() != null: $Models/F_WALL.queue_free()
	else: $Models/F_WALL.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_R_CUT").get_room_leads_to() != null: $Models/R_WALL.queue_free()
	else: $Models/R_WALL.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_B_CUT").get_room_leads_to() != null: $Models/B_WALL.queue_free()
	else: $Models/B_WALL.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_L_CUT").get_room_leads_to() != null: $Models/L_WALL.queue_free()
	else: $Models/L_WALL.visible = true
	for door in get_doors():
		if door.get_room_leads_to() == null:
			door.door_node.queue_free()
