class_name Player
extends CharacterBody3D

## First-person controller reproducing Source engine movement.
##
## The simulation runs on a fixed physics tick and reads only from [member cmd],
## so replaying the same command sequence against the same starting state
## produces the same result. The camera is decoupled from the body and
## interpolated at render rate.
##
## Distances are stored in metres. Constants are written as Source units
## multiplied by [constant U] so they can be compared against Source cvars
## directly. Rates such as friction and acceleration are unitless and port
## across unchanged.


# ---------------------------------------------------------------- units ---

## One Source unit in metres. Source hulls are measured in inches.
const U := 0.0254


# --------------------------------------------------------------- states ---

## Movement states.
enum Move {
	GROUND,  ## On walkable ground. Friction and full acceleration.
	AIR,     ## Airborne. Air acceleration only; enables strafe jumping.
	SLIDE,   ## Crouch slide. Low friction, speed-preserving steering.
	SURF,    ## Riding a surface too steep to stand on.
}


# ---------------------------------------------------------------- input ---

const IN_JUMP := 1
const IN_CROUCH := 2
const IN_SPRINT := 4
const IN_NOCLIP := 8
const IN_ATTACK := 16


## One tick of player intent. The sole input to the movement simulation.
class Cmd:
	var wish := Vector2.ZERO  ## Strafe axes. x is right, y is back.
	var buttons := 0          ## Bitfield of IN_* flags.
	var yaw := 0.0
	var pitch := 0.0
	var tick := 0

	func pressed(bit: int) -> bool:
		return buttons & bit != 0


# ------------------------------------------------------ hull and stance ---

const STAND_HEIGHT := 83.0 * U
const CROUCH_HEIGHT := 62.0 * U
const HULL_DELTA := STAND_HEIGHT - CROUCH_HEIGHT

## Origin shift applied when a duck completes in mid-air: the feet come up
## rather than the head going down. This is what gives crouch-jumping its
## extra clearance.
const HULL_SHIFT := HULL_DELTA

const STAND_EYE := 68.0 * U

## Derived so STAND_EYE - CROUCH_EYE equals HULL_SHIFT. The eye drop then
## exactly cancels the origin shift, making an air duck visually free.
const CROUCH_EYE := STAND_EYE - HULL_DELTA

const TIME_TO_DUCK := 0.4
const TIME_TO_UNDUCK := 0.2

## Window after a jump during which crouch ducks instantly instead of running
## the transition. This is what makes crouch-jumping feel sharp.
const JUMP_WINDOW := 0.51


# ---------------------------------------------------------------- slide ---

const SLIDE_TIME := 1.4
const SLIDE_COOLDOWN := 0.35
const SLIDE_EXIT_SPEED := 120.0 * U

## Crouch is remembered this long, so a press just before landing still
## converts the landing into a slide.
const SLIDE_BUFFER := 0.15

## Opening window during which friction is skipped, making a short slide pure
## profit and a long one costly.
const SLIDE_GRACE := 0.45

const SLIDE_FRICTION := 0.6
const SLIDE_HEIGHT := 40.0 * U
const SLIDE_EYE := 32.0 * U

## How fast the hull moves between crouch and slide height. Kept high so the
## pose has settled before an air duck can shift the origin.
const SLIDE_POSE_RATE := 20.0

## Extra floor snap applied while sliding. Without it a fast slide leaves the
## ground on any downslope and immediately re-enters, which reads as bouncing.
const SLIDE_SNAP := 0.5
const DEFAULT_SNAP := 0.1


# ----------------------------------------------------------------- surf ---

## Below this speed a ramp provides no steering, so ramps cannot be climbed
## from a standstill.
const SURF_MIN_SPEED := 150.0 * U

## Reference speed and multiplier feeding the acceleration rate. Sized so the
## speed cap is always the binding limit, matching Source.
const SURF_RATE_SPEED := 320.0 * U
const SURF_ACCELERATE := 100.0


# ------------------------------------------------------------------ view ---

## Source's m_yaw: degrees of rotation per mouse count, before sensitivity.
const M_YAW := 0.022

## Decay rate for [member view_offset], which absorbs hull teleports so the
## eye moves continuously.
const VIEW_SMOOTH := 3.0

## Clamped just short of vertical; at exactly 90 the forward vector becomes
## parallel to the up axis and anything derived from it degenerates.
const PITCH_LIMIT := deg_to_rad(89.0)


# --------------------------------------------------------------- noclip ---

const NOCLIP_SPEED := 500.0 * U
const NOCLIP_FAST := 3.0


# --------------------------------------------------------------- ground ---

## Source's NON_JUMP_VELOCITY. Rising faster than this and you are airborne by
## definition, with no ground trace consulted at all.
const NON_JUMP_SPEED := 140.0 * U


# ---------------------------------------------------------------- blast ---

## Source units per second of push, per point of damage. This is the shape
## worth noticing about TF2 explosions: knockback is not its own number, it is
## derived from damage, so the two cannot be tuned apart.
const BLAST_PUSH_UNITS := 6.0

## Blasting yourself off the ground is the weak version.
const BLAST_PUSH_SELF_GROUND_UNITS := 5.0

## Blasting yourself while already airborne pushes harder and, with the damage
## cut below, costs less health. That trade is the entire reason a jump comes
## before the rocket.
const BLAST_PUSH_SELF_AIR_UNITS := 10.0

## Damage kept from an airborne self blast.
const BLAST_SELF_AIR_DAMAGE := 0.6

## Push multiplier while crouched. Vanilla calls this a volume ratio.
const BLAST_CROUCH_RATIO := 1.49091

## Ceiling on what one blast may add.
const BLAST_MAX_UNITS := 1000.0

## The push is aimed from this far below where the blast actually was, which is
## why explosions lift you rather than shoving you flat. Source does it in
## CTFPlayer::OnTakeDamage_Alive.
const BLAST_ORIGIN_DROP_UNITS := 10.0

## Range over which splash damage to other people decays.
const BLAST_FALLOFF_UNITS := 1024.0

