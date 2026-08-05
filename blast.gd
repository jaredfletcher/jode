class_name Blast
extends RefCounted

## One explosion, as described by the thing that caused it.
##
## A struct rather than six positional arguments, because the list is going to
## grow. Grenades, self-damage toggles and damage types all belong here, and
## each one would otherwise be another parameter threaded through every
## blastable in the game.
##
## Carries only what the weapon knows. How hard a particular body gets thrown
## is that body's business, since it depends on stance and ground contact that
## the weapon has no view of. Splitting it this way is also what keeps the
## per-weapon numbers here and the universal physics on the player, which is
## the same line the item definitions will be cut along.


## Where the explosion happened, already lifted clear of whatever surface it
## went off against.
var origin := Vector3.ZERO

## Who fired it. Used to tell a self blast from someone else's, and to measure
## the range the shot was taken from.
var inflictor: Node3D = null

## Damage at the centre. Everything else, knockback included, is derived from
## this rather than tuned separately.
var damage := 90.0

## Falloff distance for anyone who is not the shooter.
var radius_units := 146.0

## Falloff distance for the shooter, which rings out sooner.
var self_radius_units := 121.0

## Whatever the projectile struck head on, or null if it hit the world. A body
## hit directly takes centre damage regardless of where its origin sits.
var direct_hit: Node3D = null
