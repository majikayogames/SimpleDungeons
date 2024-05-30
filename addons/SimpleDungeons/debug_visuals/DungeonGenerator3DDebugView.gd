@tool
extends Node3D

var dungeon_generator : DungeonGenerator3D = null
var wireframe_cube : Node3D = null
var debug_alert : Node3D = null

func update_visual():
	var show_editor = Engine.is_editor_hint() and dungeon_generator.show_debug_in_editor
	var show_game = not Engine.is_editor_hint() and dungeon_generator.show_debug_in_game
	if not show_editor and not show_game:
		if wireframe_cube and is_instance_valid(wireframe_cube):
			remove_child(wireframe_cube)
			wireframe_cube.queue_free()
			wireframe_cube = null
		if debug_alert and is_instance_valid(debug_alert):
			remove_child(debug_alert)
			debug_alert.queue_free()
			debug_alert = null
		return
	
	if not wireframe_cube or not is_instance_valid(wireframe_cube):
		wireframe_cube = preload("res://addons/SimpleDungeons/debug_visuals/WireframeCube.tscn").instantiate()
		wireframe_cube.enable_depth_test = true
		add_child(wireframe_cube)
	wireframe_cube.scale = Vector3(dungeon_generator.dungeon_size) * dungeon_generator.voxel_scale
	wireframe_cube.grid_size = dungeon_generator.dungeon_size
	
	if not debug_alert or not is_instance_valid(debug_alert):
		debug_alert = preload("res://addons/SimpleDungeons/debug_visuals/DebugAlert.tscn").instantiate()
		add_child(debug_alert)
	
	debug_alert.scale = Vector3(dungeon_generator.voxel_scale.y/5.0, dungeon_generator.voxel_scale.y/5.0, dungeon_generator.voxel_scale.y/5.0)
	debug_alert.position = ((Vector3(dungeon_generator.dungeon_size) / 2) + Vector3(0,0.35,0)) * Vector3(0, dungeon_generator.voxel_scale.y, 0)
	
	var err_warning = {"error": "", "warning": ""} # Closure won't capture normal vars
	dungeon_generator.validate_dungeon(
		(func(str):
			err_warning["error"] = "Error: " + str),
		(func(str): err_warning["warning"] = "Warning: " + str))
	debug_alert.text = err_warning["error"] if err_warning["error"] else err_warning["warning"]
	if not debug_alert.text: debug_alert.position = Vector3() # Fix AABB visual in editor

func _ready():
	dungeon_generator = get_parent()
	update_visual.call_deferred() # Call after parent _ready()
	set_process_input(false)

func _process(_delta):
	update_visual()