## Damage kept at the edge of the blast, as a fraction of the centre. Half
## rather than nothing is what gives rim jumps their reach.
const BLAST_EDGE_DAMAGE := 0.5


# -------------------------------------------------------------- network ---

## Send one state every N ticks. One is every tick, which for two players is
## nothing. Raise it to prove the buffer is doing its job: playback should stay
## smooth at three or four, because it interpolates across whatever gaps it is
## given rather than depending on them being small.
##
## StateBuffer.INTERP_TICKS has to stay above twice this, or the buffer runs dry
## between sends and holds instead of interpolating.
const SEND_EVERY := 1


# -------------------------------------------------------------- options ---

@export_group("Options")
@export var sensitivity: float = 3.0
@export var auto_bhop: bool = true
@export var auto_sprint: bool = true
@export var crouch_toggle: bool = false
@export var noclip_toggle: bool = false

## When true, a crouch press is ignored until you have finished standing up.
## Matches Team Fortress 2 and prevents crouch spam. Ducking can still be
## interrupted freely; only the unduck direction is protected.
@export var duck_latch: bool = true

# ------------------------------------------------ base movement (cvars) ---
#
# These are the values a Source server config would change, so they are
# exports rather than constants. Anything ending in _units holds Source units
# and needs * U at the point of use; friction and acceleration are unitless
# rates that port across unchanged.

@export_group("Base Movement")

## Downward acceleration in units per second squared.
@export var sv_gravity_units: float = 800.0

## Apex of a standing jump in units. The impulse is derived from this and
## gravity, so changing either keeps the height correct.
@export var jump_height_units: float = 45.0

## Full running speed.
@export var sv_maxspeed_units: float = 320.0

## Speed used when not sprinting.
@export var sv_walkspeed_units: float = 190.0

## How quickly ground movement reaches full speed.
@export var sv_accelerate: float = 10.0

## How quickly ground movement bleeds off speed.
@export var sv_friction: float = 4.0

## Speed below which friction decelerates at a constant rate, so you come to a
## full stop instead of creeping.
@export var sv_stopspeed_units: float = 100.0

## Acceleration rate used in the air. Has no effect once the air speed cap is
## the binding limit, which it is at default values.
@export var sv_airaccelerate: float = 10.0

@export_group("Tuning")
## Maximum speed added per tick while air strafing. Source default is 30.
@export var air_speed_cap_units: float = 100.0
## Maximum speed added per tick while strafing on a ramp.
@export var surf_speed_cap_units: float = 100.0
## Turn authority while sliding. Matches air strafing at the same value.
@export var slide_steer_cap_units: float = 100.0
## Minimum ground speed required to start a slide.
@export var slide_entry_speed_units: float = 200.0
## Speed added at the moment a slide starts.
@export var slide_boost_units: float = 60.0
## Ceiling the slide boost can reach. Zero disables the cap. Never reduces
## speed you already had.
@export var slide_speed_cap_units: float = 0.0


@export_group("Video")

## Frame rate cap during play. Zero is uncapped. CS2 defaults to 400.
@export var fps_max: float = 400.0:
	set(v):
		fps_max = v
		_apply_fps_cap()

## Frame rate cap while the pause menu is open. Without this the GPU renders
## a static menu at full speed. CS2 defaults to 120.
@export var fps_max_ui: float = 120.0:
	set(v):
		fps_max_ui = v
		_apply_fps_cap()

## Off by default for input latency. Note that irregular frame pacing makes
## the physics interpolation fraction irregular too, so turning this off can
## reintroduce a small amount of camera stepping.
@export var vsync: bool = false:
	set(v):
		vsync = v
		_apply_vsync()


# ---------------------------------------------------------------- death ---

## Seconds spent dead before respawning. Long enough to register what killed
## you, short enough not to be a punishment on top of the death.
const DEATH_TIME := 3.0


# -------------------------------------------------------------- signals ---

## Emitted when a blast lands, with the damage it did and who caused it.
##
## There is no health pool yet. This is the seam it attaches to, so the damage
## that already had to be computed in order to derive the knockback is not
## thrown away and worked out a second time later.
signal hurt(amount: float, inflictor: Node3D)

## Emitted on death and on respawn, so anything that has to change shape for a
## corpse can do it without polling.
signal died(inflictor: Node3D)
signal respawned


# ---------------------------------------------------------------- nodes ---

## Placeholder body parts, built only for remote players. Held so the drawn
## height can follow the received stance.
var body_mesh: MeshInstance3D = null
var nose_mesh: MeshInstance3D = null

@onready var health: Health = $Health
@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var hull: CylinderShape3D = collider.shape
@onready var clearance: ShapeCast3D = %StandCheck

## Optional. Handed the aim basis and eye position each tick; the player never
## needs to know what kind of weapon it is.
@onready var weapon: Node = get_node_or_null("%Weapon")


# ---------------------------------------------------------- death state ---

## Counts down while dead. Zero means alive, so nothing else needs a flag.
var death_time := 0.0


# -------------------------------------------------------- network state ---

## Received states for a remote body. Unused on the player we own, which
## simulates rather than plays back.
var net := StateBuffer.new()


# ---------------------------------------------------------- input state ---

var cmd := Cmd.new()
var prev_buttons := 0
var mouse_delta := Vector2.ZERO


# ----------------------------------------------------------- view state ---

## Updated every rendered frame, then copied into [member cmd] once per tick.
var view_yaw := 0.0
var view_pitch := 0.0

## Eye height above the origin, and the two samples the camera lerps between.
var eye_height := 0.0
var prev_eye := Vector3.ZERO
var curr_eye := Vector3.ZERO

## Absorbs hull teleports. Set to cancel a jump, then decays to zero.
var view_offset := 0.0


# ------------------------------------------------------- movement state ---

var move_state := Move.AIR
var spawn_point := Vector3.ZERO
var noclip := false

## True while the pause menu is open, which selects the UI frame cap.
var menu_open := false
var jump_time := 0.0

