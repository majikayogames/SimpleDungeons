extends Node3D

@export var orbit_speed : float = 0.3
@export var zoom_speed : float = 5.0
@export var min_zoom : float = 2.0
@export var max_zoom : float = 400.0
@export var auto_rotate_speed : float = -0.44 # Speed of auto rotation
@export var auto_rotate : bool = false # Toggle auto-rotation

var distance : float = 100.0

@onready var camera : Camera3D = $Camera3D

var is_dragging : bool = false
var last_mouse_pos : Vector2 = Vector2()
var rotation_y : float = 0.0
var rotation_x : float = 0.0

func _ready() -> void:
	# Set initial camera position
	update_camera_position()

func _process(delta : float) -> void:
	if auto_rotate:
		if OS.has_feature("movie"):
			rotation_y += auto_rotate_speed * (1.0/ProjectSettings.get_setting("editor/movie_writer/fps"))
		else:
			rotation_y += auto_rotate_speed * delta
		update_camera_position()

func _unhandled_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				last_mouse_pos = event.position
			else:
				is_dragging = false
	
	if event is InputEventMouseMotion and is_dragging:
		var delta : Vector2 = event.position - last_mouse_pos
		last_mouse_pos = event.position
		
		rotation_y += delta.x * orbit_speed * 0.01
		rotation_x += delta.y * orbit_speed * 0.01
		rotation_x = clamp(rotation_x, -PI / 2.2, PI / 2.2)

		update_camera_position()
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance += zoom_speed

		distance = clamp(distance, min_zoom, max_zoom)
		update_camera_position()

func update_camera_position() -> void:
	var new_pos : Vector3 = Vector3(
		distance * cos(rotation_y) * cos(rotation_x),
		distance * sin(rotation_x),
		distance * sin(rotation_y) * cos(rotation_x)
	)

	camera.position = new_pos
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
