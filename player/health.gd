class_name Health
extends Node

## A pool of health belonging to whatever this node is a child of.
##
## A component rather than fields on Player, so a crate, a door or a dropped bag
## can have health without inheriting anything from the player. It knows nothing
## about its owner: something calls [method take_damage], and it reports what
## happened through signals.
##
## Everything that displays health subscribes to those signals rather than
## reading the value. That matters more here than usual, because the plan is for
## the readout to stop being a HUD label and become an object in the world, and
## a subscriber can be swapped without this file changing.


## Current and maximum, whenever either moves. Carries both so a listener never
## has to reach back for the other one to draw a bar.
signal health_changed(current: float, maximum: float)

## Fired once, on the transition to zero. [param inflictor] is whoever caused
## it, or null when nothing did.
signal died(inflictor: Node3D)

## Fired on the transition back from zero.
signal revived


@export var maximum: float = 100.0

var current: float = 0.0


func _ready() -> void:
	current = maximum


func is_alive() -> bool:
	return current > 0.0


## Applies damage. Negative amounts heal, which is why healing is not a separate
## method: a bandage and a rocket differ in sign, not in kind.
##
## Damage is applied by the peer that owns the body being damaged, so nobody has
## to agree about hit registration. It follows the same rule as movement, where
## each machine is the authority on itself and simply tells everyone the result.
func take_damage(amount: float, inflictor: Node3D = null) -> void:
	if amount == 0.0:
		return

	var was_alive := is_alive()
	current = clampf(current - amount, 0.0, maximum)
	health_changed.emit(current, maximum)

	if was_alive and not is_alive():
		died.emit(inflictor)
	elif not was_alive and is_alive():
		revived.emit()


## Refills the pool without reporting a revival, for a respawn rather than a
## rescue. The body being restored is a new life, not the old one continuing.
func reset() -> void:
	current = maximum
	health_changed.emit(current, maximum)


## Overwrites the pool from a value that arrived over the network.
##
## Deliberately not routed through [method take_damage]. A received value is
## already the result of somebody else's arithmetic, and re-deriving a delta
## from it would emit a death on whoever happened to see the packet that crossed
## zero, which is not the same thing as dying.
func apply_remote(value: float, max_value: float) -> void:
	maximum = max_value
	current = value
	health_changed.emit(current, maximum)