## Cached from floor_max_angle in _ready, since it is needed every tick.
var floor_cos := 0.0

## Set by [method _clip_walls] from the last move. Read next tick by
## [method _update_state], matching the timing of is_on_floor().
var on_ramp := false


# --------------------------------------------------------- stance state ---

var is_crouched := false     ## True once a duck transition has completed.
var crouch_wanted := false   ## Intent, which is distinct from the button.
var crouch_prev := false     ## Previous intent, for slide buffer edges.
var crouch_shifted := false  ## An air duck shifted the origin; owed back.
var duck_progress := 0.0     ## 0 standing, 1 crouched.
var duck_target := 0.0
var pending_shift := 0.0     ## Shift the current transition will apply.
var stance_eye := 0.0        ## Eye from the duck system, before slide pose.


# ---------------------------------------------------------- slide state ---

var slide_time := 0.0
var slide_cooldown := 0.0
var slide_buffer := 0.0
var slide_pose := 0.0  ## 0 crouch height, 1 slide height.


# ================================================================== setup ===


func _ready() -> void:
	# Authority comes from the node name, which the spawner sets to the owning
	# peer's id. Names replicate and authority assignments do not, so every copy
	# works out the same owner unprompted. A non-numeric name leaves it alone.
	var owner_id := name.to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)

	# Surfing is almost entirely near-parallel motion against a steep face,
	# which the default 15 degree threshold would stop instead of sliding.
	wall_min_slide_angle = 0.0
	floor_max_angle = deg_to_rad(45.57)  # sv_maxstandableangle
	floor_cos = cos(floor_max_angle)

	# The camera places itself in world space every frame, so it must not be
	# dragged along by the body's transform at tick rate.
	camera.top_level = true
	eye_height = STAND_EYE

	# A fallback for a Player placed in a scene by hand. The spawner overwrites
	# both of these with teleport immediately after add_child.
	spawn_point = global_position
	teleport(global_position)

	# Scene sub-resources are shared by every instance unless marked local, so
	# without this every player collides with the same cylinder and one person
	# crouching shrinks everybody else's hull.
	collider.shape = collider.shape.duplicate()
	hull = collider.shape
	clearance.shape = clearance.shape.duplicate()

	# Set here rather than left to _update_pose, which only the local player
	# runs. Without it a remote body keeps whatever height player.tscn happens
	# to store, and its collider stops matching what is drawn.
	_apply_hull(STAND_HEIGHT)

	clearance.add_exception(self)
	var box := clearance.shape as BoxShape3D
	var w := (hull.radius - 0.02) * 2.0
	box.size = Vector3(w, 1.0, w)

	add_to_group("blastable")

	# Wired here rather than inside Health, so Health never has to know what
	# kind of thing it is attached to.
	hurt.connect(health.take_damage)
	health.died.connect(_on_died)

	if is_local_player():
		_setup_local()
	else:
		_setup_remote()


## Whether this instance belongs to the peer running it.
##
## Asked explicitly rather than through [method Node.is_multiplayer_authority],
## which compares against a peer id that does not exist in single player.
## Offline the only player in the scene is ours, so the answer is yes.
func is_local_player() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


## Setup only the owning peer runs. Everything here has a process-wide effect,
## so a second instance running it would fight the first.
func _setup_local() -> void:
	# Health is only sent when it changes, so somebody joining later would see
	# everyone at full. Each owner catches them up on arrival.
	multiplayer.peer_connected.connect(_on_peer_joined)

	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_vsync()
	_apply_fps_cap()


func _on_peer_joined(id: int) -> void:
	_receive_health.rpc_id(id, health.current, health.maximum, death_time > 0.0)


## Someone else's player. It keeps its collider so projectiles can still hit
## it, but simulates nothing: its transform will arrive over the network.
##
## The camera is cleared rather than left alone because a camera entering a
## viewport that has no current camera takes it, which happens whenever a
## remote player spawns before the local one.
func _setup_remote() -> void:
	camera.current = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	_build_placeholder_body()


## A body for remote players to be seen as. The local player is first person
## and needs none, which is why there is nothing like this in player.tscn.
## Scaffolding until there is a model to load.
func _build_placeholder_body() -> void:
	# A cylinder rather than a capsule, so what is drawn is the hull that is
	# actually there.
	body_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = STAND_HEIGHT
	cylinder.top_radius = hull.radius
	cylinder.bottom_radius = hull.radius
	body_mesh.mesh = cylinder
	body_mesh.position.y = STAND_HEIGHT * 0.5
	add_child(body_mesh)

	# A nose, so which way somebody is facing is readable from across the map.
	# Without it the sync looks correct even when the yaw is not arriving.
	nose_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.3)
	nose_mesh.mesh = box
	nose_mesh.position = Vector3(0.0, STAND_EYE, -hull.radius - 0.12)
	add_child(nose_mesh)


## Whether the player counts as standing on ground this tick.
##
## [method CharacterBody3D.is_on_floor] reports the last
## [method CharacterBody3D.move_and_slide], so anything that changes velocity
## after the move is invisible to it for a tick. An explosion is exactly that,
## and the next tick's GROUND branch would zero the impulse before it is used.
##
## Source solves it in CategorizePosition by skipping the ground trace whenever
## vertical velocity is above NON_JUMP_VELOCITY. Every ground question goes
## through here, so the stance machine and the state machine cannot disagree.
func _grounded() -> bool:
	return is_on_floor() and velocity.y <= NON_JUMP_SPEED


func is_alive() -> bool:
	return death_time <= 0.0


## Starts the death timer and stops the body being driven.
##
## The body stays in the world rather than being hidden. It still falls, still
## slides to a halt, and still collides, which is what makes a death read as
## something that happened in the world rather than a state change. It is also
## where the drop bag will be spawned from once there is one.
func _on_died(inflictor: Node3D) -> void:
	if not is_alive():
		return

	death_time = DEATH_TIME
	died.emit(inflictor)


