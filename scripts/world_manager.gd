extends Node2D

const DRAG_SPEED = 1.5

@onready var camera: Camera2D = $Camera2D
@onready var infinite_scroller: Node2D = $InfiniteScroller

var camera_position: float = 0.0
var is_dragging := false
var mouse_pressed := false  # Press confirmado, aguardando motion para virar drag
var last_mouse_pos := Vector2.ZERO
var is_animal_being_dragged := false
var can_start_camera_drag := true

var animals_state := {}
var bushes_state := {}
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
	connect_bush_signals()

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

func connect_bush_signals():
	await get_tree().process_frame
	
	var bushes = get_tree().get_nodes_in_group("bushes")
	for bush in bushes:
		reconnect_bush_signals(bush)

func reconnect_bush_signals(bush):
	if bush.has_signal("animal_revealed"):
		if bush.animal_revealed.is_connected(_on_bush_animal_revealed):
			bush.animal_revealed.disconnect(_on_bush_animal_revealed)
		bush.animal_revealed.connect(_on_bush_animal_revealed)
	if bush.has_signal("bush_clicked"):
		if bush.bush_clicked.is_connected(_on_bush_clicked):
			bush.bush_clicked.disconnect(_on_bush_clicked)
		bush.bush_clicked.connect(_on_bush_clicked)

func _on_bush_clicked():
	mouse_pressed = false
	is_dragging = false

func _on_bush_animal_revealed(animal: Animal):
	"""Quando um animal sai de uma moita, herda o plane da moita, reparentia e registra estado"""
	reconnect_animal_signals(animal)
	
	var animal_id = get_animal_unique_id(animal)
	var segment = get_segment_for_animal(animal)
	if not segment:
		print("[BUSH REVEAL ERROR] No segment found for ", animal_id)
		return
	
	# bush.gd already set animal.current_plane to the correct plane before emitting the signal
	# Just read it directly — no fragile parent-chain detection needed
	var inherited_plane = animal.current_plane
	var plane_number = inherited_plane.substr(5, 1)  # "plane1" -> "1", "plane2" -> "2"
	var target_plane_name = "Plane" + plane_number
	var target_plane = segment.get_node_or_null(target_plane_name)
	if not target_plane:
		print("[BUSH REVEAL ERROR] Plane '", target_plane_name, "' not found in segment")
		return
	print("[BUSH REVEAL] animal:", animal_id, " | inherited_plane:", inherited_plane, " | scale_before_reparent:", animal.scale)
	
	# Store current global position before reparenting
	var global_pos = animal.global_position
	
	# Remove from current parent (Bush or wherever it is now)
	var old_parent = animal.get_parent()
	if old_parent and old_parent != target_plane:
		old_parent.remove_child(animal)
		target_plane.add_child(animal)
	animal.global_position = global_pos  # Preserve world position
	
	# Sync visual properties to the new plane
	animal._sync_visual_to_plane()
	
	print("[BUSH REVEAL REPARENT] ", animal_id, " reparented to ", target_plane_name, " (inherited plane:", inherited_plane, ") in scene_index:", segment.get_meta("scene_index", -1))
	
	# Only register state if not already tracked
	if not animals_state.has(animal_id):
		# Get the animal's scene path
		var scene_path = animal.scene_file_path
		if not scene_path:
			scene_path = "res://scenes/components/capivara.tscn"
		
		# Save with the animal's ACTUAL current state (now inherited from bush)
		animals_state[animal_id] = {
			"plane": animal.current_plane,
			"scene_index": segment.get_meta("scene_index", -1),
			"local_position": animal.position,
			"scale": animal.scale,
			"is_hidden": animal.is_hidden,
			"scene_path": scene_path
		}
		animals_state[animal_id + "_active_node"] = animal
		print("[BUSH REVEAL] Registered animal:", animal_id, "| plane:", animal.current_plane, "| is_hidden:", animal.is_hidden)

# ─── Estado das moitas ──────────────────────────────────────────────────────────

