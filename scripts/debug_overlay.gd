extends CanvasLayer
## DebugOverlay — autoload singleton.
## Press F1 at runtime to show/hide the log-category toggle panel.
## Changes take effect immediately and are reflected in DebugLogger.

const _CATEGORIES: Array = [
	["bush",         "Moita (bush)"],
	["animal_state", "Estado do animal"],
	["animal_create","Criação de animal"],
	["drag",         "Drag & input"],
	["input",        "Área input (verbose)"],
	["plane",        "Plano"],
	["gravity",      "Gravidade"],
	["scroller",     "Scroller"],
]

var _panel: PanelContainer
var _checkboxes: Dictionary = {}
var _master_cb: CheckBox

func _ready() -> void:
	layer = 128          # On top of everything
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Debug Logs  [F1 fecha]"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Master switch
	_master_cb = CheckBox.new()
	_master_cb.text = "Logging ativo (master)"
	_master_cb.button_pressed = DebugLogger.enabled
	_master_cb.toggled.connect(_on_master_toggled)
	vbox.add_child(_master_cb)


	vbox.add_child(HSeparator.new())

	# Per-category checkboxes
	for cat in _CATEGORIES:
		var cb := CheckBox.new()
		cb.text = cat[1]
		cb.button_pressed = DebugLogger.get_category(cat[0])
		var key: String = cat[0]
		cb.toggled.connect(func(v: bool) -> void: DebugLogger.set_category(key, v))
		vbox.add_child(cb)
		_checkboxes[key] = cb

	vbox.add_child(HSeparator.new())

	# All ON / All OFF buttons
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var btn_on := Button.new()
	btn_on.text = "Tudo ON"
	btn_on.pressed.connect(func() -> void: DebugLogger.enable_all(); _refresh_all())
	hbox.add_child(btn_on)

	var btn_off := Button.new()
	btn_off.text = "Tudo OFF"
	btn_off.pressed.connect(func() -> void: DebugLogger.disable_all(); _refresh_all())
	hbox.add_child(btn_off)

func _on_master_toggled(value: bool) -> void:
	DebugLogger.enabled = value

func _refresh_all() -> void:
	_master_cb.set_block_signals(true)
	_master_cb.button_pressed = DebugLogger.enabled
	_master_cb.set_block_signals(false)
	for cat in _CATEGORIES:
		var cb: CheckBox = _checkboxes.get(cat[0])
		if cb:
			cb.set_block_signals(true)
			cb.button_pressed = DebugLogger.get_category(cat[0])
			cb.set_block_signals(false)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()
