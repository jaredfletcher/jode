extends Node

## Spacewar, Valve's public test app. Real lobbies and real SDR, no fee.
## Everyone testing shows up as playing Spacewar.
const APP_ID := 480

var ready_to_use := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var result := Steam.steamInitEx(APP_ID, true)
	ready_to_use = result["status"] == Steam.STEAM_API_INIT_RESULT_OK
	if not ready_to_use:
		push_warning("Steam init failed: %s" % result["verbal"])
		return
	print("Steam ready, logged in as %s" % Steam.getPersonaName())

func _process(_delta: float) -> void:
	# Steam delivers everything through callbacks, and they only fire while
	# something pumps them. Nothing lobby-related works without this line.
	if ready_to_use:
		Steam.run_callbacks()
