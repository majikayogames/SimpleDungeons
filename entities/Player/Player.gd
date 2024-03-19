class_name Player
extends CharacterBody3D

const RECORDING_FPS = 60

const CROUCH_SPEED = 3.5
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.8
const SENSITIVITY = 0.004

#bob variables
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

#fov variables
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 9.8

var initial_head_pos : Vector3
var CROUCH_TRANSLATE := Vector3(0,-0.7,0)
var crouch_lerp = 0

# multiplayer & vars for display purposes
var last_position: Vector3 = position
var camera = null
var camera_offset = Vector3(0,0,0)
var last_move_time = -INF

const MOVE_WAS_TELEPORT_THRESHOLD = 3.0

@export var is_crouched = false

@export var coyote_time_frames_grace = 5

@export var target_pos: Vector3
@export var target_dir: float = deg_to_rad(180)
@export var is_sprinting = false
@export var sync_velocity: Vector3

@onready var head = %CameraPos

@onready var Game = get_tree().root.get_child(0)

var noclip := false

var PlayerUI : Control = null

func findByClass(node: Node, className : String, result : Array) -> void:
	if node.is_class(className):
		result.push_back(node)
	for child in node.get_children():
		findByClass(child, className, result)

func _enter_tree():
	if is_multiplayer_authority():
		camera = Camera3D.new()
		%CameraPos.add_child(camera)
		
		# Make player invisible for our own camera
		var visual_instance_objs : Array[VisualInstance3D] = []
		findByClass(self, "VisualInstance3D", visual_instance_objs)
		# set all VisualInstance3d layers in this object to only 2
		for obj in visual_instance_objs:
			obj.set_layer_mask_value(1, false)
			obj.set_layer_mask_value(2, true)
		camera.set_cull_mask_value(2, false)
		# set camera layers to all except 2
		camera.set_cull_mask_value(2, false)
		
func _ready():
	initial_head_pos = %Head.position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
func got_data(data):
	position = data[0]
	rotation = data[1]
	last_rot = rotation
	
var last_rot = Vector3(0,0,0)

func _input(event):
	if event is InputEventMouseMotion and is_multiplayer_authority() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENSITIVITY)
		%CameraPos.rotate_x(-event.relative.y * SENSITIVITY)
		%CameraPos.rotation.x = clamp(%CameraPos.rotation.x, deg_to_rad(-90), deg_to_rad(90))

var _portal_tracking_us = null
func _on_portal_tracking_enter(portal):
	_portal_tracking_us = portal
func _on_portal_tracking_leave(_portal):
	_portal_tracking_us = null
func _check_if_teleport_was_teleport_to_other_portal(to_position):
	if not _portal_tracking_us:
		return false
	var position_rel_to_cur_portal = _portal_tracking_us.global_transform.affine_inverse() * global_position
	
	var to_position_offset = to_position - self.position
	var after_teleport_global_pos = self.global_position + to_position_offset
	
	var position_rel_to_other_portal = _portal_tracking_us.other_portal.global_transform.affine_inverse() * after_teleport_global_pos
	
	if (position_rel_to_cur_portal - position_rel_to_other_portal).length() < 1.0:
		return true
	else:
		return false
func _move_self_to_other_portal():
	var rel_to_cur_portal = _portal_tracking_us.global_transform.affine_inverse() * global_transform
	self.global_transform = _portal_tracking_us.other_portal.global_transform * rel_to_cur_portal

