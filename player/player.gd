class_name Player
extends CharacterBody3D

## First-person player with Source engine movement.
##
## The simulation runs on the physics tick and only reads from [member cmd], so
## the same commands from the same starting state always give the same result.
## The camera is detached from the body and interpolated at render rate.
##
## Distances are in metres. Constants are written as Source units times
## [constant U] so they can be checked against Source cvars directly. Friction
## and acceleration rates are unitless and carry over unchanged.

signal hurt(amount: float, inflictor: Node3D)
signal died(inflictor: Node3D)
signal respawned

enum Move {
	GROUND,  ## Walkable ground. Friction and full acceleration.
	AIR,     ## Airborne. Air acceleration only, which is what allows strafe jumping.
	SLIDE,   ## Crouch slide. Low friction, speed-preserving steering.
	SURF,    ## On a surface too steep to stand on.
}

## One Source unit (an inch) in metres.
const U := 0.0254

# Button bits packed into Cmd.buttons.
const IN_JUMP := 1
const IN_CROUCH := 2
const IN_SPRINT := 4
const IN_NOCLIP := 8
const IN_ATTACK := 16

# Hull and stance
const STAND_HEIGHT := 83.0 * U
const CROUCH_HEIGHT := 62.0 * U
const HULL_DELTA := STAND_HEIGHT - CROUCH_HEIGHT
## How far the origin moves up when a duck finishes in the air. The feet come up
## instead of the head going down, which is where crouch-jump height comes from.
const HULL_SHIFT := HULL_DELTA
const STAND_EYE := 68.0 * U
## Chosen so the eye drop cancels HULL_SHIFT exactly and an air duck looks seamless.
const CROUCH_EYE := STAND_EYE - HULL_DELTA
const TIME_TO_DUCK := 0.4
const TIME_TO_UNDUCK := 0.2
## For this long after a jump, crouching completes instantly.
const JUMP_WINDOW := 0.51

# Slide
const SLIDE_TIME := 1.4
const SLIDE_COOLDOWN := 0.35
const SLIDE_EXIT_SPEED := 120.0 * U
## Crouch presses are remembered this long, so pressing just before landing
## still turns the landing into a slide.
const SLIDE_BUFFER := 0.15
## No friction for this long at the start of a slide. Short slides are free,
## long ones cost speed.
const SLIDE_GRACE := 0.45
const SLIDE_FRICTION := 0.6
const SLIDE_HEIGHT := 40.0 * U
const SLIDE_EYE := 32.0 * U
## Blend rate between crouch and slide hull height. Kept fast so the pose has
## settled before an air duck can shift the origin.
const SLIDE_POSE_RATE := 20.0
## Extra floor snap while sliding so fast slides stay down on downslopes.
const SLIDE_SNAP := 0.5
const DEFAULT_SNAP := 0.1

# Surf
## Below this speed a ramp gives no steering, so it can't be climbed from a standstill.
const SURF_MIN_SPEED := 150.0 * U
## Sized so the speed cap is always the limiting factor, as in Source.
const SURF_RATE_SPEED := 320.0 * U
const SURF_ACCELERATE := 100.0

# View
## Source's m_yaw: degrees of turn per mouse count, before sensitivity.
const M_YAW := 0.022
## Decay rate of view_offset, which hides hull teleports from the camera.
const VIEW_SMOOTH := 3.0
## Just short of vertical so the forward vector never lines up with the up axis.
const PITCH_LIMIT := deg_to_rad(89.0)

# Noclip
const NOCLIP_SPEED := 500.0 * U
const NOCLIP_FAST := 3.0

## Source's NON_JUMP_VELOCITY. Moving up faster than this always counts as
## airborne, whatever the floor check says.
const NON_JUMP_SPEED := 140.0 * U

## Speed into a surface, in m/s, below which it doesn't count as pushing into it.
## Keeps float noise from reading as contact.
const CLIP_EPSILON := 0.001

# Blast knockback, following TF2. Push is in units per second per point of
# damage, so knockback always scales with damage and can't be tuned separately.
const BLAST_PUSH_UNITS := 6.0
const BLAST_PUSH_SELF_GROUND_UNITS := 5.0
## Self blasts in the air push harder and hurt less (see BLAST_SELF_AIR_DAMAGE),
## which is why you jump before firing.
const BLAST_PUSH_SELF_AIR_UNITS := 10.0
const BLAST_SELF_AIR_DAMAGE := 0.6
## Push multiplier while crouched. TF2 calls this a volume ratio.
const BLAST_CROUCH_RATIO := 1.49091
## Most speed a single blast can add.
const BLAST_MAX_UNITS := 1000.0
## The push is aimed from this far below the blast so explosions lift you
## instead of shoving you flat (CTFPlayer::OnTakeDamage_Alive).
const BLAST_ORIGIN_DROP_UNITS := 10.0
## Distance over which splash damage to other players falls off.
const BLAST_FALLOFF_UNITS := 1024.0
## Fraction of centre damage kept at the edge of the radius.
const BLAST_EDGE_DAMAGE := 0.5

