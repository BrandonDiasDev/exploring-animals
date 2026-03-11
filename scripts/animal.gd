extends Node2D
class_name Animal

const _WorldConfig := preload("res://scripts/world_config.gd")

enum AnimalState { IDLE, FLY, FALL }

signal animal_clicked(animal: Animal)
signal animal_drag_started(animal: Animal)
signal animal_drag_ended(animal: Animal)

@export var animal_name := "Capivara"
@export var animal_sound: AudioStream
@export_enum("plane1", "plane2") var current_plane := "plane2"
@export var is_hidden := false
## Se verdadeiro, a gravidade NÃO afeta este animal (ex: pássaros voadores).
@export var can_fly: bool = false
## Textura do animal acordado (IDLE + dia). Deixe vazio para usar a textura do Sprite2D da cena.
@export var idle_awake_texture: Texture2D
## Textura do animal dormindo (IDLE + noite). Deixe vazio para não alterar textura à noite.
@export var idle_sleep_texture: Texture2D
## Duração do voo em segundos antes do pouso automático (só se can_fly=true).
@export var fly_duration: float = 5.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var is_being_dragged := false
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var press_timer := 0.0
const LONG_PRESS_TIME := 0.5
var is_pressed := false
var mouse_captured := false

## Estado FSM do animal (IDLE / FLY / FALL)
var current_state: AnimalState = AnimalState.IDLE
var _fly_timer: float = 0.0
var fall_tween: Tween = null

func _ready():
	add_to_group("animals")
	
	area.input_event.connect(_on_area_input_event)
	original_position = position
	
	if is_hidden:
		visible = false
	
	_sync_visual_to_plane()

func _sync_visual_to_plane():
	"""Garantir que propriedades visuais correspondem ao plano atual.
	Os valores de escala vêm de WorldConfig (scripts/world_config.gd)."""
	var cfg := get_node_or_null("/root/WorldConfig") as _WorldConfig
	if current_plane == "plane2":

		z_index = 100
		var expected_scale: Vector2 = cfg.plane2_scale if cfg else Vector2(0.6, 0.6)
		if scale != expected_scale:
			if DebugLogger.plane: print("[SYNC PLANE] ", animal_name, " plane2: scale ", scale, " -> ", expected_scale)
			scale = expected_scale
	else:  # plane1
		z_index = 200
		var expected_scale: Vector2 = cfg.plane1_scale if cfg else Vector2(1.0, 1.0)
		if scale != expected_scale:
			if DebugLogger.plane: print("[SYNC PLANE] ", animal_name, " plane1: scale ", scale, " -> ", expected_scale)
			scale = expected_scale

