class_name PauseMenu
extends CanvasLayer

## Pause menu, settings and key rebinding.
##
## Every setting is declared once in the tables below. Building the controls,
## resetting and saving all iterate those tables, so adding a setting is just a
## new entry. An entry's "group" is the tab it shows on and must match that tab's
## title in lower case.

## Emitted from the Multiplayer tab. The world decides what these mean.
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal leave_requested

## Boolean options, shown as CheckButtons.
const TOGGLES := [
	{
		"prop": "auto_bhop",
		"group": "gameplay",
		"label": "Auto Bunny Hop",
		"tip": "Hold jump to hop continuously instead of timing each press.",
	},
	{
		"prop": "auto_sprint",
		"group": "gameplay",
		"label": "Always Sprint",
		"tip": "Run at full speed without holding the sprint key.",
	},
	{
		"prop": "crouch_toggle",
		"group": "gameplay",
		"label": "Toggle Crouch",
		"tip": "Press crouch to switch stance instead of holding it.",
	},
	{
		"prop": "noclip_toggle",
		"group": "gameplay",
		"label": "Toggle Noclip",
		"tip": "Press noclip to switch it on or off instead of holding the key.",
	},
	{
		"prop": "vsync",
		"group": "base",
		"label": "Vertical Sync",
		"tip": "Locks the frame rate to your monitor's refresh. Removes tearing at the cost of input latency.",
	},
	{
		"prop": "duck_latch",
		"group": "gameplay",
		"label": "Crouch Spam Lock",
		"tip": "While standing up, crouch input is ignored until you are fully upright. Releasing crouch mid-duck still stands you up immediately.",
	},
]

## Numeric options, shown as a slider and spinbox pair. Entries sharing a
## "section" must be next to each other, since a header is added when it changes.
const SLIDERS := [
	{
		"prop": "sensitivity",
		"group": "controls",
		"label": "Mouse Sensitivity",
		"tip": "Mouse sensitivity, using the same scale as Source games.",
		"min": 0.5, "max": 10.0, "step": 0.01,
	},

	{
		"prop": "fps_max",
		"group": "base",
		"section": "Video",
		"label": "fps_max",
		"tip": "Frame rate cap during play. Zero is uncapped.",
		"min": 0.0, "max": 1000.0, "step": 10.0,
	},
	{
		"prop": "fps_max_ui",
		"group": "base",
		"section": "Video",
		"label": "fps_max_ui",
		"tip": "Frame rate cap while this menu is open. Stops the GPU rendering a static screen at full speed.",
		"min": 0.0, "max": 1000.0, "step": 10.0,
	},

	{
		"prop": "sv_gravity_units",
		"group": "base",
		"section": "World",
		"label": "sv_gravity",
		"tip": "Downward acceleration in units per second squared.",
		"min": 100.0, "max": 2000.0, "step": 10.0,
	},
	{
		"prop": "jump_height_units",
		"group": "base",
		"section": "World",
		"label": "Jump Height",
		"tip": "Apex of a standing jump in units. The jump impulse is derived from this and gravity, so changing either keeps the height correct.",
		"min": 10.0, "max": 120.0, "step": 1.0,
	},

	{
		"prop": "sv_maxspeed_units",
		"group": "base",
		"section": "Ground",
		"label": "sv_maxspeed",
		"tip": "Full running speed in units per second.",
		"min": 50.0, "max": 800.0, "step": 10.0,
	},
	{
		"prop": "sv_walkspeed_units",
		"group": "base",
		"section": "Ground",
		"label": "Walk Speed",
		"tip": "Speed used when not sprinting, in units per second.",
		"min": 50.0, "max": 800.0, "step": 10.0,
	},
	{
		"prop": "sv_accelerate",
		"group": "base",
		"section": "Ground",
		"label": "sv_accelerate",
		"tip": "How quickly ground movement reaches full speed.",
		"min": 1.0, "max": 100.0, "step": 1.0,
	},
	{
		"prop": "sv_friction",
		"group": "base",
		"section": "Ground",
		"label": "sv_friction",
		"tip": "How quickly ground movement bleeds off speed.",
		"min": 0.0, "max": 12.0, "step": 0.1,
	},
	{
		"prop": "sv_stopspeed_units",
		"group": "base",
		"section": "Ground",
		"label": "sv_stopspeed",
		"tip": "Speed below which friction decelerates at a constant rate, so you come to a full stop instead of creeping.",
		"min": 0.0, "max": 300.0, "step": 5.0,
	},

	{
		"prop": "sv_airaccelerate",
		"group": "base",
		"section": "Air",
		"label": "sv_airaccelerate",
		"tip": "Acceleration rate used in the air.",
		"min": 1.0, "max": 200.0, "step": 1.0,
	},
	{
		"prop": "air_speed_cap_units",
		"group": "base",
		"section": "Air",
		"label": "sv_air_max_wishspeed",
		"tip": "Maximum speed added per tick while air strafing. Controls how fast bunny hopping builds speed. Source default is 30.",
		"min": 5.0, "max": 150.0, "step": 1.0,
	},

	{
		"prop": "slide_entry_speed_units",
		"group": "gameplay",
		"section": "Slide",
		"label": "Slide Entry Speed",
		"tip": "Minimum ground speed required to start a slide.",
		"min": 0.0, "max": 400.0, "step": 5.0,
	},
	{
		"prop": "slide_boost_units",
		"group": "gameplay",
		"section": "Slide",
		"label": "Slide Boost",
		"tip": "Speed added at the moment a slide starts.",
		"min": 0.0, "max": 200.0, "step": 5.0,
	},
	{
		"prop": "slide_speed_cap_units",
		"group": "gameplay",
		"section": "Slide",
		"label": "Slide Speed Cap",
		"tip": "Upper limit the slide boost can reach. Zero disables the limit. Never reduces speed you already had.",
		"min": 0.0, "max": 800.0, "step": 10.0,
	},
	{
		"prop": "slide_steer_cap_units",
		"group": "gameplay",
		"section": "Slide",
		"label": "Slide Steering",
		"tip": "Turn authority while sliding, in units per tick. Matches air strafing when set to the same value as sv_air_max_wishspeed.",
		"min": 5.0, "max": 150.0, "step": 1.0,
	},

	{
		"prop": "surf_speed_cap_units",
		"group": "gameplay",
		"section": "Surf",
		"label": "sv_air_max_wishspeed (surf)",
		"tip": "Maximum speed added per tick while strafing on a ramp. Higher values build speed faster but let you climb ramps from a standstill.",
		"min": 5.0, "max": 150.0, "step": 1.0,
	},
]

