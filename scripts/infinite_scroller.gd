extends Node2D
@export var world_width := 1920.0
#@export var world_width := 3840.0
@export var segment_scenes: Array[PackedScene] = []

var segments := []
var camera_x := 0.0
var next_segment_index := 0
var recycled_this_frame := {}  # Prevent recycling same segment multiple times per frame

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
	# Store scene_index as metadata for tracking
	segment.set_meta("scene_index", scene_index)
	add_child(segment)
	
	segments.append({
		"node": segment,
		"position_offset": offset,
		"scene_index": scene_index
	})
	
	# Restaurar estado dos animais
	call_deferred("restore_segment_animals", segment)
	
	next_segment_index += 1
	print("[SEGMENT CREATE] offset:", offset, "| scene_index:", scene_index, "| pos_x:", segment.position.x)

func restore_segment_animals(segment):
	await get_tree().process_frame
	
	var world_manager = get_parent()
	if not world_manager.has_method("restore_animal_state"):
		return
	
	# First, restore any animals that already exist in the segment
	var animals = []
	find_animals_recursive(segment, animals)
	
	for animal in animals:
		world_manager.restore_animal_state(animal)
	
	# Then check if we need to create an animal that belongs to this scene
	if world_manager.has_method("check_and_create_missing_animal"):
		world_manager.check_and_create_missing_animal(segment)

func find_animals_recursive(node, animals_array):
	if node.is_in_group("animals"):
		animals_array.append(node)
	
	for child in node.get_children():
		find_animals_recursive(child, animals_array)

func save_segment_animals(segment):
	"""Save state of all animals before segment is destroyed"""
	var world_manager = get_parent()
	if not world_manager.has_method("save_animal_state"):
		return
	
	var animals = []
	find_animals_recursive(segment, animals)
	
	for animal in animals:
		world_manager.save_animal_state(animal)
		# Clear active reference so next instance can become active
		if world_manager.has_method("clear_active_animal"):
			world_manager.clear_active_animal(animal)

func update_camera_position(new_camera_x: float) -> void:
	camera_x = new_camera_x
	recycled_this_frame.clear()  # Reset tracking for this frame
	
	# Only recycle one segment per frame to prevent ping-pong effect
	var recycled_count = 0
	
	for i in range(segments.size()):
		if recycled_count > 0:
			break  # Only recycle one segment per frame
			
		# Skip if this segment was already recycled this frame
		if recycled_this_frame.has(i):
			continue
			
		var segment_data = segments[i]
		var segment = segment_data.node
		var distance = segment.position.x - camera_x
		
		# Recycle segments that are well out of view (add extra buffer to prevent ping-pong)
		if distance < -world_width * 1.5:
			var rightmost_x = get_rightmost_segment_x()
			recycle_segment(i, rightmost_x + world_width)
			recycled_this_frame[i] = true
			recycled_count += 1
		
		elif distance > world_width * 1.5:
			var leftmost_x = get_leftmost_segment_x()
			recycle_segment(i, leftmost_x - world_width)
			recycled_this_frame[i] = true
			recycled_count += 1

# FUNÇÃO REMOVIDA: save_segment_animals()

func recycle_segment(index: int, new_x: float) -> void:
	var old_segment = segments[index].node
	var old_scene_index = segments[index].get("scene_index", -1)
	
	# Log animals before destroying
	var animals_before = []
	find_animals_recursive(old_segment, animals_before)
	print("[SEGMENT RECYCLE] Destroying scene_index:", old_scene_index, "| animals:", animals_before.size())
	
	# Save animal states preserving their WORLD positions
	var world_manager = get_parent()
	for animal in animals_before:
		if world_manager.has_method("save_animal_state_for_recycle"):
			world_manager.save_animal_state_for_recycle(animal)
		# Clear active reference so next instance can become active
		if world_manager.has_method("clear_active_animal"):
			world_manager.clear_active_animal(animal)
	
	old_segment.queue_free()
	
	# Choose scene_index based on neighboring segments to maintain alternation
	var scene_index = get_alternating_scene_index(new_x)
	
	var new_segment = segment_scenes[scene_index].instantiate()
	new_segment.position.x = new_x
	new_segment.set_meta("scene_index", scene_index)
	add_child(new_segment)
	
	segments[index].node = new_segment
	segments[index].scene_index = scene_index
	
	print("[SEGMENT RECYCLE] Created scene_index:", scene_index, "| pos_x:", new_x)
	
	# Restaurar estado dos animais
	call_deferred("restore_segment_animals", new_segment)
	
	next_segment_index += 1

func get_alternating_scene_index(new_position_x: float) -> int:
	"""Choose scene index based on spatial position to maintain cycling pattern"""
	
	# Calculate which offset position this segment is at
	var offset = round(new_position_x / world_width)
	
	# Use the offset to cycle through scenes: ..., 2, 0, 1, 2, 0, 1, ...
	# The +1 shift is because initial segments start with offset -1 = scene 0, offset 0 = scene 1
	var scene_index = posmod(offset + 1, segment_scenes.size())
	
	return scene_index

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
