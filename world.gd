extends Node3D

## Owns the player instances and the session they belong to.
##
## Players are created at runtime rather than sitting in the scene file,
## because a session needs one per peer and the scene cannot know how many that
## will be.
##
## Spawning is plain RPCs rather than a MultiplayerSpawner. The replication
## that matters in this project is going to be hand written anyway, and doing
## the spawn by hand keeps the roster, the ownership rule and the teardown
## visible in one file instead of split between a script and a node's inspector
## settings.


const PLAYER_SCENE := preload("res://player.tscn")

## Where players enter the world. One point for now; a list of them with
## round-robin selection is the obvious next version.
const SPAWN := Vector3(0.0, 2.0, 0.0)

## Clients, not counting the host.
const MAX_PEERS := 7

## Seconds to wait for a join before giving up. ENet does time out on its own
## eventually, but not quickly and not always, and a status line that says
## "connecting" indefinitely tells you nothing about which of the two it is.
const JOIN_TIMEOUT := 8.0

## How often to check on a hostname lookup, and how long to let one run.
const RESOLVE_POLL := 0.05
const RESOLVE_TIMEOUT := 5.0


## Bumped whenever a join starts or finishes, so a timeout that fires late can
## tell whether it still belongs to the attempt in progress.
var join_attempt := 0

## An outstanding hostname lookup, or -1 when there is none.
var resolve_id := IP.RESOLVER_INVALID_ID
var resolve_host := ""
var resolve_port := 0
var resolve_attempt := 0
var resolve_deadline := 0

@onready var players: Node3D = %Players

# Direct paths rather than exports, so there is nothing to wire in the editor.
# Rename either node and this breaks loudly, which is the intent.
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


## Children are ready before their parent, so the menu has already resolved its
## own nodes by the time these connect to its signals.
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	pause_menu.host_requested.connect(_host)
	pause_menu.join_requested.connect(_join)
	pause_menu.leave_requested.connect(_leave)

	_go_solo()
	_report("Not connected.")


# =============================================================== session ===


## Tears down whatever session exists and rebuilds the world around a single
## local player.
##
## Also the startup path, so launching the game and leaving a session end in
## exactly the same state rather than in two states that merely look alike.
##
## Says nothing about why it was called. Callers know that, and one of them
## defers this, so a status set here would land after the reason and erase it.
func _go_solo() -> void:
	join_attempt += 1
	_cancel_resolve()
	multiplayer.multiplayer_peer = null
	_clear_players()
	_attach_local(spawn_player(1, SPAWN))
	pause_menu.refresh_pause()


func _leave() -> void:
	_go_solo()
	_report("Not connected.")


func _host(port: int) -> void:
	if multiplayer.has_multiplayer_peer():
		_report("Already in a session. Disconnect first.")
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		_report("Could not open port %d. Error %d." % [port, err])
		return

	# The solo player is already named 1, which is the id a server takes, so
	# hosting does not have to respawn or rename anything.
	multiplayer.multiplayer_peer = peer
	pause_menu.refresh_pause()
	_report("Hosting on port %d. This machine is %s on the local network."
		% [port, _local_addresses()])


func _join(address: String, port: int) -> void:
	if multiplayer.has_multiplayer_peer():
		_report("Already in a session. Disconnect first.")
		return

	if address.is_empty():
		_report("Enter an address to join.")
		return

	_cancel_resolve()
	join_attempt += 1
	var attempt := join_attempt

	if address.is_valid_ip_address():
		_connect_to(address, address, port, attempt)
		return

	# ENet accepts a domain name and resolves it itself, but it does that on
	# the calling thread, so a name that nothing answers for freezes the game
	# until DNS gives up. Doing it here keeps the frame moving, separates a
	# name that cannot be found from a host that did not reply, and lets the
	# status line show which address the name landed on.
	#
	# That last part is the useful one when a domain points at a home
	# connection. A record that has gone stale looks exactly like a closed
	# port otherwise.
	_report("Looking up %s." % address)
	resolve_host = address
	resolve_port = port
	resolve_attempt = attempt
	resolve_deadline = Time.get_ticks_msec() + int(RESOLVE_TIMEOUT * 1000.0)
	resolve_id = IP.resolve_hostname_queue_item(address, IP.TYPE_IPV4)

	if resolve_id == IP.RESOLVER_INVALID_ID:
		_cancel_resolve()
		_report("Could not start a lookup for %s." % address)
		return

	_poll_resolve()


## Checks on an outstanding lookup, and re-arms itself until it finishes.
##
## Driven by a scene tree timer rather than by _process, which is not a style
## choice. This node's process mode is inherited, and the menu stops the tree
## whenever it is open in a solo game, so _process does not run at the exact
## moment a join is started from that menu. A SceneTreeTimer keeps running
## while the tree is stopped, which is the property needed here.
func _poll_resolve() -> void:
	if resolve_id == IP.RESOLVER_INVALID_ID:
		return

	var host := resolve_host
	var port := resolve_port
	var attempt := resolve_attempt
	var status := IP.get_resolve_item_status(resolve_id)

	if status == IP.RESOLVER_STATUS_WAITING:
		if Time.get_ticks_msec() < resolve_deadline:
			get_tree().create_timer(RESOLVE_POLL).timeout.connect(_poll_resolve)
			return

		_cancel_resolve()
		_report("Nothing came back for %s. Check your DNS is reachable." % host)
		return

	var ip := ""
	if status == IP.RESOLVER_STATUS_DONE:
		ip = IP.get_resolve_item_address(resolve_id)

	_cancel_resolve()

	if ip.is_empty():
		_report(("Could not find %s. Check the spelling, and that it has an A "
			+ "record pointing at the host.") % host)
		return

	_connect_to(host, ip, port, attempt)


