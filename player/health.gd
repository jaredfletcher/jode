class_name Health
extends Node

## A health pool for whatever it's attached to.
##
## Knows nothing about its owner. Something calls take_damage() and it reports
## the result through signals, so anything (a player, a crate, a door) can have
## health, and displays just subscribe to health_changed.

## Emitted whenever current or maximum changes.
signal health_changed(current: float, maximum: float)

## Emitted once, on reaching zero. inflictor is null when nothing caused it.
signal died(inflictor: Node3D)

## Emitted when going from zero back above it.
signal revived

@export var maximum: float = 100.0

var current: float = 0.0


func _ready() -> void:
	current = maximum


func is_alive() -> bool:
	return current > 0.0


## Negative amounts heal.
##
## Damage is applied by the peer that owns the damaged body, the same rule as
## movement: each machine is authoritative over itself and broadcasts the result.
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


## Refills without emitting revived. A respawn is a new life, not a revive.
func reset() -> void:
	current = maximum
	health_changed.emit(current, maximum)


## Sets the pool from a value received over the network. Doesn't go through
## take_damage(), since that would fire died on every peer that sees the update.
func apply_remote(value: float, max_value: float) -> void:
	maximum = max_value
	current = value
	health_changed.emit(current, maximum)