## Counts the death timer down and respawns at the end of it.
##
## Runs before the command is sampled, so the tick a player comes back on is a
## fully live one rather than one spent still dead.
func _update_death(delta: float) -> void:
	if is_alive():
		return

	death_time = maxf(death_time - delta, 0.0)
	if death_time > 0.0:
		return

	respawn()
	health.reset()
	respawned.emit()
	_broadcast_health()


## Restores the player to the spawn point and clears every piece of transient
## state. Anything that persists across a respawn is a bug.
func respawn() -> void:
	death_time = 0.0
	_set_noclip(false)

	# Input history, not just input. A stale crouch_wanted re-ducks you a tick
	# later in toggle mode, and a stale prev_buttons reads a held key as new.
	cmd.wish = Vector2.ZERO
	cmd.buttons = 0
	prev_buttons = 0
	crouch_wanted = false
	crouch_prev = false

	mouse_delta = Vector2.ZERO
	view_yaw = 0.0
	view_pitch = 0.0
	cmd.yaw = 0.0
	cmd.pitch = 0.0
	rotation.y = 0.0

	velocity = Vector3.ZERO
	move_state = Move.AIR
	on_ramp = false
	jump_time = 0.0

	duck_progress = 0.0
	duck_target = 0.0
	pending_shift = 0.0
	view_offset = 0.0
	crouch_shifted = false
	_finish_unduck()

	slide_pose = 0.0
	slide_time = 0.0
	slide_cooldown = 0.0
	slide_buffer = 0.0

	eye_height = STAND_EYE
	teleport(spawn_point)


## Places the player and reseeds the camera samples, so the render-rate lerp
## does not sweep across the jump.
##
## Separate from [method respawn] because spawning needs the same thing without
## clearing state that was never set.
func teleport(to: Vector3) -> void:
	global_position = to
	curr_eye = to + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye


## Advances the pair the camera lerps between. Called at the end of a tick,
## once the body has finished moving.
func _sample_eye() -> void:
	prev_eye = curr_eye
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)


# ================================================================= loops ===


## Mouse deltas are accumulated here and consumed in [method _process], so the
## view turns at monitor rate rather than tick rate.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative


## Draws whichever kind of player this is.
##
## Ours renders the view: rotation at frame rate so mouse look stays sharp,
## position lerped between the last two physics samples. This mirrors Source's
## split between ExtraMouseSample and CreateMove, where the rendered angle leads
## the simulated one while the command still carries one angle per tick.
##
## Someone else's plays back from the state buffer. Same idea either way, only
## the samples are further behind and arrived over the network.
func _process(delta: float) -> void:
	if not is_local_player():
		_draw_remote(delta)
		return

	var amount := M_YAW * sensitivity
	view_yaw = wrapf(view_yaw - deg_to_rad(mouse_delta.x * amount), -PI, PI)
	view_pitch = clampf(view_pitch - deg_to_rad(mouse_delta.y * amount), -PITCH_LIMIT, PITCH_LIMIT)
	mouse_delta = Vector2.ZERO

	var f := Engine.get_physics_interpolation_fraction()
	camera.global_position = prev_eye.lerp(curr_eye, f)
	camera.global_rotation = Vector3(view_pitch, view_yaw, 0.0)


## The movement simulation. Everything below is a pure function of [member cmd]
## and the player's own state.
func _physics_process(delta: float) -> void:
	_update_death(delta)
	_sample_input()

	if noclip_toggle:
		if _just_pressed(IN_NOCLIP):
			_set_noclip(not noclip)
	else:
		_set_noclip(cmd.pressed(IN_NOCLIP))

	if noclip:
		_move_noclip(delta)
		_sample_eye()
		_broadcast_state()
		return

	# Source splits gravity across the move: half before, half after. Applying
	# it all up front costs roughly v*dt/2 of jump apex.
	velocity.y -= sv_gravity_units * U * 0.5 * delta

	jump_time = maxf(jump_time - delta, 0.0)
	if _grounded():
		crouch_shifted = false

	var speed := flat_speed()
	_update_crouch(delta)
	_update_state(delta, speed)
	_update_pose(delta)

	var max_speed := _current_max_speed()
	var wish_dir := (transform.basis * Vector3(cmd.wish.x, 0.0, cmd.wish.y)).normalized()
	var jump_held := cmd.pressed(IN_JUMP) if auto_bhop else _just_pressed(IN_JUMP)

	# Leaving the ground before the friction block is what preserves speed
	# through a bunny hop.
	if (move_state == Move.GROUND or move_state == Move.SLIDE) and jump_held:
		jump_time = JUMP_WINDOW
		velocity.y = _jump_impulse()
		if move_state == Move.SLIDE:
			_exit_slide()
		move_state = Move.AIR

	match move_state:
		Move.GROUND:
			velocity.y = 0.0
			_apply_friction(delta, sv_friction)
			_accelerate(wish_dir, max_speed, INF, sv_accelerate, delta)
		Move.SLIDE:
			_move_slide(wish_dir, delta)
		Move.AIR:
			_accelerate(wish_dir, max_speed, air_speed_cap_units * U, sv_airaccelerate, delta)
		Move.SURF:
			_move_surf(wish_dir, delta)

	# Ground and slide need wall blocking to avoid stuttering against steep
	# faces; air and surf need free sliding for strafe control.
	floor_block_on_wall = (move_state == Move.GROUND or move_state == Move.SLIDE)
	floor_snap_length = SLIDE_SNAP if move_state == Move.SLIDE else DEFAULT_SNAP

	move_and_slide()
	_clip_walls()

	velocity.y -= sv_gravity_units * U * 0.5 * delta
	_sample_eye()

	if weapon != null and weapon.has_method("update"):
		weapon.update(delta, self, _aim_basis(), curr_eye, cmd.pressed(IN_ATTACK))

	_broadcast_state()


# =============================================================== network ===


