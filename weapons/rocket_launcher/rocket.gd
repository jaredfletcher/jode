class_name Rocket
extends Node3D

## A projectile that sweeps forward each tick and explodes on contact.
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

## Damage at the centre of the blast. Knockback is derived from this on the
## receiving end, so this one number sets how hard the rocket both hurts and
## throws. TF2 rockets do 90.
@export var damage: float = 90.0

## Falloff distance for anyone who is not the shooter. TF2 uses 146.
@export var blast_radius_units: float = 146.0

## Falloff distance for the shooter. Shorter, so your own damage drops off
## faster than it does for everyone else.
@export var self_blast_radius_units: float = 121.0

## Seconds before an unobstructed rocket removes itself.
@export var lifetime: float = 6.0

## Set by the launcher. Excluded from the sweep so a rocket cannot hit its
## owner directly; self damage only ever arrives through the blast.
var shooter: Player = null

var direction := Vector3.FORWARD
var age := 0.0

## The mesh is decoupled from the body for the same reason the player's camera
## is. The simulation steps 0.42 metres at a time, and drawing at those steps
## reads as stuttering at any frame rate above the tick rate.
@onready var visual: Node3D = $MeshInstance3D

var prev_position := Vector3.ZERO
var curr_position := Vector3.ZERO


func _ready() -> void:
	visual.top_level = true


## Sets the whole spawn state in one call, after the rocket is in the tree.
##
## A method rather than field by field, because the interpolation samples have
## to be seeded from the real starting position. Seeded in _ready instead they
## capture wherever the node was before the launcher moved it, and the first
## frame draws as a streak from the origin.
func launch(from: Vector3, dir: Vector3, by: Player) -> void:
	global_position = from
	direction = dir
	shooter = by

	# Points along its own path rather than along the shooter's view, which are
	# not the same once the muzzle offset and the aim convergence are in.
	if not dir.is_zero_approx():
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		look_at(from + dir, up)

	prev_position = from
	curr_position = from
	visual.global_position = from
	visual.global_basis = global_basis


func _process(_delta: float) -> void:
	visual.global_position = prev_position.lerp(
		curr_position, Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return

	var step := direction * speed_units * U * delta
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + step)
	if shooter != null:
		query.exclude = [shooter.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position += step
	else:
		# Lifted a unit clear of the surface before detonating, which vanilla
		# does in CTFBaseRocket::Explode. It is also what makes the line of
		# sight test on the receiving end safe: a ray leaving a surface it sits
		# exactly on can go either way on a floating point comparison.
		global_position = hit.position + hit.normal * U

	prev_position = curr_position
	curr_position = global_position

	if not hit.is_empty():
		_explode(hit.collider as Node3D)


## Hands the explosion to everything in the blastable group and lets each decide
## what it means. Splitting it this way means anything that can be pushed only
## has to implement apply_blast, and the weapon never has to know what it hit.
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
