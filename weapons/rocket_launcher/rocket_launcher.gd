class_name RocketLauncher
extends Node3D

## Rocket launcher.
##
## The player calls update() every tick with everything firing needs. The weapon
## never reads Input or looks up the player on its own, so the player doesn't
## need to know what kind of weapon it's holding. Aim comes from the command
## angles, not the camera, so firing stays deterministic on the tick.

const U := Player.U

@export var rocket_scene: PackedScene
## Seconds between shots. TF2's rocket launcher is about 0.8.
@export var fire_delay: float = 0.8
## Muzzle offset from the eye in units, as right, up, forward. TF2 uses 12, -3, 23.5.
@export var muzzle_offset_units := Vector3(12.0, -3.0, 23.5)
## Muzzle offset while crouched, where the weapon sits higher relative to the eye.
@export var muzzle_offset_crouched_units := Vector3(12.0, 8.0, 23.5)
## How far to trace for whatever the crosshair is on.
@export var aim_range_units: float = 2000.0
## Closer than this, don't converge onto the crosshair target. Stops a wall right
## next to you from pulling the rocket into it.
@export var aim_converge_min_units: float = 200.0

var cooldown := 0.0


## Called once per tick by the player. Returns true on the tick a shot fires
## (hook for recoil, sound and viewmodel animation later).
func update(delta: float, shooter: Player, aim: Basis, eye: Vector3, firing: bool) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	if not firing or cooldown > 0.0:
		return false

	cooldown = fire_delay
	_fire(shooter, aim, eye)
	return true


## Works out where the rocket starts (the muzzle) and which way it goes (toward
## the crosshair), then launches it.
func _fire(shooter: Player, aim: Basis, eye: Vector3) -> void:
	if rocket_scene == null:
		push_warning("RocketLauncher has no rocket_scene assigned.")
		return

	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())

	var forward := -aim.z

	# Aim at what the crosshair is on rather than straight ahead. The rocket
	# leaves from the muzzle, so firing it parallel to the view would miss by the
	# width of the offset.
	var far := eye + forward * aim_range_units * U
	var target := far
	var ahead := _trace(eye, far, exclude)
	if not ahead.is_empty() and eye.distance_to(ahead.position) > aim_converge_min_units * U:
		target = ahead.position

	var offset := muzzle_offset_units
	if shooter != null and shooter.is_crouched:
		offset = muzzle_offset_crouched_units

	var muzzle := eye + aim.x * offset.x * U + aim.y * offset.y * U + forward * offset.z * U

	# The muzzle is almost two feet in front of the eye, which can be through a
	# wall you're standing against. Like Source, trace out to it and start at the
	# first thing in the way, lifted off along the normal.
	var blocked := _trace(eye, muzzle, exclude)
	if not blocked.is_empty():
		muzzle = blocked.position + blocked.normal * U

	var direction := muzzle.direction_to(target)
	if direction.length_squared() < 0.001:
		direction = forward

	# Added to the scene root so the rocket keeps flying if the shooter dies or
	# switches weapons.
	var rocket := rocket_scene.instantiate() as Rocket
	get_tree().current_scene.add_child(rocket)
	rocket.launch(muzzle, direction, shooter)


func _trace(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
