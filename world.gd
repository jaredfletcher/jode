extends Node3D

## Owns the session and the player instances in it.
##
## Players are spawned at runtime, one per peer. Spawning uses plain RPCs rather
## than a MultiplayerSpawner so the roster, the ownership rule and the teardown
## all live in this file.

const PLAYER_SCENE := preload("res://player/player.tscn")

# TODO: multiple spawn points with round-robin selection.
const SPAWN := Vector3(0.0, 2.0, 0.0)

## Clients, not counting the host.
const MAX_PEERS := 7

## Seconds to wait for a join before giving up. ENet times out on its own
## eventually, but slowly and not always.
const JOIN_TIMEOUT := 8.0

## How often to poll a hostname lookup, and how long to let it run.
const RESOLVE_POLL := 0.05
const RESOLVE_TIMEOUT := 5.0

## Bumped whenever a join starts or finishes, so a late timeout can tell whether
## it still belongs to the current attempt.
var join_attempt := 0

## The outstanding hostname lookup, if any.
var resolve_id := IP.RESOLVER_INVALID_ID
var resolve_host := ""
var resolve_port := 0
var resolve_attempt := 0
var resolve_deadline := 0

@onready var players: Node3D = %Players
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


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


#region Session

## Tears down any session and rebuilds the world around one local player. Also
## the startup path, so launching and leaving end up in exactly the same state.
##
## Doesn't set a status message. One caller defers this, so a message set here
## would overwrite the caller's reason.
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

	# The solo player is already named 1, which is the server's id, so nothing
	# needs respawning.
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

	# ENet can resolve names itself, but it blocks the main thread while it does.
	# Resolving here keeps the game responsive, tells "name not found" apart from
	# "host didn't answer", and lets the status show the resolved address (handy
	# when a domain points at a home connection whose IP may have changed).
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


## Checks on the outstanding lookup and re-arms itself until it finishes.
##
## Uses a SceneTreeTimer rather than _process because the tree is paused while
## the menu is open in a solo game, which is exactly when a join gets started.
## SceneTreeTimers keep running while paused.
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


## The resolver keeps finished items until they're erased.
func _cancel_resolve() -> void:
	if resolve_id != IP.RESOLVER_INVALID_ID:
		IP.erase_resolve_item(resolve_id)
	resolve_id = IP.RESOLVER_INVALID_ID
	resolve_host = ""


## Takes the hostname and the resolved IP separately so the status can show both.
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


## Gives up on a join that never landed. SceneTreeTimers can't be cancelled, so
## a leftover timer from an earlier attempt just finds a stale attempt number.
func _abandon_join(attempt: int, address: String, port: int) -> void:
	if attempt != join_attempt:
		return

	_go_solo()
	_report(("No answer from %s:%d. Check that the host is running, that UDP "
			+ "%d reaches it, and that this is not your own public address seen "
			+ "from inside your own network.") % [address, port, port])

#endregion


#region Multiplayer signals

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return

	# Send the newcomer everyone already here, before it's spawned itself.
	for p in players.get_children():
		_spawn_remote.rpc_id(id, p.name.to_int(), p.global_position)

	# Then tell everyone, newcomer included, about the newcomer.
	_spawn_remote.rpc(id, SPAWN)

	# The RPC is call_remote, so the server spawns its own copy here.
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

	# The solo player is named 1, which belongs to the host. Cleared here rather
	# than when the join started, so a failed join leaves you where you were.
	_clear_players()
	_report("Connected as peer %d. Waiting for the world." % multiplayer.get_unique_id())


# These two fire from inside multiplayer.poll(), and _go_solo() drops the peer
# being polled, so the teardown is deferred until the poll is done.

func _on_connection_failed() -> void:
	join_attempt += 1
	_go_solo.call_deferred()
	_report("Connection failed. Nothing answered on that address.")


func _on_server_disconnected() -> void:
	_go_solo.call_deferred()
	_report("Host closed the session.")

#endregion


#region RPC

# World's multiplayer authority is the default of 1, so "authority" here means
# only the server can call these.

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

#endregion


#region Roster

## Creates the player owned by peer_id. The node is named after the peer id and
## Player._ready() derives its authority from that name.
func spawn_player(peer_id: int, at: Vector3) -> Player:
	# Replace any existing node with this name. Godot would otherwise rename the
	# duplicate to something like @1@2, which parses to peer id 0 and silently
	# hands the body to the wrong authority.
	_despawn(peer_id)

	var p := PLAYER_SCENE.instantiate() as Player
	p.name = str(peer_id)
	players.add_child(p)

	# After add_child, since teleport() seeds camera samples set up in _ready().
	p.teleport(at)
	p.spawn_point = at
	return p


func _despawn(peer_id: int) -> void:
	var p := players.get_node_or_null(NodePath(str(peer_id)))
	if p != null:
		_free_player(p)


func _clear_players() -> void:
	# Detach the UI first. A freed Node doesn't compare equal to null, so they
	# can't be left holding a reference to it.
	hud.setup(null)
	pause_menu.setup(null)

	for p in players.get_children():
		_free_player(p)


## Removed from the tree before freeing, since queue_free() is deferred and the
## name would still be taken if that peer reconnected in the same frame.
func _free_player(p: Node) -> void:
	players.remove_child(p)
	p.queue_free()


func _attach_local(p: Player) -> void:
	hud.setup(p)
	pause_menu.setup(p)

#endregion


#region Status

func _report(text: String) -> void:
	pause_menu.set_session_status(text)


## LAN addresses this machine can be reached on, so hosting can show what to give
## out. Loopback and link-local are skipped.
func _local_addresses() -> String:
	var found: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.count(".") != 3:
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)

	return ", ".join(found) if not found.is_empty() else "not detected"


## Counts what's actually spawned rather than the peer list.
func _report_roster() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var n := players.get_child_count()
	var role := "Hosting" if multiplayer.is_server() else "Connected"
	_report("%s. %d player%s in the session." % [role, n, "" if n == 1 else "s"])

#endregion
