extends CanvasLayer

const TOGGLES := [
	{
		"prop": "auto_bhop",
		"label": "Auto Bunny Hop",
		"tip": "Hold jump to hop continuously instead of timing each press.",
	},
	{
		"prop": "auto_sprint",
		"label": "Always Sprint",
		"tip": "Run at full speed without holding the sprint key.",
	},
	{
		"prop": "crouch_toggle",
		"label": "Toggle Crouch",
		"tip": "Press crouch to switch stance instead of holding it.",
	},
]

const SLIDERS := [
	{
		"prop": "sensitivity",
		"label": "Mouse Sensitivity",
		"tip": "Same scale as Source games — enter the value from your TF2 config.",
		"min": 0.5,
		"max": 10.0,
		"step": 0.01,
	},
	{
		"prop": "slide_entry_speed_units",
		"label": "Slide Entry Speed",
		"tip": "Minimum speed needed to start a slide, in units per second.",
		"min": 0.0, "max": 400.0, "step": 5.0,
	},
	{
		"prop": "slide_boost_units",
		"label": "Slide Boost",
		"tip": "Speed added the moment a slide begins.",
		"min": 0.0, "max": 200.0, "step": 5.0,
	},
	{
		"prop": "slide_speed_cap_units",
		"label": "Slide Speed Cap",
		"tip": "Ceiling the boost can raise you to. Zero means uncapped.",
		"min": 0.0, "max": 800.0, "step": 10.0,
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
]
const CONFIG_PATH := "user://input.cfg"

@export var player: Player

@onready var bind_list: VBoxContainer = %BindList
@onready var toggle_list: VBoxContainer = %ToggleList
@onready var slider_list: VBoxContainer = %SliderList

var listening_action := ""
var listening_button: Button = null
var bind_buttons := {}


func _ready() -> void:
	_load_config()
	_build_sliders()
	_build_toggles()
	_build_binds()

	visible = false

	%ResumeButton.pressed.connect(_set_open.bind(false))
	%RespawnButton.pressed.connect(_on_respawn)
	%QuitButton.pressed.connect(get_tree().quit)


func _input(event: InputEvent) -> void:
	if listening_action != "":
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			_stop_listening()
			get_viewport().set_input_as_handled()
			return
		if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
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
		cb.tooltip_text = t.tip
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
		label.custom_minimum_size.x = 180

		var button := Button.new()
		button.text = _bind_text(action)
		button.custom_minimum_size.x = 180
		button.pressed.connect(_start_listening.bind(action, button))
		bind_buttons[action] = button

		row.add_child(label)
		row.add_child(button)
		bind_list.add_child(row)


func _build_sliders() -> void:
	for child in slider_list.get_children():
		child.queue_free()
	if player == null:
		return

	for s in SLIDERS:
		var prop: String = s.prop
		var row := VBoxContainer.new()
		var header := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = s.label
		name_label.tooltip_text = s.tip
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var spin := SpinBox.new()
		spin.min_value = s.min
		spin.max_value = s.max
		spin.step = s.step
		spin.value = player.get(prop)
		spin.custom_minimum_size.x = 90
		spin.select_all_on_focus = true
		spin.tooltip_text = s.tip

		var slider := HSlider.new()
		slider.min_value = s.min
		slider.max_value = s.max
		slider.step = s.step
		slider.value = player.get(prop)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = s.tip

		slider.share(spin)
		slider.value_changed.connect(func(v: float) -> void:
			player.set(prop, v)
			_save_config()
		)

		header.add_child(name_label)
		header.add_child(spin)
		row.add_child(header)
		row.add_child(slider)
		slider_list.add_child(row)


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
			continue
		var e := events[0]
		if e is InputEventKey:
			cfg.set_value("keys", action, e.physical_keycode)
		elif e is InputEventMouseButton:
			cfg.set_value("mouse", action, e.button_index)

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
	if cfg.has_section("keys"):
		for action in cfg.get_section_keys("keys"):
			var e := InputEventKey.new()
			e.physical_keycode = cfg.get_value("keys", action)
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, e)
	if cfg.has_section("mouse"):
		for action in cfg.get_section_keys("mouse"):
			var e := InputEventMouseButton.new()
			e.button_index = cfg.get_value("mouse", action)
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, e)
	if player != null and cfg.has_section("settings"):
		for prop in cfg.get_section_keys("settings"):
			player.set(prop, cfg.get_value("settings", prop))