func get_bush_unique_id(bush) -> String:
	return "bush/" + bush.name

func save_bush_state(bush):
	var bush_id = get_bush_unique_id(bush)
	var segment = get_node_or_null_in_parents(bush)
	if not segment:
		return
	bushes_state[bush_id] = {
		"is_revealed": bush.is_revealed,
		"scene_index": segment.get_meta("scene_index", -1)
	}

func restore_bush_state(bush):
	var bush_id = get_bush_unique_id(bush)
	if not bushes_state.has(bush_id):
		connect_bush_signals_for(bush)
		return
	var state = bushes_state[bush_id]
	if state["is_revealed"]:
		bush.is_revealed = true
		bush._apply_revealed_state()
	connect_bush_signals_for(bush)

func connect_bush_signals_for(bush):
	reconnect_bush_signals(bush)

func get_node_or_null_in_parents(node) -> Node2D:
	"""Retorna o segmento pai do nó (filho direto do InfiniteScroller)"""
	var current = node.get_parent()
	while current:
		if current.get_parent() == infinite_scroller:
			return current
		current = current.get_parent()
	return null



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
	# Animais ainda dentro de uma moita são gerenciados pela moita, não por aqui
	if animal.has_meta("managed_by_bush"):
		return
	
	var animal_id = get_animal_unique_id(animal)
	
	if not animal.visible:
		print("[SAVE] SKIPPED - hidden duplicate")
		return
	
	var animal_global_pos = animal.global_position
	
	# FIRST: Check if animal is actually a child of a segment
	var current_segment = get_segment_for_animal(animal)
	var target_segment = current_segment
	
	# ONLY use find_segment_containing_position as fallback if not in a segment
	if not target_segment:
		target_segment = find_segment_containing_position(animal_global_pos)
	
	if not target_segment:
		print("[SAVE ERROR] No segment found for position:", animal_global_pos)
		return
	
	var scene_index = target_segment.get_meta("scene_index", -1)
	var local_pos = animal_global_pos - target_segment.global_position
	
	# Check if animal needs to move to a different segment physically
	if current_segment and current_segment != target_segment:
		var current_scene_idx = current_segment.get_meta("scene_index", -1)
		print("[SAVE] Animal crossing from scene:", current_scene_idx, " to scene:", scene_index, " | global_pos:", animal_global_pos)
		move_animal_to_segment(animal, target_segment, local_pos)
		# Update local_pos after move
		local_pos = animal.global_position - target_segment.global_position
	
	# Get the animal's scene path
	var scene_path = animal.scene_file_path
	if not scene_path:
		scene_path = "res://scenes/components/capivara.tscn"
	
	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"scene_index": scene_index,
		"local_position": local_pos,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden,
		"scene_path": scene_path
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
	"""Check if any animals should exist in this segment and create if missing"""
	var segment_scene_index = segment.get_meta("scene_index", -1)
	
	# Check all saved animal states
	for animal_id in animals_state:
		if animal_id.ends_with("_active_node"):
			continue  # Skip the active node markers
		
		var state = animals_state[animal_id]
		if not state is Dictionary:
			continue
		
		var saved_scene_index = state.get("scene_index", -1)
		
		# Does this animal belong to this scene?
		if saved_scene_index == segment_scene_index:
			# Check if this animal is ALREADY physically in this segment (outside bushes)
			var animals_in_segment = []
			if infinite_scroller.has_method("find_animals_recursive"):
				infinite_scroller.find_animals_recursive(segment, animals_in_segment)
			
			var already_exists = false
			for existing_animal in animals_in_segment:
				if get_animal_unique_id(existing_animal) == animal_id:
					already_exists = true
					print("[CHECK MISSING] Animal ", animal_id, " already in segment (outside bush)")
					var active_key = animal_id + "_active_node"
					if animals_state.has(active_key):
						var old_active = animals_state[active_key]
						if is_instance_valid(old_active) and old_active != existing_animal:
							old_active.visible = false
							print("[CHECK MISSING] Hid duplicate instance")
					animals_state[active_key] = existing_animal
					break
			
			if not already_exists:
				# Check if active instance exists in a different segment
				var active_key = animal_id + "_active_node"
				if animals_state.has(active_key):
					var active_animal = animals_state[active_key]
					if is_instance_valid(active_animal):
						print("[CREATE MISSING] SKIP ", animal_id, " - active instance in another segment")
						continue
				
				# CRITICAL: Before creating new, check if animal is hiding inside a bush
				# in this segment. If yes, extract it and restore — don't create a duplicate.
				var animal_name = animal_id.trim_prefix("animal/")
				var bush_animal = find_animal_inside_bush(segment, animal_name)
				if bush_animal:
					print("[CREATE MISSING] Found ", animal_id, " hiding in bush - extracting instead of creating new")
					extract_animal_from_bush(bush_animal, segment, state)
					continue
				
				# No existing instance anywhere - create it
				print("[CREATE MISSING] scene_index:", segment_scene_index, " needs animal:", animal_id)
				create_animal_in_segment(segment, animal_id, state)

