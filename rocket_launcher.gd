class_name RocketLauncher
extends Node3D

## A weapon, structured the way the eventual item system should work.
##
## The weapon does not reach into the player. It is handed an aim basis, a
## muzzle position, and whether the attack button is down, and it decides what
## to do with them. That keeps it swappable, testable on its own, and means the
## player never has to know what kind of weapon it is holding.
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
func update(delta: float, aim: Basis, eye: Vector3, firing: bool) -> bool:
	cooldown = maxf(cooldown - delta, 0.0)
	if not firing or cooldown > 0.0:
		return false

	cooldown = fire_delay
	_fire(aim, eye)
	return true


func _fire(aim: Basis, eye: Vector3) -> void:
	if rocket_scene == null:
		push_warning("RocketLauncher has no rocket_scene assigned.")
		return

	var forward := -aim.z
	var muzzle := eye \
		+ forward * muzzle_forward_units * U \
		+ aim.x * muzzle_offset_units.x * U \
		+ aim.y * muzzle_offset_units.y * U

	var rocket := rocket_scene.instantiate() as Rocket
	rocket.direction = forward
	rocket.shooter = owner as Player

	# Added to the scene root rather than to the weapon, so a rocket keeps
	# flying if the shooter dies, respawns, or switches weapons.
	get_tree().current_scene.add_child(rocket)
	rocket.global_position = muzzle
	rocket.global_basis = aim
