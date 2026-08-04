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

## Movement states. Kept in sync with STATE_NAMES in hud.gd.
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
		if is_inside_tree():
			_apply_vsync()


# ---------------------------------------------------------------- nodes ---

## Received states for a remote body. Unused on the player we own, which
## simulates rather than plays back.
var net := StateBuffer.new()

## Placeholder body parts, built only for remote players. Held so the drawn
## height can follow the received stance.
var body_mesh: MeshInstance3D = null
var nose_mesh: MeshInstance3D = null

@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var hull: CylinderShape3D = collider.shape
@onready var clearance: ShapeCast3D = %StandCheck

## Optional. Handed the aim basis and eye position each tick; the player never
## needs to know what kind of weapon it is.
@onready var weapon: Node = get_node_or_null("%Weapon")


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


# ================================================================ setup ===


func _ready() -> void:
	# Authority is derived from the node name, which the spawner sets to the id
	# of the owning peer. Node names replicate and authority assignments do
	# not, so every copy of this player works out the same owner without being
	# told. A name that is not a peer id, such as a Player dropped into a scene
	# by hand, leaves the default authority alone.
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
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye

	# A fallback for a Player placed in a scene by hand. The spawner overwrites
	# this with teleport immediately after add_child.
	spawn_point = global_position

	# Sub-resources in a scene are shared by every instance of it unless they
	# are marked local to the scene, so without this every player would collide
	# with the same cylinder and one person crouching would shrink everybody
	# else's hull. Duplicated here rather than ticking a box in the inspector,
	# because this is where the reason can be written down.
	collider.shape = collider.shape.duplicate()
	hull = collider.shape
	clearance.shape = clearance.shape.duplicate()

	# Set here rather than left to _update_pose, which only the local player
	# runs. Without it a remote body keeps whatever height player.tscn happens
	# to store, and its collider stops matching what is drawn.
	hull.height = STAND_HEIGHT
	collider.position.y = STAND_HEIGHT * 0.5

	clearance.add_exception(self)
	var box := clearance.shape as BoxShape3D
	var w := (hull.radius - 0.02) * 2.0
	box.size = Vector3(w, 1.0, w)

	add_to_group("blastable")

	if is_local_player():
		_setup_local()
	else:
		_setup_remote()


## Whether this instance belongs to the peer running it.
##
## Asked explicitly rather than calling [method Node.is_multiplayer_authority]
## everywhere, because that compares against the peer's unique id and there is
## no peer at all in single player. Offline the only player in the scene is
## ours, so the answer is yes.
func is_local_player() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


## Setup only the owning peer runs. Everything here has a process-wide effect,
## so a second instance running it would fight the first.
func _setup_local() -> void:
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_vsync()
	_apply_fps_cap()


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
## and needs nothing, which is why nothing like this is in player.tscn.
##
## Scaffolding until there is a real model to load, so it is built in code
## rather than added to the scene: it costs nothing to delete later, and it
## cannot be mistaken for the real thing in the editor.
func _build_placeholder_body() -> void:
	# A cylinder rather than a capsule, so what is drawn is the hull that is
	# actually there. A placeholder that lies about its own shape is worse than
	# no placeholder.
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
## [method CharacterBody3D.is_on_floor] reports the result of the last
## [method CharacterBody3D.move_and_slide], so anything that changes velocity
## after the move is invisible to it for a full tick. An explosion is exactly
## that: the rocket resolves after the player has already moved, so the impulse
## lands while the floor contact still reads as true, and the next tick's
## GROUND branch zeroes the vertical component before it is ever used.
##
## Source has the same ordering problem and solves it in CategorizePosition by
## skipping the ground trace whenever vertical velocity is above
## NON_JUMP_VELOCITY. Every place that asks about ground contact goes through
## here, so the duck transition and the origin shift agree with the state
## machine about which one is happening.
func _grounded() -> bool:
	return is_on_floor() and velocity.y <= NON_JUMP_SPEED