## Publishes what this player looks like right now.
##
## Sent from the tick loop so every state carries the tick it was true on, which
## is what lets the receiver rebuild a timeline rather than a pile of positions.
## What goes out is the result of the simulation, not its input: remote bodies
## display rather than simulate, so they want the hull height the stance machine
## produced, not the crouch key that went in.
##
## Velocity is absent on purpose. Nothing on the far end extrapolates, so
## nothing needs it. It goes in when animation wants it.
func _broadcast_state() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_local_player():
		return
	if SEND_EVERY > 1 and cmd.tick % SEND_EVERY != 0:
		return

	_receive_state.rpc(
		cmd.tick,
		global_position,
		view_yaw,
		view_pitch,
		hull.height,
		eye_height,
		move_state)


## Health is sent on change over a reliable channel rather than riding in the
## state packet. It moves rarely and every change matters, which is the opposite
## of position: that is sent constantly and any one packet is disposable.
func _broadcast_health() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_local_player():
		return
	_receive_health.rpc(health.current, health.maximum, death_time > 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _receive_health(value: float, max_value: float, dead: bool) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return

	health.apply_remote(value, max_value)

	# Held rather than counted down, since a remote body does not run the tick
	# that would decrement it. The owner sends the transition back.
	death_time = DEATH_TIME if dead else 0.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_state(tick: int, pos: Vector3, yaw: float, pitch: float,
		hull_h: float, eye_h: float, state: int) -> void:
	# Only the peer that owns this body may say where it is. Declared "any_peer"
	# with the check written out rather than "authority", because a client's
	# packet reaches the other clients by being relayed through the server.
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return

	var s := StateBuffer.State.new()
	s.tick = tick
	s.position = pos
	s.yaw = yaw
	s.pitch = pitch
	s.hull_height = hull_h
	s.eye_height = eye_h
	s.move_state = state
	net.push(s)


## Draws a remote body from the buffer.
##
## In _process rather than _physics_process, for the same reason the camera is:
## the job is a position for every frame drawn, not for every tick simulated.
func _draw_remote(delta: float) -> void:
	net.advance(delta)
	var s := net.sample()
	if s == null:
		return

	rotation.y = s.yaw
	view_yaw = s.yaw
	view_pitch = s.pitch
	move_state = s.move_state as Move

	# Kept in step with the drawn hull so a crouching player is not shot
	# through the head they no longer have there.
	_apply_hull(s.hull_height)

	# teleport rather than plain assignment, so both camera samples collapse
	# onto the new spot instead of sweeping across the gap.
	eye_height = s.eye_height
	teleport(s.position)

	if body_mesh != null:
		(body_mesh.mesh as CylinderMesh).height = s.hull_height
		body_mesh.position.y = s.hull_height * 0.5
	if nose_mesh != null:
		nose_mesh.position.y = s.eye_height
		nose_mesh.rotation.x = s.pitch


# ================================================================= input ===


## Samples every input into [member cmd] once per tick. Sampling per frame
## instead would make edge detection frame-rate dependent, so a fast tap could
## be missed or counted twice.
func _sample_input() -> void:
	prev_buttons = cmd.buttons
	cmd.tick += 1
	cmd.yaw = view_yaw
	cmd.pitch = view_pitch
	rotation.y = view_yaw

	# Neither the menu nor being dead stops the world in a session, so the
	# simulation runs underneath both. An empty command is what standing still
	# means here: friction halts you, gravity applies, nothing fires. The tick
	# keeps counting because the command stream has no gap in it either, and the
	# button history clears so a key held through either is not a fresh press.
	if menu_open or not is_alive():
		cmd.wish = Vector2.ZERO
		cmd.buttons = 0
		prev_buttons = 0
		return

	cmd.wish = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	cmd.buttons = 0
	if Input.is_action_pressed("jump"):
		cmd.buttons |= IN_JUMP
	if Input.is_action_pressed("crouch"):
		cmd.buttons |= IN_CROUCH
	if Input.is_action_pressed("sprint"):
		cmd.buttons |= IN_SPRINT
	if Input.is_action_pressed("noclip"):
		cmd.buttons |= IN_NOCLIP
	if Input.is_action_pressed("attack"):
		cmd.buttons |= IN_ATTACK


func _just_pressed(bit: int) -> bool:
	return (cmd.buttons & bit) != 0 and (prev_buttons & bit) == 0


# ========================================================== acceleration ===


## Horizontal speed, ignoring anything vertical. Public because the HUD wants
## it too, and a second copy of the formula would be one too many.
func flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Source's Friction. Scales the whole velocity vector, so it slows you down
## without ever turning you. Sliding passes its own [param rate].
func _apply_friction(delta: float, rate: float) -> void:
	var speed := velocity.length()
	if speed < 0.01:
		return

	# The floor under `control` is what makes you actually stop. Without it
	# the decay is exponential and you creep forever.
	var control := maxf(speed, sv_stopspeed_units * U)
	var drop := control * rate * delta
	velocity *= maxf(speed - drop, 0.0) / speed


## Source's Accelerate and AirAccelerate, which differ only in whether the
## budget is capped. Pass INF for [param speed_cap] to get the ground version.
##
## The speed check is a projection of current velocity onto the push
## direction, not the actual speed. Push sideways relative to your motion and
## that projection is near zero, so the budget stays full and you gain speed
## every tick. Strafe jumping, surfing and slide steering all fall out of it.
func _accelerate(wish_dir: Vector3, wish_speed: float, speed_cap: float, accel: float, delta: float) -> void:
	# The budget is capped; the rate uses the uncapped speed. Swapping these
	# gives air control that feels plausible and never gains speed.
	var add_speed := minf(wish_speed, speed_cap) - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return

	velocity += wish_dir * minf(accel * wish_speed * delta, add_speed)


# ==================================================== hull and clearance ===


## Current hull height, accounting for both the duck transition and the slide
## pose. Every clearance test measures from here.
func _hull_height() -> float:
	var base_h := CROUCH_HEIGHT if is_crouched else STAND_HEIGHT
	return lerpf(base_h, SLIDE_HEIGHT, slide_pose)


## Writes the hull height and keeps the collider centred on it. Always a pair.
func _apply_hull(height: float) -> void:
	hull.height = height
	collider.position.y = height * 0.5


func _set_clearance(height: float, center_y: float) -> void:
	(clearance.shape as BoxShape3D).size.y = height
	clearance.position.y = center_y


## Whether the hull can grow to [param height]. Only the slab between the
## current hull top and the target is tested, since the space already occupied
## is known to be clear.
func _fits(height: float) -> bool:
	var top := _hull_height()
	if height <= top:
		return true
	_set_clearance(height - top, (height + top) * 0.5)
	clearance.force_shapecast_update()
	return not clearance.is_colliding()


## Whether standing up is possible. An air duck raised the origin, so undoing
## it grows the hull in both directions and needs the full standing volume
## tested rather than a slab above.
func _can_stand() -> bool:
	if crouch_shifted:
		_set_clearance(STAND_HEIGHT, STAND_HEIGHT * 0.5 - HULL_SHIFT)
		clearance.force_shapecast_update()
		return not clearance.is_colliding()
	return _fits(STAND_HEIGHT)


func _headroom_clear() -> bool:
	return _fits(CROUCH_HEIGHT)


## Source's ClipVelocity, applied to surfaces too steep to stand on.
##
## Godot's grounded motion mode leaves vertical velocity untouched on walls,
## deliberately, so characters do not stick to them. Surfing needs that
## component removed, so it is done here. Floors and ceilings are skipped and
## left to move_and_slide.
##
## Also records whether any surfable ramp was touched, saving a second pass
## over the same collision list.
func _clip_walls() -> void:
	on_ramp = false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > floor_cos or n.y < -0.1:
			continue
		if n.y > 0.01:
			on_ramp = true
		var into := velocity.dot(n)
		if into < 0.0:
			velocity -= n * into


# ================================================================ stance ===


## Applies the crouched hull. In mid-air the origin rises so the feet come up,
## which is what a crouch-jump clears a ledge with.
func _finish_duck() -> void:
	is_crouched = true
	_apply_hull(CROUCH_HEIGHT)
	if not _grounded():
		global_position.y += HULL_SHIFT
		crouch_shifted = true


## Applies the standing hull, undoing an origin shift only if this duck was
## the one that created it. Branching on ground contact instead would let you
## give back a shift you never took.
func _finish_unduck() -> void:
	is_crouched = false
	_apply_hull(STAND_HEIGHT)
	if crouch_shifted:
		global_position.y -= HULL_SHIFT
	crouch_shifted = false


## Origin shift the in-progress transition will apply when it completes.
## Biasing the eye by this amount as the transition approaches keeps the view
## continuous across the jump.
func _pending_for(target: float) -> float:
	if target >= 1.0 and not is_crouched:
		return 0.0 if _grounded() else HULL_SHIFT
	if target <= 0.0 and is_crouched:
		return -HULL_SHIFT if crouch_shifted else 0.0
	return 0.0


## Smoothstep. Source runs the duck fraction through SimpleSpline before
## applying it to the eye, which is what stops the motion reading as
## mechanical.
func _spline(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Runs the duck transition and publishes the resulting eye height in
## [member stance_eye]. The hull itself only changes at the endpoints.
func _update_crouch(delta: float) -> void:
	if crouch_toggle:
		if _just_pressed(IN_CROUCH):
			crouch_wanted = not crouch_wanted
	else:
		crouch_wanted = cmd.pressed(IN_CROUCH)

	# Buffered on intent rather than the button, so it behaves the same in
	# toggle mode.
	var edge := crouch_wanted and not crouch_prev
	crouch_prev = crouch_wanted
	if edge:
		slide_buffer = SLIDE_BUFFER

	# Source defers the hull change until the transition completes, then
	# branches on ground contact. Crouching within the jump window therefore
	# ducks instantly and gets the airborne shift.
	if crouch_wanted and not is_crouched and jump_time > 0.0 and not _grounded():
		var eye_before := eye_height
		duck_progress = 1.0
		_finish_duck()
		pending_shift = 0.0
		view_offset = eye_before - CROUCH_EYE - HULL_SHIFT
		stance_eye = CROUCH_EYE
		return

	var desired := 1.0
	if not crouch_wanted and (not is_crouched or _can_stand()):
		desired = 0.0

	# The latch protects the unduck direction only: a crouch press is ignored
	# until you are upright, but releasing mid-duck stands you up immediately.
	var latched := duck_latch and duck_progress > 0.0 and duck_progress < 1.0 and duck_target <= 0.0
	if not latched:
		duck_target = desired
	var target := duck_target

	var rate := (1.0 / TIME_TO_DUCK) if target > duck_progress else (1.0 / TIME_TO_UNDUCK)
	duck_progress = move_toward(duck_progress, target, rate * delta)

	view_offset = move_toward(view_offset, 0.0, VIEW_SMOOTH * delta)

	var finished := false
	if not is_crouched and duck_progress >= 1.0:
		_finish_duck()
		finished = true
	elif is_crouched and duck_progress <= 0.0:
		_finish_unduck()
		finished = true

	# A completed transition moves the origin, which replaces the bias. Any
	# other change to the pending shift has no origin move behind it, so the
	# difference has to go into view_offset or the eye jumps.
	var pending := _pending_for(target)
	var blend := 1.0 - absf(target - duck_progress)
	if not finished and pending != pending_shift:
		view_offset += (pending_shift - pending) * blend
	pending_shift = pending

	stance_eye = lerpf(STAND_EYE, CROUCH_EYE, _spline(duck_progress)) + pending * blend


## Applies the slide pose on top of the duck stance, then writes the hull and
## the eye. Runs after [method _update_crouch] every tick, so whatever the
## stance endpoints left behind is corrected here before anything reads it.
func _update_pose(delta: float) -> void:
	var target := 1.0 if move_state == Move.SLIDE else 0.0
	# Ending a slide under low geometry keeps you pinned until you are clear.
	if target < slide_pose and not _headroom_clear():
		target = slide_pose
	slide_pose = move_toward(slide_pose, target, SLIDE_POSE_RATE * delta)

	_apply_hull(_hull_height())

	eye_height = lerpf(stance_eye, SLIDE_EYE, slide_pose) + view_offset


# ================================================================= slide ===


## Whether a slide may start. From the air the crouch key only needs to be
## held; from the ground it needs a recent press, so holding crouch while
## walking does not repeatedly re-slide.
func _can_slide(speed: float, from_air: bool) -> bool:
	if speed < slide_entry_speed_units * U or slide_cooldown > 0.0:
		return false
	return crouch_wanted if from_air else slide_buffer > 0.0


func _enter_slide() -> void:
	move_state = Move.SLIDE
	slide_time = SLIDE_TIME
	slide_buffer = 0.0

	# The hull must shrink now rather than over the duck transition, since a
	# slide is often started to fit under something immediately. The eye
	# difference goes into view_offset so only the collision snaps.
	if not is_crouched:
		view_offset += stance_eye - CROUCH_EYE
		stance_eye = CROUCH_EYE
		duck_progress = 1.0
		_finish_duck()
		pending_shift = 0.0

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var spd := flat.length()
	if spd > 0.01:
		var boosted := spd + slide_boost_units * U
		# maxf keeps the cap a ceiling on gaining, never a cut to what you
		# arrived with.
		if slide_speed_cap_units > 0.0:
			boosted = minf(boosted, maxf(spd, slide_speed_cap_units * U))
		velocity.x = flat.x / spd * boosted
		velocity.z = flat.z / spd * boosted


func _exit_slide() -> void:
	slide_cooldown = SLIDE_COOLDOWN


## Slide movement. Friction is skipped for the opening window, and steering
## uses the same acceleration as air strafing, rescaled to preserve speed so
## the strafe-gain exploit does not leak onto the ground.
func _move_slide(wish_dir: Vector3, delta: float) -> void:
	velocity.y = 0.0

	if SLIDE_TIME - slide_time > SLIDE_GRACE:
		_apply_friction(delta, SLIDE_FRICTION)

	var before := flat_speed()
	if before > 0.01 and wish_dir.length_squared() > 0.0:
		_accelerate(wish_dir, sv_maxspeed_units * U, slide_steer_cap_units * U, sv_airaccelerate, delta)
		var after := flat_speed()
		if after > 0.01:
			velocity.x *= before / after
			velocity.z *= before / after


# ================================================================== surf ===


## Surf movement. Steering authority fades in with speed, so a ramp cannot be
## climbed from a standstill but rewards arriving fast.
func _move_surf(wish_dir: Vector3, delta: float) -> void:
	var speed := flat_speed()
	if speed < SURF_MIN_SPEED:
		return
	var t := clampf((speed - SURF_MIN_SPEED) / (SURF_MIN_SPEED * 2.0), 0.0, 1.0)
	_accelerate(wish_dir, SURF_RATE_SPEED, surf_speed_cap_units * U * t, SURF_ACCELERATE, delta)


# ========================================================= state machine ===


## Decides which state the player is in. Only transitions happen here;
## the movement for each state runs in [method _physics_process].
func _update_state(delta: float, speed: float) -> void:
	slide_buffer = maxf(slide_buffer - delta, 0.0)
	slide_cooldown = maxf(slide_cooldown - delta, 0.0)
	var grounded := _grounded()

	match move_state:
		Move.GROUND:
			if not grounded:
				move_state = Move.AIR
			elif _can_slide(speed, false):
				_enter_slide()
		Move.AIR:
			if grounded:
				_land(speed)
			elif on_ramp:
				move_state = Move.SURF
		Move.SURF:
			if grounded:
				_land(speed)
			elif not on_ramp:
				move_state = Move.AIR
		Move.SLIDE:
			slide_time -= delta
			if not grounded:
				_exit_slide()
				move_state = Move.AIR
			elif slide_time <= 0.0 or speed < SLIDE_EXIT_SPEED or not crouch_wanted:
				_exit_slide()
				move_state = Move.GROUND


## Shared by AIR and SURF so landing off a ramp behaves the same as landing
## off a jump, including converting into a slide.
func _land(speed: float) -> void:
	if _can_slide(speed, true):
		_enter_slide()
	else:
		move_state = Move.GROUND


# ================================================================== speed ===


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return true if auto_sprint else cmd.pressed(IN_SPRINT)


## Jump velocity for the configured height, from v = sqrt(2 * g * h). Derived
## rather than stored so gravity and jump height cannot drift apart.
func _jump_impulse() -> float:
	return sqrt(2.0 * sv_gravity_units * U * jump_height_units * U)


## Ducked movement is a third of normal, matching TF2, rather than a fixed
## speed. The value feeds both ground acceleration and the air rate.
func _current_max_speed() -> float:
	var base := sv_maxspeed_units * U if _is_sprinting() else sv_walkspeed_units * U
	return base / 3.0 if is_crouched else base


# ==================================================================== aim ===


## Aim orientation from the command angles, not the rendered camera. The camera
## leads the simulation between ticks, so using it would make shots depend on
## frame rate.
func _aim_basis() -> Basis:
	return Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0))


