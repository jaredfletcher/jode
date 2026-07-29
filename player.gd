class_name Player
extends CharacterBody3D

const U := 0.0254

const SV_GRAVITY := 600.0 * U
const SV_STOPSPEED := 100.0 * U
const SV_FRICTION := 4.0
const SV_ACCELERATE := 10.0
const SV_AIRACCELERATE := 10.0
const SV_AIRSPEEDCAP := 30.0 * U
const JUMP_IMPULSE := 160.0 * U

const SV_SPRINTSPEED := 320.0 * U
const SV_WALKSPEED := 190.0 * U
const SV_DUCKSPEED := 63.0 * U

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 0.9
const STAND_EYE := 1.6
const CROUCH_EYE := 0.7

const TIME_TO_DUCK := 0.4
const TIME_TO_UNDUCK := 0.2

const VIEW_SMOOTH := 3.0

const HULL_DELTA := STAND_HEIGHT - CROUCH_HEIGHT
const HULL_SHIFT := HULL_DELTA * 0.5

const M_YAW := 0.022

@export var sensitivity: float = 6.0
@export var auto_bhop: bool = true
@export var auto_sprint: bool = true
@export var crouch_toggle: bool = false

@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var capsule: CapsuleShape3D = collider.shape
@onready var stand_check: ShapeCast3D = %StandCheck

var duck_progress := 0.0
var view_offset := 0.0

var is_crouched := false
var crouch_wanted := false
var crouch_shifted := false

func _ready() -> void:
	stand_check.add_exception(self)
	(stand_check.shape as CapsuleShape3D).radius = capsule.radius - 0.02
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var amount := M_YAW * sensitivity
		rotation.y -= deg_to_rad(event.relative.x * amount)
		camera.rotation.x -= deg_to_rad(event.relative.y * amount)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


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


func _can_stand() -> bool:
	var shape := stand_check.shape as CapsuleShape3D
	if crouch_shifted:
		shape.height = STAND_HEIGHT
		stand_check.position.y = STAND_HEIGHT * 0.5 - HULL_SHIFT
	else:
		shape.height = HULL_DELTA
		stand_check.position.y = (STAND_HEIGHT + CROUCH_HEIGHT) * 0.5
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


func _finish_duck() -> void:
	is_crouched = true
	capsule.height = CROUCH_HEIGHT
	collider.position.y = CROUCH_HEIGHT * 0.5
	if not is_on_floor():
		global_position.y += HULL_SHIFT
		view_offset -= HULL_SHIFT
		crouch_shifted = true


func _finish_unduck() -> void:
	is_crouched = false
	capsule.height = STAND_HEIGHT
	collider.position.y = STAND_HEIGHT * 0.5
	if crouch_shifted:
		global_position.y -= HULL_SHIFT
		view_offset += HULL_SHIFT
	crouch_shifted = false


func _update_crouch(delta: float) -> void:
	if crouch_toggle:
		if Input.is_action_just_pressed("crouch"):
			crouch_wanted = not crouch_wanted
	else:
		crouch_wanted = Input.is_action_pressed("crouch")

	var target := 1.0
	if not crouch_wanted and (not is_crouched or _can_stand()):
		target = 0.0

	var rate := (1.0 / TIME_TO_DUCK) if target > duck_progress else (1.0 / TIME_TO_UNDUCK)
	duck_progress = move_toward(duck_progress, target, rate * delta)

	view_offset = move_toward(view_offset, 0.0, VIEW_SMOOTH * delta)

	if not is_crouched and duck_progress >= 1.0:
		_finish_duck()
	elif is_crouched and duck_progress <= 0.0:
		_finish_unduck()

	camera.position.y = lerpf(STAND_EYE, CROUCH_EYE, duck_progress) + view_offset


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return true if auto_sprint else Input.is_action_pressed("sprint")


func _current_max_speed() -> float:
	if is_crouched:
		return SV_DUCKSPEED
	return SV_SPRINTSPEED if _is_sprinting() else SV_WALKSPEED


func _physics_process(delta: float) -> void:
	if is_on_floor():
		crouch_shifted = false
	_update_crouch(delta)
	var max_speed := _current_max_speed()
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var jump_held := Input.is_action_pressed("jump") if auto_bhop else Input.is_action_just_pressed("jump")

	var grounded := is_on_floor()

	if grounded and jump_held:
		velocity.y = JUMP_IMPULSE
		grounded = false

	if grounded:
		velocity.y = 0.0
		_apply_friction(delta)
		_accelerate(wish_dir, max_speed, SV_ACCELERATE, delta)
	else:
		velocity.y -= SV_GRAVITY * delta
		_air_accelerate(wish_dir, max_speed, SV_AIRACCELERATE, delta)

	move_and_slide()