## Rebindable actions, shown as a label, a bind button and a clear button.
const BINDABLE := [
	{"action": "move_forward", "label": "Move Forward"},
	{"action": "move_back", "label": "Move Back"},
	{"action": "move_left", "label": "Strafe Left"},
	{"action": "move_right", "label": "Strafe Right"},
	{"action": "jump", "label": "Jump"},
	{"action": "crouch", "label": "Crouch"},
	{"action": "sprint", "label": "Sprint"},
	{"action": "noclip", "label": "Noclip"},
	{"action": "attack", "label": "Attack"},
]

const CONFIG_PATH := "user://input.cfg"

const DEFAULT_ADDRESS := "joe.jared0.com"
const DEFAULT_PORT := 27015

## Pixels scrolled per wheel notch when the wheel lands on a slider.
const SCROLL_STEP := 48

## Type tags for saved binds.
const BIND_NONE := -1
const BIND_KEY := 0
const BIND_MOUSE := 1

## InputMap's "all devices" id. Rebound events use it so they match whatever
## device id the keyboard or mouse reports.
const ALL_DEVICES := -1

## Set by the world through setup(), since players spawn at runtime.
var player: Player = null

## Player settings as they were before the saved config was applied, so a reset
## goes back to real defaults rather than the last save.
var defaults := {}

## Input Map events from project.godot, captured once before any saved binds load.
var default_binds := {}

## Bind buttons by action, so one row can be relabelled without a rebuild.
var bind_buttons := {}

var listening_action := ""
var listening_button: Button = null
var confirm: ConfirmationDialog

@onready var tabs: TabContainer = %TabContainer
@onready var bind_list: VBoxContainer = %BindList
@onready var toggle_list: VBoxContainer = %ToggleList
@onready var reset_button: Button = %ResetButton

