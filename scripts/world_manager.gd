extends Node2D

const DRAG_SPEED = 1.5

@onready var camera: Camera2D = $Camera2D
@onready var infinite_scroller: Node2D = $InfiniteScroller

var camera_position: float = 0.0
var is_dragging := false
var last_mouse_pos := Vector2.ZERO
var is_animal_being_dragged := false
var can_start_camera_drag := true  # NOVO

var animals_state := {}
var world_width: float = 0.0

func _ready():
	add_to_group("world_manager")
	
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2.ZERO
	camera_position = 0.0
	
	if infinite_scroller:
		world_width = infinite_scroller.world_width
	else:
		push_error("InfiniteScroller não encontrado!")
		world_width = 1920.0
	
	connect_animal_signals()

func connect_animal_signals():
	await get_tree().process_frame
	
	var animals = get_tree().get_nodes_in_group("animals")
	
	for animal in animals:
		if animal.has_signal("animal_drag_started"):
			animal.animal_drag_started.connect(_on_animal_drag_started)
		if animal.has_signal("animal_drag_ended"):
			animal.animal_drag_ended.connect(_on_animal_drag_ended)
		if animal.has_signal("animal_clicked"):
			animal.animal_clicked.connect(_on_animal_clicked)



func get_animal_unique_id(animal) -> String:
	# Use just the animal's name, not the parent path, so ID stays constant
	# across plane changes
	return "animal/" + animal.name

func get_segment_for_animal(animal) -> Node2D:
	var current = animal.get_parent()
	while current:
		if current.get_parent() == infinite_scroller:
			return current
		current = current.get_parent()
	return null

func save_animal_state(animal):
	var animal_id = get_animal_unique_id(animal)
	
	if not animal.visible:
		print("[SAVE] SKIPPED - hidden duplicate")
		return
	
	# Determine which segment the animal's position falls within
	var animal_global_pos = animal.global_position
	var target_segment = find_segment_containing_position(animal_global_pos)
	
	if not target_segment:
		print("[SAVE ERROR] No segment contains position:", animal_global_pos)
		return
	
	var scene_index = target_segment.get_meta("scene_index", -1)
	var local_pos = animal_global_pos - target_segment.global_position
	
	# Check if animal needs to move to a different segment physically
	var current_segment = get_segment_for_animal(animal)
	if current_segment and current_segment != target_segment:
		var current_scene_idx = current_segment.get_meta("scene_index", -1)
		print("[SAVE] Animal crossing from scene:", current_scene_idx, " to scene:", scene_index, " | global_pos:", animal_global_pos)
		move_animal_to_segment(animal, target_segment, local_pos)
		# Update local_pos after move
		local_pos = animal.global_position - target_segment.global_position
	
	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"scene_index": scene_index,
		"local_position": local_pos,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden
	}
	print("[SAVE] id:", animal_id, " | scene_index:", scene_index, " | local_pos:", local_pos, " | plane:", animal.current_plane)

func move_animal_to_segment(animal, target_segment: Node2D, target_local_pos: Vector2):
	"""Physically move animal node to a different segment"""
	# Convert plane name: "plane1" -> "Plane1", "plane2" -> "Plane2"
	var plane_number = animal.current_plane.substr(5, 1)  # Get the number
	var target_plane_name = "Plane" + plane_number
	
	var target_plane = target_segment.get_node_or_null(target_plane_name)
	
	if not target_plane:
		print("[MOVE ERROR] Target plane '", target_plane_name, "' not found in segment | Available children:")
		for child in target_segment.get_children():
			print("  - ", child.name)
		return
	
	# Store global position before moving
	var old_global_pos = animal.global_position
	
	# Remove from current parent
	var old_parent = animal.get_parent()
	if old_parent:
		old_parent.remove_child(animal)
	
	# Add to new parent
	target_plane.add_child(animal)
	animal.global_position = old_global_pos  # Maintain world position during move
	
	# Reconnect signals after reparenting
	reconnect_animal_signals(animal)
	
	print("[MOVE] Animal moved to segment scene_index:", target_segment.get_meta("scene_index", -1), " | new parent:", target_plane.name, " | global_pos:", animal.global_position)