## Restores the player to the spawn point and clears every piece of transient
## state. Anything that persists across a respawn is a bug.
func respawn() -> void:
	_set_noclip(false)

	# Input history, not just input. Leaving crouch_wanted set meant respawning
	# while crouched in toggle mode re-ducked you a tick later, and leaving
	# prev_buttons set meant a held key could read as a fresh press.
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
## clearing state that was never set, and because it removes the old ordering
## trap where the spawn position had to be assigned before add_child.
func teleport(to: Vector3) -> void:
	global_position = to
	curr_eye = to + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye


# ================================================================= loops ===


## Mouse deltas are accumulated here and consumed in [method _process], so the
## view turns at monitor rate rather than tick rate.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative


## Draws whichever kind of player this is.
##
## Ours renders the view: rotation is applied at frame rate so mouse look stays
## sharp, and position is interpolated between the last two physics samples.
## This mirrors Source's split between ExtraMouseSample and CreateMove, where
## the rendered angle leads the simulated one while the command still carries a
## single angle per tick.
##
## Somebody else's plays back from the state buffer instead. Both are the same
## idea, that drawing happens at frame rate over samples taken at tick rate.
## They differ only in how far behind the samples are and where they came from.
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
	_sample_input()

	if noclip_toggle:
		if _just_pressed(IN_NOCLIP):
			_set_noclip(not noclip)
	else:
		_set_noclip(cmd.pressed(IN_NOCLIP))

	if noclip:
		_move_noclip(delta)
		prev_eye = curr_eye
		curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
		_broadcast_state()
		return

	# Source splits gravity across the move: half before, half after. Applying
	# it all up front costs roughly v*dt/2 of jump apex.
	velocity.y -= sv_gravity_units * U * 0.5 * delta

	jump_time = maxf(jump_time - delta, 0.0)
	if _grounded():
		crouch_shifted = false

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_update_crouch(delta)
	_update_state(delta, flat_speed)
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
			_apply_friction(delta)
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
	prev_eye = curr_eye
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)

	if weapon != null and weapon.has_method("update"):
		weapon.update(delta, self, _aim_basis(), curr_eye, cmd.pressed(IN_ATTACK))

	_broadcast_state()


# =============================================================== network ===


## Publishes what this player looks like right now.
##
## Sent from the tick loop so every state carries the tick it was true on,
## which is what lets the receiver rebuild a timeline instead of a pile of
## positions. What goes out is the result of the simulation, not its input:
## remote bodies display, they do not simulate, so they need the hull height
## that came out of the stance machine rather than the crouch key that went in.
##
## Velocity is deliberately absent. Nothing on the receiving end extrapolates,
## so nothing needs it. It goes in when animation wants it and not before.
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


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_state(tick: int, pos: Vector3, yaw: float, pitch: float,
		hull_h: float, eye_h: float, state: int) -> void:
	# Only the peer that owns this body may say where it is. Declared
	# "any_peer" with the check written out, rather than "authority", because a
	# client's packet reaches the other clients by being relayed through the
	# server, and this is the rule worth being able to read.
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
## the job is to produce a position for every frame drawn, not for every tick
## simulated. A remote player interpolated at tick rate would be exactly as
## steppy as one that was not interpolated at all.
func _draw_remote(delta: float) -> void:
	net.advance(delta)
	var s := net.sample()
	if s == null:
		return

	global_position = s.position
	rotation.y = s.yaw
	view_yaw = s.yaw
	view_pitch = s.pitch
	move_state = s.move_state

	# Kept in step with the drawn hull so a crouching player is not shot
	# through the head they no longer have there.
	hull.height = s.hull_height
	collider.position.y = s.hull_height * 0.5

	eye_height = s.eye_height
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye

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

	# The menu does not stop the world in a session, so the simulation keeps
	# running underneath it. An empty command is what standing still means
	# here: friction brings you to a halt, gravity still applies, nothing
	# fires, and noclip cannot be toggled from behind the menu. The tick keeps
	# counting, because the command stream has no gap in it either.
	#
	# The button history is cleared with it, so holding a key through the menu
	# does not read as a fresh press on the way out.
	if menu_open:
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