func _on_area_input_event(_viewport, event: InputEvent, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var area2d = get_node_or_null("Area2D")
		var mon: String = str(area2d.monitoring) if area2d else "NO_AREA"
		var pickable: String = str(area2d.input_pickable) if area2d else "NO_AREA"
		var parent_name: String = str(get_parent().name) if get_parent() else "NULL"
		if DebugLogger.input:
			print("[ANIMAL AREA INPUT] ", animal_name,
				" | is_hidden:", is_hidden,
				" | visible:", visible,
				" | z_index:", z_index,
				" | monitoring:", mon,
				" | input_pickable:", pickable,
				" | parent:", parent_name)

	if is_hidden:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Avisar o world_manager que uma área capturou este press,
			# impedindo que o próximo Motion inicie o drag da câmera.
			var wm = get_tree().get_first_node_in_group("world_manager")
			if wm and wm.has_method("notify_press_intercepted"):
				wm.notify_press_intercepted()
			is_pressed = true
			press_timer = 0.0
			mouse_captured = true
			set_process_input(true)
			get_viewport().set_input_as_handled()

func _input(event):
	if mouse_captured:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				handle_mouse_release()
				get_viewport().set_input_as_handled()
		
		elif event is InputEventMouseMotion:
			if is_being_dragged:
				global_position = get_global_mouse_position() + drag_offset
				get_viewport().set_input_as_handled()

func handle_mouse_release():
	"""Centralizar tratamento de quando o mouse é solto"""
	if not mouse_captured:
		return
	
	var timer_snapshot = press_timer
	var was_dragging = is_being_dragged
	
	mouse_captured = false
	set_process_input(false)
	
	if is_pressed:
		if press_timer < LONG_PRESS_TIME:
			# Clique simples
			if DebugLogger.drag: print("[INPUT] ", animal_name, " >> CLICK | timer:", "%.3f" % timer_snapshot, " | was_dragging:", was_dragging)
			on_click()
		else:
			# Long press - terminou o drag
			if is_being_dragged:
				if DebugLogger.drag: print("[INPUT] ", animal_name, " >> DRAG END | timer:", "%.3f" % timer_snapshot, " | gpos:", global_position)
				end_drag()
			else:
				if DebugLogger.drag: print("[INPUT] ", animal_name, " >> LONG HOLD (sem drag) | timer:", "%.3f" % timer_snapshot)
		is_pressed = false
		press_timer = 0.0

func _process(delta):
	# CRÍTICO: Só incrementar timer e iniciar drag se AINDA estiver pressionado
	if is_pressed and not is_being_dragged and mouse_captured:  # MODIFICADO
		press_timer += delta
		if press_timer >= LONG_PRESS_TIME:
			# Verificar novamente se ainda está pressionado
			if is_pressed and mouse_captured:  # NOVO: Double check
				start_drag()
	# Temporizador de voo: pousa automaticamente após fly_duration expirar
	if current_state == AnimalState.FLY:
		_fly_timer += delta
		if _fly_timer >= fly_duration:
			if DebugLogger.animal_fsm:
				print("[FSM] ", animal_name, ": voo expirou (", "%.1f" % _fly_timer, "s) → IDLE")
			transition_to(AnimalState.IDLE)
			check_plane_change()
			var _wm := get_tree().get_first_node_in_group("world_manager")
			if _wm and _wm.has_method("save_animal_state"):
				_wm.save_animal_state(self)

func on_click():
	_cancel_transition()  # Transação cancelada pelo clique; ação normal retoma
	emit_signal("animal_clicked", self)
	play_click_animation()
	play_sound()
	zoom_camera()

func start_drag():
	if is_being_dragged:
		return
	
	if not is_pressed or not mouse_captured:
		return
	
	_cancel_transition()  # Pode estar caindo ou voando; drag assume controle
	if DebugLogger.drag: print("[DRAG START] Animal:", animal_name, "| pos:", position)
	is_being_dragged = true
	drag_offset = global_position - get_global_mouse_position()
	
	modulate = Color(1, 1, 1, 0.7)
	z_index = 100
	
	emit_signal("animal_drag_started", self)

func end_drag():
	if not is_being_dragged:
		return
	
	if DebugLogger.drag: print("[DRAG END] Animal:", animal_name, " | gpos:", global_position)
	is_being_dragged = false
	
	modulate = Color(1, 1, 1, 1)
	z_index = 100 if current_plane == "plane2" else 200
	
	emit_signal("animal_drag_ended", self)
	
	# Aguardar um frame de física para as sobreposições serem atualizadas
	await get_tree().physics_frame
	
	var bush_result = _check_bush_drop()
	if bush_result == "accepted" or bush_result == "rejected":
		return  # A moita assume o controle a partir daqui

	# Gravidade assume se o animal solto caiu acima da linha de terra.
	# apply_gravity() callá check_plane_change e save_animal_state ao pousar.
	if apply_gravity():
		return

	check_plane_change()

	# Save state after drag
	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager and world_manager.has_method("save_animal_state"):
		world_manager.save_animal_state(self)

func _check_bush_drop() -> String:
	var bushes = get_tree().get_nodes_in_group("bushes")
	
	if bushes.is_empty():
		return ""
	
	for bush in bushes:
		var overlapping = area.overlaps_area(bush.area)
		var occupied_str = "ocupada" if bush.is_occupied else "livre"
		if DebugLogger.drag:
			print("[BUSH DROP] ", animal_name, " -> ", bush.name,
				" overlap:", overlapping,
				" (", occupied_str, ")")
		if overlapping:
			var result = bush.try_accept_animal(self)
			return "accepted" if result else "rejected"
	
	return ""

## Chamado pela moita quando já tem um animal dentro.
## O animal quica para longe em um pequeno arco.
func bounce_away_from(source_pos: Vector2):
	var dir = (global_position - source_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(randf_range(-1.0, 1.0), -0.5).normalized()
	
	var bounce_dist = randf_range(180.0, 260.0)
	var arc_peak = global_position + dir * bounce_dist * 0.5 + Vector2(0, -90)
	var target = global_position + dir * bounce_dist
	
	if DebugLogger.drag:
		print("[BOUNCE] ", animal_name, " dir:", "(%.2f,%.2f)" % [dir.x, dir.y],
			" dist:", "%.0f" % bounce_dist,
			" from:", global_position, " to:", "(%.0f,%.0f)" % [target.x, target.y])
	
	# Pop de escala: feedback visual de rejeição
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", scale * 1.3, 0.07).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", scale, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Movimento em arco: sobe e vola para longe
	var move_tween = create_tween()
	move_tween.tween_property(self, "global_position", arc_peak, 0.18).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "global_position", target, 0.22) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	
	await move_tween.finished
	
	if DebugLogger.drag: print("[BOUNCE] ", animal_name, " pousou em:", global_position)

	# Ajustar plano e salvar estado na posição final
	check_plane_change()
	var world_manager = get_tree().get_first_node_in_group("world_manager")
	# Gravidade pode assumir se o bounce deixou o animal acima da linha de terra.
	# Se não, salvar estado aqui normalmente.
	if not apply_gravity():
		if world_manager and world_manager.has_method("save_animal_state"):
			world_manager.save_animal_state(self)
	if world_manager and world_manager.has_method("notify_bounce_finished"):
		world_manager.notify_bounce_finished(self)

func check_plane_change():
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var viewport_size = get_viewport_rect().size
	var camera_pos = camera.global_position
	
	var camera_top = camera_pos.y - (viewport_size.y / (2.0 * camera.zoom.y))
	var camera_bottom = camera_pos.y + (viewport_size.y / (2.0 * camera.zoom.y))
	var division_y = camera_top + (camera_bottom - camera_top) * 0.6
	
	# Usar a base dos pés como referencial: centro do sprite + metade da altura * escala + offset
	const FEET_OFFSET := 20.0
	var feet_y := global_position.y
	if sprite and sprite.texture:
		feet_y += sprite.texture.get_height() / 2.0 * scale.y + FEET_OFFSET
	
	var new_plane = ""
	if feet_y < division_y:
		new_plane = "plane2"
	else:
		new_plane = "plane1"
	
	if current_plane != new_plane:
		if DebugLogger.plane:
			print("[PLANE CHANGE] ", current_plane, " -> ", new_plane,
				" | feet_y:", "%.0f" % feet_y, " | division_y:", "%.0f" % division_y)
		change_to_plane(new_plane)

func change_to_plane(new_plane: String):
	var _old_plane = current_plane
	current_plane = new_plane
	
	var target_scale = Vector2.ZERO
	var target_z_index = 0
	
	if new_plane == "plane2":
		target_scale = Vector2(0.6, 0.6)
		target_z_index = 100
	else:
		target_scale = Vector2(1.0, 1.0)
		target_z_index = 200
	
	# Scale e z_index mudam instantaneamente — sem tween para não colidir com animações de reveal
	scale = target_scale
	z_index = target_z_index
	
	# Reparentar para o nó Plane correto (preservando posição global)
	_reparent_to_plane(new_plane)
	
	# Só o flash de modulate como feedback visual da mudança de plano
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(0.5, 0.5, 1.0), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1), 0.1)
	
	await tween.finished
	play_plane_change_sound()