## Seconds dead before respawning.
const DEATH_TIME := 3.0

## Send a state every N ticks. StateBuffer.INTERP_TICKS has to stay above twice
## this or remote playback runs dry between packets.
const SEND_EVERY := 1


## One tick of player input. The only thing the movement simulation reads.
class Cmd:
	var wish := Vector2.ZERO  ## Movement axes. x is right, y is back.
	var buttons := 0          ## IN_* bit flags.
	var yaw := 0.0
	var pitch := 0.0
	var tick := 0

	func pressed(bit: int) -> bool:
		return (buttons & bit) != 0


@export_group("Options")
@export var sensitivity: float = 3.0
@export var auto_bhop: bool = true
@export var auto_sprint: bool = true
@export var crouch_toggle: bool = false
@export var noclip_toggle: bool = false
## Ignore crouch presses while standing back up, like TF2. Stops crouch spam.
## Releasing crouch mid-duck still stands you up right away.
@export var duck_latch: bool = true

# Anything ending in _units is in Source units and needs * U where it's used.
@export_group("Base Movement")
## Downward acceleration in units/s^2.
@export var sv_gravity_units: float = 800.0
## Apex of a standing jump in units. The jump impulse is derived from this and
## gravity, so changing either keeps the height right.
@export var jump_height_units: float = 45.0
## Full running speed.
@export var sv_maxspeed_units: float = 320.0
## Speed when not sprinting.
@export var sv_walkspeed_units: float = 190.0
## How quickly ground movement reaches full speed.
@export var sv_accelerate: float = 10.0
## How quickly ground movement bleeds off speed.
@export var sv_friction: float = 4.0
## Below this speed friction decelerates at a constant rate, so you actually stop.
@export var sv_stopspeed_units: float = 100.0
## Air acceleration rate. Has no effect while the air speed cap is the limit,
## which it is at default values.
@export var sv_airaccelerate: float = 10.0

@export_group("Tuning")
## Most speed added per tick while air strafing. Source default is 30.
@export var air_speed_cap_units: float = 100.0
## Most speed added per tick while strafing on a ramp.
@export var surf_speed_cap_units: float = 100.0
## Turn authority while sliding. Matches air strafing at the same value.
@export var slide_steer_cap_units: float = 100.0
## Minimum ground speed to start a slide.
@export var slide_entry_speed_units: float = 200.0
## Speed added when a slide starts.
@export var slide_boost_units: float = 60.0
## Ceiling for the slide boost. Zero means no cap. Never reduces speed you already had.
@export var slide_speed_cap_units: float = 0.0

@export_group("Video")
## Frame rate cap during play. Zero is uncapped. CS2 defaults to 400.
@export var fps_max: float = 400.0:
	set(value):
		fps_max = value
		_apply_fps_cap()
## Frame rate cap while the pause menu is open. CS2 defaults to 120.
@export var fps_max_ui: float = 120.0:
	set(value):
		fps_max_ui = value
		_apply_fps_cap()
## Off by default for input latency. Uneven frame pacing with vsync off can
## bring back a little camera stepping.
@export var vsync: bool = false:
	set(value):
		vsync = value
		_apply_vsync()

## Placeholder meshes, only built for remote players.
var body_mesh: MeshInstance3D = null
var nose_mesh: MeshInstance3D = null

## States received for a remote player. Unused on the local player.
var net := StateBuffer.new()

var cmd := Cmd.new()
var prev_buttons := 0
var mouse_delta := Vector2.ZERO

## Seconds left until respawn. Zero while alive.
var death_time := 0.0
var spawn_point := Vector3.ZERO

# View
## Updated every frame, copied into cmd once per tick.
var view_yaw := 0.0
var view_pitch := 0.0
## Eye height above the origin, and the two samples the camera lerps between.
var eye_height := 0.0
var prev_eye := Vector3.ZERO
var curr_eye := Vector3.ZERO
## Cancels hull teleports so the eye moves smoothly. Decays to zero.
var view_offset := 0.0
## Set by the pause menu. Blocks input and switches to the menu frame cap.
var menu_open := false

# Movement
var move_state := Move.AIR
var noclip := false
var jump_time := 0.0
## cos(floor_max_angle), cached since it's needed every tick.
var floor_cos := 0.0
## Touched a surfable ramp during the last move. Read on the next tick, same
## timing as is_on_floor().
var on_ramp := false
## How far the body really moved over the last tick, per second. Unlike velocity,
## this is what happened rather than what was asked for.
var actual_velocity := Vector3.ZERO