@onready var status_label: Label = %StatusLabel
@onready var address_field: LineEdit = %AddressField
@onready var port_field: LineEdit = %PortField

## Slider containers by group, matching the "group" field in SLIDERS.
@onready var slider_lists := {
	"controls": %SliderList,
	"gameplay": %GameplaySliderList,
	"base": %BaseSliderList,
}


func _ready() -> void:
	visible = false

	confirm = ConfirmationDialog.new()
	confirm.title = "Reset Settings"
	confirm.ok_button_text = "Reset"
	confirm.confirmed.connect(_do_reset)
	add_child(confirm)

	%ResumeButton.pressed.connect(_set_open.bind(false))
	%RespawnButton.pressed.connect(_on_respawn)
	%QuitButton.pressed.connect(_on_quit)
	reset_button.pressed.connect(_ask_reset)

	address_field.text = DEFAULT_ADDRESS
	port_field.text = str(DEFAULT_PORT)

	%HostButton.pressed.connect(func() -> void:
		host_requested.emit(_port())
	)
	%JoinButton.pressed.connect(func() -> void:
		join_requested.emit(address_field.text.strip_edges(), _port())
	)
	%LeaveButton.pressed.connect(func() -> void:
		leave_requested.emit()
	)

	tabs.tab_changed.connect(func(_i: int) -> void: _update_reset_label())
	_update_reset_label()

	# Runs before the world's _ready, so the Input Map is still untouched here.
	_capture_default_binds()


## Uses _input rather than _unhandled_input so a key pressed while rebinding is
## seen before a focused Button treats it as a click.
func _input(event: InputEvent) -> void:
	if listening_action != "":
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			_stop_listening()
			get_viewport().set_input_as_handled()
			return
		if (event is InputEventKey or event is InputEventMouseButton) \
				and event.is_pressed() and not event.is_echo():
			var action := listening_action
			listening_action = ""
			listening_button = null
			_assign(action, event)
			get_viewport().set_input_as_handled()
		# Swallow everything else while capturing a bind.
		return

	if event.is_action_pressed("ui_cancel"):
		_set_open(not visible)
		get_viewport().set_input_as_handled()


## Called by the world when the local player changes (or goes away).
func setup(p: Player) -> void:
	player = p

	# A player spawned while the menu is open captures the mouse, not knowing the
	# menu is there. Re-assert the menu's state.
	if player != null:
		player.set_menu_open(visible)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED

	# Defaults before the config overwrites them, controls after it's applied.
	_capture_default_settings()
	_load_config()
	_rebuild()


## Only pauses the tree when playing solo. Called by the world whenever a session
## starts or ends, since that changes the answer without the menu being touched.
func refresh_pause() -> void:
	get_tree().paused = visible and not multiplayer.has_multiplayer_peer()


## Called by the world to show what the session is doing.
func set_session_status(text: String) -> void:
	status_label.text = text


#region Open and close