func find_segment_containing_position(global_pos: Vector2) -> Node2D:
	"""Find which segment contains the given global position"""
	if not infinite_scroller:
		return null
	
	var segments = infinite_scroller.segments
	var closest_segment = null
	var min_distance = INF
	
	for segment_data in segments:
		var segment = segment_data["node"]
		var segment_x = segment.global_position.x
		var distance = abs(global_pos.x - segment_x)
		
		if distance < min_distance:
			min_distance = distance
			closest_segment = segment
	
	return closest_segment

func check_and_create_missing_animal(segment: Node2D):
	"""Check if an animal should exist in this segment and create it if missing"""
	var segment_scene_index = segment.get_meta("scene_index", -1)
	
	# Check all saved animal states to see if any belong to this scene
	for animal_id in animals_state:
		if animal_id.ends_with("_active_node"):
			continue  # Skip the active node markers
		
		var state = animals_state[animal_id]
		if not state is Dictionary:
			continue
		
		var saved_scene_index = state.get("scene_index", -1)
		
		# Does this animal belong to this scene?
		if saved_scene_index == segment_scene_index:
			# Check if active instance already exists anywhere
			var active_key = animal_id + "_active_node"
			if animals_state.has(active_key):
				var active_animal = animals_state[active_key]
				if is_instance_valid(active_animal):
					print("[CREATE MISSING] SKIP - active instance already exists")
					return
			
			# No active instance - create it
			print("[CREATE MISSING] scene_index:", segment_scene_index, " needs animal:", animal_id)
			create_animal_in_segment(segment, animal_id, state)
			return  # Only one animal per game

func create_animal_in_segment(segment: Node2D, animal_id: String, state: Dictionary):
	"""Instantiate a new animal node and restore its state"""
	# Load the animal scene
	var animal_scene = load("res://scenes/components/capivara.tscn")
	if not animal_scene:
		print("[CREATE ERROR] Could not load animal scene")
		return
	
	var animal = animal_scene.instantiate()
	
	# Get the correct plane parent
	var plane_name = "Plane1" if state["plane"] == "plane1" else "Plane2"
	var plane = segment.get_node_or_null(plane_name)
	
	if not plane:
		print("[CREATE ERROR] Plane", plane_name, "not found in segment")
		animal.queue_free()
		return
	
	# Add to plane
	plane.add_child(animal)
	
	# Restore state
	animal.current_plane = state["plane"]
	animal.position = state["local_position"]
	animal.scale = state["scale"]
	animal.is_hidden = state.get("is_hidden", false)
	animal.visible = not animal.is_hidden
	
	# Set z_index
	if animal.current_plane == "plane2":
		animal.z_index = 100
	else:
		animal.z_index = 200
	
	# Sync visual
	if animal.has_method("_sync_visual_to_plane"):
		animal._sync_visual_to_plane()
	
	# Mark as active
	animals_state[animal_id + "_active_node"] = animal
	
	# Connect signals
	await get_tree().process_frame
	reconnect_animal_signals(animal)
	
	print("[CREATE MISSING] Created animal in scene:", segment.get_meta("scene_index", -1), " | pos:", animal.position, " | global_pos:", animal.global_position)

func save_animal_state_for_recycle(animal):
	var animal_id = get_animal_unique_id(animal)
	
	if not animal.visible:
		return
	
	# Get which scene is being recycled
	var segment = get_segment_for_animal(animal)
	if not segment:
		return
	
	var segment_scene_index = segment.get_meta("scene_index", -1)
	
	# Check if animal already has a saved state
	if animals_state.has(animal_id):
		var saved_scene_index = animals_state[animal_id].get("scene_index", -1)
		
		# If animal was moved to a different scene, don't overwrite with old segment data
		if saved_scene_index != segment_scene_index:
			print("[SAVE RECYCLE] SKIP - animal belongs to scene:", saved_scene_index, "| this segment:", segment_scene_index)
			return
	
	# Animal belongs to this segment - save its state
	var local_pos = animal.position
	
	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"scene_index": segment_scene_index,
		"local_position": local_pos,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden
	}
	print("[SAVE RECYCLE] id:", animal_id, "| scene_index:", segment_scene_index, "| local_pos:", local_pos)

