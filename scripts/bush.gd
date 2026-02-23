extends Node2D
class_name Bush

signal animal_revealed(animal: Animal)

@export var bush_name := "Arbusto"
@export var is_revealed := false

@onready var bush_sprite: Sprite2D = $BushSprite
@onready var area: Area2D = $Area2D
@onready var hidden_animal: Animal = $HiddenAnimal

var is_pressed := false
var press_timer := 0.0
const LONG_PRESS_TIME := 0.5
var mouse_captured := false

func _ready():
	add_to_group("bushes")
	area.input_event.connect(_on_area_input_event)

	if is_revealed:
		_apply_revealed_state()
	else:
		_apply_hidden_state()

# ─── Estado inicial ────────────────────────────────────────────────────────────

func _apply_hidden_state():
	if hidden_animal:
		hidden_animal.visible = false
		hidden_animal.is_hidden = true
		# Protege o animal de ser gerenciado pelo world_manager enquanto está na moita
		hidden_animal.set_meta("managed_by_bush", true)

func _apply_revealed_state():
	if hidden_animal:
		hidden_animal.visible = true
		hidden_animal.is_hidden = false

# ─── Input ─────────────────────────────────────────────────────────────────────

func _on_area_input_event(_viewport, event: InputEvent, _shape_idx):
	# Moita já revelada: ignora cliques no arbusto (animal responde sozinho)
	if is_revealed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_pressed = true
			press_timer = 0.0
			mouse_captured = true
			set_process_input(true)
			get_viewport().set_input_as_handled()

func _input(event):
	if not mouse_captured:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if is_pressed and press_timer < LONG_PRESS_TIME:
				on_click()
			_reset_input_state()
			get_viewport().set_input_as_handled()

func _reset_input_state():
	is_pressed = false
	mouse_captured = false
	set_process_input(false)

func _process(delta):
	if is_pressed:
		press_timer += delta

# ─── Revelar animal ────────────────────────────────────────────────────────────

func on_click():
	if is_revealed:
		return
	reveal_animal()

func reveal_animal():
	is_revealed = true

	# Desabilita a área imediatamente para evitar cliques duplos
	area.set_deferred("monitoring", false)

	# Animação de susto do arbusto
	var bush_tween = create_tween()
	bush_tween.tween_property(bush_sprite, "scale", Vector2(1.25, 0.75), 0.08)
	bush_tween.tween_property(bush_sprite, "scale", Vector2(0.85, 1.25), 0.08)
	bush_tween.tween_property(bush_sprite, "scale", Vector2(1.0, 1.0), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	await bush_tween.finished

	# Apresenta o animal com pop-in
	if hidden_animal:
		# Guardar a scale correta que _sync_visual_to_plane definiu no _ready()
		var target_scale = hidden_animal.scale
		hidden_animal.is_hidden = false
		hidden_animal.visible = true
		hidden_animal.scale = Vector2(0.05, 0.05)

		var animal_tween = create_tween()
		animal_tween.tween_property(hidden_animal, "scale", target_scale * 1.2, 0.3) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		animal_tween.tween_property(hidden_animal, "scale", target_scale, 0.1)

		await animal_tween.finished
		# Libera o animal para ser gerenciado normalmente pelo world_manager
		if hidden_animal.has_meta("managed_by_bush"):
			hidden_animal.remove_meta("managed_by_bush")
		emit_signal("animal_revealed", hidden_animal)