# Stance
var is_crouched := false     ## True once a duck transition has completed.
var crouch_wanted := false   ## Crouch intent. Differs from the button in toggle mode.
var crouch_prev := false     ## Last tick's crouch_wanted, for edge detection.
var crouch_shifted := false  ## An air duck raised the origin and unducking must undo it.
var duck_progress := 0.0     ## 0 standing, 1 crouched.
var duck_target := 0.0
var pending_shift := 0.0     ## Origin shift the current transition will apply.
var stance_eye := 0.0        ## Eye height from ducking, before the slide pose.

# Slide
var slide_time := 0.0
var slide_cooldown := 0.0
var slide_buffer := 0.0
var slide_pose := 0.0  ## 0 at crouch height, 1 at slide height.

@onready var health: Health = $Health
@onready var camera: Camera3D = %Camera3D
@onready var collider: CollisionShape3D = %CollisionShape3D
@onready var hull: CylinderShape3D = collider.shape
@onready var clearance: ShapeCast3D = %StandCheck
## Optional. Given the aim and eye position each tick through update().
@onready var weapon: Node = get_node_or_null("%Weapon")


#region Lifecycle

func _ready() -> void:
	# The spawner names each player after its owner's peer id. Names replicate,
	# so every peer works out the same authority without an extra message.
	var owner_id := name.to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)

	# Surfing is mostly near-parallel motion along steep faces, which the default
	# 15 degree threshold would stop dead.
	wall_min_slide_angle = 0.0
	floor_max_angle = deg_to_rad(45.57)  # sv_maxstandableangle
	floor_cos = cos(floor_max_angle)

	# The camera is placed in world space every frame.
	camera.top_level = true
	eye_height = STAND_EYE

	# Fallback for a Player placed in a scene by hand. The spawner overwrites both.
	spawn_point = global_position
	teleport(global_position)

	# Scene sub-resources are shared between instances. Without these copies,
	# one player crouching would shrink everyone's hull.
	collider.shape = collider.shape.duplicate()
	hull = collider.shape
	clearance.shape = clearance.shape.duplicate()

	# Remote players never run _update_pose, so set the hull here or they keep
	# whatever height player.tscn stores.
	_apply_hull(STAND_HEIGHT)

	clearance.add_exception(self)
	var box := clearance.shape as BoxShape3D
	var width := (hull.radius - 0.02) * 2.0
	box.size = Vector3(width, 1.0, width)

	add_to_group("blastable")
	hurt.connect(health.take_damage)
	health.died.connect(_on_died)

	if is_local_player():
		_setup_local()
	else:
		_setup_remote()


## Mouse motion is collected here and applied in _process, so the view turns at
## frame rate rather than tick rate.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative


## Local player: mouse look at frame rate, and the camera lerped between the last
## two tick positions (Source's ExtraMouseSample vs CreateMove split).
## Remote players: playback from the state buffer.
func _process(delta: float) -> void:
	if not is_local_player():
		_draw_remote(delta)
		return

	var deg_per_count := M_YAW * sensitivity
	view_yaw = wrapf(view_yaw - deg_to_rad(mouse_delta.x * deg_per_count), -PI, PI)
	view_pitch = clampf(view_pitch - deg_to_rad(mouse_delta.y * deg_per_count),
			-PITCH_LIMIT, PITCH_LIMIT)
	mouse_delta = Vector2.ZERO

	var frac := Engine.get_physics_interpolation_fraction()
	camera.global_position = prev_eye.lerp(curr_eye, frac)
	camera.global_rotation = Vector3(view_pitch, view_yaw, 0.0)


func _physics_process(delta: float) -> void:
	_update_death(delta)
	_sample_input()
	_update_noclip()

	var start := global_position
	if noclip:
		_move_noclip(delta)
	else:
		_move(delta)
	actual_velocity = (global_position - start) / delta

	_sample_eye()
	if not noclip:
		_update_weapon(delta)

	_broadcast_state()

#endregion


#region Setup

## True if this instance belongs to the peer running it. Checked by hand because
## is_multiplayer_authority() compares against a peer id that doesn't exist
## offline, where the only player is always ours.
func is_local_player() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


## Only the owning peer runs this. Everything here affects the whole process.
func _setup_local() -> void:
	multiplayer.peer_connected.connect(_on_peer_joined)
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_vsync()
	_apply_fps_cap()


## Remote players keep their collider so projectiles can hit them, but don't
## simulate. Their camera is cleared explicitly because a camera entering a
## viewport with no current camera takes over, which happens whenever a remote
## player spawns before the local one.
func _setup_remote() -> void:
	camera.current = false
	set_physics_process(false)
	set_process_unhandled_input(false)
	_build_placeholder_body()


