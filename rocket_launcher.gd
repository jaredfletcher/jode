class_name RocketLauncher
extends Node3D

## A weapon, structured the way the eventual item system should work.
##
## The weapon does not reach into the player. It is handed a shooter, an aim
## basis, a muzzle position, and whether the attack button is down, and it
## decides what to do with them. That keeps it swappable, testable on its own,
## and means the player never has to know what kind of weapon it is holding.
##
## Aim comes from the command angles rather than the rendered camera, so firing
## is deterministic on the tick. Reading the camera would work today and break
## the moment prediction is added.


const U := Player.U

@export var rocket_scene: PackedScene

## Seconds between shots. TF2's rocket launcher fires roughly every 0.8s.
@export var fire_delay: float = 0.8

## Distance ahead of the eye to spawn the rocket, so it clears the player hull.
@export var muzzle_forward_units: float = 24.0

## Offset down and right from the eye, matching where a viewmodel would sit.
@export var muzzle_offset_units := Vector2(8.0, -6.0)

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


## Places the muzzle and launches a rocket from it.
##
## The muzzle sits most of two feet in front of the eye, which is far enough to
## be on the far side of a wall you are standing against. Source traces from
## the eye out to the muzzle and spawns at the first thing in the way, so a
## rocket fired into a wall explodes on your side of it instead of behind it.
func _fire(shooter: Player, aim: Basis, eye: Vector3) -> void:
	if rocket_scene == null:
		push_warning("RocketLauncher has no rocket_scene assigned.")
		return

	var forward := -aim.z
	var muzzle := eye \
		+ forward * muzzle_forward_units * U \
		+ aim.x * muzzle_offset_units.x * U \
		+ aim.y * muzzle_offset_units.y * U

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, muzzle)
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	var blocked := space.intersect_ray(query)
	if not blocked.is_empty():
		# Lifted off the surface along its normal, so the rocket's own sweep
		# starts outside the geometry rather than exactly on it, where a ray
		# can go either way on a floating point comparison.
		muzzle = blocked.position + blocked.normal * 0.01

	var rocket := rocket_scene.instantiate() as Rocket

	# Added to the scene root rather than to the weapon, so a rocket keeps
	# flying if the shooter dies, respawns, or switches weapons.
	get_tree().current_scene.add_child(rocket)

	rocket.launch(muzzle, forward, aim, shooter)