func _reparent_to_plane(target_plane_name: String):
	"""Move o animal para o nó Plane correto dentro do segmento, preservando posição global.
	Hierarquia esperada: animal -> Plane1|Plane2 -> Segment -> InfiniteScroller"""
	var target_node_name = "Plane1" if target_plane_name == "plane1" else "Plane2"
	
	var current_parent = get_parent()
	if not current_parent:
		return
	
	# Já está no plano correto?
	if current_parent.name == target_node_name:
		return
	
	# O segmento é o avô do animal (pai do Plane node)
	var segment = current_parent.get_parent()
	if not segment:
		return
	
	var target_plane = segment.get_node_or_null(target_node_name)
	if not target_plane:
		return
	
	# Reparentar preservando posição global
	var gpos = global_position
	current_parent.remove_child(self)
	target_plane.add_child(self)
	global_position = gpos
	if DebugLogger.plane: print("[REPARENT PLANE] ", animal_name, " ", current_parent.name, " -> ", target_node_name)

# ── FSM ──────────────────────────────────────────────────────────────────────

## Ponto de entrada único para todas as mudanças de estado do animal.
## Garante que _exit_state e _enter_state são sempre chamados em par.
func transition_to(new_state: AnimalState) -> void:
	if current_state == new_state:
		return
	var old_state := current_state
	if DebugLogger.animal_fsm:
		print("[FSM] ", animal_name, ": ", AnimalState.keys()[old_state], " → ", AnimalState.keys()[new_state])
	_exit_state(old_state)
	current_state = new_state
	_enter_state(new_state)