## Stand-in body until there's a player model: a cylinder matching the hull, and
## a nose so you can tell which way someone is facing.
func _build_placeholder_body() -> void:
	body_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = STAND_HEIGHT
	cylinder.top_radius = hull.radius
	cylinder.bottom_radius = hull.radius
	body_mesh.mesh = cylinder
	body_mesh.position.y = STAND_HEIGHT * 0.5
	add_child(body_mesh)

	nose_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.3)
	nose_mesh.mesh = box
	nose_mesh.position = Vector3(0.0, STAND_EYE, -hull.radius - 0.12)
	add_child(nose_mesh)

#endregion


#region Life and death

func is_alive() -> bool:
	return death_time <= 0.0


## Puts the player back at the spawn point with full health and clean state.
func respawn() -> void:
	_reset_state()
	teleport(spawn_point)
	health.reset()
	respawned.emit()
	_broadcast_health()


## Moves the player and resets both camera samples, so the render lerp doesn't
## sweep across the gap.
func teleport(to: Vector3) -> void:
	global_position = to
	curr_eye = to + Vector3(0.0, eye_height, 0.0)
	prev_eye = curr_eye


## The body stays in the world while dead. It keeps falling and colliding, it
## just stops taking input.
func _on_died(inflictor: Node3D) -> void:
	if not is_alive():
		return
	death_time = DEATH_TIME
	died.emit(inflictor)
	# TODO: spawn the drop bag from here.


## Runs before input is sampled, so the respawn tick is a fully live one.
func _update_death(delta: float) -> void:
	if is_alive():
		return
	death_time = maxf(death_time - delta, 0.0)
	if death_time <= 0.0:
		respawn()


## Clears all transient state. Anything that survives a respawn is a bug.
func _reset_state() -> void:
	death_time = 0.0
	_set_noclip(false)

	# Input history too: a stale crouch_wanted re-ducks you in toggle mode, and a
	# stale prev_buttons reads a held key as a new press.
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
	actual_velocity = Vector3.ZERO
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


## Advances the pair of eye positions the camera lerps between. Called once the
## body has finished moving for the tick.
func _sample_eye() -> void:
	prev_eye = curr_eye
	curr_eye = global_position + Vector3(0.0, eye_height, 0.0)

#endregion


#region Input

## Samples input into cmd once per tick. Sampling per frame would make press
## detection depend on frame rate.
func _sample_input() -> void:
	prev_buttons = cmd.buttons
	cmd.tick += 1
	cmd.yaw = view_yaw
	cmd.pitch = view_pitch
	rotation.y = view_yaw

	# The menu doesn't pause a networked game and death doesn't stop the
	# simulation, so both feed an empty command. Clearing prev_buttons means a key
	# held through either isn't read as a fresh press afterwards.
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

#endregion


#region Movement

## One tick of regular movement. Roughly Source's FullWalkMove.
func _move(delta: float) -> void:
	# Gravity is split half before and half after the move, as in Source.
	# Applying it all up front loses about v*dt/2 of jump height.
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
	var wants_jump := cmd.pressed(IN_JUMP) if auto_bhop else _just_pressed(IN_JUMP)

	# Jumping before friction runs is what keeps speed through a bunny hop.
	if (move_state == Move.GROUND or move_state == Move.SLIDE) and wants_jump:
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

	# Ground and slide block on walls to avoid stuttering against steep faces.
	# Air and surf need free sliding for strafe control.
	floor_block_on_wall = move_state == Move.GROUND or move_state == Move.SLIDE
	floor_snap_length = SLIDE_SNAP if move_state == Move.SLIDE else DEFAULT_SNAP

	move_and_slide()
	_clip_velocity()

	velocity.y -= sv_gravity_units * U * 0.5 * delta


## Horizontal speed of velocity, the speed the simulation is asking for.
func flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Horizontal speed the body really moved over the last tick.
func actual_speed() -> float:
	return Vector2(actual_velocity.x, actual_velocity.z).length()


## Ground check used everywhere instead of is_on_floor().
##
## is_on_floor() reflects the last move_and_slide(), so velocity added after the
## move (an explosion) would get zeroed by the next GROUND tick. Like Source's
## CategorizePosition, rising faster than NON_JUMP_SPEED always counts as airborne.
func _grounded() -> bool:
	return is_on_floor() and velocity.y <= NON_JUMP_SPEED


## Source's Friction. Scales the whole velocity, so it slows you without turning you.
func _apply_friction(delta: float, rate: float) -> void:
	var speed := velocity.length()
	if speed < 0.01:
		return

	# The stopspeed floor makes you actually stop instead of creeping forever.
	var control := maxf(speed, sv_stopspeed_units * U)
	var drop := control * rate * delta
	velocity *= maxf(speed - drop, 0.0) / speed


