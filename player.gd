class_name Player
extends CharacterBody3D

const U := 0.0254

enum Move { GROUND, AIR, SLIDE }

const SLIDE_BUFFER := 0.15
const SLIDE_GRACE := 0.45

const SLIDE_EXIT_SPEED := 120.0 * U
const SLIDE_FRICTION := 0.6
const SLIDE_TIME := 1.4
const SLIDE_COOLDOWN := 0.35
const SLIDE_STEER := 1.2
const SLIDE_HEIGHT := 40.0 * U
const SLIDE_EYE := 32.0 * U
const SLIDE_POSE_RATE := 8.0

const SV_GRAVITY := 800.0 * U
const SV_STOPSPEED := 100.0 * U
const SV_FRICTION := 4.0
const SV_ACCELERATE := 10.0
const SV_AIRACCELERATE := 10.0
const SV_AIRSPEEDCAP := 30.0 * U
const JUMP_IMPULSE := 268.33 * U

const SV_SPRINTSPEED := 320.0 * U
const SV_WALKSPEED := 190.0 * U
const SV_DUCKSPEED := 63.0 * U

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

@export var sensitivity: float = 6.0
@export var auto_bhop: bool = true
@export var auto_sprint: bool = true
@export var crouch_toggle: bool = false
@export var duck_latch: bool = true
@export var slide_speed_cap_units: float = 0.0
@export var slide_entry_speed_units: float = 200.0
@export var slide_boost_units: float = 60.0

@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var capsule: CapsuleShape3D = collider.shape
@onready var stand_check: ShapeCast3D = %StandCheck

var spawn_point := Vector3.ZERO

var slide_buffer := 0.0
var move_state := Move.AIR
var slide_time := 0.0
var slide_cooldown := 0.0
var crouch_prev := false
var slide_pose := 0.0
var crouch_eye_out := 0.0

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
var pitch := 0.0

func _ready() -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var amount := M_YAW * sensitivity
		rotation.y -= deg_to_rad(event.relative.x * amount)
		pitch = clampf(pitch - deg_to_rad(event.relative.y * amount), deg_to_rad(-89.0), deg_to_rad(89.0))


func respawn() -> void:
	velocity = Vector3.ZERO
	rotation.y = 0.0
	pitch = 0.0
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


func _air_accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var capped_speed := minf(wish_speed, SV_AIRSPEEDCAP)

	var current_speed := velocity.dot(wish_dir)
	var add_speed := capped_speed - current_speed
	if add_speed <= 0.0:
		return

	var accel_speed := minf(accel * wish_speed * delta, add_speed)
	velocity += wish_dir * accel_speed


func _set_check(height: float, center_y: float) -> void:
	(stand_check.shape as BoxShape3D).size.y = height
	stand_check.position.y = center_y


func _can_stand() -> bool:
	if crouch_shifted:
		_set_check(STAND_HEIGHT, STAND_HEIGHT * 0.5 - HULL_SHIFT)
	else:
		_set_check(HULL_DELTA, (STAND_HEIGHT + CROUCH_HEIGHT) * 0.5)
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


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
		if Input.is_action_just_pressed("crouch"):
			crouch_wanted = not crouch_wanted
	else:
		crouch_wanted = Input.is_action_pressed("crouch")

	var edge := crouch_wanted and not crouch_prev
	crouch_prev = crouch_wanted
	if edge:
		slide_buffer = SLIDE_BUFFER

	if crouch_wanted and not is_crouched and jump_time > 0.0 and not is_on_floor():
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
	_set_check(CROUCH_HEIGHT - SLIDE_HEIGHT, (CROUCH_HEIGHT + SLIDE_HEIGHT) * 0.5)
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


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


func _enter_slide() -> void:
	move_state = Move.SLIDE
	slide_time = SLIDE_TIME
	slide_buffer = 0.0

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


func _move_slide(delta: float) -> void:
	velocity.y = 0.0

	if SLIDE_TIME - slide_time > SLIDE_GRACE:
		var speed := velocity.length()
		if speed > 0.01:
			var control := maxf(speed, SV_STOPSPEED)
			var drop := control * SLIDE_FRICTION * delta
			velocity *= maxf(speed - drop, 0.0) / speed

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var spd := flat.length()
	var look := -global_basis.z
	look.y = 0.0

	if spd > 0.01 and look.length_squared() > 0.0:
		look = look.normalized()
		var dir := flat / spd
		var align := dir.dot(look)
		if align > 0.0:
			var steered := (dir + look * SLIDE_STEER * align * delta).normalized()
			velocity.x = steered.x * spd
			velocity.z = steered.z * spd


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return true if auto_sprint else Input.is_action_pressed("sprint")


func _current_max_speed() -> float:
	var base := SV_SPRINTSPEED if _is_sprinting() else SV_WALKSPEED
	return base / 3.0 if is_crouched else base


func _process(_delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	camera.global_position = prev_eye.lerp(curr_eye, f)
	camera.global_rotation = Vector3(pitch, rotation.y, 0.0)


func _physics_process(delta: float) -> void:
	velocity.y -= SV_GRAVITY * 0.5 * delta
	jump_time = maxf(jump_time - delta, 0.0)
	if is_on_floor():
		crouch_shifted = false
	_update_crouch(delta)
	_update_state(delta)
	_update_pose(delta)

	var max_speed := _current_max_speed()
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var jump_held := Input.is_action_pressed("jump") if auto_bhop else Input.is_action_just_pressed("jump")

	if move_state != Move.AIR and jump_held:
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
			_move_slide(delta)
		Move.AIR:
			_air_accelerate(wish_dir, max_speed, SV_AIRACCELERATE, delta)

	move_and_slide()
	velocity.y -= SV_GRAVITY * 0.5 * delta
	prev_eye = curr_eye
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