var noclip_speed_mult := 3.0
func _handle_noclip(delta):
	if Input.is_action_just_pressed("_noclip") and OS.has_feature("debug"):
		noclip = !noclip
		noclip_speed_mult = 3.0
	if Input.is_action_just_released("_MWU"):
		noclip_speed_mult = min(100.0, noclip_speed_mult * 1.1)
	elif Input.is_action_just_released("_MWD"):
		noclip_speed_mult = max(0.1, noclip_speed_mult * 0.9)
	if noclip:
		self.velocity = Vector3.ZERO
		$CollisionShape3D.disabled = true
		self.set_axis_lock(0xFFFFFF, true)
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	else:
		$CollisionShape3D.disabled = false
		self.set_axis_lock(0xFFFFFF, false)
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		return
	
	if Input.is_action_pressed("crouch"):
		self.position.y -= delta * get_speed()
	elif Input.is_action_pressed("jump"):
		self.position.y += delta * get_speed()
	
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var speed = get_speed() * noclip_speed_mult
	if Input.is_action_pressed("sprint"):
		speed *= 3.0
	if input_dir.length():
		var cam_new_pos = %CameraPos.global_transform * (Vector3(input_dir.x, 0, input_dir.y).normalized() * delta * speed)
		global_position += cam_new_pos - %CameraPos.global_position

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = sin(time * BOB_FREQ / 2) * BOB_AMP
	#to fix this need to teleport with camera child in portal for CharacterBody3D
	return pos

var _smoothed_velocity_for_headbob : float = 0
func _juice_camera(delta):
	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	
	# Trend headbob towards the camera's original position to prevent glitchiness
	# Best to not have camera at an offset when standing still.
	# Looks odd when rotating the camera if it's offset
	var diff = clampf(velocity.length() - _smoothed_velocity_for_headbob, -15.0 * delta, 15.0 * delta)
	_smoothed_velocity_for_headbob = clampf(_smoothed_velocity_for_headbob + diff, 0.0, WALK_SPEED)
	
	%Headbob.transform.origin = lerp(Vector3.ZERO, _headbob(t_bob), _smoothed_velocity_for_headbob / WALK_SPEED)
	
	# FOV
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	#camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

var _was_on_floor_last_frame = false
var _snapped_to_stairs_last_frame = false
func _snap_down_to_stairs_check():
	var did_snap = false
	if not is_on_floor() and velocity.y <= 0 and (_was_on_floor_last_frame or _snapped_to_stairs_last_frame) and $StairsBelowRayCast3D.is_colliding():
		var body_test_result = PhysicsTestMotionResult3D.new()
		var params = PhysicsTestMotionParameters3D.new()
		var max_step_down = -0.5
		params.from = self.global_transform
		params.motion = Vector3(0,max_step_down,0)
		if PhysicsServer3D.body_test_motion(self.get_rid(), params, body_test_result):
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true

	_was_on_floor_last_frame = is_on_floor()
	_snapped_to_stairs_last_frame = did_snap