## Source's Accelerate and AirAccelerate. Pass INF as speed_cap for the ground version.
##
## The limit is checked against velocity projected onto wish_dir, not actual
## speed. Pushing sideways to your motion keeps that projection near zero, so
## speed keeps building. Strafe jumping, surfing and slide steering all come from this.
func _accelerate(wish_dir: Vector3, wish_speed: float, speed_cap: float, accel: float,
		delta: float) -> void:
	# Cap the budget but use the uncapped speed for the rate. Swapping these gives
	# air control that feels fine but never gains speed.
	var add_speed := minf(wish_speed, speed_cap) - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return

	velocity += wish_dir * minf(accel * wish_speed * delta, add_speed)


## Removes any part of velocity that runs into a surface the last move touched,
## following Source's TryPlayerMove. Also records whether a surfable ramp was touched.
##
## move_and_slide() stops the body at a surface but mostly leaves velocity alone,
## so without this a body pinned in a corner keeps its full speed while going
## nowhere, and slide entry, slide boost and anything else reading velocity
## sees speed that isn't real. Surfing also needs the vertical part clipped,
## which Godot deliberately skips on walls.
func _clip_velocity() -> void:
	on_ramp = false
	var planes: Array[Vector3] = []
	var pushing := false

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		for j in collision.get_collision_count():
			var normal := collision.get_normal(j)
			_add_plane(planes, normal)
			if _is_floor(normal):
				continue
			if normal.y > 0.01:
				on_ramp = true
			if velocity.dot(normal) < -CLIP_EPSILON:
				pushing = true

	# Floor contact alone is normal ground movement and stays with move_and_slide().
	if pushing:
		velocity = _clip_to_planes(velocity, planes)


## Clips v so it doesn't run into any of the planes.
##
## Tries each plane on its own first. That fails in an acute crease, where
## clearing one plane pushes back into the other, and the leftover velocity then
## builds up tick after tick. So when no single plane works, v follows the line
## where two planes meet, and with three or more it stops.
func _clip_to_planes(v: Vector3, planes: Array[Vector3]) -> Vector3:
	for plane in planes:
		# Floors only limit the result. Clipping against one would change how
		# ground movement runs up slopes.
		if _is_floor(plane):
			continue
		var clipped := v - plane * minf(v.dot(plane), 0.0)
		if _clear_of_planes(clipped, planes, plane):
			return clipped

	if planes.size() == 2:
		var crease := planes[0].cross(planes[1]).normalized()
		return crease * crease.dot(v)

	return Vector3.ZERO


## Whether v stays out of every plane except skip. A floor only blocks v going
## down into it; running along or up a floor is ordinary ground movement.
func _clear_of_planes(v: Vector3, planes: Array[Vector3], skip: Vector3) -> bool:
	for plane in planes:
		if plane == skip or v.dot(plane) >= -CLIP_EPSILON:
			continue
		if _is_floor(plane) and v.y >= -CLIP_EPSILON:
			continue
		return false
	return true


## Collisions often report the same surface more than once.
func _add_plane(planes: Array[Vector3], normal: Vector3) -> void:
	for plane in planes:
		if plane.dot(normal) > 0.99:
			return
	planes.append(normal)


func _is_floor(normal: Vector3) -> bool:
	return normal.y > floor_cos


func _is_sprinting() -> bool:
	if is_crouched:
		return false
	return auto_sprint or cmd.pressed(IN_SPRINT)


## v = sqrt(2gh), so gravity and jump height can't drift apart.
func _jump_impulse() -> float:
	return sqrt(2.0 * sv_gravity_units * U * jump_height_units * U)


## Crouched speed is a third of normal, as in TF2. Feeds both ground and air.
func _current_max_speed() -> float:
	var base := sv_maxspeed_units * U if _is_sprinting() else sv_walkspeed_units * U
	return base / 3.0 if is_crouched else base


## Aim from the command angles rather than the camera. The camera runs ahead of
## the simulation between ticks, so using it would make shots frame-rate dependent.
func _aim_basis() -> Basis:
	return Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0))


func _update_weapon(delta: float) -> void:
	if weapon != null and weapon.has_method("update"):
		weapon.update(delta, self, _aim_basis(), curr_eye, cmd.pressed(IN_ATTACK))

#endregion


#region State machine

## Decides which movement state applies. Only transitions happen here; the
## movement for each state runs in _move().
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


## Shared by AIR and SURF so landing off a ramp works like landing off a jump,
## including turning into a slide.
func _land(speed: float) -> void:
	if _can_slide(speed, true):
		_enter_slide()
	else:
		move_state = Move.GROUND

#endregion


#region Slide

