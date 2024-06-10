@tool
extends Node3D

@export var dungeon_generator : DungeonGenerator3D
@export var show_delay_ms := 1000

var done_time
var done = false

func _update_to_dungeon():
	if not dungeon_generator:
		return
	var realsize = Vector3(dungeon_generator.dungeon_size) * dungeon_generator.voxel_scale
	$HouseWalls/InsideCut.size = realsize
	$HouseWalls.size = realsize + Vector3(5,5,5)
	$Roof.mesh.size = realsize + Vector3(10,10,10)
	$Roof.mesh.size.y = 20
	$Roof.position.y = realsize.y / 2 + 10 + 2.5
	if not done_time and dungeon_generator.stage == DungeonGenerator3D.BuildStage.DONE:
		done_time = Time.get_ticks_msec()
	if not done and done_time and Time.get_ticks_msec() - done_time > show_delay_ms:
		done = true
		var entrance = dungeon_generator.get_node("MansionEntranceRoom")
		var xform_to_global = dungeon_generator.global_transform * entrance.get_xform_to(DungeonRoom3D.SPACE.LOCAL_GRID, DungeonRoom3D.SPACE.DUNGEON_SPACE)
		var corner_of_room = xform_to_global * Vector3(0,0,3)
		$Entrance.position = corner_of_room
		$Entrance/FrontDoorCut.reparent($HouseWalls)
	self.visible = done
	

func _ready():
	_update_to_dungeon()

func _process(delta):
	_update_to_dungeon()
