class_name Player
extends CharacterBody3D

const U := 0.0254

enum Move { GROUND, AIR, SLIDE, SURF }

const IN_JUMP := 1
const IN_CROUCH := 2
const IN_SPRINT := 4
const IN_NOCLIP := 8

class Cmd:
	var wish := Vector2.ZERO
	var buttons := 0
	var yaw := 0.0
	var pitch := 0.0
	var tick := 0

	func pressed(bit: int) -> bool:
		return buttons & bit != 0

const SLIDE_BUFFER := 0.15
const SLIDE_GRACE := 0.45

const SLIDE_EXIT_SPEED := 120.0 * U
const SLIDE_FRICTION := 0.6
const SLIDE_TIME := 1.4
const SLIDE_COOLDOWN := 0.35
const SLIDE_HEIGHT := 40.0 * U
const SLIDE_EYE := 32.0 * U
const SLIDE_POSE_RATE := 8.0

const SURF_MIN_SPEED := 150.0 * U
const SURF_RATE_SPEED := 320.0 * U
const SURF_ACCELERATE := 100.0

const SV_GRAVITY := 800.0 * U
const SV_STOPSPEED := 100.0 * U
const SV_FRICTION := 4.0
const SV_ACCELERATE := 10.0
const SV_AIRACCELERATE := 10.0
const JUMP_IMPULSE := 268.33 * U

const SV_SPRINTSPEED := 320.0 * U
const SV_WALKSPEED := 190.0 * U

const STAND_HEIGHT := 83.0 * U
const CROUCH_HEIGHT := 62.0 * U
const STAND_EYE := 68.0 * U
const CROUCH_EYE := STAND_EYE - HULL_DELTA

const TIME_TO_DUCK := 0.4
const TIME_TO_UNDUCK := 0.2

const VIEW_SMOOTH := 3.0

const HULL_DELTA := STAND_HEIGHT - CROUCH_HEIGHT
const HULL_SHIFT := HULL_DELTA

const JUMP_WINDOW := 0.51

const M_YAW := 0.022

const NOCLIP_SPEED := 500.0 * U
const NOCLIP_FAST := 3.0

@export var noclip_toggle: bool = false
@export var sensitivity: float = 3.0
@export var auto_bhop: bool = true
@export var auto_sprint: bool = true
@export var crouch_toggle: bool = false
@export var slide_steer_cap_units: float = 100.0
@export var slide_speed_cap_units: float = 0.0
@export var slide_entry_speed_units: float = 200.0
@export var slide_boost_units: float = 60.0
@export var slide_steer: float = 1.2
@export var air_speed_cap_units: float = 100.0
@export var surf_speed_cap_units: float = 100.0

@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var capsule: CylinderShape3D = collider.shape
@onready var stand_check: ShapeCast3D = %StandCheck

var mouse_delta := Vector2.ZERO
var cmd := Cmd.new()
var prev_buttons := 0
var view_yaw := 0.0
var view_pitch := 0.0

var noclip := false

var spawn_point := Vector3.ZERO

var slide_buffer := 0.0
var move_state := Move.AIR
var slide_time := 0.0
var slide_cooldown := 0.0
var crouch_prev := false
var slide_pose := 0.0
var crouch_eye_out := 0.0

var duck_latch:= true
var duck_target := 0.0
var jump_time := 0.0
var last_pending := 0.0
var duck_progress := 0.0
var view_offset := 0.0

var is_crouched := false
var crouch_wanted := false
var crouch_shifted := false

var eye_height := 0.0
var prev_eye := Vector3.ZERO
var curr_eye := Vector3.ZERO

func _ready() -> void:
	wall_min_slide_angle = 0.0
	floor_max_angle = deg_to_rad(45.57)
	camera.top_level = true
	eye_height = STAND_EYE
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye
	spawn_point = global_position
	stand_check.add_exception(self)
	var box := stand_check.shape as BoxShape3D
	var w := (capsule.radius - 0.02) * 2.0
	box.size = Vector3(w, 1.0, w)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _sample_input() -> void:
	prev_buttons = cmd.buttons
	cmd.wish = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	cmd.buttons = 0
	if Input.is_action_pressed("jump"):
		cmd.buttons |= IN_JUMP
	if Input.is_action_pressed("crouch"):
		cmd.buttons |= IN_CROUCH
	if Input.is_action_pressed("sprint"):
		cmd.buttons |= IN_SPRINT
	if Input.is_action_pressed("noclip"):
		cmd.buttons |= IN_NOCLIP
	
	cmd.yaw = view_yaw
	cmd.pitch = view_pitch
	rotation.y = view_yaw
	cmd.tick += 1