func restore_animal_state(animal):
	var animal_id = get_animal_unique_id(animal)
	
	# Check if another animal with same ID already exists and is active
	if animals_state.has(animal_id + "_active_node"):
		var active_animal = animals_state[animal_id + "_active_node"]
		if is_instance_valid(active_animal) and active_animal != animal:
			# Another instance already claimed this animal - hide this duplicate
			animal.visible = false
			animal.set_process(false)
			animal.set_physics_process(false)
			if animal.has_method("set_process_input"):
				animal.set_process_input(false)
			# Disable the area so it can't be clicked
			if animal.has_node("Area2D"):
				animal.get_node("Area2D").set_deferred("monitoring", false)
				animal.get_node("Area2D").set_deferred("monitorable", false)
			print("[RESTORE] HIDING - another instance already active")
			return false
	
	# No active instance yet - mark this as active
	animals_state[animal_id + "_active_node"] = animal
	
	if animals_state.has(animal_id):
		var state = animals_state[animal_id]
		
		# Check if this animal belongs to this segment's scene
		var segment = get_segment_for_animal(animal)
		if not segment:
			print("[RESTORE ERROR] No segment found")
			return false
		
		var this_scene_index = segment.get_meta("scene_index", -1)
		var saved_scene_index = state.get("scene_index", -1)
		
		if this_scene_index != saved_scene_index:
			# Animal belongs to different scene - hide this instance
			animal.visible = false
			animal.set_process(false)
			animal.set_physics_process(false)
			if animal.has_method("set_process_input"):
				animal.set_process_input(false)
			if animal.has_node("Area2D"):
				animal.get_node("Area2D").set_deferred("monitoring", false)
				animal.get_node("Area2D").set_deferred("monitorable", false)
			print("[RESTORE] WRONG SCENE - this:", this_scene_index, "| saved:", saved_scene_index, "| HIDING | global_pos:", animal.global_position)
			return false
		
		# Correct scene - restore animal here
		animal.current_plane = state["plane"]
		
		if state.has("local_position"):
			animal.position = state["local_position"]
			print("[RESTORE] scene_index:", this_scene_index, "| local_pos:", state["local_position"], "| global_pos:", animal.global_position, "| MATCH!")
		
		animal.scale = state["scale"]
		animal.is_hidden = state["is_hidden"]
		animal.visible = not state["is_hidden"]
		print("[RESTORE] Setting visible:", animal.visible, "| is_hidden:", state["is_hidden"])
		animal.set_process(true)
		animal.set_physics_process(true)
		if animal.has_method("set_process_input"):
			animal.set_process_input(true)
		
		if animal.current_plane == "plane2":
			animal.z_index = 100
		else:
			animal.z_index = 200
		
		if animal.has_method("_sync_visual_to_plane"):
			animal._sync_visual_to_plane()
		
		reconnect_animal_signals(animal)
		
		print("[RESTORE] id:", animal_id, "| plane:", state["plane"], "| final_global_pos:", animal.global_position, "| ACTIVE")
		return true
	else:
		# First time - save initial state based on which segment animal was created in
		var segment = get_segment_for_animal(animal)
		if segment:
			var scene_index = segment.get_meta("scene_index", -1)
			var this_scene_index = scene_index
			
			# Save initial state
			animals_state[animal_id] = {
				"plane": animal.current_plane,
				"scene_index": scene_index,
				"local_position": animal.position,
				"scale": animal.scale,
				"is_hidden": animal.is_hidden
			}
			print("[RESTORE] FIRST TIME - Saved initial state | scene_index:", scene_index, "| local_pos:", animal.position)
			
			# This is the correct scene for this animal
			animal.visible = true
			animal.set_process(true)
			animal.set_physics_process(true)
			if animal.has_method("set_process_input"):
				animal.set_process_input(true)
			if animal.current_plane == "plane2":
				animal.z_index = 100
			else:
				animal.z_index = 200
			animals_state[animal_id + "_active_node"] = animal
			reconnect_animal_signals(animal)
			return true
		else:
			print("[RESTORE ERROR] First time but no segment found")
			return false

