extends Node

## Starts Steam at launch. Autoloaded as SteamManager.
##
## Nothing uses Steam yet beyond init. Lobbies and the Steam networking transport
## will build on this.

## Spacewar, Valve's public test app. Real lobbies and Steam Datagram Relay with
## no app fee, but everyone testing shows up as playing Spacewar.
const APP_ID := 480

var initialized := false


func _ready() -> void:
	# Second argument embeds callbacks, so GodotSteam calls run_callbacks() itself
	# every frame. No manual pump needed.
	var result := Steam.steamInitEx(APP_ID, true)
	initialized = result["status"] == Steam.STEAM_API_INIT_RESULT_OK
	if not initialized:
		push_warning("Steam init failed: %s" % result["verbal"])
		return
	print("Steam ready, logged in as %s" % Steam.getPersonaName())
