class_name Rocket
extends Node3D

## A projectile that sweeps forward each tick and applies a radial impulse on
## contact.
##
## Movement is a raycast rather than an Area3D because at 1100 units per second
## the rocket covers about 0.42 metres per tick, which is enough to tunnel
## through thin geometry before an overlap test would notice.
##
## Everything here runs on the physics tick and reads no global input, so a
## rocket fired from the same tick with the same aim lands in the same place.
## That is what lets it be predicted and replayed later.


const U := Player.U

## Muzzle velocity. TF2 rockets travel at 1100.
@export var speed_units: float = 1100.0

## Impulse applied at the centre of the blast, falling off to zero at the edge.
@export var blast_force_units: float = 500.0

## TF2 rockets use a 146 unit blast radius.
@export var blast_radius_units: float = 146.0

## Seconds before an unobstructed rocket removes itself.
@export var lifetime: float = 6.0

## Set by the launcher. Excluded from the sweep so a rocket cannot hit its
## owner directly; self damage only ever arrives through the blast.
var shooter: Player = null

var direction := Vector3.FORWARD
var age := 0.0


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return

	var step := direction * speed_units * U * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return

	global_position = hit.position
	_explode()


## Impulses everything in the blastable group. Splitting this from the player
## means anything that can be pushed only has to implement apply_blast.
func _explode() -> void:
	for node in get_tree().get_nodes_in_group("blastable"):
		if node.has_method("apply_blast"):
			node.apply_blast(global_position, blast_force_units, blast_radius_units)
	queue_free()
