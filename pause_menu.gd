class_name PauseMenu
extends CanvasLayer

## Pause menu, settings, and key rebinding.
##
## Every setting is declared once in one of the three tables below. The build
## functions, the reset, and the save and load all iterate those tables, so
## adding a setting means adding a dictionary entry and nothing else.
##
## Each entry's `group` names the tab it appears in and must match that tab
## node's title in lower case.


# ------------------------------------------------------- setting tables ---

## Boolean options, rendered as CheckButtons.
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

## Numeric options, rendered as a slider and spinbox pair. Entries sharing a
## `section` must be contiguous, since the header is emitted on change.
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

## Rebindable actions, rendered as a label, a bind button, and a clear button.
const BINDABLE := [
	{"action": "move_forward", "label": "Move Forward"},
	{"action": "move_back", "label": "Move Back"},
	{"action": "move_left", "label": "Strafe Left"},
	{"action": "move_right", "label": "Strafe Right"},
	{"action": "jump", "label": "Jump"},
	{"action": "crouch", "label": "Crouch"},
	{"action": "sprint", "label": "Sprint"},
	{"action": "noclip", "label": "Noclip"},
]


# ------------------------------------------------------------ constants ---

const CONFIG_PATH := "user://input.cfg"

## Pixels scrolled per wheel notch when the wheel lands on a slider.
const SCROLL_STEP := 48

## Type tags written into the saved bind entries.
const BIND_NONE := -1
const BIND_KEY := 0
const BIND_MOUSE := 1


# ---------------------------------------------------------------- nodes ---

## Assigned through [method setup] rather than exported. The player is spawned
## at runtime now, so there is no NodePath in the world scene to bake.
var player: Player = null

@onready var tabs: TabContainer = %TabContainer
@onready var bind_list: VBoxContainer = %BindList
@onready var toggle_list: VBoxContainer = %ToggleList
@onready var reset_button: Button = %ResetButton

## Slider containers keyed by group, matching the `group` field in SLIDERS.
@onready var slider_lists := {
	"controls": %SliderList,
	"gameplay": %DebugSliderList,
	"base": %BaseSliderList,
}


# ---------------------------------------------------------------- state ---

## Player property values captured before the saved config is applied, so a
## reset restores the real defaults rather than the last saved values.
var defaults := {}

## Input events captured from the Input Map for the same reason.
var default_binds := {}

## Bind buttons keyed by action, so a rebind can relabel one row rather than
## rebuilding the list.
var bind_buttons := {}

var listening_action := ""
var listening_button: Button = null
var confirm: ConfirmationDialog


# ================================================================ setup ===


func _ready() -> void:
	visible = false

	confirm = ConfirmationDialog.new()
	confirm.title = "Reset Settings"
	confirm.ok_button_text = "Reset"
	confirm.confirmed.connect(_do_reset)
	add_child(confirm)

	%ResumeButton.pressed.connect(_set_open.bind(false))
	%RespawnButton.pressed.connect(_on_respawn)
	%QuitButton.pressed.connect(get_tree().quit)
	reset_button.pressed.connect(_ask_reset)

	tabs.tab_changed.connect(func(_i: int) -> void: _update_reset_label())
	_update_reset_label()


## Called by the world once the local player exists. Everything that reads or
## writes player properties lives here rather than in _ready, because at scene
## load there is no player to read.
##
## Order still matters: defaults must be captured before the config overwrites
## them, and the controls must be built after it, so they show the values
## actually in effect.
func setup(p: Player) -> void:
	player = p
	_capture_defaults()
	_load_config()
	_rebuild()