@onready var _initial_separation_ray_dist_from_center = ($StepUpSeparationRay_F.position * Vector3(1.0,0,1.0)).length()
var last_xz_vel : Vector3 = Vector3(0,0,0)
func _rotate_step_up_separation_ray():
	var xz_vel = velocity * Vector3(1,0,1)
	if xz_vel.length() < 0.1:
		xz_vel = last_xz_vel
	else:
		last_xz_vel = xz_vel
	var xz_ray_pos : Vector3 = xz_vel.normalized() * _initial_separation_ray_dist_from_center
	$StepUpSeparationRay_F.global_position.x = self.global_position.x + xz_ray_pos.x
	$StepUpSeparationRay_F.global_position.z = self.global_position.z + xz_ray_pos.z
	
	var xz_l_ray_pos = xz_ray_pos.rotated(Vector3(0,1.0,0), deg_to_rad(-50))
	$StepUpSeparationRay_L.global_position.x = self.global_position.x + xz_l_ray_pos.x
	$StepUpSeparationRay_L.global_position.z = self.global_position.z + xz_l_ray_pos.z
	
	var xz_r_ray_pos = xz_ray_pos.rotated(Vector3(0,1.0,0), deg_to_rad(50))
	$StepUpSeparationRay_R.global_position.x = self.global_position.x + xz_r_ray_pos.x
	$StepUpSeparationRay_R.global_position.z = self.global_position.z + xz_r_ray_pos.z
	
	# To prevent character from running up walls, we do a check for how steep
	# the slope in contact with our separation rays is
	$StepUpSeparationRay_F/RayCast3D.force_raycast_update()
	$StepUpSeparationRay_L/RayCast3D.force_raycast_update()
	$StepUpSeparationRay_R/RayCast3D.force_raycast_update()
	var max_slope_ang_dot = Vector3(0,1,0).rotated(Vector3(1.0,0,0), self.floor_max_angle).dot(Vector3(0,1,0))
	var any_too_steep = false
	if $StepUpSeparationRay_F/RayCast3D.is_colliding() and $StepUpSeparationRay_F/RayCast3D.get_collision_normal().dot(Vector3(0,1,0)) < max_slope_ang_dot:
		any_too_steep = true
	if $StepUpSeparationRay_L/RayCast3D.is_colliding() and $StepUpSeparationRay_L/RayCast3D.get_collision_normal().dot(Vector3(0,1,0)) < max_slope_ang_dot:
		any_too_steep = true
	if $StepUpSeparationRay_R/RayCast3D.is_colliding() and $StepUpSeparationRay_R/RayCast3D.get_collision_normal().dot(Vector3(0,1,0)) < max_slope_ang_dot:
		any_too_steep = true
	
	# Added blocked by wall check with ray to fix a glitch where you would jitter when running into
	# a wall next to a slope/stair. For some reason the Raycast3D hit from inside didn't work for this.
	$WallRayCast3D.target_position = $StepUpSeparationRay_F.position * Vector3(1,0,1)
	$WallRayCast3D.force_raycast_update()
	var f_blocked_by_wall = $WallRayCast3D.is_colliding()
	$WallRayCast3D.target_position = $StepUpSeparationRay_L.position * Vector3(1,0,1)
	$WallRayCast3D.force_raycast_update()
	var l_blocked_by_wall = $WallRayCast3D.is_colliding()
	$WallRayCast3D.target_position = $StepUpSeparationRay_R.position * Vector3(1,0,1)
	$WallRayCast3D.force_raycast_update()
	var r_blocked_by_wall = $WallRayCast3D.is_colliding()
	
	var should_disable = xz_vel.length() == 0 or any_too_steep
	$StepUpSeparationRay_F.disabled = should_disable or f_blocked_by_wall or (is_on_floor_only() and not $StepUpSeparationRay_F/RayCast3D.is_colliding())
	$StepUpSeparationRay_L.disabled = should_disable or l_blocked_by_wall or (is_on_floor_only() and not $StepUpSeparationRay_L/RayCast3D.is_colliding())
	$StepUpSeparationRay_R.disabled = should_disable or r_blocked_by_wall or (is_on_floor_only() and not $StepUpSeparationRay_R/RayCast3D.is_colliding())
	# It's necessary to disable the separation rays when on floor and not colliding
	# otherwise getting weird behavior for is_on_floor, it flickers between true and false
	# I made it is_on_floor_only since is_on_floor was causing other glitch when running into wall
	
	# There are still some slight glitches in edge cases but this one seems pretty stable
	
	#debug
	#$StepUpSeparationRay_F/MeshInstance3D.set_layer_mask_value(1, !should_disable)
	#$StepUpSeparationRay_L/MeshInstance3D.set_layer_mask_value(1, !should_disable)
	#$StepUpSeparationRay_R/MeshInstance3D.set_layer_mask_value(1, !should_disable)
	
func get_speed():
	if is_crouched:
		return CROUCH_SPEED
	elif is_sprinting:
		return SPRINT_SPEED
	else:
		return WALK_SPEED

var _cur_phys_frame = 0
var _last_frame_was_on_floor = -coyote_time_frames_grace - 1
var frame = 1
var last_time_ms = 0
func get_real_time_ms():
	var ms_per_frame_recording = 1000/60
	return frame * ms_per_frame_recording
	#return Time.get_ticks_msec()
