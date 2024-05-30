@tool
extends Node3D

@export var grid_size := Vector3i(1,1,1)
@export var show_coordinates := true
@export var color := Color.BLACK
@export var enable_depth_test := false

var last_grid_size = null
var last_voxel_scale = null
var last_show_coordinates = null
var last_enable_depth = null

func update_grid():
	for child in %Levels.get_children():
		%Levels.remove_child(child)
		child.queue_free()
	
	%Front.mesh.material.shader = preload("res://addons/SimpleDungeons/debug_visuals/WireframeCubeDepthEnabled.gdshader") if enable_depth_test else preload("res://addons/SimpleDungeons/debug_visuals/WireframeCube.gdshader")
	%Right.mesh.material.shader = preload("res://addons/SimpleDungeons/debug_visuals/WireframeCubeDepthEnabled.gdshader") if enable_depth_test else preload("res://addons/SimpleDungeons/debug_visuals/WireframeCube.gdshader")
	%Top.mesh.material.shader = preload("res://addons/SimpleDungeons/debug_visuals/WireframeCubeDepthEnabled.gdshader") if enable_depth_test else preload("res://addons/SimpleDungeons/debug_visuals/WireframeCube.gdshader")
	
	%Front.mesh.material.set_shader_parameter("grid_size", Vector2(grid_size.x, grid_size.y))
	%Right.mesh.material.set_shader_parameter("grid_size", Vector2(grid_size.z, grid_size.y))
	%Top.mesh.material.set_shader_parameter("grid_size", Vector2(grid_size.x, grid_size.z))

	%Front.mesh.material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	%Right.mesh.material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	%Top.mesh.material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	
	if grid_size.x < 1 or grid_size.y < 1 or grid_size.z < 1:
		return
	if grid_size.x <= 1 and grid_size.y <= 1 and grid_size.z <= 1:
		return
	
	for y in range(1, grid_size.y):
		var level = %Top.duplicate()
		%Levels.add_child(level)
		level.position.y -= float(y) / grid_size.y - 0.00001
	var b = grid_size - Vector3i(1,1,1)
	var positions = [Vector3i(0,0,0), Vector3i(grid_size.x-1,0,0), Vector3i(0,grid_size.y-1,0), Vector3i(0,0,grid_size.z-1),
					 b, b - Vector3i(grid_size.x-1,0,0), b - Vector3i(0,grid_size.y-1,0), b - Vector3i(0,0,grid_size.z-1)]
	
	if not show_coordinates:
		return
	
	var make_scale_uniform_node = Node3D.new()
	%Levels.add_child(make_scale_uniform_node)
	make_scale_uniform_node.scale = self.transform.basis.inverse().get_scale()
	for grid_pos in positions:
		var label = Label3D.new()
		label.text = str(grid_pos)
		make_scale_uniform_node.add_child(label)
		label.position = ((Vector3(grid_pos) + Vector3(0.5, 0.5, 0.5)) / Vector3(grid_size)) * self.scale - self.scale/2
		label.scale *= (Vector3(1,1,1) / Vector3(grid_size)) * self.scale
		label.scale.x = min(label.scale.x, label.scale.y, label.scale.z)
		label.scale.y = min(label.scale.x, label.scale.y, label.scale.z)
		label.scale.z = min(label.scale.x, label.scale.y, label.scale.z)

func _ready():
	update_grid()
	set_process_input(false)

func _process(delta):
	if last_grid_size != grid_size or last_show_coordinates != show_coordinates or last_enable_depth != enable_depth_test:
		update_grid()
		last_grid_size = grid_size
		last_show_coordinates = show_coordinates
		last_enable_depth = enable_depth_test