func _exit_state(state: AnimalState) -> void:
	match state:
		AnimalState.FALL:
			if fall_tween and fall_tween.is_valid():
				fall_tween.kill()
			fall_tween = null
		AnimalState.FLY:
			_fly_timer = 0.0
		AnimalState.IDLE:
			pass  # sem cleanup necessário

func _enter_state(state: AnimalState) -> void:
	match state:
		AnimalState.IDLE:
			_update_idle_visual()
		AnimalState.FLY:
			_fly_timer = 0.0
			# Animação de voo (se existir na cena)
			if animation_player and animation_player.has_animation("fly"):
				animation_player.play("fly")
		AnimalState.FALL:
			_start_fall_tween()

func _update_idle_visual() -> void:
	"""Atualiza a textura do Sprite2D com base no estado dia/noite atual."""
	var cfg := get_node_or_null("/root/WorldConfig") as _WorldConfig
	var is_night := (cfg != null and not cfg.is_day)
	if is_night and idle_sleep_texture != null:
		sprite.texture = idle_sleep_texture
	elif idle_awake_texture != null:
		sprite.texture = idle_awake_texture
	# Se ambas forem nulas, mantém a textura atual definida na cena.
	if DebugLogger.animal_fsm:
		var vis := "sleep" if (is_night and idle_sleep_texture != null) else "awake"
		print("[FSM] ", animal_name, ": idle_visual = ", vis)

## Chamado pelo WorldManager quando o ciclo dia/noite muda.
## Só atua em estado IDLE — FLY e FALL não alteram textura.
func notify_day_night_changed(_to_day: bool) -> void:
	if current_state == AnimalState.IDLE:
		_update_idle_visual()

# ── Gravidade ─────────────────────────────────────────────────────────────────

## Ponto de entrada para aplicar gravidade/voo após soltar o animal ou revelá-lo.
## can_fly=true  → transição para FLY (voo livre com timer).
## can_fly=false → transição para FALL se acima da linha de terra.
## Retorna true se iniciou uma transição, false se o animal já está em posição final.
func apply_gravity() -> bool:
	if is_being_dragged or is_hidden or current_state != AnimalState.IDLE:
		return false

	if can_fly:
		transition_to(AnimalState.FLY)
		return true

	var cfg := get_node_or_null("/root/WorldConfig") as _WorldConfig
	if not cfg:
		return false

	# Calcular posição dos pés (mesmo critério de check_plane_change)
	const FEET_OFFSET_G := 20.0
	var feet_y := global_position.y
	if sprite and sprite.texture:
		feet_y += sprite.texture.get_height() / 2.0 * scale.y + FEET_OFFSET_G

	if feet_y >= cfg.background_earth_y:
		return false  # Já está na terra ou abaixo — sem queda necessária

	transition_to(AnimalState.FALL)
	return true