func find_animal_inside_bush(segment: Node2D, animal_name: String) -> Animal:
	"""Search inside all bushes of a segment for an animal with the given name"""
	var bushes = []
	if infinite_scroller.has_method("find_bushes_recursive"):
		infinite_scroller.find_bushes_recursive(segment, bushes)
	for bush in bushes:
		if bush.has_method("get") and bush.get("current_hidden_animal"):
			var hidden = bush.current_hidden_animal
			if hidden and hidden.name == animal_name:
				print("[FIND IN BUSH] Found ", animal_name, " inside bush:", bush.name)
				return hidden
	return null

func extract_animal_from_bush(animal: Animal, segment: Node2D, state: Dictionary):
	"""Extract an animal from its bush and restore it to saved state, reusing the existing node"""
	var animal_id = get_animal_unique_id(animal)
	var bush = animal.get_parent()
	
	# Tell the bush this animal is being taken
	if bush and bush.has_method("get"):
		bush.set("is_revealed", true)
		bush.set("is_occupied", false)
		bush.set("current_hidden_animal", null)
	
	# Remove meta so world_manager can manage it
	if animal.has_meta("managed_by_bush"):
		animal.remove_meta("managed_by_bush")
	
	# Determine target plane
	var plane_name = "Plane1" if state["plane"] == "plane1" else "Plane2"
	var target_plane = segment.get_node_or_null(plane_name)
	if not target_plane:
		print("[EXTRACT ERROR] Plane ", plane_name, " not found")
		return
	
	# Reparent from Bush to Plane
	var global_pos_before = animal.global_position
	bush.remove_child(animal)
	target_plane.add_child(animal)
	
	# Restore saved state
	animal.current_plane = state["plane"]
	animal.position = state["local_position"]
	animal.scale = state["scale"]
	animal.is_hidden = state.get("is_hidden", false)
	animal.visible = not animal.is_hidden
	if animal.current_plane == "plane2":
		animal.z_index = 100
	else:
		animal.z_index = 200
	if animal.has_method("_sync_visual_to_plane"):
		animal._sync_visual_to_plane()
	
	# Enable Area2D monitoring so drag works
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", true)
	
	# Register as active and reconnect signals
	animals_state[animal_id + "_active_node"] = animal
	reconnect_animal_signals(animal)
	
	print("[EXTRACT] Restored ", animal_id, " from bush | plane:", animal.current_plane, " | local_pos:", animal.position, " | global_pos:", animal.global_position)

