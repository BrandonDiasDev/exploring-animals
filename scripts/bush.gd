extends Node2D
class_name Bush

signal animal_revealed(animal: Animal)

@export var bush_name := "Arbusto"
@export var is_revealed := false
## Raio (px) em que um animal solto é capturado pela moita
@export var hide_radius := 170.0

@onready var bush_sprite: Sprite2D = $BushSprite
@onready var area: Area2D = $Area2D
@onready var hidden_animal: Animal = $HiddenAnimal

var is_occupied := false
var current_hidden_animal: Animal = null

var is_pressed := false
var press_timer := 0.0
const LONG_PRESS_TIME := 0.5
var mouse_captured := false

func _ready():
	add_to_group("bushes")
	area.input_event.connect(_on_area_input_event)

	# O animal padrão da cena já conta como ocupante
	current_hidden_animal = hidden_animal
	is_occupied = current_hidden_animal != null

	if is_revealed:
		_apply_revealed_state()
	else:
		_apply_hidden_state()

# ─── Estado inicial ────────────────────────────────────────────────────────────

func _apply_hidden_state():
	if current_hidden_animal:
		current_hidden_animal.visible = false
		current_hidden_animal.is_hidden = true
		current_hidden_animal.set_meta("managed_by_bush", true)

func _apply_revealed_state():
	if current_hidden_animal:
		current_hidden_animal.visible = true
		current_hidden_animal.is_hidden = false

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
	if not current_hidden_animal:
		return

	is_revealed = true
	is_occupied = false

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
	var animal = current_hidden_animal
	current_hidden_animal = null

	var target_scale = animal.scale
	animal.is_hidden = false
	animal.visible = true
	animal.scale = Vector2(0.05, 0.05)

	var animal_tween = create_tween()
	animal_tween.tween_property(animal, "scale", target_scale * 1.2, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	animal_tween.tween_property(animal, "scale", target_scale, 0.1)

	await animal_tween.finished

	if animal.has_meta("managed_by_bush"):
		animal.remove_meta("managed_by_bush")
	emit_signal("animal_revealed", animal)

# ─── Esconder animal arrastado ────────────────────────────────────────────────

## Chamado por animal.gd quando é solto sobre esta moita.
## Retorna true se aceitou, false se rejeitou.
func try_accept_animal(dropped_animal: Animal) -> bool:
	print("[BUSH] try_accept | bush:", name,
		" is_occupied:", is_occupied,
		" is_revealed:", is_revealed,
		" animal:", dropped_animal.animal_name)
	if is_occupied:
		print("[BUSH] >> REJECT")
		_play_rejection(dropped_animal)
		return false
	print("[BUSH] >> ACCEPT")
	_accept_animal(dropped_animal)
	return true

func _accept_animal(animal: Animal):
	is_occupied = true
	is_revealed = false
	current_hidden_animal = animal
	animal.set_meta("managed_by_bush", true)

	# Guardar a scale alvo antes de animar
	var original_scale = animal.scale

	# Desabilitar interação durante animação
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", false)

	# Animal voa em direção ao centro do arbusto e encolhe
	var move_tween = create_tween()
	move_tween.set_parallel(true)
	move_tween.tween_property(animal, "global_position", global_position, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	move_tween.tween_property(animal, "scale", Vector2(0.05, 0.05), 0.22) \
		.set_ease(Tween.EASE_IN)
	move_tween.tween_property(animal, "modulate", Color(1, 1, 1, 0), 0.18) \
		.set_ease(Tween.EASE_IN)

	await move_tween.finished

	animal.visible = false
	animal.is_hidden = true
	animal.modulate = Color(1, 1, 1, 1)
	animal.scale = original_scale  # Restaurar scale para quando sair

	# Arbusto faz animação de "engolida"
	var gulp_tween = create_tween()
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(1.2, 0.8), 0.07)
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(0.88, 1.18), 0.07)
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Re-habilitar área para que um clique revele o novo animal
	area.set_deferred("monitoring", true)

func _play_rejection(dropped_animal: Animal):
	print("[BUSH] _play_rejection para:", dropped_animal.animal_name)
	_shake_bush()
	dropped_animal.bounce_away_from(global_position)

## Retorna true se a posição global está dentro da área de collisão da moita.
## Usa o CollisionShape2D real (retângulo) se disponível; fallback para hide_radius circular.
func is_position_inside(gpos: Vector2) -> bool:
	var col = area.get_node_or_null("CollisionShape2D")
	if col and col.shape is RectangleShape2D:
		var half = col.shape.size / 2.0
		var center = global_position + col.position
		var local = gpos - center
		var inside = abs(local.x) <= half.x and abs(local.y) <= half.y
		print("[BUSH RECT] center:", "(%.0f,%.0f)" % [center.x, center.y],
			" half:", "(%.0f,%.0f)" % [half.x, half.y],
			" animal_local:", "(%.1f,%.1f)" % [local.x, local.y],
			" inside:", inside)
		return inside
	# Fallback circular
	return gpos.distance_to(global_position) <= hide_radius

func _shake_bush():
	var orig = bush_sprite.position
	var tween = create_tween()
	for i in range(3):
		var dir = 1 if i % 2 == 0 else -1
		tween.tween_property(bush_sprite, "position", orig + Vector2(dir * 9, 0), 0.05)
	tween.tween_property(bush_sprite, "position", orig + Vector2(-4, 0), 0.04)
	tween.tween_property(bush_sprite, "position", orig, 0.04)