## From the air, crouch only needs to be held. On the ground it needs a recent
## press, so holding crouch while walking doesn't keep re-sliding.
func _can_slide(speed: float, from_air: bool) -> bool:
	if speed < slide_entry_speed_units * U or slide_cooldown > 0.0:
		return false
	return crouch_wanted if from_air else slide_buffer > 0.0


func _enter_slide() -> void:
	move_state = Move.SLIDE
	slide_time = SLIDE_TIME
	slide_buffer = 0.0

	# Shrink the hull now rather than over the duck transition, since slides are
	# often used to get under something. The eye difference goes into
	# view_offset so only the collision snaps.
	if not is_crouched:
		view_offset += stance_eye - CROUCH_EYE
		stance_eye = CROUCH_EYE
		duck_progress = 1.0
		_finish_duck()
		pending_shift = 0.0

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	if speed > 0.01:
		var boosted := speed + slide_boost_units * U
		# The cap limits the boost only, never speed you arrived with.
		if slide_speed_cap_units > 0.0:
			boosted = minf(boosted, maxf(speed, slide_speed_cap_units * U))
		velocity.x = flat.x / speed * boosted
		velocity.z = flat.z / speed * boosted


func _exit_slide() -> void:
	slide_cooldown = SLIDE_COOLDOWN


## Friction is skipped during SLIDE_GRACE. Steering uses air acceleration, then
## rescales back to the original speed so strafing can't gain speed on the ground.
func _move_slide(wish_dir: Vector3, delta: float) -> void:
	velocity.y = 0.0

	if SLIDE_TIME - slide_time > SLIDE_GRACE:
		_apply_friction(delta, SLIDE_FRICTION)

	var before := flat_speed()
	if before > 0.01 and wish_dir.length_squared() > 0.0:
		_accelerate(wish_dir, sv_maxspeed_units * U, slide_steer_cap_units * U,
				sv_airaccelerate, delta)
		var after := flat_speed()
		if after > 0.01:
			velocity.x *= before / after
			velocity.z *= before / after

#endregion


#region Surf

## Steering fades in above SURF_MIN_SPEED, so a ramp rewards arriving fast.
func _move_surf(wish_dir: Vector3, delta: float) -> void:
	var speed := flat_speed()
	if speed < SURF_MIN_SPEED:
		return
	var authority := clampf((speed - SURF_MIN_SPEED) / (SURF_MIN_SPEED * 2.0), 0.0, 1.0)
	_accelerate(wish_dir, SURF_RATE_SPEED, surf_speed_cap_units * U * authority,
			SURF_ACCELERATE, delta)

#endregion


#region Stance

## Current hull height, including both the duck state and the slide pose.
func _hull_height() -> float:
	var base_height := CROUCH_HEIGHT if is_crouched else STAND_HEIGHT
	return lerpf(base_height, SLIDE_HEIGHT, slide_pose)


## Sets the hull height and keeps the collider centred on it. Skips the write
## when nothing changed, since resizing a shape rebuilds it in the physics server.
func _apply_hull(height: float) -> void:
	if hull.height == height and collider.position.y == height * 0.5:
		return
	hull.height = height
	collider.position.y = height * 0.5


func _set_clearance(height: float, center_y: float) -> void:
	(clearance.shape as BoxShape3D).size.y = height
	clearance.position.y = center_y


## Whether the hull can grow to this height. Only the slab above the current hull
## is tested, since the space it already fills is known to be clear.
func _fits(height: float) -> bool:
	var top := _hull_height()
	if height <= top:
		return true
	_set_clearance(height - top, (height + top) * 0.5)
	clearance.force_shapecast_update()
	return not clearance.is_colliding()


## After an air duck the origin was raised, so standing up grows the hull in both
## directions and the whole standing volume has to be tested.
func _can_stand() -> bool:
	if crouch_shifted:
		_set_clearance(STAND_HEIGHT, STAND_HEIGHT * 0.5 - HULL_SHIFT)
		clearance.force_shapecast_update()
		return not clearance.is_colliding()
	return _fits(STAND_HEIGHT)


func _headroom_clear() -> bool:
	return _fits(CROUCH_HEIGHT)


## Applies the crouched hull. In the air the origin moves up so the feet come up,
## which is how a crouch-jump clears a ledge.
func _finish_duck() -> void:
	is_crouched = true
	_apply_hull(CROUCH_HEIGHT)
	if not _grounded():
		global_position.y += HULL_SHIFT
		crouch_shifted = true


## Applies the standing hull, and only undoes an origin shift if this duck made
## one. Checking ground contact instead could give back a shift you never took.
func _finish_unduck() -> void:
	is_crouched = false
	_apply_hull(STAND_HEIGHT)
	if crouch_shifted:
		global_position.y -= HULL_SHIFT
	crouch_shifted = false


