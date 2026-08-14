class_name RocketLauncher
extends Node3D

## A weapon, structured the way the item system should work.
##
## The weapon is handed its shooter rather than resolving one, and reads from it
## only what firing depends on. It never registers itself with the player, never
## assumes where it sits in the tree, and never touches Input, so the player
## does not have to know what kind of weapon it is holding.
##
## Aim comes from the command angles rather than the rendered camera, so firing
## is deterministic on the tick. Reading the camera would work today and break
## the moment prediction is added.


const U := Player.U

@export var rocket_scene: PackedScene

## Seconds between shots. TF2's rocket launcher fires roughly every 0.8s.
@export var fire_delay: float = 0.8

## Muzzle offset from the eye in Source units, as right, up and forward. TF2
## uses 12 right, 3 down, 23.5 forward.
@export var muzzle_offset_units := Vector3(12.0, -3.0, 23.5)

## The same offset while crouched, where the weapon sits higher relative to a
## lowered eye.
@export var muzzle_offset_crouched_units := Vector3(12.0, 8.0, 23.5)

## How far ahead to look for whatever the crosshair is actually resting on.
@export var aim_range_units: float = 2000.0

## Below this range the rocket is not converged onto what is ahead. Peeking a
## corner puts a wall a few units from your eye, and aiming at it would fire
## the rocket straight into it instead of past it.
@export var aim_converge_min_units: float = 200.0

var cooldown := 0.0


## Called once per tick by the player. Returns true on the frame a shot fires,
## which is the hook for recoil, sound, and viewmodel animation later.
func update(delta: float, shooter: Player, aim: Basis, eye: Vector3, firing: bool) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	if not firing or cooldown > 0.0:
		return false

	cooldown = fire_delay
	_fire(shooter, aim, eye)
	return true


## Places the muzzle, works out where the rocket should actually be pointed, and
## launches it.
##
## Two corrections happen here and they are worth keeping apart: one decides
## where the rocket starts, the other which way it goes.
func _fire(shooter: Player, aim: Basis, eye: Vector3) -> void:
	if rocket_scene == null:
		push_warning("RocketLauncher has no rocket_scene assigned.")
		return

	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())

	var forward := -aim.z

	# Where the crosshair lands. The rocket leaves the muzzle rather than the
	# eye, so fired straight forward it runs parallel to the view and lands
	# beside what was aimed at by the width of the offset. Aiming it at the hit
	# point makes the two converge, which is why TF2 rockets go where the
	# crosshair is.
	var far := eye + forward * aim_range_units * U
	var target := far
	var ahead := _trace(eye, far, exclude)
	if not ahead.is_empty() \
			and eye.distance_to(ahead.position) > aim_converge_min_units * U:
		target = ahead.position

	var offset := muzzle_offset_units
	if shooter != null and shooter.is_crouched:
		offset = muzzle_offset_crouched_units

	var muzzle := eye \
		+ aim.x * offset.x * U \
		+ aim.y * offset.y * U \
		+ forward * offset.z * U

	# The muzzle sits most of two feet in front of the eye, far enough to be on
	# the far side of a wall you are standing against. Source traces out to it
	# and starts at the first thing in the way, so a rocket fired into a wall
	# explodes on your side of it.
	var blocked := _trace(eye, muzzle, exclude)
	if not blocked.is_empty():
		# Lifted off the surface along its normal, so the rocket's own sweep
		# starts outside the geometry rather than exactly on it.
		muzzle = blocked.position + blocked.normal * U

	var direction := muzzle.direction_to(target)
	if direction.length_squared() < 0.001:
		direction = forward

	var rocket := rocket_scene.instantiate() as Rocket

	# Added to the scene root rather than to the weapon, so a rocket keeps
	# flying if the shooter dies, respawns, or switches weapons.
	get_tree().current_scene.add_child(rocket)

	rocket.launch(muzzle, direction, shooter)


func _trace(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
