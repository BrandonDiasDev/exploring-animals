extends Node2D
class_name Animal

signal animal_clicked(animal: Animal)
signal animal_drag_started(animal: Animal)
signal animal_drag_ended(animal: Animal)

@export var animal_name := "Capivara"
@export var animal_sound: AudioStream
@export_enum("plane1", "plane2") var current_plane := "plane2"
@export var is_hidden := false

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

func _ready():
	add_to_group("animals")
	
	area.input_event.connect(_on_area_input_event)
	original_position = position
	
	if is_hidden:
		visible = false
	
	_sync_visual_to_plane()

func _sync_visual_to_plane():
	"""Garantir que propriedades visuais correspondem ao plano atual"""
	if current_plane == "plane2":
		z_index = 100  # Ensure plane2 animals are above all segment contents
		var expected_scale = Vector2(0.6, 0.6)
		if scale != expected_scale:
			scale = expected_scale
	else:  # plane1
		z_index = 200  # Ensure plane1 animals are above plane2 and all segment contents
		var expected_scale = Vector2(1.0, 1.0)
		if scale != expected_scale:
			scale = expected_scale

func _on_area_input_event(_viewport, event: InputEvent, _shape_idx):
	if is_hidden:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
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
			print("[INPUT] ", animal_name, " >> CLICK | timer:", "%.3f" % timer_snapshot, " | was_dragging:", was_dragging)
			on_click()
		else:
			# Long press - terminou o drag
			if is_being_dragged:
				print("[INPUT] ", animal_name, " >> DRAG END | timer:", "%.3f" % timer_snapshot, " | gpos:", global_position)
				end_drag()
			else:
				print("[INPUT] ", animal_name, " >> LONG HOLD (sem drag) | timer:", "%.3f" % timer_snapshot)
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

func on_click():
	emit_signal("animal_clicked", self)
	play_click_animation()
	play_sound()
	zoom_camera()

func start_drag():
	if is_being_dragged:
		return
	
	if not is_pressed or not mouse_captured:
		return
	
	print("[DRAG START] Animal:", animal_name, "| pos:", position)
	is_being_dragged = true
	drag_offset = global_position - get_global_mouse_position()
	
	modulate = Color(1, 1, 1, 0.7)
	z_index = 100
	
	emit_signal("animal_drag_started", self)

func end_drag():
	if not is_being_dragged:
		return
	
	print("[DRAG END] Animal:", animal_name, " | gpos:", global_position)
	is_being_dragged = false
	
	modulate = Color(1, 1, 1, 1)
	z_index = 0 if current_plane == "plane2" else 10
	
	emit_signal("animal_drag_ended", self)
	
	# Aguardar um frame de física para as sobreposições serem atualizadas
	await get_tree().physics_frame
	
	var bush_result = _check_bush_drop()
	if bush_result == "accepted" or bush_result == "rejected":
		return  # A moita assume o controle a partir daqui
	
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
	
	print("[BOUNCE] ", animal_name, " pousou em:", global_position)
	
	# Ajustar plano e salvar estado na posição final
	check_plane_change()
	var world_manager = get_tree().get_first_node_in_group("world_manager")
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
	
	var new_plane = ""
	if global_position.y < division_y:
		new_plane = "plane2"
	else:
		new_plane = "plane1"
	
	if current_plane != new_plane:
		print("[PLANE CHANGE] ", current_plane, " -> ", new_plane)
		change_to_plane(new_plane)

func change_to_plane(new_plane: String):
	var old_plane = current_plane
	current_plane = new_plane
	
	var target_scale = Vector2.ZERO
	var target_z_index = 0
	
	if new_plane == "plane2":
		target_scale = Vector2(0.6, 0.6)
		target_z_index = 0
	else:
		target_scale = Vector2(1.0, 1.0)
		target_z_index = 10
	
	z_index = target_z_index
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(self, "scale", target_scale, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color(0.5, 0.5, 1.0), 0.15)
	tween.chain().tween_property(self, "modulate", Color(1, 1, 1), 0.15)
	
	await tween.finished
	play_plane_change_sound()

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
		
		play_sound()

func _exit_tree():
	if mouse_captured:
		mouse_captured = false
		set_process_input(false)
		if is_being_dragged:
			emit_signal("animal_drag_ended", self)