## The local player stops taking input either way. The tree is only paused when
## nobody else is connected; pausing your own physics in a session would freeze
## you in everyone else's view (and stop the world for them on a listen server).
func _set_open(open: bool) -> void:
	_stop_listening()
	visible = open
	refresh_pause()
	if player != null:
		player.set_menu_open(open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


## Clearing the peer first sends a proper disconnect instead of making the other
## side wait for a timeout.
func _on_quit() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().quit()


func _on_respawn() -> void:
	if player != null:
		player.respawn()
	_set_open(false)

#endregion


#region Defaults and reset

## Every toggle and slider entry. Both carry "prop" and "group".
func _settings() -> Array:
	return TOGGLES + SLIDERS


func _capture_default_settings() -> void:
	if player == null:
		return
	for entry in _settings():
		defaults[entry.prop] = player.get(entry.prop)


func _capture_default_binds() -> void:
	for b in BINDABLE:
		var copies := []
		for e in InputMap.action_get_events(b.action):
			copies.append(e.duplicate())
		default_binds[b.action] = copies


## Appends the default value to a tooltip, read from the captured defaults so it
## can't drift from the export.
func _tip(prop: String, base: String) -> String:
	if not defaults.has(prop):
		return base
	var v = defaults[prop]
	var text := ""
	if v is bool:
		text = "on" if v else "off"
	elif v is float and is_equal_approx(v, roundf(v)):
		text = str(int(v))
	else:
		text = str(v)
	return "%s\n\nDefault: %s" % [base, text]


## The active tab's title in lower case, matching the "group" field.
func _current_group() -> String:
	return tabs.get_tab_title(tabs.current_tab).to_lower()


## Hides the reset button on tabs that have no settings.
func _update_reset_label() -> void:
	var group := _current_group()
	var resettable := group == "controls"
	for entry in _settings():
		if entry.group == group:
			resettable = true
			break

	reset_button.visible = resettable
	reset_button.text = "Reset %s" % tabs.get_tab_title(tabs.current_tab)


func _ask_reset() -> void:
	confirm.dialog_text = "Reset all %s settings to their defaults?" % _current_group()
	confirm.popup_centered()


## Resets the active tab only.
func _do_reset() -> void:
	var group := _current_group()

	if player != null:
		for entry in _settings():
			if entry.group == group:
				player.set(entry.prop, defaults[entry.prop])

	if group == "controls":
		for action in default_binds:
			InputMap.action_erase_events(action)
			for e in default_binds[action]:
				InputMap.action_add_event(action, e.duplicate())

	_save_config()
	_rebuild()

#endregion


#region Building controls

func _rebuild() -> void:
	_build_sliders()
	_build_toggles()
	_build_binds()


func _clear(list: Node) -> void:
	for child in list.get_children():
		child.queue_free()


func _build_toggles() -> void:
	_clear(toggle_list)
	if player == null:
		return

	for t in TOGGLES:
		var prop: String = t.prop
		var cb := CheckButton.new()
		cb.text = t.label
		cb.tooltip_text = _tip(prop, t.tip)
		cb.button_pressed = player.get(prop)
		cb.toggled.connect(func(on: bool) -> void:
			player.set(prop, on)
			_save_config()
		)
		toggle_list.add_child(cb)


func _build_sliders() -> void:
	for list in slider_lists.values():
		_clear(list)
	if player == null:
		return

	# Per group, so each tab gets its own section headers.
	var last_section := {}

	for s in SLIDERS:
		var target: VBoxContainer = slider_lists[s.group]
		var section: String = s.get("section", "")

		if section != "" and last_section.get(s.group, "") != section:
			if last_section.has(s.group):
				target.add_child(HSeparator.new())
			var section_label := Label.new()
			section_label.text = section
			section_label.add_theme_font_size_override("font_size", 16)
			target.add_child(section_label)
			last_section[s.group] = section

		var prop: String = s.prop
		var tip := _tip(prop, s.tip)

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var header := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = s.label
		name_label.tooltip_text = tip
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var spin := SpinBox.new()
		spin.min_value = s.min
		spin.max_value = s.max
		spin.step = s.step
		spin.value = player.get(prop)
		spin.custom_minimum_size.x = 90
		spin.select_all_on_focus = true
		spin.tooltip_text = tip
		spin.gui_input.connect(_block_scroll.bind(spin))

		var slider := HSlider.new()
		slider.min_value = s.min
		slider.max_value = s.max
		slider.step = s.step
		slider.value = player.get(prop)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = tip
		slider.gui_input.connect(_block_scroll.bind(slider))

		# Both are Ranges, so sharing keeps them in sync with one handler.
		slider.share(spin)
		slider.value_changed.connect(func(v: float) -> void:
			player.set(prop, v)
			_save_config()
		)

		header.add_child(name_label)
		header.add_child(spin)
		row.add_child(header)
		row.add_child(slider)
		target.add_child(row)


func _build_binds() -> void:
	_clear(bind_list)
	bind_buttons.clear()

	for b in BINDABLE:
		var action: String = b.action

		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = b.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.text = _bind_text(action)
		button.custom_minimum_size.x = 200
		button.pressed.connect(_start_listening.bind(action, button))
		bind_buttons[action] = button

		var clear := Button.new()
		clear.text = "✕"
		clear.custom_minimum_size.x = 36
		clear.tooltip_text = "Clear this binding"
		clear.pressed.connect(func() -> void:
			_stop_listening()
			InputMap.action_erase_events(action)
			_save_config()
			_refresh_labels()
		)

		row.add_child(label)
		row.add_child(button)
		row.add_child(clear)
		bind_list.add_child(row)

#endregion


#region Rebinding

func _start_listening(action: String, button: Button) -> void:
	_stop_listening()
	listening_action = action
	listening_button = button
	button.text = "press any key"
	button.release_focus()


func _stop_listening() -> void:
	if listening_action != "" and is_instance_valid(listening_button):
		listening_button.text = _bind_text(listening_action)
	listening_action = ""
	listening_button = null


## Shows the key for the current layout, so the same physical key reads W on
## QWERTY and Z on AZERTY.
func _bind_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "unbound"
	var e := events[0]
	if e is InputEventKey:
		return OS.get_keycode_string(
				DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode))
	return e.as_text()