## Source's Friction. Scales the whole velocity vector, so it slows you down
## without ever turning you.
func _apply_friction(delta: float) -> void:
	var speed := velocity.length()
	if speed < 0.01:
		return

	# The floor under `control` is what makes you actually stop. Without it
	# the decay is exponential and you creep forever.
	var control := maxf(speed, sv_stopspeed_units * U)
	var drop := control * sv_friction * delta
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
	hull.height = CROUCH_HEIGHT
	collider.position.y = CROUCH_HEIGHT * 0.5
	if not _grounded():
		global_position.y += HULL_SHIFT
		crouch_shifted = true


## Applies the standing hull, undoing an origin shift only if this duck was
## the one that created it. Branching on ground contact instead would let you
## give back a shift you never took.
func _finish_unduck() -> void:
	is_crouched = false
	hull.height = STAND_HEIGHT
	collider.position.y = STAND_HEIGHT * 0.5
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


## Applies the slide pose on top of the duck stance and writes the final hull
## height and eye position. This is the only place either is set.
func _update_pose(delta: float) -> void:
	var target := 1.0 if move_state == Move.SLIDE else 0.0
	# Ending a slide under low geometry keeps you pinned until you are clear.
	if target < slide_pose and not _headroom_clear():
		target = slide_pose
	slide_pose = move_toward(slide_pose, target, SLIDE_POSE_RATE * delta)

	var h := _hull_height()
	hull.height = h
	collider.position.y = h * 0.5

	eye_height = lerpf(stance_eye, SLIDE_EYE, slide_pose) + view_offset


# ================================================================= slide ===


## Whether a slide may start. From the air the crouch key only needs to be
## held; from the ground it needs a recent press, so holding crouch while
## walking does not repeatedly re-slide.
func _can_slide(flat_speed: float, from_air: bool) -> bool:
	if flat_speed < slide_entry_speed_units * U or slide_cooldown > 0.0:
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
		var speed := velocity.length()
		if speed > 0.01:
			var control := maxf(speed, sv_stopspeed_units * U)
			var drop := control * SLIDE_FRICTION * delta
			velocity *= maxf(speed - drop, 0.0) / speed

	var before := Vector2(velocity.x, velocity.z).length()
	if before > 0.01 and wish_dir.length_squared() > 0.0:
		_accelerate(wish_dir, sv_maxspeed_units * U, slide_steer_cap_units * U, sv_airaccelerate, delta)
		var after := Vector2(velocity.x, velocity.z).length()
		if after > 0.01:
			velocity.x *= before / after
			velocity.z *= before / after


# ================================================================== surf ===


## Surf movement. Steering authority fades in with speed, so a ramp cannot be
## climbed from a standstill but rewards arriving fast.
func _move_surf(wish_dir: Vector3, delta: float) -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed < SURF_MIN_SPEED:
		return
	var t := clampf((flat_speed - SURF_MIN_SPEED) / (SURF_MIN_SPEED * 2.0), 0.0, 1.0)
	_accelerate(wish_dir, SURF_RATE_SPEED, surf_speed_cap_units * U * t, SURF_ACCELERATE, delta)


# ========================================================= state machine ===


## Decides which state the player is in. Only transitions happen here;
## the movement for each state runs in [method _physics_process].
func _update_state(delta: float, flat_speed: float) -> void:
	slide_buffer = maxf(slide_buffer - delta, 0.0)
	slide_cooldown = maxf(slide_cooldown - delta, 0.0)
	var grounded := _grounded()

	match move_state:
		Move.GROUND:
			if not grounded:
				move_state = Move.AIR
			elif _can_slide(flat_speed, false):
				_enter_slide()
		Move.AIR:
			if grounded:
				_land(flat_speed)
			elif on_ramp:
				move_state = Move.SURF
		Move.SURF:
			if grounded:
				_land(flat_speed)
			elif not on_ramp:
				move_state = Move.AIR
		Move.SLIDE:
			slide_time -= delta
			if not grounded:
				_exit_slide()
				move_state = Move.AIR
			elif slide_time <= 0.0 or flat_speed < SLIDE_EXIT_SPEED or not crouch_wanted:
				_exit_slide()
				move_state = Move.GROUND


