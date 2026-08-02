extends CanvasLayer

const STATE_NAMES := ["GROUND", "AIR", "SLIDE", "SURF"]

@export var player: Player

@onready var fps_label: Label = $VBoxContainer/FPSLabel
@onready var speed_label: Label = $VBoxContainer/SpeedLabel
@onready var state_label: Label = $VBoxContainer/StateLabel


func _process(_delta: float) -> void:
	fps_label.text = "%3d fps" % Engine.get_frames_per_second()
	if player == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed_label.text = "%4.0f u/s" % (speed / Player.U)
	state_label.text = STATE_NAMES[player.move_state]
