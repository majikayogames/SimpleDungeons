@tool
extends Node3D

var dungeon_room : DungeonRoom3D = null
var wireframe_cube : Node3D = null
var debug_alert : Node3D = null
var aabb_with_doors : Node3D = null

# Dict mapping DungeonRoom3D Door:DoorDebugVisual
var door_visuals = []
func update_door_visuals(show_visuals : bool):
	var room_doors := []
	if show_visuals:
		room_doors = dungeon_room.get_doors()
	# Add/remove debug visuals to match
	while len(door_visuals) < len(room_doors):
		var door_visual = preload("res://addons/SimpleDungeons/debug_visuals/DoorDebugVisual.tscn").instantiate()
		add_child(door_visual)
		door_visuals.push_back(door_visual)
	while len(door_visuals) > len(room_doors):
		var door_visual = door_visuals.pop_back()
		remove_child(door_visual)
		door_visual.queue_free()
	for i in len(room_doors):
		door_visuals[i].position = (Vector3(room_doors[i].local_pos) + Vector3(.5,.5,.5)) * dungeon_room.voxel_scale
		door_visuals[i].position -= Vector3(dungeon_room.size_in_voxels) * dungeon_room.voxel_scale * 0.5
		door_visuals[i].position += DungeonUtils.DIRECTION_VECTORS[room_doors[i].dir] * 0.5 * dungeon_room.voxel_scale
		door_visuals[i].rotation.y = -DungeonUtils.DIRECTION_VECTORS[room_doors[i].dir].signed_angle_to(DungeonUtils.DIRECTION_VECTORS[DungeonUtils.Direction.FRONT], Vector3.UP)
		door_visuals[i].scale = dungeon_room.voxel_scale / 10.0
		var col = Color.YELLOW if room_doors[i].optional else Color.GREEN
		door_visuals[i].text = "OPTIONAL DOOR" if room_doors[i].optional else "DOOR"
		door_visuals[i].color = col if room_doors[i].validate_door() else Color.RED

func update_visual():
	var show_editor = Engine.is_editor_hint() and dungeon_room.show_debug_in_editor
	var show_game = not Engine.is_editor_hint() and dungeon_room.show_debug_in_game
	#if not get_parent() is DungeonGenerator3D:
		#print(dungeon_room.name)
	if dungeon_room.dungeon_generator and dungeon_room.dungeon_generator.hide_debug_visuals_for_all_generated_rooms and not (dungeon_room.get_parent() is DungeonGenerator3D):
		show_editor = false
		show_game = false
	if not show_editor and not show_game:
		update_door_visuals(false)
		for dbg_visual in [wireframe_cube, debug_alert, aabb_with_doors]:
			if dbg_visual and is_instance_valid(dbg_visual):
				remove_child(dbg_visual)
				dbg_visual.queue_free()
		wireframe_cube = null; debug_alert = null; aabb_with_doors = null;
		return
	
	update_door_visuals(true)
	
	if not wireframe_cube or not is_instance_valid(wireframe_cube):
		wireframe_cube = preload("res://addons/SimpleDungeons/debug_visuals/WireframeCube.tscn").instantiate()
		add_child(wireframe_cube)
	wireframe_cube.scale = Vector3(dungeon_room.size_in_voxels) * dungeon_room.voxel_scale
	wireframe_cube.grid_size = dungeon_room.size_in_voxels
	wireframe_cube.show_coordinates = false
	wireframe_cube.color = Color.WHITE if dungeon_room.was_preplaced else Color.BLACK
	
	# Show grid AABB with doors
	if not aabb_with_doors:
		aabb_with_doors = CSGBox3D.new()
		aabb_with_doors.material = preload("res://addons/SimpleDungeons/debug_visuals/WireframeColorMat.tres")
		add_child(aabb_with_doors)
	var rel_room_aabb = dungeon_room.xform_aabb(dungeon_room.get_grid_aabbi(true).to_AABB(), dungeon_room.get_xform_to(DungeonRoom3D.SPACE.DUNGEON_GRID, DungeonRoom3D.SPACE.LOCAL_SPACE)).abs()
	aabb_with_doors.size = rel_room_aabb.size if dungeon_room.show_grid_aabb_with_doors else Vector3()
	aabb_with_doors.position = rel_room_aabb.get_center()
	aabb_with_doors.visible = dungeon_room.show_grid_aabb_with_doors
	
	if not debug_alert or not is_instance_valid(debug_alert):
		debug_alert = preload("res://addons/SimpleDungeons/debug_visuals/DebugAlert.tscn").instantiate()
		add_child(debug_alert)
	
	debug_alert.scale = Vector3(dungeon_room.voxel_scale.y/10.0, dungeon_room.voxel_scale.y/10.0, dungeon_room.voxel_scale.y/10.0)
	debug_alert.position = ((Vector3(dungeon_room.size_in_voxels) / 2) + Vector3(0,0.35,0)) * Vector3(0, dungeon_room.voxel_scale.y, 0)
	
	var err_warning = {"error": "", "warning": ""} # Closure won't capture normal vars
	dungeon_room.validate_room(
		(func(str):
			err_warning["error"] = "Error: " + str),
		(func(str): err_warning["warning"] = "Warning: " + str))
	debug_alert.text = err_warning["error"] if err_warning["error"] else err_warning["warning"]
	if not debug_alert.text: debug_alert.position = Vector3() # Fix AABB visual in editor

func _ready():
	dungeon_room = get_parent()
	update_visual.call_deferred() # Call after parent _ready()
	set_process_input(false)

func _process(_delta):
	update_visual()
