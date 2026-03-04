extends Node2D
class_name Bush

signal animal_revealed(animal: Animal)
signal bush_clicked
signal animal_accepted_by_bush(animal: Animal, bush: Bush)

@export var bush_name := "Arbusto"
@export var is_revealed := false
## Cena do animal que fica escondido neste arbusto. Deixe vazio para arbusto sem animal.
@export var hidden_animal_scene: PackedScene
## Nomes dos animais que este esconderijo aceita receber arrastados pelo jogador.
## Deixe vazio para aceitar qualquer animal. Ex.: ["Capivara", "Tamanduá"]
@export var accepted_animal_names: Array[String] = []

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
			# Aplicar estado oculto imediatamente (não precisa estar na árvore)
			animal.visible = false
			animal.is_hidden = true
			animal.set_meta("managed_by_bush", true)
			current_hidden_animal = animal
			is_occupied = true
			# Adicionar ao PAI do arbusto via deferred: _ready() roda enquanto o
			# segmento ainda está instanciando filhos; add_child síncrono falha.
			# Adicionamos ao Plane2/Plane1 (pai do arbusto) para evitar reparent no reveal.
			call_deferred("_attach_hidden_animal", animal)
		else:
			push_warning("[BUSH] hidden_animal_scene não gerou um Animal válido: ", hidden_animal_scene.resource_path)

	if is_revealed:
		_apply_revealed_state()
	# _apply_hidden_state é chamado dentro de _attach_hidden_animal após add_child

# ─── Anexar animal ao pai (deferred) ──────────────────────────────────────────

func _attach_hidden_animal(animal: Animal):
	"""Adiciona o animal ao pai do arbusto (ex: Plane2) após a árvore estar pronta."""
	if not is_instance_valid(animal):
		return
	var bush_parent = get_parent()
	if bush_parent:
		bush_parent.add_child(animal)
		animal.position = self.position  # mesma posição do arbusto no Plane
		if DebugLogger.bush: print("[BUSH ATTACH] ", name, " -> '", animal.name, "' adicionado a '", bush_parent.name,
			"' pos:", animal.position)
	else:
		add_child(animal)  # fallback: arbusto sem pai
		if DebugLogger.bush: print("[BUSH ATTACH] ", name, " -> fallback, animal adicionado ao próprio arbusto")
	# Desabilitar monitoring agora que o nó está na árvore
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", false)

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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var _parent_name: String = str(get_parent().name) if get_parent() else ""
		var animal_z: String = str(current_hidden_animal.z_index) if current_hidden_animal else "(sem animal)"
		var animal_mon = ""
		if current_hidden_animal and current_hidden_animal.has_node("Area2D"):
			var a = current_hidden_animal.get_node("Area2D")
			animal_mon = " | anim.monitoring:" + str(a.monitoring) + " | anim.pickable:" + str(a.input_pickable)
		if DebugLogger.input:
			print("[BUSH AREA INPUT] ", name,
				" | is_revealed:", is_revealed,
				" | is_occupied:", is_occupied,
				" | bush.z_index:", z_index,
				" | animal_z:", animal_z, animal_mon)

	# Moita já revelada: ignora cliques no arbusto (animal responde sozinho)
	if is_revealed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Avisar o world_manager que uma área capturou este press
			# (impede câmera de arrastar — vale tanto para arbusto ocupado quanto vazio)
			var wm = get_tree().get_first_node_in_group("world_manager")
			if wm and wm.has_method("notify_press_intercepted"):
				wm.notify_press_intercepted()
			is_pressed = true
			press_timer = 0.0
			mouse_captured = true
			set_process_input(true)
			if is_occupied:
				# Arbusto com animal: consome o evento para que APENAS o arbusto responda.
				# O animal está oculto, nada mais precisa do press.
				if DebugLogger.input: print("[BUSH] ocupado -> set_input_as_handled")
				get_viewport().set_input_as_handled()
			else:
				# Arbusto VAZIO: NÃO consome o evento.
				# O animal revelado pode estar sobreposto — ele também precisa receber o press.
				# A câmera já foi bloqueada por notify_press_intercepted().
				# No release, on_click() → _shake_bush() será chamado normalmente.
				if DebugLogger.input: print("[BUSH] vazio -> press registrado SEM set_input_as_handled (animal pode receber também)")

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
	if not current_hidden_animal:
		_shake_bush()
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

	# Usar o plano DO ARBUSTO para determinar scale correta — não a scale armazenada,
	# que pode vir de outro plano (ex: animal entrou do Plane1 mas o arbusto é Plane2)
	var bush_parent_name: String = str(get_parent().name) if get_parent() else ""
	var target_scale: Vector2
	if bush_parent_name == "Plane2":
		target_scale = Vector2(0.6, 0.6)
	else:
		target_scale = Vector2(1.0, 1.0)
	if DebugLogger.bush:
		print("[BUSH REVEAL] bush:", name, " | parent:", bush_parent_name,
			" | target_scale (from plane):", target_scale, " | animal.scale_stored:", animal.scale)

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
	if DebugLogger.bush: print("[BUSH REVEAL SET PLANE] animal:", animal.name, " | current_plane:", animal.current_plane, " | scale:", animal.scale)

	# Reabilitar o monitoring do animal via set_deferred:
	# A reparentagem ocorre síncrona no signal handler deste mesmo frame.
	# Alterar monitoring DIRETAMENTE antes do reparent corrompe o estado
	# do sistema de física (Area2D desce e sobe da árvore com monitoring=true
	# no meio da operação). set_deferred aplica DEPOIS que o reparent terminou.
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", true)

	var dbg_area = animal.get_node_or_null("Area2D")
	if DebugLogger.bush:
		print("[REVEAL PRE-SIGNAL] ", animal.name,
			" | z_index:", animal.z_index,
			" | visible:", animal.visible,
			" | is_hidden:", animal.is_hidden,
			" | current_plane:", animal.current_plane,
			" | parent:", (str(animal.get_parent().name) if animal.get_parent() else "NULL"),
			" | area.monitoring (deferred pending, atual):", (str(dbg_area.monitoring) if dbg_area else "NO_AREA"),
			" | area.input_pickable:", (str(dbg_area.input_pickable) if dbg_area else "NO_AREA"),
			" | bush.z_index:", z_index)

	emit_signal("animal_revealed", animal)

	# Arbusto agora está vazio: resetar is_revealed para que cliques futuros
	# (ex: tremidinha de arbusto vazio) funcionem normalmente
	is_revealed = false

	# Reabilitar área: arbusto vazio precisa detectar um novo animal solto sobre ele
	area.set_deferred("monitoring", true)
	if DebugLogger.bush: print("[BUSH] reveal completo, area.monitoring = true novamente | bush.z_index:", z_index)