#func _physics_process(delta): # Hack to smooth out recording
func _process(delta):
	delta = (get_real_time_ms() - last_time_ms) / 1000.0
	last_time_ms = get_real_time_ms()
	frame += 1
	# Smooth camera for recording
	var camera_child = %CameraPos.get_child(0)
	camera_child.top_level = true
	# Interpolate global position including Y position
	var target_position = %CameraPos.global_position
	var current_position = camera_child.global_position
	# Smooth Y position
	var smoothed_y = lerp(current_position.y, target_position.y, delta * 12.0)
	camera_child.global_position = Vector3(current_position.x, smoothed_y, current_position.z)
	camera_child.global_position.x = target_position.x
	camera_child.global_position.z = target_position.z
	# Rotation interpolation - Convert global orientations to Quaternions for slerp
	var target_global_rotation_quat = Quaternion(%CameraPos.global_transform.basis.orthonormalized())
	var child_global_rotation_quat = Quaternion(camera_child.global_transform.basis.orthonormalized())
	var interpolated_rotation : Quaternion = child_global_rotation_quat.slerp(target_global_rotation_quat, delta * 6.0)
	camera_child.global_rotation = interpolated_rotation.get_euler()
	
	if is_multiplayer_authority():
		# Add the gravity.
		if not is_on_floor():
			velocity.y -= gravity * delta
			
		# Handle Jump.
		_cur_phys_frame = _cur_phys_frame + 1
		if is_on_floor():
			_last_frame_was_on_floor = _cur_phys_frame
		if (Input.is_action_just_pressed("jump")
			and (is_on_floor() or _snapped_to_stairs_last_frame
			or _cur_phys_frame - _last_frame_was_on_floor < coyote_time_frames_grace)):
			velocity.y = JUMP_VELOCITY
			
		# Handle Sprint.
		if Input.is_action_pressed("sprint"):
			is_sprinting = true
		else:
			is_sprinting = false
		
		if Input.is_action_pressed("crouch"):
			is_crouched = true
			is_sprinting = false
			crouch_lerp = clampf(crouch_lerp + 7.5 * delta, 0, 1)
		else:
			is_crouched = false
			crouch_lerp = clampf(crouch_lerp - 7.5 * delta, 0, 1)
		%Head.position = initial_head_pos + lerp(Vector3.ZERO, CROUCH_TRANSLATE, crouch_lerp)
		
	var did_move = false
		
	if is_multiplayer_authority():
		# Get the input direction and handle the movement/deceleration.
		var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if input_dir.length():
			did_move = true
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if is_on_floor():
			if direction:
				velocity.x = direction.x * get_speed()
				velocity.z = direction.z * get_speed()
			else:
				velocity.x = lerp(velocity.x, direction.x * get_speed(), delta * 7.0)
				velocity.z = lerp(velocity.z, direction.z * get_speed(), delta * 7.0)
		else:
			velocity.x = lerp(velocity.x, direction.x * get_speed(), delta * 3.0)
			velocity.z = lerp(velocity.z, direction.z * get_speed(), delta * 3.0)
			
		_handle_noclip(delta)
	else:
		if (target_pos - position).length() >= MOVE_WAS_TELEPORT_THRESHOLD and _check_if_teleport_was_teleport_to_other_portal(target_pos):
			# Continue moving player smoothly at expected speed as they go through portal
			# Without this, the teleport code in the Portal will cause a teleport to trigger and
			# force move the player to the latest position
			_move_self_to_other_portal()
		# stairs handling
		if sync_velocity.y == 0 and position.y != target_pos.y:
			position.y = target_pos.y
		var move_vec = target_pos - position
		rotation.y = target_dir
		
		if move_vec.length() < MOVE_WAS_TELEPORT_THRESHOLD:
			if move_vec.length() > 0:
				var move_this_frame = move_vec.normalized() * delta * sync_velocity.length()
				if move_this_frame.length() >= move_vec.length() or move_this_frame.length() == 0:
					position = target_pos
				else:
					position += move_this_frame
				last_move_time = Time.get_ticks_msec()
		else:
			position = target_pos
	
	if is_multiplayer_authority():
		_rotate_step_up_separation_ray()
		move_and_slide()
		_snap_down_to_stairs_check()
		_juice_camera(delta)
		target_pos = position
		target_dir = rotation.y
		sync_velocity = velocity
		last_rot = rotation
