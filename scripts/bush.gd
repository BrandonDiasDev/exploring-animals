extends Node2D
class_name Bush

signal animal_revealed(animal: Animal)
signal bush_clicked
signal animal_accepted_by_bush(animal: Animal, bush: Bush)

@export var bush_name := "Arbusto"
@export var is_revealed := false
## Cena do animal que fica escondido neste arbusto. Deixe vazio para arbusto sem animal.
@export var hidden_animal_scene: PackedScene

@onready var bush_sprite: Sprite2D = $BushSprite
@onready var area: Area2D = $Area2D

var is_occupied := false
var current_hidden_animal: Animal = null

var is_pressed := false
var press_timer := 0.0
const LONG_PRESS_TIME := 0.5
var mouse_captured := false

func _ready():
	add_to_group("bushes")
	area.input_event.connect(_on_area_input_event)
	# monitorable SEMPRE true: animais precisam detectar sobreposição com a moita
	area.monitorable = true

	# Instanciar o animal escondido a partir da cena exportada (se definida)
	if hidden_animal_scene:
		var animal := hidden_animal_scene.instantiate() as Animal
		if animal:
			add_child(animal)
			current_hidden_animal = animal
			is_occupied = true
		else:
			push_warning("[BUSH] hidden_animal_scene não gerou um Animal válido: ", hidden_animal_scene.resource_path)

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
		# Desabilitar monitoring para não interferir em overlap detection
		if current_hidden_animal.has_node("Area2D"):
			current_hidden_animal.get_node("Area2D").set_deferred("monitoring", false)

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
			# NAO chama set_input_as_handled() no release:
			# o world_manager precisa ver este release para resetar o drag da camera

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
	emit_signal("bush_clicked")
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
	print("[BUSH REVEAL] bush:", name, " | parent:", (get_parent().name if get_parent() else "NULL"),
		" | target_scale:", target_scale, " | animal.scale_now:", animal.scale)

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

	# Gravar o plane correto NO animal antes de emitir o signal
	# O world_manager vai herdar esse valor sem precisar detectar pelo parent chain
	var bush_parent = get_parent()
	if bush_parent and bush_parent.name == "Plane2":
		animal.current_plane = "plane2"
	else:
		animal.current_plane = "plane1"
	print("[BUSH REVEAL SET PLANE] animal:", animal.name, " | current_plane:", animal.current_plane, " | scale:", animal.scale)

	# Reabilitar o monitoring do animal para que overlaps_area funcione ao ser solto
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", true)

	emit_signal("animal_revealed", animal)

	# Reabilitar área: arbusto vazio precisa detectar um novo animal solto sobre ele
	area.set_deferred("monitoring", true)
	print("[BUSH] reveal completo, area.monitoring = true novamente")

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

	# Mover o animal para o Plane deste segmento.
	# Sem isso, o animal continua filho do segmento de onde veio e é destruído
	# quando aquele segmento recicla, mesmo estando logicamente nessa moita.
	var our_plane = get_parent()  # ex: Plane2 do nosso segmento
	if our_plane and animal.get_parent() != our_plane:
		var gpos = animal.global_position
		var old_parent = animal.get_parent()
		if old_parent:
			old_parent.remove_child(animal)
		our_plane.add_child(animal)
		animal.global_position = gpos
		print("[BUSH ACCEPT REPARENT] ", animal.name, " -> ", our_plane.name, " de ", (our_plane.get_parent().name if our_plane.get_parent() else "?"))

	# Notificar world_manager para atualizar scene_index do animal
	emit_signal("animal_accepted_by_bush", animal, self)

	# Guardar a scale alvo antes de animar
	var original_scale = animal.scale
	print("[BUSH ACCEPT] animal:", animal.name, " | current_plane:", animal.current_plane, " | scale_entering:", original_scale)

	# Desabilitar TANTO a área do animal QUANTO da moita durante a animação
	# Evita que o release do mouse dispare on_click() e revele imediatamente
	area.set_deferred("monitoring", false)
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
	print("[BUSH ACCEPT DONE] animal:", animal.name, " | scale_stored:", animal.scale)

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

func _shake_bush():
	var orig = bush_sprite.position
	var tween = create_tween()
	for i in range(3):
		var dir = 1 if i % 2 == 0 else -1
		tween.tween_property(bush_sprite, "position", orig + Vector2(dir * 9, 0), 0.05)
	tween.tween_property(bush_sprite, "position", orig + Vector2(-4, 0), 0.04)
	tween.tween_property(bush_sprite, "position", orig, 0.04)
