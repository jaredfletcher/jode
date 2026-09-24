class_name Blast
extends RefCounted

## One explosion, as described by whatever caused it.
##
## Only carries what the weapon knows. How hard a body gets pushed depends on its
## stance and ground contact, so each receiver works that out in apply_blast().

## Where it went off, already lifted clear of the surface it hit.
var origin := Vector3.ZERO

## Who fired it. Used to tell self blasts apart and to measure shot distance.
var inflictor: Node3D = null

## Damage at the centre. Knockback is derived from this.
var damage := 90.0

## Falloff radius for everyone except the shooter.
var radius_units := 146.0

## Falloff radius for the shooter. Smaller, so self damage drops off sooner.
var self_radius_units := 121.0

## What the projectile hit directly, or null if it hit the world. A direct hit
## takes full centre damage.
var direct_hit: Node3D = null
