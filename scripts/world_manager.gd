extends Node2D

const DRAG_SPEED = 1.5
const WORLD_WIDTH = 3840.0  # Mesmo valor do infinite_scroller

@onready var camera: Camera2D = $Camera2D
@onready var infinite_scroller: Node2D = $InfiniteScroller

var camera_position: float = 0.0
var is_dragging := false
var last_mouse_pos := Vector2.ZERO
var is_animal_being_dragged := false

# Sistema de persistência baseado em posição no mundo circular
var animals_state := {}  # animal_unique_id -> {plane, position, scale, etc}

func _ready():
	# Adicionar ao grupo para ser encontrado facilmente
	add_to_group("world_manager")
	
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2.ZERO
	camera_position = 0.0
	
	connect_animal_signals()

func connect_animal_signals():
	await get_tree().process_frame
	
	var animals = get_tree().get_nodes_in_group("animals")
	print("🔍 Encontrados ", animals.size(), " animais")
	
	for animal in animals:
		print("  - Conectando: ", animal.name)
		if animal.has_signal("animal_drag_started"):
			animal.animal_drag_started.connect(_on_animal_drag_started)
		if animal.has_signal("animal_drag_ended"):
			animal.animal_drag_ended.connect(_on_animal_drag_ended)
		
		register_animal(animal)

func register_animal(animal):
	var animal_id = get_animal_unique_id(animal)
	
	if not animals_state.has(animal_id):
		animals_state[animal_id] = {
			"plane": animal.current_plane,
			"local_position": animal.position,
			"scale": animal.scale,
			"is_hidden": animal.is_hidden
		}
		print("  📝 Animal registrado: ", animal_id)

func get_animal_unique_id(animal) -> String:
	# ID baseado em: segmento_index + caminho do animal
	var segment = get_segment_for_animal(animal)
	if not segment:
		return animal.name
	
	# Calcular qual "slot" do mundo circular este segmento representa
	var segment_x = segment.position.x
	var segment_slot = int(round(segment_x / WORLD_WIDTH))
	
	# Normalizar para 0 ou 1 (já que alternamos entre 2 cenas)
	segment_slot = posmod(segment_slot, 2)
	
	var parent = animal.get_parent()
	var path = parent.name + "/" + animal.name if parent else animal.name
	
	return "slot_" + str(segment_slot) + "/" + path

func get_segment_for_animal(animal) -> Node2D:
	var current = animal.get_parent()
	while current:
		if current.get_parent() == infinite_scroller:
			return current
		current = current.get_parent()
	return null

func save_animal_state(animal):
	var animal_id = get_animal_unique_id(animal)
	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"local_position": animal.position,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden
	}
	print("💾 Estado salvo: ", animal_id, " | Plano: ", animal.current_plane, " | Pos: ", animal.position)

func restore_animal_state(animal):
	var animal_id = get_animal_unique_id(animal)
	
	if animals_state.has(animal_id):
		var state = animals_state[animal_id]
		animal.current_plane = state.plane
		animal.position = state.local_position
		animal.scale = state.scale
		animal.is_hidden = state.is_hidden
		
		if animal.current_plane == "plane2":
			animal.z_index = 0
		else:
			animal.z_index = 10
		
		print("📂 Estado restaurado: ", animal_id, " | Plano: ", animal.current_plane, " | Pos: ", animal.position)
		return true
	else:
		print("⚠️ Nenhum estado salvo para: ", animal_id)
	return false

func _on_animal_drag_started(_animal):
	is_animal_being_dragged = true
	is_dragging = false
	print("🔒 Drag da câmera bloqueado")

func _on_animal_drag_ended(animal):
	is_animal_being_dragged = false
	is_dragging = false
	print("🔓 Drag da câmera liberado")

func _input(event):
	if is_animal_being_dragged:
		if is_dragging:
			is_dragging = false
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				last_mouse_pos = event.position
			else:
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		var delta_x = event.position.x - last_mouse_pos.x
		camera_position -= delta_x * DRAG_SPEED
		last_mouse_pos = event.position

func _process(delta: float):
	camera.position.x = lerp(camera.position.x, camera_position, delta * 10.0)
	
	if infinite_scroller:
		infinite_scroller.update_camera_position(camera.position.x)
