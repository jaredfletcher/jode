class_name StateBuffer
extends RefCounted

## A timeline of states received from one other peer, played back on a delay.
##
## This is the whole answer to why remote players look smooth. Packets do not
## arrive on tick boundaries and do not arrive evenly, so assigning each one on
## receipt makes a body jump between positions rather than move between them.
## Instead every state is filed under the tick it was true on, and playback runs
## slightly behind the newest one, interpolating between the two samples that
## bracket the current playback time.
##
## The cost is that you see everyone a fixed distance in the past. The benefit
## is that every position drawn is one that actually happened. Nothing is ever
## guessed forward, so nothing ever has to be taken back, and taking it back is
## what reads as rubber banding.
##
## Source calls the delay cl_interp and defaults it to 100ms.


## Playback delay behind the newest received state, in sender ticks. The only
## real knob: too small and an ordinary late packet leaves nothing to draw, too
## large and everyone lags further behind where they actually are. Four ticks is
## around 60ms at 66, which absorbs a couple of dropped or bunched packets.
##
## Wants to stay above two send intervals. Raise Player.SEND_EVERY and this has
## to come up with it.
const INTERP_TICKS := 4.0

## Most the clock may run fast or slow to close a gap, as a fraction of real
## time. Small enough not to be readable as speeding up or slowing down.
const CATCHUP := 0.08

## Gain on the clock correction. Error is measured in ticks.
const CATCHUP_GAIN := 0.1

## Error past which nudging is pointless and the clock jumps. A stall or a
## hiccup, rather than ordinary jitter.
const RESYNC_TICKS := 30.0

## Ceiling on stored samples, so a stalled reader cannot grow without bound.
const MAX_SAMPLES := 64


## One received state.
##
## Deliberately the outputs of the sender's simulation rather than its inputs. A
## remote body is not simulating anything, it is showing what already happened
## somewhere else, so it wants the hull height that came out of the stance
## machine and not the crouch key that went in.
class State:
	var tick := 0
	var position := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var hull_height := 0.0
	var eye_height := 0.0
	var move_state := 0


var samples := []

## Current playback point, in sender ticks, fractional between them.
var play_time := 0.0

## Clear until the first state lands, so the clock starts on real data rather
## than winding up from zero.
var started := false


## Files a received state.
##
## Out of order arrivals are dropped rather than sorted. The channel is already
## unreliable_ordered, so anything late has been discarded before it gets here,
## and a state older than one already held has nothing to add to the timeline.
func push(s: State) -> void:
	if not samples.is_empty():
		var newest: State = samples.back()
		if s.tick <= newest.tick:
			return

	samples.append(s)
	if samples.size() > MAX_SAMPLES:
		samples.remove_at(0)


## Advances the playback clock by [param delta] real seconds.
##
## The clock free-runs at real time and is nudged toward the target rather than
## snapped onto it. Snapping every frame would put playback exactly where it
## belongs and still look terrible, because the target only moves when a packet
## lands, so the motion would inherit the arrival pattern of the network. This
## is the part that separates smooth from merely correct.
##
## Sender ticks and local ticks are the same unit because both peers run the
## project's physics rate. Read rather than stored, so there is no second copy
## of 66 to fall out of step with the project setting.
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

	# Never run past the newest thing held. There is nothing out there to draw,
	# and letting the clock wander into the future while a sender is stalled
	# only buys a jump when it comes back.
	play_time = minf(play_time, float(newest.tick))

	# Drop what the clock has passed, keeping the one sample still needed as the
	# left hand side of the current span.
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

	# Playback has run past everything held, so the next state has not arrived.
	# Hold on the newest rather than carry on along the last direction: a brief
	# stall reads better than sliding somewhere wrong and being yanked back when
	# the truth turns up.
	var last: State = samples.back()
	return last


## Angles go through lerp_angle because yaw is wrapped to +/- PI and a plain
## lerp takes the long way round the seam.
##
## move_state is not blended at all. It is a label rather than a quantity, and
## the label that held across the span is the one it started on.
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