# ─── Esconder animal arrastado ────────────────────────────────────────────────

## Chamado por animal.gd quando é solto sobre esta moita.
## Retorna true se aceitou, false se rejeitou.
func try_accept_animal(dropped_animal: Animal) -> bool:
	var _is_hole := bush_name.begins_with("Hole") or bush_name.to_lower().contains("buraco")
	var _tag := "[HOLE]" if _is_hole else "[BUSH]"

	if _is_hole and DebugLogger.hole:
		print(_tag, " try_accept | buraco:", name,
			" | animal solto: '", dropped_animal.animal_name, "'",
			" | lista permitidos: ", accepted_animal_names if accepted_animal_names.size() > 0 else ["(qualquer)"],
			" | is_occupied:", is_occupied)
	elif DebugLogger.drag:
		print(_tag, " try_accept | bush:", name,
			" is_occupied:", is_occupied,
			" is_revealed:", is_revealed,
			" animal:", dropped_animal.animal_name)

	if is_occupied:
		if _is_hole and DebugLogger.hole:
			print(_tag, " >> REJEITAR (buraco ocupado)")
		elif DebugLogger.drag:
			print(_tag, " >> REJECT (ocupado)")
		_play_rejection(dropped_animal)
		return false

	# Verificar lista de animais permitidos (vazia = aceita todos)
	if accepted_animal_names.size() > 0 and dropped_animal.animal_name not in accepted_animal_names:
		if _is_hole and DebugLogger.hole:
			print(_tag, " >> REJEITAR — '", dropped_animal.animal_name,
				"' NÃO está na lista | permitidos: ", accepted_animal_names)
		elif DebugLogger.drag:
			print(_tag, " >> REJECT (animal não permitido: ", dropped_animal.animal_name,
				" | permitidos: ", accepted_animal_names, ")")
		_play_rejection(dropped_animal)
		return false

	if _is_hole and DebugLogger.hole:
		print(_tag, " >> ACEITAR — '", dropped_animal.animal_name,
			"' é compatível com a lista: ", accepted_animal_names if accepted_animal_names.size() > 0 else ["(qualquer)"])
	elif DebugLogger.drag:
		print(_tag, " >> ACCEPT")
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
		if DebugLogger.bush: print("[BUSH ACCEPT REPARENT] ", animal.name, " -> ", our_plane.name, " de ", (str(our_plane.get_parent().name) if our_plane.get_parent() else "?"))

	# Notificar world_manager para atualizar scene_index do animal
	emit_signal("animal_accepted_by_bush", animal, self)

	# Guardar a scale alvo antes de animar
	var original_scale = animal.scale
	if DebugLogger.bush: print("[BUSH ACCEPT] animal:", animal.name, " | current_plane:", animal.current_plane, " | scale_entering:", original_scale)

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
	if DebugLogger.bush: print("[BUSH ACCEPT DONE] animal:", animal.name, " | scale_stored:", animal.scale)

	# Arbusto faz animação de "engolida"
	var gulp_tween = create_tween()
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(1.2, 0.8), 0.07)
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(0.88, 1.18), 0.07)
	gulp_tween.tween_property(bush_sprite, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Re-habilitar área para que um clique revele o novo animal
	area.set_deferred("monitoring", true)

func _play_rejection(dropped_animal: Animal):
	if DebugLogger.drag: print("[BUSH] _play_rejection para:", dropped_animal.animal_name)
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
