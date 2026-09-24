class_name Hud
extends CanvasLayer

## Debug readout: fps, speed, movement state and health.

var state_names := Player.Move.keys()

## Set by the world through setup(), since players spawn at runtime.
var player: Player = null

@onready var fps_label: Label = $VBoxContainer/FPSLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var state_label: Label = $VBoxContainer/StateLabel
@onready var health_label: Label = $VBoxContainer/HealthLabel


func _process(_delta: float) -> void:
	fps_label.text = "%3d fps" % Engine.get_frames_per_second()
	if player == null:
		return
	# Measured from how far the body moved, so it reads zero when you're stuck
	# even if velocity says otherwise.
	speed_label.text = "%4.0f u/s" % (player.actual_speed() / Player.U)
	state_label.text = state_names[player.move_state]


## Health is shown from its signal rather than polled, so this label can be
## swapped for an in-world display later without touching Health or Player.
func setup(p: Player) -> void:
	if player != null and is_instance_valid(player):
		player.health.health_changed.disconnect(_on_health_changed)

	player = p
	if player == null:
		health_label.text = ""
		return

	player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health.current, player.health.maximum)


func _on_health_changed(current: float, maximum: float) -> void:
	health_label.text = "%3.0f / %3.0f hp" % [current, maximum]
