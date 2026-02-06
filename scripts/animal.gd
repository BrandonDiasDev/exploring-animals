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
	
	# NOVO: Validar que escala e z-index estão consistentes com o plano
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
	
	mouse_captured = false
	set_process_input(false)
	
	if is_pressed:
		if press_timer < LONG_PRESS_TIME:
			# Clique simples
			on_click()
		else:
			# Long press - terminou o drag
			if is_being_dragged:  # NOVO: Só terminar drag se realmente estava arrastando
				end_drag()
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
	
	print("[DRAG END] Animal:", animal_name, "| pos:", position)
	is_being_dragged = false
	
	modulate = Color(1, 1, 1, 1)
	z_index = 0 if current_plane == "plane2" else 10
	
	emit_signal("animal_drag_ended", self)
	
	check_plane_change()
	
	# Save state after drag
	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager and world_manager.has_method("save_animal_state"):
		world_manager.save_animal_state(self)

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