## Shared by AIR and SURF so landing off a ramp behaves the same as landing
## off a jump, including converting into a slide.
func _land(flat_speed: float) -> void:
	if _can_slide(flat_speed, true):
		_enter_slide()
	else:
		move_state = Move.GROUND


# ================================================================= speed ===


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return true if auto_sprint else cmd.pressed(IN_SPRINT)


## Applies the frame cap for the current context. Called from the property
## setters, so dragging a slider takes effect immediately.
##
## Guarded because the cap belongs to the process, not to a player. Without it
## a remote instance carrying a scene-stored override would reset the local
## player's cap on spawn.
##
## The play cap is dropped while vsync is on. Two limiters running at once beat
## against each other and the result is uneven frame times, which matters more
## here than in most games: the camera lerps on the physics interpolation
## fraction every frame, so irregular frames turn straight into visible
## stepping. With vsync on the refresh rate is already the cap.
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


## Aim orientation from the command angles, not the rendered camera. The camera
## leads the simulation between ticks, so using it would make shots depend on
## frame rate.
func _aim_basis() -> Basis:
	return Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0))


## Adds an explosion impulse. Force falls off linearly to zero at the radius
## edge and is applied along the vector from the blast to the hull centre.
##
## Existing velocity is kept rather than replaced, which is what makes rocket
## jumps chain. Leaving the ground here matters too: staying in GROUND would
## run friction on the next tick and eat most of the impulse.
func apply_blast(origin: Vector3, force_units: float, radius_units: float) -> void:
	# Only the peer that owns this body may push it. A remote instance would
	# take the impulse into a velocity nothing integrates, then have its
	# position overwritten by the next state packet anyway.
	#
	# The consequence is that explosions do not cross the network yet: your
	# rocket moves you and nobody else. That needs the blast itself to be sent,
	# not the result of it, so each owner applies its own.
	if not is_local_player():
		return

	var radius := radius_units * U
	var centre := global_position + Vector3(0.0, _hull_height() * 0.5, 0.0)
	var offset := centre - origin
	var dist := offset.length()
	if dist >= radius:
		return

	var dir := offset.normalized() if dist > 0.001 else Vector3.UP
	velocity += dir * force_units * U * (1.0 - dist / radius)

	if move_state != Move.AIR:
		move_state = Move.AIR
		# Opens the instant duck window, so crouching straight after a rocket
		# jump gains height the same way it does after a normal jump.
		jump_time = JUMP_WINDOW


## Jump velocity for the configured height, from v = sqrt(2 * g * h). Derived
## rather than stored so gravity and jump height cannot drift apart.
func _jump_impulse() -> float:
	return sqrt(2.0 * sv_gravity_units * U * jump_height_units * U)


## Ducked movement is a third of normal, matching TF2, rather than a fixed
## speed. The value feeds both ground acceleration and the air rate.
func _current_max_speed() -> float:
	var base := sv_maxspeed_units * U if _is_sprinting() else sv_walkspeed_units * U
	return base / 3.0 if is_crouched else base


# ================================================================ noclip ===


func _set_noclip(on: bool) -> void:
	if on == noclip:
		return
	noclip = on
	collider.disabled = on

	# Zeroed in both directions. Leaving noclip used to keep whatever the fly
	# code last wrote, which is 500 units per second, or 1500 while sprinting,
	# so the collider came back and you were launched.
	velocity = Vector3.ZERO

	# Entering, so the state machine is not left reporting a slide it has
	# stopped simulating. Leaving, so the normal ground check resolves where
	# you actually are rather than trusting a contact from before the flight.
	move_state = Move.AIR
	slide_time = 0.0
	slide_cooldown = 0.0
	slide_buffer = 0.0


## Flies along the aim basis rather than the body's, so you move where you are
## looking including up and down.
##
## The basis comes from the command angles, not from the camera. The camera is
## written at render rate and leads the simulation, so reading it here would
## make how far you fly per tick depend on frame rate.
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