func _just_pressed(bit: int) -> bool:
	return (cmd.buttons & bit) != 0 and (prev_buttons & bit) == 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative


func respawn() -> void:
	mouse_delta = Vector2.ZERO
	cmd.yaw = 0.0
	cmd.pitch = 0.0
	view_yaw = 0.0
	view_pitch = 0.0
	velocity = Vector3.ZERO
	rotation.y = 0.0
	move_state = Move.AIR
	duck_progress = 0.0
	duck_target = 0.0
	slide_pose = 0.0
	view_offset = 0.0
	last_pending = 0.0
	slide_time = 0.0
	slide_cooldown = 0.0
	slide_buffer = 0.0
	jump_time = 0.0
	crouch_shifted = false
	_finish_unduck()
	global_position = spawn_point
	eye_height = STAND_EYE
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye


func _set_noclip(on: bool) -> void:
	if on == noclip:
		return
	noclip = on
	collider.disabled = on
	if on:
		velocity = Vector3.ZERO
	else:
		move_state = Move.AIR


func _move_noclip(delta: float) -> void:
	var dir := camera.global_basis * Vector3(cmd.wish.x, 0.0, cmd.wish.y)
	if cmd.pressed(IN_JUMP):
		dir.y += 1.0
	if cmd.pressed(IN_CROUCH):
		dir.y -= 1.0

	var speed := NOCLIP_SPEED
	if cmd.pressed(IN_SPRINT):
		speed *= NOCLIP_FAST

	velocity = dir.normalized() * speed if dir.length_squared() > 0.0 else Vector3.ZERO
	global_position += velocity * delta


func _apply_friction(delta: float) -> void:
	var speed := velocity.length()
	if speed < 0.01:
		return

	var control := maxf(speed, SV_STOPSPEED)
	var drop := control * SV_FRICTION * delta
	var new_speed := maxf(speed - drop, 0.0)

	velocity *= new_speed / speed


func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return

	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	velocity += wish_dir * accel_speed


func _air_accelerate(wish_dir: Vector3, wish_speed: float, speed_cap: float, accel: float, delta: float) -> void:
	var capped_speed := minf(wish_speed, speed_cap)
	
	var current_speed := velocity.dot(wish_dir)
	var add_speed := capped_speed - current_speed
	if add_speed <= 0.0:
		return

	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	velocity += wish_dir * accel_speed


func _set_check(height: float, center_y: float) -> void:
	(stand_check.shape as BoxShape3D).size.y = height
	stand_check.position.y = center_y


func _hull_height() -> float:
	var base_h := CROUCH_HEIGHT if is_crouched else STAND_HEIGHT
	return lerpf(base_h, SLIDE_HEIGHT, slide_pose)


func _fits(height: float) -> bool:
	var top := _hull_height()
	if height <= top:
		return true
	_set_check(height - top, (height + top) * 0.5)
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


func _can_stand() -> bool:
	if crouch_shifted:
		_set_check(STAND_HEIGHT, STAND_HEIGHT * 0.5 - HULL_SHIFT)
		stand_check.force_shapecast_update()
		return not stand_check.is_colliding()
	return _fits(STAND_HEIGHT)


func _finish_duck() -> void:
	is_crouched = true
	capsule.height = CROUCH_HEIGHT
	collider.position.y = CROUCH_HEIGHT * 0.5
	if not is_on_floor():
		global_position.y += HULL_SHIFT
		crouch_shifted = true


func _finish_unduck() -> void:
	is_crouched = false
	capsule.height = STAND_HEIGHT
	collider.position.y = STAND_HEIGHT * 0.5
	if crouch_shifted:
		global_position.y -= HULL_SHIFT
	crouch_shifted = false


func _pending_shift(target: float) -> float:
	if target >= 1.0 and not is_crouched:
		return 0.0 if is_on_floor() else HULL_SHIFT
	if target <= 0.0 and is_crouched:
		return -HULL_SHIFT if crouch_shifted else 0.0
	return 0.0