## Origin shift the current transition will apply when it completes.
func _pending_for(target: float) -> float:
	if target >= 1.0 and not is_crouched:
		return 0.0 if _grounded() else HULL_SHIFT
	if target <= 0.0 and is_crouched:
		return -HULL_SHIFT if crouch_shifted else 0.0
	return 0.0


## Source's SimpleSpline (smoothstep), applied to the duck fraction before it
## reaches the eye so the motion doesn't look mechanical.
func _simple_spline(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Advances the duck transition and sets stance_eye. The hull only changes when
## a transition completes.
func _update_crouch(delta: float) -> void:
	if crouch_toggle:
		if _just_pressed(IN_CROUCH):
			crouch_wanted = not crouch_wanted
	else:
		crouch_wanted = cmd.pressed(IN_CROUCH)

	# Buffer on intent rather than the button so toggle mode behaves the same.
	var crouch_edge := crouch_wanted and not crouch_prev
	crouch_prev = crouch_wanted
	if crouch_edge:
		slide_buffer = SLIDE_BUFFER

	# Inside the jump window a crouch completes instantly and takes the air shift.
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

	# The latch only blocks re-crouching while standing up. Releasing crouch
	# mid-duck still stands you up immediately.
	var latched := (duck_latch and duck_progress > 0.0 and duck_progress < 1.0
			and duck_target <= 0.0)
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

	# The eye leans toward the pending origin shift as the transition nears its
	# end. A completed transition moves the origin itself; any other change in
	# the pending shift goes into view_offset so the eye doesn't jump.
	var pending := _pending_for(target)
	var blend := 1.0 - absf(target - duck_progress)
	if not finished and pending != pending_shift:
		view_offset += (pending_shift - pending) * blend
	pending_shift = pending

	stance_eye = lerpf(STAND_EYE, CROUCH_EYE, _simple_spline(duck_progress)) + pending * blend


## Layers the slide pose over the duck stance, then writes the hull and eye.
## Runs after _update_crouch every tick.
func _update_pose(delta: float) -> void:
	var target := 1.0 if move_state == Move.SLIDE else 0.0
	# Ending a slide under low geometry keeps you down until there's room.
	if target < slide_pose and not _headroom_clear():
		target = slide_pose
	slide_pose = move_toward(slide_pose, target, SLIDE_POSE_RATE * delta)

	_apply_hull(_hull_height())

	eye_height = lerpf(stance_eye, SLIDE_EYE, slide_pose) + view_offset

#endregion


#region Noclip

func _update_noclip() -> void:
	if noclip_toggle:
		if _just_pressed(IN_NOCLIP):
			_set_noclip(not noclip)
	else:
		_set_noclip(cmd.pressed(IN_NOCLIP))


func _set_noclip(on: bool) -> void:
	if on == noclip:
		return
	noclip = on
	collider.disabled = on

	# Zeroed both ways, or leaving noclip at fly speed launches you.
	velocity = Vector3.ZERO

	# Restart from AIR either way and let the next ground check sort it out.
	move_state = Move.AIR
	slide_time = 0.0
	slide_cooldown = 0.0
	slide_buffer = 0.0


## Flies where you're looking, including up and down. Uses the command angles,
## not the camera, so distance per tick doesn't depend on frame rate.
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

#endregion


#region Blast

## Applies an explosion the way TF2 does.
##
## The weapon supplies damage and radius. Knockback is worked out here from the
## damage, since it depends on stance and ground contact. Velocity is added
## rather than replaced, so rocket jumps chain.
##
## Unlike TF2, a blast doesn't force you airborne. That falls out of
## NON_JUMP_SPEED in _grounded(), so a mostly sideways blast slides you instead.
func apply_blast(blast: Blast) -> void:
	# Only the owning peer moves its own body, so right now blasts only affect
	# the shooter.
	# TODO: send the Blast to each affected owner so explosions work across the network.
	if not is_local_player() or not is_alive():
		return

	var is_self := blast.inflictor == self
	var centre := blast_centre()
	var radius := (blast.self_radius_units if is_self else blast.radius_units) * U

	# Distance to the nearer of feet and centre, approximating TF2's nearest point
	# on the bounding box. A direct hit skips this and takes full damage.
	var dist := 0.0
	if blast.direct_hit != self:
		dist = minf(blast.origin.distance_to(global_position),
				blast.origin.distance_to(centre))
		if dist >= radius:
			return

	if not _blast_reaches(blast.origin, centre):
		return

	var edge_damage := blast.damage * BLAST_EDGE_DAMAGE
	var damage := clampf(remap(dist, 0.0, radius, blast.damage, edge_damage),
			edge_damage, blast.damage)

	var push := BLAST_PUSH_UNITS
	if is_self:
		if _grounded():
			push = BLAST_PUSH_SELF_GROUND_UNITS
		else:
			damage *= BLAST_SELF_AIR_DAMAGE
			push = BLAST_PUSH_SELF_AIR_UNITS
	elif blast.inflictor != null:
		damage *= _blast_falloff(blast.inflictor.global_position.distance_to(global_position))

	var crouch_ratio := BLAST_CROUCH_RATIO if is_crouched else 1.0
	var force := minf(damage * crouch_ratio * push, BLAST_MAX_UNITS) * U

	var from := blast.origin - Vector3(0.0, BLAST_ORIGIN_DROP_UNITS * U, 0.0)
	var dir := from.direction_to(centre)
	if dir.length_squared() < 0.001:
		dir = Vector3.UP

	velocity += dir * force

	if move_state != Move.AIR:
		move_state = Move.AIR
		# Opens the instant-duck window, same as a normal jump.
		jump_time = JUMP_WINDOW

	hurt.emit(damage, blast.inflictor)
	_broadcast_health()


## Roughly Source's WorldSpaceCenter. Blast direction and line of sight both aim
## here, so a crouched body gets pushed from lower down.
func blast_centre() -> Vector3:
	return global_position + Vector3(0.0, _hull_height() * 0.5, 0.0)


## Line of sight from the blast to this body. Relies on the rocket detonating a
## unit off the surface, since a ray starting exactly on a surface is unreliable.
func _blast_reaches(origin: Vector3, centre: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, centre)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Damage multiplier by shot distance, for hits on other players. A bit above 1
## at point blank, then decays, following TF2's distance curve.
func _blast_falloff(distance: float) -> float:
	var t := clampf(distance / (BLAST_FALLOFF_UNITS * U), 0.0, 1.0)
	return cubic_interpolate(1.25, 0.5, 0.25, 0.0, t)

#endregion


#region Networking

## Sends this player's state to everyone, tagged with the tick it was true on.
## Sends simulation results (hull and eye height) rather than inputs, since remote
## copies only display. No velocity yet because nothing extrapolates.
func _broadcast_state() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_local_player():
		return
	if SEND_EVERY > 1 and cmd.tick % SEND_EVERY != 0:
		return

	_receive_state.rpc(cmd.tick, global_position, view_yaw, view_pitch,
			hull.height, eye_height, move_state)


## Health is sent reliably and only when it changes, unlike position which is
## sent every tick and can afford to lose packets.
func _broadcast_health() -> void:
	if not multiplayer.has_multiplayer_peer() or not is_local_player():
		return
	_receive_health.rpc(health.current, health.maximum, death_time > 0.0)


## Health only goes out on change, so a new peer needs catching up directly.
func _on_peer_joined(id: int) -> void:
	_receive_health.rpc_id(id, health.current, health.maximum, death_time > 0.0)


# RPCs are "any_peer" with a manual sender check rather than "authority",
# because client packets reach other clients relayed through the server.

@rpc("any_peer", "call_remote", "reliable")
func _receive_health(value: float, max_value: float, dead: bool) -> void:
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return

	health.apply_remote(value, max_value)

	# Remote copies don't run the death timer. The owner sends the change back.
	death_time = DEATH_TIME if dead else 0.0


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_state(tick: int, pos: Vector3, yaw: float, pitch: float,
		hull_h: float, eye_h: float, state: int) -> void:
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


## Draws a remote player from the state buffer. Runs per frame, like the camera.
func _draw_remote(delta: float) -> void:
	net.advance(delta)
	var s := net.sample()
	if s == null:
		return

	rotation.y = s.yaw
	view_yaw = s.yaw
	view_pitch = s.pitch
	move_state = s.move_state as Move

	# Keep the collider matching the drawn stance so shots hit what you see.
	_apply_hull(s.hull_height)

	# teleport() collapses both camera samples onto the new spot.
	eye_height = s.eye_height
	teleport(s.position)

	# Scaled rather than resized, so the mesh isn't regenerated every frame.
	if body_mesh != null:
		body_mesh.scale.y = s.hull_height / STAND_HEIGHT
		body_mesh.position.y = s.hull_height * 0.5
	if nose_mesh != null:
		nose_mesh.position.y = s.eye_height
		nose_mesh.rotation.x = s.pitch

#endregion


#region Display

## Called by the pause menu.
func set_menu_open(open: bool) -> void:
	menu_open = open
	# Drop mouse motion that queued up while the cursor was being released.
	mouse_delta = Vector2.ZERO
	_apply_fps_cap()


## Applies the frame cap for the current context. Only the local player touches
## it, so a remote instance can't override it. The play cap is dropped under
## vsync because two limiters together cause uneven frame pacing.
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
	# The play cap depends on vsync, so reapply it.
	_apply_fps_cap()

#endregion