# ================================================================== blast ===


## Takes an explosion, as TF2 resolves one.
##
## The weapon supplies damage and radius; how hard this body moves is decided
## here, because it turns on stance and ground contact the weapon cannot see.
## Knockback derives from damage rather than being a second number, so a weaker
## rocket is a weaker jump by construction.
##
## Velocity is added to rather than replaced, which is what makes rocket jumps
## chain. Leaving the ground matters too: staying in GROUND would run friction
## next tick and eat most of the impulse.
##
## One vanilla behaviour is deliberately not copied. TF2 forces you airborne
## outright; here that falls out of NON_JUMP_VELOCITY in [method _grounded], so
## a mostly sideways blast leaves you sliding rather than launching.
func apply_blast(blast: Blast) -> void:
	# Only the peer that owns this body may push it, so explosions do not cross
	# the network yet: your rocket moves you and nobody else. Fixing that means
	# sending the blast rather than its result, so each owner applies its own.
	if not is_local_player() or not is_alive():
		return

	var is_self := blast.inflictor == self
	var centre := blast_centre()

	# Rings out sooner on yourself than on anyone else.
	var radius := (blast.self_radius_units if is_self else blast.radius_units) * U

	# Measured to the nearer of the feet and the centre, which approximates
	# vanilla measuring to the closest point on the bounding box rather than to
	# one origin. A body struck head on skips the measurement and takes the
	# full centre value.
	var dist := 0.0
	if blast.direct_hit != self:
		dist = minf(blast.origin.distance_to(global_position),
				blast.origin.distance_to(centre))
		if dist >= radius:
			return

	if not _blast_reaches(blast.origin, centre):
		return

	var edge := blast.damage * BLAST_EDGE_DAMAGE
	var damage := clampf(
		remap(dist, 0.0, radius, blast.damage, edge), edge, blast.damage)

	var push := BLAST_PUSH_UNITS
	if is_self:
		if _grounded():
			push = BLAST_PUSH_SELF_GROUND_UNITS
		else:
			damage *= BLAST_SELF_AIR_DAMAGE
			push = BLAST_PUSH_SELF_AIR_UNITS
	elif blast.inflictor != null:
		damage *= _blast_falloff(
			blast.inflictor.global_position.distance_to(global_position))

	# Crouching does not only tuck the hull in, it multiplies the push outright.
	var ratio := BLAST_CROUCH_RATIO if is_crouched else 1.0
	var force := minf(damage * ratio * push, BLAST_MAX_UNITS) * U

	var from := blast.origin - Vector3(0.0, BLAST_ORIGIN_DROP_UNITS * U, 0.0)
	var dir := from.direction_to(centre)
	if dir.length_squared() < 0.001:
		dir = Vector3.UP

	velocity += dir * force

	if move_state != Move.AIR:
		move_state = Move.AIR
		# Opens the instant duck window, so crouching straight after a rocket
		# jump gains height the same way it does after a normal jump.
		jump_time = JUMP_WINDOW

	hurt.emit(damage, blast.inflictor)
	_broadcast_health()