func _spline(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _update_crouch(delta: float) -> void:
	if crouch_toggle:
		if _just_pressed(IN_CROUCH):
			crouch_wanted = not crouch_wanted
	else:
		crouch_wanted = cmd.pressed(IN_CROUCH)

	var edge := crouch_wanted and not crouch_prev
	crouch_prev = crouch_wanted
	if edge:
		slide_buffer = SLIDE_BUFFER

	if crouch_wanted and not is_crouched and jump_time > 0.0 and not is_on_floor() and move_state != Move.SURF:
		var eye_before := eye_height
		duck_progress = 1.0
		_finish_duck()
		last_pending = 0.0
		view_offset = eye_before - CROUCH_EYE - HULL_SHIFT
		crouch_eye_out = CROUCH_EYE
		return

	var desired := 1.0
	if not crouch_wanted and (not is_crouched or _can_stand()):
		desired = 0.0

	var latched := duck_latch and duck_progress > 0.0 and duck_progress < 1.0 and duck_target <= 0.0
	if not latched:
		duck_target = desired
	var target := duck_target

	var rate := (1.0 / TIME_TO_DUCK) if target > duck_progress else (1.0 / TIME_TO_UNDUCK)
	duck_progress = move_toward(duck_progress, target, rate * delta)

	view_offset = move_toward(view_offset, 0.0, VIEW_SMOOTH * delta)

	var finished := false
	if not is_crouched and duck_progress >= 1.0:
		_finish_duck()
		finished = true
	elif is_crouched and duck_progress <= 0.0:
		_finish_unduck()
		finished = true

	var pending := _pending_shift(target)
	var blend := 1.0 - absf(target - duck_progress)
	if not finished and pending != last_pending:
		view_offset += (last_pending - pending) * blend
	last_pending = pending

	crouch_eye_out = lerpf(STAND_EYE, CROUCH_EYE, _spline(duck_progress)) + pending * blend


func _can_slide(flat_speed: float, from_air: bool) -> bool:
	if flat_speed < slide_entry_speed_units * U or slide_cooldown > 0.0:
		return false
	return crouch_wanted if from_air else slide_buffer > 0.0


func _update_pose(delta: float) -> void:
	var target := 1.0 if move_state == Move.SLIDE else 0.0
	if target < slide_pose and not _headroom_clear():
		target = slide_pose
	slide_pose = move_toward(slide_pose, target, SLIDE_POSE_RATE * delta)

	var base_h := CROUCH_HEIGHT if is_crouched else STAND_HEIGHT
	var h := lerpf(base_h, SLIDE_HEIGHT, slide_pose)
	capsule.height = h
	collider.position.y = h * 0.5

	eye_height = lerpf(crouch_eye_out, SLIDE_EYE, slide_pose) + view_offset


func _headroom_clear() -> bool:
	return _fits(CROUCH_HEIGHT)


func _update_state(delta: float) -> void:
	slide_buffer = maxf(slide_buffer - delta, 0.0)
	slide_cooldown = maxf(slide_cooldown - delta, 0.0)
	var grounded := is_on_floor()
	var flat_speed := Vector2(velocity.x, velocity.z).length()

	match move_state:
		Move.SLIDE:
			slide_time -= delta
			if not grounded:
				_exit_slide()
				move_state = Move.AIR
			elif slide_time <= 0.0 or flat_speed < SLIDE_EXIT_SPEED or not crouch_wanted:
				_exit_slide()
				move_state = Move.GROUND
		Move.GROUND:
			if not grounded:
				move_state = Move.AIR
			elif _can_slide(flat_speed, false):
				_enter_slide()
		Move.AIR:
			if grounded:
				if _can_slide(flat_speed, true):
					_enter_slide()
				else:
					move_state = Move.GROUND
			elif _on_surf_ramp():
				move_state = Move.SURF
		Move.SURF:
			if grounded:
				if _can_slide(flat_speed, true):
					_enter_slide()
				else:
					move_state = Move.GROUND
			elif not _on_surf_ramp():
				move_state = Move.AIR


func _enter_slide() -> void:
	move_state = Move.SLIDE
	slide_time = SLIDE_TIME
	slide_buffer = 0.0
	velocity.y = minf(velocity.y, 0.0)

	if not is_crouched:
		view_offset += crouch_eye_out - CROUCH_EYE
		crouch_eye_out = CROUCH_EYE
		duck_progress = 1.0
		_finish_duck()
		last_pending = 0.0

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var spd := flat.length()
	if spd > 0.01:
		var boosted := spd + slide_boost_units * U
		if slide_speed_cap_units > 0.0:
			boosted = minf(boosted, maxf(spd, slide_speed_cap_units * U))
		velocity.x = flat.x / spd * boosted
		velocity.z = flat.z / spd * boosted


func _exit_slide() -> void:
	slide_cooldown = SLIDE_COOLDOWN


func _move_slide(wish_dir: Vector3, delta: float) -> void:
	velocity.y = 0.0

	if SLIDE_TIME - slide_time > SLIDE_GRACE:
		var speed := velocity.length()
		if speed > 0.01:
			var control := maxf(speed, SV_STOPSPEED)
			var drop := control * SLIDE_FRICTION * delta
			velocity *= maxf(speed - drop, 0.0) / speed

	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.01 and wish_dir.length_squared() > 0.0:
		_air_accelerate(wish_dir, SV_SPRINTSPEED, slide_steer_cap_units * U, SV_AIRACCELERATE, delta)
		var after := Vector2(velocity.x, velocity.z).length()
		if after > 0.01:
			velocity.x *= spd / after
			velocity.z *= spd / after


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return true if auto_sprint else cmd.pressed(IN_SPRINT)


func _current_max_speed() -> float:
	var base := SV_SPRINTSPEED if _is_sprinting() else SV_WALKSPEED
	return base / 3.0 if is_crouched else base


func _clip_walls() -> void:
	var floor_cos := cos(floor_max_angle)
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > floor_cos or n.y < -0.1:
			continue
		var into := velocity.dot(n)
		if into < 0.0:
			velocity -= n * into


func _on_surf_ramp() -> bool:
	var floor_cos := cos(floor_max_angle)
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > 0.01 and n.y < floor_cos:
			return true
	return false


func _process(_delta: float) -> void:
	var amount := M_YAW * sensitivity
	view_yaw = wrapf(view_yaw - deg_to_rad(mouse_delta.x * amount), -PI, PI)
	view_pitch = clampf(view_pitch - deg_to_rad(mouse_delta.y * amount), deg_to_rad(-89.0), deg_to_rad(89.0))
	mouse_delta = Vector2.ZERO

	var f := Engine.get_physics_interpolation_fraction()
	camera.global_position = prev_eye.lerp(curr_eye, f)
	camera.global_rotation = Vector3(view_pitch, view_yaw, 0.0)


func _physics_process(delta: float) -> void:
	_sample_input()

	var np := cmd.pressed(IN_NOCLIP)
	if noclip_toggle:
		if _just_pressed(IN_NOCLIP):
			_set_noclip(not noclip)
	else:
		_set_noclip(np)

	if noclip:
		_move_noclip(delta)
		prev_eye = curr_eye
		curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
		return

	velocity.y -= SV_GRAVITY * 0.5 * delta
	jump_time = maxf(jump_time - delta, 0.0)
	if is_on_floor():
		crouch_shifted = false
	_update_crouch(delta)
	_update_state(delta)
	_update_pose(delta)

	var max_speed := _current_max_speed()
	var wish_dir := (transform.basis * Vector3(cmd.wish.x, 0.0, cmd.wish.y)).normalized()
	var jump_held := cmd.pressed(IN_JUMP) if auto_bhop else _just_pressed(IN_JUMP)

	if (move_state == Move.GROUND or move_state == Move.SLIDE) and jump_held:
		jump_time = JUMP_WINDOW
		velocity.y = JUMP_IMPULSE
		if move_state == Move.SLIDE:
			_exit_slide()
		move_state = Move.AIR

	match move_state:
		Move.GROUND:
			velocity.y = 0.0
			_apply_friction(delta)
			_accelerate(wish_dir, max_speed, SV_ACCELERATE, delta)
		Move.SLIDE:
			_move_slide(wish_dir, delta)
		Move.AIR:
			_air_accelerate(wish_dir, max_speed, air_speed_cap_units * U, SV_AIRACCELERATE, delta)
		Move.SURF:
			var flat := Vector2(velocity.x, velocity.z).length()
			if flat >= SURF_MIN_SPEED:
				var t := clampf((flat - SURF_MIN_SPEED) / (SURF_MIN_SPEED * 2.0), 0.0, 1.0)
				_air_accelerate(wish_dir, SURF_RATE_SPEED, surf_speed_cap_units * U * t, SURF_ACCELERATE, delta)

	floor_block_on_wall = (move_state == Move.GROUND or move_state == Move.SLIDE)
	move_and_slide()
	_clip_walls()

	velocity.y -= SV_GRAVITY * 0.5 * delta
	prev_eye = curr_eye
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