## Uses _input rather than _unhandled_input so a keypress during rebinding is
## seen before any focused Button treats it as a click.
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
		# Nothing else may see input while capturing a bind.
		return

	if event.is_action_pressed("ui_cancel"):
		_set_open(not visible)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_stop_listening()
	visible = open
	get_tree().paused = open
	if player != null:
		player.set_menu_open(open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _on_respawn() -> void:
	if player != null:
		player.respawn()
	_set_open(false)


# ============================================================= defaults ===


## Every settable entry across both tables. Both shapes carry `prop` and
## `group`, which is all the defaults and reset code needs.
func _settings() -> Array:
	return TOGGLES + SLIDERS


func _capture_defaults() -> void:
	if player == null:
		return
	for entry in _settings():
		defaults[entry.prop] = player.get(entry.prop)
	for b in BINDABLE:
		var copies := []
		for e in InputMap.action_get_events(b.action):
			copies.append(e.duplicate())
		default_binds[b.action] = copies


## Appends the captured default to a tooltip. Reading it back rather than
## hardcoding it means the tooltip cannot drift from the export.
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


# ================================================================ reset ===


## The active tab's title, lower cased, matching the `group` field.
func _current_group() -> String:
	return tabs.get_tab_title(tabs.current_tab).to_lower()


func _update_reset_label() -> void:
	reset_button.text = "Reset %s" % tabs.get_tab_title(tabs.current_tab)


func _ask_reset() -> void:
	confirm.dialog_text = "Reset all %s settings to their defaults?" % _current_group()
	confirm.popup_centered()


## Restores defaults for the active tab only, so tuning one page cannot wipe
## another.
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


# ================================================================ build ===


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

	# Tracked per group so each tab emits its own section headers.
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

		# Both extend Range, so sharing keeps them in step with one handler.
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


# ============================================================ rebinding ===


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


## Converts a physical key code back through the current layout, so a QWERTY
## user sees W and an AZERTY user sees Z for the same physical key.
func _bind_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "unbound"
	var e := events[0]
	if e is InputEventKey:
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode))
	return e.as_text()


## Relabels the existing buttons rather than rebuilding the rows. queue_free
## is deferred, so a rebuild would leave old and new buttons overlapping for a
## frame, which reads as the rebind not taking.
func _refresh_labels() -> void:
	for action in bind_buttons:
		bind_buttons[action].text = _bind_text(action)


## Strips a captured event down to the field that identifies the input. A raw
## mouse event also carries a screen position and click count, which would
## make is_match behave unpredictably.
func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		# Physical, so a binding follows the key's location rather than the
		# letter printed on it.
		k.physical_keycode = event.physical_keycode
		return k
	var m := InputEventMouseButton.new()
	m.button_index = (event as InputEventMouseButton).button_index
	return m


func _assign(action: String, event: InputEvent) -> void:
	var clean := _clean(event)

	# Taking a key from whichever action held it keeps bindings unique.
	for other in BINDABLE:
		for existing in InputMap.action_get_events(other.action):
			if existing.is_match(clean, false):
				InputMap.action_erase_event(other.action, existing)

	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_save_config()
	_refresh_labels()


# ========================================================== persistence ===


## Binds are stored as [type, code] in a single section. Keeping the type tag
## alongside the code avoids an ordering dependency between separate key and
## mouse sections, and leaves room for a third input type later.
func _save_config() -> void:
	var cfg := ConfigFile.new()

	for b in BINDABLE:
		var action: String = b.action
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			# Explicit, so a cleared bind stays cleared rather than falling
			# back to the Input Map default.
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
				var k := InputEventKey.new()
				k.physical_keycode = entry[1]
				InputMap.action_add_event(action, k)
			elif entry[0] == BIND_MOUSE:
				var m := InputEventMouseButton.new()
				m.button_index = entry[1]
				InputMap.action_add_event(action, m)

	if player == null or not cfg.has_section("settings"):
		return

	# Only properties still declared in the tables are restored. Without this
	# a stale key from a removed setting would be applied silently, with no
	# control left to change it back.
	var known := PackedStringArray()
	for entry in _settings():
		known.append(entry.prop)
	for prop in cfg.get_section_keys("settings"):
		if prop in known:
			player.set(prop, cfg.get_value("settings", prop))


# ============================================================== helpers ===


func _find_scroll(node: Node) -> ScrollContainer:
	var n := node.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


## Stops the wheel from nudging a value when it happens to land on a slider,
## and forwards the scroll to the enclosing page instead.
func _block_scroll(event: InputEvent, control: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var b := event as InputEventMouseButton
	if b.button_index != MOUSE_BUTTON_WHEEL_UP and b.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return

	# Both the press and the release must be accepted, or the release reaches
	# the slider; only the press should scroll, or one notch moves two steps.
	control.accept_event()
	if not b.pressed:
		return

	var sc := _find_scroll(control)
	if sc != null:
		sc.scroll_vertical += -SCROLL_STEP if b.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP
