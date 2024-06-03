@tool
extends DungeonRoom3D


# Called when the node enters the scene tree for the first time.
func _ready():
	super._ready()
	dungeon_done_generating.connect(remove_unused_doors_and_walls)

func remove_unused_doors_and_walls():
	if get_door_by_node($"CSGBox3D/DOOR?_B_CUT").get_room_leads_to() == null: $Models/B_DOOR.queue_free(); $Models/B_WALL.visible = true
	else: $Models/B_WALL.queue_free(); $Models/B_DOOR.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_RB_CUT").get_room_leads_to() == null: $Models/RB_DOOR.queue_free(); $Models/RB_WALL.visible = true
	else: $Models/RB_WALL.queue_free(); $Models/RB_DOOR.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_RF_CUT").get_room_leads_to() == null: $Models/RF_DOOR.queue_free(); $Models/RF_WALL.visible = true
	else: $Models/RF_WALL.queue_free(); $Models/RF_DOOR.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_LB_CUT").get_room_leads_to() == null: $Models/LB_DOOR.queue_free(); $Models/LB_WALL.visible = true
	else: $Models/LB_WALL.queue_free(); $Models/LB_DOOR.visible = true
	if get_door_by_node($"CSGBox3D/DOOR?_LF_CUT").get_room_leads_to() == null: $Models/LF_DOOR.queue_free(); $Models/LF_WALL.visible = true
	else: $Models/LF_WALL.queue_free(); $Models/LF_DOOR.visible = true
	for door in get_doors():
		if door.get_room_leads_to() == null:
			door.door_node.queue_free()
