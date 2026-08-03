extends Node3D

## Owns the player instances.
##
## Players are created at runtime instead of sitting in the scene file, because
## a session needs one per peer and the scene does not know how many that will
## be. Adding them as children of a single container is also what a
## MultiplayerSpawner watches later, so the shape here does not change when
## networking arrives.


const PLAYER_SCENE := preload("res://player.tscn")

## Where the single local player starts, matching where the Player node used to
## sit in this scene.
const SPAWN := Vector3(0.0, 2.0, 0.0)


@onready var players: Node3D = %Players

# Direct paths rather than exports, so there is nothing to wire in the editor.
# Rename either node and this breaks loudly, which is the intent.
@onready var hud: Hud = $CanvasLayer
@onready var pause_menu: PauseMenu = $PauseMenu


## Children are ready before their parent, so both UI nodes have finished their
## own setup by the time they are handed a player.
func _ready() -> void:
	var local := spawn_player(1, SPAWN)
	hud.setup(local)
	pause_menu.setup(local)


## Creates the player owned by [param peer_id].
##
## The node is named after the peer id because names replicate and authority
## assignments do not, so every copy can derive the owner from the name alone.
## Player._ready reads it and claims authority.
func spawn_player(peer_id: int, at: Vector3) -> Player:
	var p := PLAYER_SCENE.instantiate() as Player

	p.name = str(peer_id)

	# Both of these must happen before add_child, since add_child is what runs
	# _ready, and _ready reads the name for authority and the position for the
	# respawn point. Setting the local position works because Players sits at
	# the origin; give that node a transform and this stops being true.
	p.position = at

	players.add_child(p)
	return p
