extends CanvasLayer

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
		"label": "Toggle Noclip",
		"group": "gameplay",
		"tip": "Press noclip to switch it on or off instead of holding the key.",
	},
]

const SLIDERS := [
	{
		"prop": "sensitivity",
		"group": "controls",
		"label": "Mouse Sensitivity",
		"tip": "Mouse sensitivity, using the same scale as Source games.",
		"min": 0.5, "max": 10.0, "step": 0.01,
	},
	{
		"prop": "air_speed_cap_units",
		"group": "gameplay",
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
const CONFIG_PATH := "user://input.cfg"
const SCROLL_STEP := 48

@export var player: Player

@onready var tabs: TabContainer = %TabContainer
@onready var bind_list: VBoxContainer = %BindList
@onready var toggle_list: VBoxContainer = %ToggleList
@onready var slider_lists := {
	"controls": %SliderList,
	"gameplay": %DebugSliderList,
}

var default_binds := {}
var confirm: ConfirmationDialog
var listening_action := ""
var listening_button: Button = null
var bind_buttons := {}
var defaults := {}


func _capture_defaults() -> void:
	if player == null:
		return
	for t in TOGGLES:
		defaults[t.prop] = player.get(t.prop)
	for s in SLIDERS:
		defaults[s.prop] = player.get(s.prop)
	for b in BINDABLE:
		var copies := []
		for e in InputMap.action_get_events(b.action):
			copies.append(e.duplicate())
		default_binds[b.action] = copies


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


func _current_group() -> String:
	return tabs.get_tab_title(tabs.current_tab).to_lower()


func _update_reset_label() -> void:
	%ResetButton.text = "Reset %s" % tabs.get_tab_title(tabs.current_tab)


func _ask_reset() -> void:
	confirm.dialog_text = "Reset all %s settings to their defaults?" % _current_group()
	confirm.popup_centered()


func _do_reset() -> void:
	var group := _current_group()

	if player != null:
		for t in TOGGLES:
			if t.group == group:
				player.set(t.prop, defaults[t.prop])
		for s in SLIDERS:
			if s.group == group:
				player.set(s.prop, defaults[s.prop])

	if group == "controls":
		for action in default_binds:
			InputMap.action_erase_events(action)
			for e in default_binds[action]:
				InputMap.action_add_event(action, e.duplicate())

	_save_config()
	_build_sliders()
	_build_toggles()
	_build_binds()


func _ready() -> void:
	_capture_defaults()
	_load_config()
	_build_sliders()
	_build_toggles()
	_build_binds()

	visible = false

	confirm = ConfirmationDialog.new()
	confirm.title = "Reset Settings"
	confirm.ok_button_text = "Reset"
	confirm.confirmed.connect(_do_reset)
	add_child(confirm)

	%ResumeButton.pressed.connect(_set_open.bind(false))
	%RespawnButton.pressed.connect(_on_respawn)
	%QuitButton.pressed.connect(get_tree().quit)
	%ResetButton.pressed.connect(_ask_reset)

	tabs.tab_changed.connect(func(_i: int) -> void: _update_reset_label())
	_update_reset_label()


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
		return

	if event.is_action_pressed("ui_cancel"):
		_set_open(not visible)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_stop_listening()
	visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _find_scroll(node: Node) -> ScrollContainer:
	var n := node.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _block_scroll(event: InputEvent, control: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var b := event as InputEventMouseButton
	if b.button_index != MOUSE_BUTTON_WHEEL_UP and b.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return

	control.accept_event()
	if not b.pressed:
		return

	var sc := _find_scroll(control)
	if sc != null:
		sc.scroll_vertical += -SCROLL_STEP if b.button_index == MOUSE_BUTTON_WHEEL_UP else SCROLL_STEP


func _on_respawn() -> void:
	if player != null:
		player.respawn()
	_set_open(false)


func _build_toggles() -> void:
	for child in toggle_list.get_children():
		child.queue_free()
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


func _build_binds() -> void:
	for child in bind_list.get_children():
		child.queue_free()
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


func _build_sliders() -> void:
	for list in slider_lists.values():
		for child in list.get_children():
			child.queue_free()
	if player == null:
		return

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
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var header := HBoxContainer.new()
		var tip := _tip(prop, s.tip)

		var name_label := Label.new()
		name_label.text = s.label
		name_label.tooltip_text = tip
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var spin := SpinBox.new()
		spin.gui_input.connect(_block_scroll.bind(spin))
		spin.min_value = s.min
		spin.max_value = s.max
		spin.step = s.step
		spin.value = player.get(prop)
		spin.custom_minimum_size.x = 90
		spin.select_all_on_focus = true
		spin.tooltip_text = tip

		var slider := HSlider.new()
		slider.gui_input.connect(_block_scroll.bind(slider))
		slider.min_value = s.min
		slider.max_value = s.max
		slider.step = s.step
		slider.value = player.get(prop)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = tip

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


func _refresh_labels() -> void:
	for action in bind_buttons:
		bind_buttons[action].text = _bind_text(action)


func _bind_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "unbound"
	var e := events[0]
	if e is InputEventKey:
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode))
	return e.as_text()


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


func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = event.physical_keycode
		return k
	var m := InputEventMouseButton.new()
	m.button_index = (event as InputEventMouseButton).button_index
	return m


func _assign(action: String, event: InputEvent) -> void:
	var clean := _clean(event)

	for other in BINDABLE:
		for existing in InputMap.action_get_events(other.action):
			if existing.is_match(clean, false):
				InputMap.action_erase_event(other.action, existing)

	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_save_config()
	_refresh_labels()


func _save_config() -> void:
	var cfg := ConfigFile.new()
	for b in BINDABLE:
		var action: String = b.action
		var events := InputMap.action_get_events(action)
		if events.is_empty():
			cfg.set_value("binds", action, [-1, 0])
			continue
		var e := events[0]
		if e is InputEventKey:
			cfg.set_value("binds", action, [0, e.physical_keycode])
		elif e is InputEventMouseButton:
			cfg.set_value("binds", action, [1, e.button_index])

	if player != null:
		for t in TOGGLES:
			cfg.set_value("settings", t.prop, player.get(t.prop))
		for s in SLIDERS:
			cfg.set_value("settings", s.prop, player.get(s.prop))

	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if cfg.has_section("binds"):
		for action in cfg.get_section_keys("binds"):
			var entry: Array = cfg.get_value("binds", action)
			InputMap.action_erase_events(action)
			if entry[0] == 0:
				var k := InputEventKey.new()
				k.physical_keycode = entry[1]
				InputMap.action_add_event(action, k)
			elif entry[0] == 1:
				var m := InputEventMouseButton.new()
				m.button_index = entry[1]
				InputMap.action_add_event(action, m)
	if cfg.has_section("mouse"):
		for action in cfg.get_section_keys("mouse"):
			var e := InputEventMouseButton.new()
			e.button_index = cfg.get_value("mouse", action)
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, e)
	if player != null and cfg.has_section("settings"):
		var known := PackedStringArray()
		for t in TOGGLES:
			known.append(t.prop)
		for s in SLIDERS:
			known.append(s.prop)
		for prop in cfg.get_section_keys("settings"):
			if prop in known:
				player.set(prop, cfg.get_value("settings", prop))