## Roughly Source's WorldSpaceCenter. Both the blast direction and the line of
## sight test aim at this rather than at the feet, so a crouched body is pushed
## from lower down simply because its centre is lower.
func blast_centre() -> Vector3:
	return global_position + Vector3(0.0, _hull_height() * 0.5, 0.0)


## Whether anything solid stands between the blast and this body.
##
## Safe to trace only because the projectile lifts the blast a unit clear of
## whatever it hit before detonating. A ray leaving a surface it is sitting
## exactly on can go either way on a floating point comparison, which would
## make rocket jumps fail at random.
func _blast_reaches(origin: Vector3, centre: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, centre)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Splash damage multiplier by how far the shot was taken from, for everyone
## except the shooter. Ramps slightly above one at point blank before decaying,
## matching TF2's distance curve rather than a plain falloff.
func _blast_falloff(distance: float) -> float:
	var t := clampf(distance / (BLAST_FALLOFF_UNITS * U), 0.0, 1.0)
	return cubic_interpolate(1.25, 0.5, 0.25, 0.0, t)


# ================================================================ display ===


## Applies the frame cap for the current context. Called from the property
## setters, so dragging a slider takes effect immediately.
##
## Guarded because the cap belongs to the process, not to a player: a remote
## instance carrying a scene-stored override would reset the local one's cap.
##
## The play cap is dropped while vsync is on. Two limiters beat against each
## other into uneven frame times, and the camera lerps on the interpolation
## fraction every frame, so irregular frames become visible stepping.
func _apply_fps_cap() -> void:
	if not is_local_player():
		return
	var cap := fps_max_ui if menu_open else (0.0 if vsync else fps_max)
	Engine.max_fps = int(maxf(cap, 0.0))


