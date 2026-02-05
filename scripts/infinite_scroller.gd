extends Node2D

@export var world_width := 2052.0
@export var segment_scenes: Array[PackedScene] = []

var segments := []
var camera_x := 0.0
var next_segment_index := 0

func _ready():
	if segment_scenes.is_empty():
		push_error("ERRO: Adicione pelo menos 1 segment_scene!")
		return
	
	# Criar 3 segmentos iniciais
	for i in range(3):
		create_segment_at_offset(i - 1)

func create_segment_at_offset(offset: int) -> void:
	# Escolher qual sprite usar (alternando)
	var scene_index = next_segment_index % segment_scenes.size()
	var segment = segment_scenes[scene_index].instantiate()
	
	segment.position.x = offset * world_width
	add_child(segment)
	
	segments.append({
		"node": segment,
		"position_offset": offset
	})
	
	next_segment_index += 1
	print("Segmento criado no offset ", offset, " usando sprite ", scene_index)

func update_camera_position(new_camera_x: float) -> void:
	camera_x = new_camera_x
	
	for i in range(segments.size()):
		var segment_data = segments[i]
		var segment = segment_data.node
		var distance = segment.position.x - camera_x
		
		# Se está muito à esquerda (jogador foi para direita)
		if distance < -world_width:
			# Destruir e recriar na direita com próxima sprite
			var rightmost_x = get_rightmost_segment_x()
			recycle_segment(i, rightmost_x + world_width)
		
		# Se está muito à direita (jogador foi para esquerda)
		elif distance > world_width * 2:
			# Destruir e recriar na esquerda com próxima sprite
			var leftmost_x = get_leftmost_segment_x()
			recycle_segment(i, leftmost_x - world_width)

func recycle_segment(index: int, new_x: float) -> void:
	# Remover o segmento antigo
	var old_segment = segments[index].node
	old_segment.queue_free()
	
	# Criar novo segmento com próxima sprite
	var scene_index = next_segment_index % segment_scenes.size()
	var new_segment = segment_scenes[scene_index].instantiate()
	new_segment.position.x = new_x
	add_child(new_segment)
	
	# Atualizar referência
	segments[index].node = new_segment
	
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
