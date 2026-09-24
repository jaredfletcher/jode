class_name Rocket
extends Node3D

## A projectile that sweeps forward each tick and explodes on contact.
##
## Moves by raycast instead of an Area3D. At 1100 u/s it covers about 0.42 m per
## tick, enough to tunnel through thin geometry before an overlap test notices.
## Runs entirely on the physics tick with no global input, so the same shot
## always lands in the same place.

const U := Player.U

## Muzzle velocity. TF2 rockets travel at 1100.
@export var speed_units: float = 1100.0
## Damage at the centre of the blast. Also sets knockback, since that's derived
## from damage on the receiving end. TF2 rockets do 90.
@export var damage: float = 90.0
## Falloff radius for everyone except the shooter. TF2 uses 146.
@export var blast_radius_units: float = 146.0
## Falloff radius for the shooter. Smaller, so self damage drops off sooner.
@export var self_blast_radius_units: float = 121.0
## Seconds before a rocket that hits nothing removes itself.
@export var lifetime: float = 6.0

## Set by the launcher. Excluded from the sweep so a rocket can't hit its owner
## directly; self damage only comes through the blast.
var shooter: Player = null
var direction := Vector3.FORWARD
var age := 0.0

## The mesh is interpolated between tick positions, same as the player camera.
var prev_position := Vector3.ZERO
var curr_position := Vector3.ZERO

@onready var visual: Node3D = $MeshInstance3D


func _ready() -> void:
	visual.top_level = true


func _process(_delta: float) -> void:
	visual.global_position = prev_position.lerp(
			curr_position, Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return

	var step := direction * speed_units * U * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position += step
	else:
		# Detonate a unit off the surface, like CTFBaseRocket::Explode. Keeps the
		# receiving end's line of sight check from starting inside the surface.
		global_position = hit.position + hit.normal * U

	prev_position = curr_position
	curr_position = global_position

	if not hit.is_empty():
		_explode(hit.collider as Node3D)


## Sets up the rocket once it's in the tree. The interpolation samples have to be
## seeded from the real start position, or the first frame draws a streak from
## wherever the node was before.
func launch(from: Vector3, dir: Vector3, by: Player) -> void:
	global_position = from
	direction = dir
	shooter = by

	# Face along the flight path, which differs from the view direction once the
	# muzzle offset and aim convergence are applied.
	if not dir.is_zero_approx():
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		look_at(from + dir, up)

	prev_position = from
	curr_position = from
	visual.global_position = from
	visual.global_basis = global_basis


## Hands the blast to everything in the "blastable" group and lets each one
## decide what it means.
func _explode(struck: Node3D) -> void:
	var blast := Blast.new()
	blast.origin = global_position
	blast.inflictor = shooter
	blast.damage = damage
	blast.radius_units = blast_radius_units
	blast.self_radius_units = self_blast_radius_units
	blast.direct_hit = struck

	for node in get_tree().get_nodes_in_group("blastable"):
		if node.has_method("apply_blast"):
			node.apply_blast(blast)

	queue_free()
