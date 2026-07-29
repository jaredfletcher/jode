extends CanvasLayer

@export var player: Player

@onready var speed_label: Label = $Label


func _process(_delta: float) -> void:
	if player == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	speed_label.text = "%4.0f u/s" % (speed / Player.U)
