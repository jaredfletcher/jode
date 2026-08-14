class_name Hud
extends CanvasLayer

## Read off the enum rather than written out again, so the names cannot drift
## from the states they label.
var state_names := Player.Move.keys()

## Assigned through [method setup] rather than exported. The player is spawned
## at runtime, so there is no NodePath in the world scene to bake.
var player: Player = null

@onready var fps_label: Label = $VBoxContainer/FPSLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var state_label: Label = $VBoxContainer/StateLabel
@onready var health_label: Label = $VBoxContainer/HealthLabel


## Health is drawn from its signal rather than read every frame, so this file is
## a stand-in for whatever ends up showing it. A wristwatch or a walkie talkie
## subscribes to the same signal and this one is deleted, with nothing in Health
## or Player needing to change.
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


func _process(_delta: float) -> void:
	fps_label.text = "%3d fps" % Engine.get_frames_per_second()
	if player == null:
		return
	speed_label.text = "%4.0f u/s" % (player.flat_speed() / Player.U)
	state_label.text = state_names[player.move_state]
