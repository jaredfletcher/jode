class_name Hud
extends CanvasLayer

const STATE_NAMES := ["GROUND", "AIR", "SLIDE", "SURF"]

## Assigned through [method setup] rather than exported. The player is spawned
## at runtime now, so there is no NodePath in the world scene to bake.
var player: Player = null

@onready var fps_label: Label = $VBoxContainer/FPSLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var state_label: Label = $VBoxContainer/StateLabel


func setup(p: Player) -> void:
	player = p


func _process(_delta: float) -> void:
	fps_label.text = "%3d fps" % Engine.get_frames_per_second()
	if player == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed_label.text = "%4.0f u/s" % (speed / Player.U)
	state_label.text = STATE_NAMES[player.move_state]
