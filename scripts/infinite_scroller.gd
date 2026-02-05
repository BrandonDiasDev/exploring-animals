extends Node2D

@export var world_width := 3840.0
@export var segment_scenes: Array[PackedScene] = []

var segments := []
var camera_x := 0.0
var next_segment_index := 0

func _ready():
	if segment_scenes.is_empty():
		push_error("ERRO: Adicione pelo menos 1 segment_scene!")
		return
	
	for i in range(3):
		create_segment_at_offset(i - 1)

func create_segment_at_offset(offset: int) -> void:
	var scene_index = next_segment_index % segment_scenes.size()
	var segment = segment_scenes[scene_index].instantiate()
	
	segment.position.x = offset * world_width
	add_child(segment)
	
	segments.append({
		"node": segment,
		"position_offset": offset
	})
	
	# Restaurar estado dos animais
	call_deferred("restore_segment_animals", segment)
	
	next_segment_index += 1
	print("Segmento criado no offset ", offset, " usando sprite ", scene_index)

func restore_segment_animals(segment):
	await get_tree().process_frame
	
	var world_manager = get_parent()
	if not world_manager.has_method("restore_animal_state"):
		return
	
	var animals = []
	find_animals_recursive(segment, animals)
	
	for animal in animals:
		world_manager.restore_animal_state(animal)

func find_animals_recursive(node, animals_array):
	if node.is_in_group("animals"):
		animals_array.append(node)
	
	for child in node.get_children():
		find_animals_recursive(child, animals_array)

func update_camera_position(new_camera_x: float) -> void:
	camera_x = new_camera_x
	
	for i in range(segments.size()):
		var segment_data = segments[i]
		var segment = segment_data.node
		var distance = segment.position.x - camera_x
		
		if distance < -world_width:
			# REMOVIDO: save_segment_animals(segment)
			var rightmost_x = get_rightmost_segment_x()
			recycle_segment(i, rightmost_x + world_width)
		
		elif distance > world_width * 2:
			# REMOVIDO: save_segment_animals(segment)
			var leftmost_x = get_leftmost_segment_x()
			recycle_segment(i, leftmost_x - world_width)

# FUNÇÃO REMOVIDA: save_segment_animals()

func recycle_segment(index: int, new_x: float) -> void:
	var old_segment = segments[index].node
	old_segment.queue_free()
	
	var scene_index = next_segment_index % segment_scenes.size()
	var new_segment = segment_scenes[scene_index].instantiate()
	new_segment.position.x = new_x
	add_child(new_segment)
	
	segments[index].node = new_segment
	
	# Restaurar estado dos animais
	call_deferred("restore_segment_animals", new_segment)
	
	next_segment_index += 1
	print("Segmento reciclado na posição ", new_x, " usando sprite ", scene_index)

func get_rightmost_segment_x() -> float:
	var max_x = -INF
	for seg in segments:
		if seg.node.position.x > max_x:
			max_x = seg.node.position.x
	return max_x

func get_leftmost_segment_x() -> float:
	var min_x = INF
	for seg in segments:
		if seg.node.position.x < min_x:
			min_x = seg.node.position.x
	return min_x