## Drops any outstanding lookup. The resolver holds onto finished items until
## they are erased, so this is not only bookkeeping.
func _cancel_resolve() -> void:
	if resolve_id != IP.RESOLVER_INVALID_ID:
		IP.erase_resolve_item(resolve_id)
	resolve_id = IP.RESOLVER_INVALID_ID
	resolve_host = ""


## Opens the connection once there is an address to open it to.
##
## Takes the name and the address separately so the status line can show both.
## Seeing what a domain actually resolved to is the first thing worth checking
## when it points at a connection whose address may have moved.
func _connect_to(host: String, ip: String, port: int, attempt: int) -> void:
	# The attempt may have been abandoned while the lookup was running.
	if attempt != join_attempt:
		return

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_report("Could not reach %s:%d. Error %d." % [host, port, err])
		return

	var shown := host if host == ip else "%s (%s)" % [host, ip]

	multiplayer.multiplayer_peer = peer
	pause_menu.refresh_pause()
	_report("Connecting to %s:%d." % [shown, port])

	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(
		func() -> void: _abandon_join(attempt, shown, port))


## Gives up on a join that never landed.
##
## Matched against the attempt counter rather than cancelled, because a
## SceneTreeTimer cannot be stopped once started. A timer left over from an
## attempt that already resolved simply finds a number it does not recognise.
func _abandon_join(attempt: int, address: String, port: int) -> void:
	if attempt != join_attempt:
		return

	_go_solo()
	_report(("No answer from %s:%d. Check that the host is running, that UDP "
		+ "%d reaches it, and that this is not your own public address seen "
		+ "from inside your own network.") % [address, port, port])


# =============================================================== signals ===


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return

	# The newcomer needs everyone already here. Sent before it is spawned, so
	# this loop cannot accidentally include it.
	for p in players.get_children():
		_spawn_remote.rpc_id(id, p.name.to_int(), p.global_position)

	# And everyone, the newcomer included, needs the newcomer.
	_spawn_remote.rpc(id, SPAWN)

	# Declared call_remote, so the server still has to do it locally.
	spawn_player(id, SPAWN)
	_report_roster()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_despawn_remote.rpc(id)
	_despawn(id)
	_report_roster()


func _on_connected() -> void:
	join_attempt += 1

	# The solo player is named 1, and 1 belongs to the host. Cleared here
	# rather than when the attempt started, so a join that never lands leaves
	# you standing in the world you were already in instead of an empty one.
	_clear_players()
	_report("Connected as peer %d. Waiting for the world." % multiplayer.get_unique_id())


## Both of these arrive from inside multiplayer.poll, and _go_solo drops the
## peer that is doing the polling. Deferred so the teardown happens after the
## API has finished with it rather than underneath it.
func _on_connection_failed() -> void:
	join_attempt += 1
	_go_solo.call_deferred()
	_report("Connection failed. Nothing answered on that address.")


func _on_server_disconnected() -> void:
	_go_solo.call_deferred()
	_report("Host closed the session.")


# =================================================================== rpc ===


## Declared on World, whose multiplayer authority is the default of 1, so the
## annotation alone means only the server may call these.
@rpc("authority", "call_remote", "reliable")
func _spawn_remote(peer_id: int, at: Vector3) -> void:
	var p := spawn_player(peer_id, at)
	if peer_id == multiplayer.get_unique_id():
		_attach_local(p)
	_report_roster()


@rpc("authority", "call_remote", "reliable")
func _despawn_remote(peer_id: int) -> void:
	_despawn(peer_id)
	_report_roster()


# ================================================================ roster ===


## Creates the player owned by [param peer_id].
##
## The node is named after the peer id, and Player._ready derives its authority
## from that name. One string carries ownership to every machine, with no
## second message that could disagree with it.
func spawn_player(peer_id: int, at: Vector3) -> Player:
	# Replaces rather than collides. Godot renames a duplicate instead of
	# erroring, and a node called @1@2 parses to an id of zero, so it would
	# quietly fall back to the default authority and hand somebody a body they
	# cannot drive.
	_despawn(peer_id)

	var p := PLAYER_SCENE.instantiate() as Player
	p.name = str(peer_id)
	players.add_child(p)

	# After add_child, because teleport reseeds the camera interpolation
	# samples and those only exist once _ready has run. Global rather than
	# local, so a transform on the Players node cannot shift the spawn.
	p.teleport(at)
	p.spawn_point = at
	return p


func _despawn(peer_id: int) -> void:
	var p := players.get_node_or_null(NodePath(str(peer_id)))
	if p == null:
		return

	# Removed before freeing, because queue_free is deferred and the name would
	# otherwise still be taken if that peer reconnected inside the same frame.
	players.remove_child(p)
	p.queue_free()


func _clear_players() -> void:
	# Told first, because both hold a reference that is about to be freed and a
	# freed Node does not compare equal to null.
	hud.setup(null)
	pause_menu.setup(null)

	for p in players.get_children():
		players.remove_child(p)
		p.queue_free()


func _attach_local(p: Player) -> void:
	hud.setup(p)
	pause_menu.setup(p)


func _report(text: String) -> void:
	pause_menu.set_session_status(text)


## Addresses this machine can actually be reached on, so hosting can say what
## to hand out instead of leaving you to go and find it. Loopback and
## link-local are dropped because nobody else can use them.
func _local_addresses() -> String:
	var found: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.count(".") != 3:
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)

	return ", ".join(found) if not found.is_empty() else "not detected"


## Counts what is actually in the world rather than what the peer list claims,
## since the spawned roster is the thing the player can see.
func _report_roster() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var n := players.get_child_count()
	var role := "Hosting" if multiplayer.is_server() else "Connected"
	_report("%s. %d player%s in the session." % [role, n, "" if n == 1 else "s"])