func _start_fall_tween() -> void:
	"""Inicia o tween de queda. Chamado por _enter_state(FALL)."""
	var cfg := get_node_or_null("/root/WorldConfig") as _WorldConfig
	if not cfg:
		transition_to(AnimalState.IDLE)
		return

	const FEET_OFFSET_G := 20.0
	var feet_y := global_position.y
	if sprite and sprite.texture:
		feet_y += sprite.texture.get_height() / 2.0 * scale.y + FEET_OFFSET_G

	# Destino: pés pousam em Y aleatório entre background_earth_y e o centro (0)
	var target_feet_y := randf_range(cfg.background_earth_y, 0.0)
	var feet_offset_val: float = 0.0
	if sprite and sprite.texture:
		feet_offset_val = sprite.texture.get_height() / 2.0 * scale.y + FEET_OFFSET_G
	var target_global_y := target_feet_y - feet_offset_val

	# Converter global Y → local Y do parent.
	# O parent (Plane1/Plane2) só se move no eixo X, então parent.global_position.y é estável.
	var parent_node := get_parent() as Node2D
	var parent_global_y: float = parent_node.global_position.y if parent_node else 0.0
	var target_local_y: float = target_global_y - parent_global_y

	# Duração proporcional à distância (~400 px/s), entre 0.3s e 1.2s
	var fall_distance := absf(target_global_y - global_position.y)
	var fall_duration := clampf(fall_distance / 400.0, 0.3, 1.2)

	if fall_tween and fall_tween.is_valid():
		fall_tween.kill()
	fall_tween = create_tween()
	fall_tween.set_trans(Tween.TRANS_QUAD)
	fall_tween.set_ease(Tween.EASE_IN)
	fall_tween.tween_property(self, "position:y", target_local_y, fall_duration)
	fall_tween.tween_callback(_on_fall_finished)

	if DebugLogger.gravity:
		print("[GRAVITY] ", animal_name,
			" caindo de feet_y:", "%.0f" % feet_y,
			" -> target_feet_y:", "%.0f" % target_feet_y,
			" | duracao:", "%.2f" % fall_duration, "s")

func _cancel_transition() -> void:
	"""Cancela qualquer transição em andamento (FALL ou FLY). Chamado ao iniciar drag ou clicar."""
	if current_state == AnimalState.IDLE:
		return
	if DebugLogger.gravity:
		print("[FSM CANCEL] ", animal_name, " estado:", AnimalState.keys()[current_state], " em y:", "%.0f" % global_position.y)
	transition_to(AnimalState.IDLE)

func _on_fall_finished():
	"""Callback do tween de queda. Ajusta plano e salva estado."""
	fall_tween = null
	if DebugLogger.gravity: print("[GRAVITY LAND] ", animal_name, " pousou em y:", "%.0f" % global_position.y)
	transition_to(AnimalState.IDLE)
	check_plane_change()
	var world_manager := get_tree().get_first_node_in_group("world_manager")
	if world_manager and world_manager.has_method("save_animal_state"):
		world_manager.save_animal_state(self)

# ─────────────────────────────────────────────────────────────────────────────

func play_click_animation():
	var tween = create_tween()
	tween.tween_property(sprite, "position", Vector2(0, -20), 0.15)
	tween.tween_property(sprite, "position", Vector2(0, 0), 0.15)

func play_sound():
	if animal_sound:
		print("🔊 ", animal_name, " fez seu som!")

func play_plane_change_sound():
	pass  # Sound implementation here

func zoom_camera():
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("zoom_to_target"):
		camera.zoom_to_target(global_position)
	else:
		var tween = create_tween()
		tween.tween_property(camera, "zoom", Vector2(1.5, 1.5), 0.3)
		await tween.finished
		await get_tree().create_timer(1.0).timeout
		var tween2 = create_tween()
		tween2.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.3)

func reveal():
	if is_hidden:
		is_hidden = false
		visible = true

		scale = Vector2(0.1, 0.1)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		# Após a animação de reveal, verificar se o animal precisa cair.
		tween.tween_callback(apply_gravity)

		play_sound()

func _exit_tree():
	if mouse_captured:
		mouse_captured = false
		set_process_input(false)
		if is_being_dragged:
			emit_signal("animal_drag_ended", self)