func create_animal_in_segment(segment: Node2D, animal_id: String, state: Dictionary):
	"""Instantiate a new animal node and restore its state"""
	# Get the correct scene path
	var scene_path = state.get("scene_path", "res://scenes/components/capivara.tscn")
	var animal_scene = load(scene_path)
	
	if not animal_scene:
		print("[CREATE ERROR] Could not load animal scene:", scene_path)
		return
	
	var animal = animal_scene.instantiate()
	
	# Extract animal name from ID ("animal/AnimalName" -> "AnimalName")
	var animal_name = animal_id.trim_prefix("animal/")
	animal.name = animal_name  # Preserve the name so ID stays consistent
	
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
	
	# Set z_index based on plane
	if animal.current_plane == "plane2":
		animal.z_index = 100
	else:
		animal.z_index = 200
	
	print("[CREATE MISSING] Setting plane:", animal.current_plane, " | z_index:", animal.z_index, " | is_hidden:", animal.is_hidden)
	
	# Sync visual after setting plane and z_index
	if animal.has_method("_sync_visual_to_plane"):
		animal._sync_visual_to_plane()
	
	# Mark as active
	var active_key = animal_id + "_active_node"
	animals_state[active_key] = animal
	
	# Connect signals
	await get_tree().process_frame
	reconnect_animal_signals(animal)
	
	print("[CREATE MISSING] Created ", animal_name, " in scene_index:", segment.get_meta("scene_index", -1), " | local_pos:", animal.position, " | global_pos:", animal.global_position)

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
	
	# Get the animal's scene path
	var scene_path = animal.scene_file_path
	if not scene_path:
		scene_path = "res://scenes/components/capivara.tscn"
	
	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"scene_index": segment_scene_index,
		"local_position": local_pos,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden,
		"scene_path": scene_path
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
			
			# Get the animal's scene path for later recreation
			var scene_path = animal.scene_file_path
			if not scene_path:
				scene_path = "res://scenes/components/capivara.tscn"
			
			# Save initial state
			animals_state[animal_id] = {
				"plane": animal.current_plane,
				"scene_index": scene_index,
				"local_position": animal.position,
				"scale": animal.scale,
				"is_hidden": animal.is_hidden,
				"scene_path": scene_path
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

func _on_animal_clicked(animal):
	is_dragging = false
	mouse_pressed = false
	can_start_camera_drag = false
	await get_tree().process_frame
	can_start_camera_drag = true

func _on_animal_drag_started(animal):
	print("[CAM] drag_started:", animal.animal_name, " | is_dragging antes:", is_dragging)
	is_animal_being_dragged = true
	is_dragging = false
	mouse_pressed = false
	can_start_camera_drag = false

func _on_animal_drag_ended(animal):
	print("[CAM] drag_ended:", animal.animal_name, " | is_animal_being_dragged permanece true por 0.15s")
	is_dragging = false
	# Não liberar aqui — notify_bounce_finished() irá liberar após bounce (se houver)
	# O timer de segurança garante que mesmo sem bounce, a flag é liberada
	var timer = get_tree().create_timer(0.5)  # Aumentado para cobrir bounce (0.40s)
	timer.timeout.connect(func(): 
		if is_animal_being_dragged:
			print("[CAM] drag_ended timer expirou -> is_animal_being_dragged = false")
			is_animal_being_dragged = false
	)

func notify_bounce_finished(animal):
	"""Chamado pelo animal após bounce_away_from terminar"""
	print("[CAM] bounce_finished:", animal.animal_name, " -> is_animal_being_dragged = false")
	is_animal_being_dragged = false

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			mouse_pressed = false
			is_dragging = false

func _unhandled_input(event):
	if is_animal_being_dragged:
		if mouse_pressed or is_dragging:
			mouse_pressed = false
			is_dragging = false
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				mouse_pressed = true
				last_mouse_pos = event.position
			else:
				mouse_pressed = false
				is_dragging = false
	
	elif event is InputEventMouseMotion and mouse_pressed:
		if is_animal_being_dragged:
			mouse_pressed = false
			is_dragging = false
			return
		
		if not is_dragging:
			is_dragging = true
		
		var delta_x = event.position.x - last_mouse_pos.x
		camera_position -= delta_x * DRAG_SPEED
		last_mouse_pos = event.position

func _process(delta: float):
	camera.position.x = lerp(camera.position.x, camera_position, delta * 10.0)
	
	if infinite_scroller:
		infinite_scroller.update_camera_position(camera.position.x)