func clear_active_animal(animal):
	"""Clear active reference when animal's segment is being destroyed"""
	var animal_id = get_animal_unique_id(animal)
	var active_key = animal_id + "_active_node"
	
	# Only clear active if this animal actually belongs to this segment's scene
	if animals_state.has(animal_id):
		var saved_scene_index = animals_state[animal_id].get("scene_index", -1)
		var segment = get_segment_for_animal(animal)
		if segment:
			var segment_scene_index = segment.get_meta("scene_index", -1)
			
			if saved_scene_index != segment_scene_index:
				print("[CLEAR ACTIVE] SKIP - animal belongs to scene:", saved_scene_index, "| this segment:", segment_scene_index)
				return
	
	if animals_state.has(active_key):
		var active_animal = animals_state[active_key]
		if active_animal == animal:
			animals_state.erase(active_key)
			print("[CLEAR ACTIVE] id:", animal_id)

func find_replacement_animal(animal_id: String):
	"""Find a visible animal to become the new active one"""
	var all_animals = get_tree().get_nodes_in_group("animals")
	
	for animal in all_animals:
		if get_animal_unique_id(animal) == animal_id and animal.visible:
			animals_state[animal_id + "_active_node"] = animal
			print("[REPLACEMENT] id:", animal_id, "| new active animal found")
			return

func reconnect_animal_signals(animal):
	"""Reconectar sinais de um animal (usado após reciclagem de segmento)"""
	
	# Desconectar se já estava conectado (evitar duplicatas)
	if animal.animal_drag_started.is_connected(_on_animal_drag_started):
		animal.animal_drag_started.disconnect(_on_animal_drag_started)
	if animal.animal_drag_ended.is_connected(_on_animal_drag_ended):
		animal.animal_drag_ended.disconnect(_on_animal_drag_ended)
	if animal.animal_clicked.is_connected(_on_animal_clicked):
		animal.animal_clicked.disconnect(_on_animal_clicked)
	
	# Reconectar
	if animal.has_signal("animal_drag_started"):
		animal.animal_drag_started.connect(_on_animal_drag_started)
	if animal.has_signal("animal_drag_ended"):
		animal.animal_drag_ended.connect(_on_animal_drag_ended)
	if animal.has_signal("animal_clicked"):
		animal.animal_clicked.connect(_on_animal_clicked)

func _on_animal_clicked(_animal):
	can_start_camera_drag = false
	await get_tree().process_frame
	can_start_camera_drag = true

func _on_animal_drag_started(_animal):
	is_animal_being_dragged = true
	is_dragging = false
	can_start_camera_drag = false

func _on_animal_drag_ended(animal):
	is_dragging = false
	await get_tree().create_timer(0.15).timeout
	is_animal_being_dragged = false

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
				if is_dragging:
					is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		if is_animal_being_dragged:
			is_dragging = false
			return
		
		var delta_x = event.position.x - last_mouse_pos.x
		camera_position -= delta_x * DRAG_SPEED
		last_mouse_pos = event.position

func _process(delta: float):
	if is_animal_being_dragged and is_dragging:
		is_dragging = false
	
	camera.position.x = lerp(camera.position.x, camera_position, delta * 10.0)
	
	if infinite_scroller:
		infinite_scroller.update_camera_position(camera.position.x)
