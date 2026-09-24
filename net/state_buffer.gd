class_name StateBuffer
extends RefCounted

## Snapshot interpolation for one remote player.
##
## Each received state is stored under the tick it happened on, and playback runs
## a few ticks behind the newest one, blending between the two states either side
## of the playback time. Remote players are shown slightly in the past, but
## everything drawn really happened, so there's nothing to correct and no rubber
## banding. Source calls this delay cl_interp (100ms by default).

## Playback delay behind the newest state, in ticks. Too small and a late packet
## leaves nothing to draw; too large and everyone lags further behind. Four ticks
## is about 60ms at 66 Hz. Keep it above twice Player.SEND_EVERY.
const INTERP_TICKS := 4.0

## Most the playback clock can speed up or slow down to close a gap, as a
## fraction of real time. Small enough not to be noticeable.
const CATCHUP := 0.08

## Gain on the clock correction, per tick of error.
const CATCHUP_GAIN := 0.1

## Past this much error the clock jumps instead of drifting. That's a stall,
## not ordinary jitter.
const RESYNC_TICKS := 30.0

## Cap on stored states so a stalled reader can't grow without bound.
const MAX_SAMPLES := 64


## One received state. These are the sender's simulation outputs (hull height,
## not the crouch key), since the remote copy only displays them.
class State:
	var tick := 0
	var position := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var hull_height := 0.0
	var eye_height := 0.0
	var move_state := 0


var samples: Array[State] = []

## Current playback time in sender ticks. Fractional between ticks.
var play_time := 0.0

## False until the first state arrives, so the clock starts from real data.
var started := false


## Stores a received state. Anything not newer than the latest held state is
## dropped. The channel is unreliable_ordered, so that should already be rare.
func push(s: State) -> void:
	if not samples.is_empty():
		var newest: State = samples.back()
		if s.tick <= newest.tick:
			return

	samples.append(s)
	if samples.size() > MAX_SAMPLES:
		samples.remove_at(0)


## Advances the playback clock by delta seconds.
##
## The clock runs at real time and gets nudged toward the target rather than
## snapped to it. The target only moves when a packet arrives, so snapping would
## make motion follow the network's arrival pattern.
##
## Sender and local ticks are the same unit because every peer runs the same
## physics tick rate.
func advance(delta: float) -> void:
	if samples.is_empty():
		return

	var newest: State = samples.back()
	var target := float(newest.tick) - INTERP_TICKS

	if not started or absf(target - play_time) > RESYNC_TICKS:
		play_time = target
		started = true
	else:
		var error := target - play_time
		var rate := 1.0 + clampf(error * CATCHUP_GAIN, -CATCHUP, CATCHUP)
		play_time += delta * float(Engine.physics_ticks_per_second) * rate

	# Never play past the newest state. There's nothing there to draw, and
	# drifting ahead during a stall just causes a jump when packets resume.
	play_time = minf(play_time, float(newest.tick))

	# Drop states the clock has passed, keeping one as the start of the current span.
	while samples.size() >= 2:
		var second: State = samples[1]
		if float(second.tick) > play_time:
			break
		samples.remove_at(0)


## The state to draw this frame, or null before anything has arrived.
func sample() -> State:
	if samples.is_empty():
		return null
	if samples.size() == 1:
		var only: State = samples[0]
		return only

	var from: State = samples[0]
	for i in range(1, samples.size()):
		var to: State = samples[i]
		if float(to.tick) >= play_time:
			var span := float(to.tick - from.tick)
			var t := 0.0
			if span > 0.0:
				t = clampf((play_time - float(from.tick)) / span, 0.0, 1.0)
			return _blend(from, to, t)
		from = to

	# Played past everything held. Hold the newest rather than extrapolating, since
	# a short freeze looks better than guessing wrong and snapping back.
	var last: State = samples.back()
	return last


## Angles use lerp_angle so yaw doesn't take the long way round at +/- PI.
## move_state is a label, not a quantity, so it isn't blended.
func _blend(from: State, to: State, t: float) -> State:
	var s := State.new()
	s.tick = from.tick
	s.position = from.position.lerp(to.position, t)
	s.yaw = lerp_angle(from.yaw, to.yaw, t)
	s.pitch = lerp_angle(from.pitch, to.pitch, t)
	s.hull_height = lerpf(from.hull_height, to.hull_height, t)
	s.eye_height = lerpf(from.eye_height, to.eye_height, t)
	s.move_state = from.move_state
	return s
