extends Node2D
class_name Animal

signal animal_clicked(animal: Animal)
signal animal_drag_started(animal: Animal)
signal animal_drag_ended(animal: Animal)

@export var animal_name := "Capivara"
@export var animal_sound: AudioStream  # Som do animal
@export_enum("plane1", "plane2") var current_plane := "plane2"
@export var is_hidden := false  # Se está escondido em moita

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var is_being_dragged := false
var drag_offset := Vector2.ZERO
var original_position := Vector2.ZERO
var press_timer := 0.0
const LONG_PRESS_TIME := 0.5
var is_pressed := false

func _ready():
	# Adicionar ao grupo para ser detectado pelo WorldManager
	add_to_group("animals")
	
	# Conectar sinais do Area2D
	area.input_event.connect(_on_area_input_event)
	original_position = position
	
	# Se está escondido, ficar invisível
	if is_hidden:
		visible = false
	
	# Definir z-index baseado no plano inicial
	if current_plane == "plane2":
		z_index = 0
	else:
		z_index = 10

func _on_area_input_event(_viewport, event: InputEvent, _shape_idx):
	if is_hidden:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_pressed = true
			press_timer = 0.0
			get_viewport().set_input_as_handled()  # Consumir evento
		else:
			if is_pressed:
				if press_timer < LONG_PRESS_TIME:
					on_click()
				else:
					end_drag()
				is_pressed = false
				press_timer = 0.0
			get_viewport().set_input_as_handled()  # Consumir evento

func _process(delta):
	if is_pressed and not is_being_dragged:
		press_timer += delta
		if press_timer >= LONG_PRESS_TIME:
			# Iniciou drag
			start_drag()

func _input(event):
	if is_being_dragged and event is InputEventMouseMotion:
		# Atualizar posição durante drag
		global_position = get_global_mouse_position() + drag_offset
		get_viewport().set_input_as_handled()  # Consumir evento de movimento

func on_click():
	print(animal_name, " clicado!")
	emit_signal("animal_clicked", self)
	play_click_animation()
	play_sound()
	zoom_camera()

func start_drag():
	if is_being_dragged:
		return
	
	print(animal_name, " começou a ser arrastado")
	is_being_dragged = true
	drag_offset = global_position - get_global_mouse_position()
	
	# Visual feedback
	modulate = Color(1, 1, 1, 0.7)  # Transparente
	z_index = 100  # Trazer para frente
	
	emit_signal("animal_drag_started", self)

func end_drag():
	if not is_being_dragged:
		return
	
	print(animal_name, " terminou de ser arrastado")
	is_being_dragged = false
	
	# Restaurar visual
	modulate = Color(1, 1, 1, 1)
	z_index = 0
	
	emit_signal("animal_drag_ended", self)
	
	# DEBUG: Verificar posição e plano
	print("  Posição Y global: ", global_position.y)
	print("  Plano atual: ", current_plane)
	
	# Determinar em qual plano foi solto
	check_plane_change()

func check_plane_change():
	# Usar a câmera para determinar o viewport real
	var camera = get_viewport().get_camera_2d()
	if not camera:
		print("  ⚠️ Câmera não encontrada!")
		return
	
	# Pegar o tamanho real da viewport visível
	var viewport_size = get_viewport_rect().size
	var camera_pos = camera.global_position
	
	# Calcular os limites visíveis da câmera
	var camera_top = camera_pos.y - (viewport_size.y / (2.0 * camera.zoom.y))
	var camera_bottom = camera_pos.y + (viewport_size.y / (2.0 * camera.zoom.y))
	var camera_middle = (camera_top + camera_bottom) / 2.0
	
	# Divisão em 60% da altura visível
	var division_y = camera_top + (camera_bottom - camera_top) * 0.6
	
	print("  Câmera Y: ", camera_pos.y)
	print("  Topo visível: ", camera_top)
	print("  Fundo visível: ", camera_bottom)
	print("  Divisão em Y: ", division_y)
	print("  Animal está em Y: ", global_position.y)
	
	var new_plane = ""
	
	if global_position.y < division_y:
		new_plane = "plane2"
		print("  → Está acima da divisão = PLANO 2")
	else:
		new_plane = "plane1"
		print("  → Está abaixo da divisão = PLANO 1")
	
	print("  Plano atual: ", current_plane, " | Novo plano: ", new_plane)
	
	if current_plane != new_plane:
		change_to_plane(new_plane)
	else:
		print("  ⚠️ Já está neste plano, não mudou")

func change_to_plane(new_plane: String):
	var old_plane = current_plane
	current_plane = new_plane
	
	print("🔄 ", animal_name, " mudou: ", old_plane, " → ", new_plane)
	
	# FEEDBACK VISUAL 1: Escala
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
	
	# Animar escala
	tween.tween_property(self, "scale", target_scale, 0.3).set_ease(Tween.EASE_OUT)
	
	# FEEDBACK VISUAL 2: Cor temporária
	tween.tween_property(self, "modulate", Color(0.5, 0.5, 1.0), 0.15)
	tween.chain().tween_property(self, "modulate", Color(1, 1, 1), 0.15)
	
	# Aguardar animação terminar e DEPOIS salvar estado
	await tween.finished
	
	# NOVO: Notificar WorldManager para salvar estado AGORA
	var world_manager = get_tree().get_first_node_in_group("world_manager")
	if world_manager and world_manager.has_method("save_animal_state"):
		world_manager.save_animal_state(self)
	
	# Som de mudança
	play_plane_change_sound()

func play_click_animation():
	# Animação de "pulo"
	var tween = create_tween()
	tween.tween_property(sprite, "position", Vector2(0, -20), 0.15)
	tween.tween_property(sprite, "position", Vector2(0, 0), 0.15)

func play_sound():
	if animal_sound:
		# Vamos implementar audio depois
		print("🔊 ", animal_name, " fez seu som!")

func play_plane_change_sound():
	print("🔊 Som de mudança de plano")

func zoom_camera():
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("zoom_to_target"):
		camera.zoom_to_target(global_position)
	else:
		# Zoom simples
		var tween = create_tween()
		tween.tween_property(camera, "zoom", Vector2(1.5, 1.5), 0.3)
		await tween.finished
		await get_tree().create_timer(1.0).timeout
		var tween2 = create_tween()
		tween2.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.3)

func reveal():
	# Chamado quando sai da moita
	if is_hidden:
		is_hidden = false
		visible = true
		
		# Animação de aparecer
		scale = Vector2(0.1, 0.1)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		
		play_sound()