func _apply_vsync() -> void:
	if not is_local_player():
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	# The play cap depends on the vsync state, so it has to follow it.
	_apply_fps_cap()


## Called by the pause menu. Also the switch that suppresses input, since the
## menu no longer stops the simulation in a session.
func set_menu_open(open: bool) -> void:
	menu_open = open

	# Motion queued before the mouse was released, or in the gap between that
	# and this call, would otherwise land on the first frame back.
	mouse_delta = Vector2.ZERO

	_apply_fps_cap()


# ================================================================= noclip ===


func _set_noclip(on: bool) -> void:
	if on == noclip:
		return
	noclip = on
	collider.disabled = on

	# Both directions. Keeping the fly speed on the way out, 500 units per
	# second or 1500 sprinting, launches you the moment the collider returns.
	velocity = Vector3.ZERO

	# Entering, so no slide is left reported that nothing is simulating.
	# Leaving, so the ground check resolves where you actually are rather than
	# trusting a contact from before the flight.
	move_state = Move.AIR
	slide_time = 0.0
	slide_cooldown = 0.0
	slide_buffer = 0.0


## Flies along the aim basis rather than the body's, so you move where you are
## looking including up and down.
##
## The basis comes from the command angles, not the camera. The camera leads
## the simulation at render rate, so reading it would make the distance flown
## per tick depend on frame rate.
func _move_noclip(delta: float) -> void:
	var dir := _aim_basis() * Vector3(cmd.wish.x, 0.0, cmd.wish.y)
	if cmd.pressed(IN_JUMP):
		dir.y += 1.0
	if cmd.pressed(IN_CROUCH):
		dir.y -= 1.0

	var speed := NOCLIP_SPEED
	if cmd.pressed(IN_SPRINT):
		speed *= NOCLIP_FAST

	velocity = dir.normalized() * speed if dir.length_squared() > 0.0 else Vector3.ZERO
	global_position += velocity * delta