## Relabels the existing buttons instead of rebuilding. queue_free() is deferred,
## so a rebuild would show old and new rows together for a frame.
func _refresh_labels() -> void:
	for action in bind_buttons:
		bind_buttons[action].text = _bind_text(action)


func _key_event(physical_keycode: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.device = ALL_DEVICES
	# Physical, so a bind follows the key's position rather than its printed letter.
	k.physical_keycode = physical_keycode
	return k


func _mouse_event(button_index: MouseButton) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.device = ALL_DEVICES
	m.button_index = button_index
	return m


## Rebuilds a captured event with only the fields that identify the input. Raw
## mouse events also carry position and click count, which confuse is_match().
func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		return _key_event(event.physical_keycode)
	return _mouse_event((event as InputEventMouseButton).button_index)


func _assign(action: String, event: InputEvent) -> void:
	var clean := _clean(event)

	# Take the input away from whichever action had it, so binds stay unique.
	for other in BINDABLE:
		for existing in InputMap.action_get_events(other.action):
			if existing.is_match(clean, false):
				InputMap.action_erase_event(other.action, existing)

	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_save_config()
	_refresh_labels()

#endregion


#region Config file

## Binds are saved as [type, code] pairs in one section.
func _save_config() -> void:
	var cfg := ConfigFile.new()

	for b in BINDABLE:
		var action: String = b.action
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			# Saved explicitly, so a cleared bind stays cleared instead of falling
			# back to the project default.
			cfg.set_value("binds", action, [BIND_NONE, 0])
			continue
		var e := events[0]
		if e is InputEventKey:
			cfg.set_value("binds", action, [BIND_KEY, e.physical_keycode])
		elif e is InputEventMouseButton:
			cfg.set_value("binds", action, [BIND_MOUSE, e.button_index])

	if player != null:
		for entry in _settings():
			cfg.set_value("settings", entry.prop, player.get(entry.prop))

	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return

	if cfg.has_section("binds"):
		for action in cfg.get_section_keys("binds"):
			var entry: Array = cfg.get_value("binds", action)
			InputMap.action_erase_events(action)
			if entry[0] == BIND_KEY:
				InputMap.action_add_event(action, _key_event(entry[1]))
			elif entry[0] == BIND_MOUSE:
				InputMap.action_add_event(action, _mouse_event(entry[1]))

	if player == null or not cfg.has_section("settings"):
		return

	# Only restore settings that still exist in the tables, so a removed setting
	# can't be applied from an old save with no control left to change it.
	var known := PackedStringArray()
	for entry in _settings():
		known.append(entry.prop)
	for prop in cfg.get_section_keys("settings"):
		if prop in known:
			player.set(prop, cfg.get_value("settings", prop))

#endregion


#region Helpers

## Falls back to the default port on a blank or invalid entry.
func _port() -> int:
	var value := port_field.text.strip_edges().to_int()
	return value if value > 0 and value < 65536 else DEFAULT_PORT


func _find_scroll(node: Node) -> ScrollContainer:
	var n := node.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


## Stops the mouse wheel changing a slider's value and scrolls the page instead.
func _block_scroll(event: InputEvent, control: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var b := event as InputEventMouseButton
	if b.button_index != MOUSE_BUTTON_WHEEL_UP and b.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return

	# Accept both press and release so neither reaches the slider, but only
	# scroll on press or one notch moves two steps.
	control.accept_event()
	if not b.pressed:
		return

	var sc := _find_scroll(control)
	if sc != null:
		sc.scroll_vertical += -SCROLL_STEP if b.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP

#endregion
