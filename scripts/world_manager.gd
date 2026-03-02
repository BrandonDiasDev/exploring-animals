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
# True quando uma Area2D (animal ou arbusto) capturou o press deste frame.
# Impede que um motion imediatamente após o press inicie o drag da câmera.
var press_intercepted_by_area := false

var animals_state := {}
var bushes_state := {}
var world_width: float = 0.0

# Validador de invariantes — instanciado sob demanda, apenas em debug builds
var _validator = null

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
	if bush.has_signal("animal_accepted_by_bush"):
		if bush.animal_accepted_by_bush.is_connected(_on_bush_accepted_animal):
			bush.animal_accepted_by_bush.disconnect(_on_bush_accepted_animal)
		bush.animal_accepted_by_bush.connect(_on_bush_accepted_animal)

func _on_bush_accepted_animal(animal: Animal, bush: Bush):
	"""Atualiza scene_index, local_position, bush_id e is_hidden do animal.
	O nó foi reparentado para o Plane do segmento da moita (em bush.gd).
	Sem esses updates, check_and_create_missing usaria dados do segmento de origem."""
	var animal_id = get_animal_unique_id(animal)
	var segment = get_node_or_null_in_parents(bush)
	if not segment:
		print("[BUSH ACCEPT WM] ", animal_id, " -> sem segmento para bush:", bush.name)
		return
	var new_scene_index = segment.get_meta("scene_index", -1)
	var bush_id = get_bush_unique_id(bush)
	# Após o reparent em bush.gd, o animal está no Plane do novo segmento.
	# Depois da animação, o animal termina na posição da moita — usamos bush.position como aproximação.
	var local_pos_approx = bush.position

	if animals_state.has(animal_id):
		var old_index = animals_state[animal_id].get("scene_index", -1)
		animals_state[animal_id]["scene_index"] = new_scene_index
		animals_state[animal_id]["local_position"] = local_pos_approx
		animals_state[animal_id]["is_hidden"] = true
		animals_state[animal_id]["bush_id"] = bush_id
		print("[BUSH ACCEPT WM] ", animal_id, " scene_index:", old_index, " -> ", new_scene_index,
			" | bush_id:", bush_id, " | is_hidden:true | local_pos_approx:", local_pos_approx)
	else:
		# Sem estado prévio (ex: animal nativo saindo pela primeira vez)
		var scene_path = animal.scene_file_path
		if not scene_path:
			scene_path = "res://scenes/components/capivara.tscn"
		animals_state[animal_id] = {
			"scene_index": new_scene_index,
			"local_position": local_pos_approx,
			"is_hidden": true,
			"bush_id": bush_id,
			"plane": animal.current_plane,
			"scale": animal.scale,
			"scene_path": scene_path
		}
		print("[BUSH ACCEPT WM] ", animal_id, " novo estado | scene_index:", new_scene_index, " | bush_id:", bush_id)

	# A moita aceitou o animal: o drag terminou definitivamente (sem bounce).
	# Limpar a flag aqui antes de validar, pois o timer de 0.5s em _on_animal_drag_ended
	# ainda não expirou e causaria um falso erro de "flag vazada".
	if is_animal_being_dragged:
		print("[BUSH ACCEPT WM] is_animal_being_dragged = false (drag encerrado via moita)")
		is_animal_being_dragged = false

	validate_state("after_bush_accept")

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
	else:
		# Sem reparent necessário, mas move o animal para o fim da lista de filhos.
		# Isso garante que o animal dispara input_event ANTES do arbusto (mesmo Plane2),
		# independente da ordem em que foram adicionados anteriormente.
		if old_parent:
			old_parent.move_child(animal, old_parent.get_child_count() - 1)
			print("[BUSH REVEAL REPARENT] move_child: ", animal_id, " -> fim de ", old_parent.name)
	animal.global_position = global_pos  # Preserve world position
	
	# Sync visual properties to the new plane
	animal._sync_visual_to_plane()
	
	var wm_area = animal.get_node_or_null("Area2D")
	var wm_parent = animal.get_parent()
	print("[BUSH REVEAL REPARENT] ", animal_id, " reparented to ", target_plane_name,
		" (inherited plane:", inherited_plane,
		") in scene_index:", segment.get_meta("scene_index", -1),
		" | animal.z_index:", animal.z_index,
		" | parent.z_index:", (wm_parent.z_index if wm_parent else "N/A"),
		" | parent.z_as_relative:", (wm_parent.z_as_relative if wm_parent else "N/A"),
		" | area.monitoring:", (wm_area.monitoring if wm_area else "NO_AREA"),
		" | area.input_pickable:", (wm_area.input_pickable if wm_area else "NO_AREA"),
		" | animal.visible:", animal.visible,
		" | animal.is_hidden:", animal.is_hidden)

	# Verificar estado 1 frame depois (após set_deferred do monitoring aplicar)
	call_deferred("_log_reveal_next_frame", animal, animal_id)

	# Registrar / atualizar estado. Se já existia (ex: animal da cena que passou por
	# restore_animal_state antes do reveal), só atualiza is_hidden e garante active_node.
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
			"is_hidden": false,
			"scene_path": scene_path
		}
		animals_state[animal_id + "_active_node"] = animal
		print("[BUSH REVEAL] Registered animal:", animal_id, "| plane:", animal.current_plane, "| is_hidden:false")
	else:
		# Estado já existe (animal da cena que foi encontrado por restore_animal_state).
		# Apenas atualiza is_hidden e garante que o active_node aponta para este nó.
		animals_state[animal_id]["is_hidden"] = false
		animals_state[animal_id + "_active_node"] = animal
		print("[BUSH REVEAL] Updated existing state for:", animal_id, "| is_hidden -> false | active_node set")

	validate_state("after_bush_reveal")

# ─── Estado das moitas ──────────────────────────────────────────────────────────

func get_bush_unique_id(bush) -> String:
	return "bush/" + bush.name

func save_bush_state(bush):
	var bush_id = get_bush_unique_id(bush)
	var segment = get_node_or_null_in_parents(bush)
	if not segment:
		return
	var hidden_animal_id = ""
	var is_dragged_in = false
	if bush.current_hidden_animal:
		hidden_animal_id = get_animal_unique_id(bush.current_hidden_animal)
		# Animal arrastado fica em Plane2/Plane1 (não é filho do Bush)
		is_dragged_in = (bush.current_hidden_animal.get_parent() != bush)
	bushes_state[bush_id] = {
		"is_revealed": bush.is_revealed,
		"is_occupied": bush.is_occupied,
		"scene_index": segment.get_meta("scene_index", -1),
		"hidden_animal_id": hidden_animal_id,
		"is_dragged_in": is_dragged_in
	}
	print("[SAVE BUSH] ", bush.name, " | is_revealed:", bush.is_revealed, " | is_occupied:", bush.is_occupied, " | hidden_animal_id:", hidden_animal_id, " | is_dragged_in:", is_dragged_in)

func restore_bush_state(bush):
	var bush_id = get_bush_unique_id(bush)
	if not bushes_state.has(bush_id):
		print("[RESTORE BUSH] ", bush.name, " -> sem estado salvo, conectando sinais")
		connect_bush_signals_for(bush)
		return
	var state = bushes_state[bush_id]
	if state["is_revealed"]:
		# _ready() pode ter instanciado um novo animal, mas o arbusto já estava revelado.
		# Liberamos o animal recém-criado para não duplicar.
		if bush.current_hidden_animal:
			print("[RESTORE BUSH] ", bush.name, " -> revelado, descartando animal recém-instanciado:", bush.current_hidden_animal.name)
			bush.current_hidden_animal.queue_free()
			bush.current_hidden_animal = null
		bush.is_revealed = true
		bush.is_occupied = false
		bush.area.set_deferred("monitoring", true)
	else:
		# Bush is NOT revealed — it may have a hidden animal inside.
		if bush.current_hidden_animal:
			# Animal original da cena (filho direto do bush node)
			var hidden_animal = bush.current_hidden_animal
			var hidden_id = get_animal_unique_id(hidden_animal)
			var this_segment = get_node_or_null_in_parents(bush)
			var this_scene_index = this_segment.get_meta("scene_index", -1) if this_segment else -1
			var saved_hidden_id = state.get("hidden_animal_id", "")
			var saved_is_dragged_in = state.get("is_dragged_in", false)
			print("[RESTORE BUSH] ", bush.name, " -> não revelado | animal original:", hidden_id,
				" | this_scene:", this_scene_index, " | saved_hidden_id:", saved_hidden_id)

			# Verificar se o estado salvo indica que um animal DIFERENTE deveria estar aqui.
			# Isso acontece quando o usuário retirou o nativo e arrastou outro para dentro.
			if saved_is_dragged_in and saved_hidden_id != "" and saved_hidden_id != hidden_id:
				print("[RESTORE BUSH] ", bush.name, " -> descartando nativo ", hidden_id,
					": estado salvo pede ", saved_hidden_id)
				# remove_child imediato antes de queue_free para que o nome fique livre
				# ainda neste frame — evita rename ao recriar animal com mesmo nome.
				if hidden_animal.get_parent():
					hidden_animal.get_parent().remove_child(hidden_animal)
				hidden_animal.queue_free()
				bush.current_hidden_animal = null
				bush.is_occupied = false
				# Tentar re-esconder o animal arrastado que deveria estar aqui
				var active_key = saved_hidden_id + "_active_node"
				if animals_state.has(active_key):
					var the_animal = animals_state[active_key]
					if is_instance_valid(the_animal):
						print("[RESTORE BUSH] ", bush.name, " -> re-escondendo ", saved_hidden_id, " no lugar do nativo")
						_rehide_animal_in_bush(bush, the_animal)
					else:
						animals_state.erase(active_key)
						print("[RESTORE BUSH] ", bush.name, " -> active_node de ", saved_hidden_id, " destruído, apagado para recriação")
				else:
					print("[RESTORE BUSH] ", bush.name, " -> sem active_node para ", saved_hidden_id, ", será recriado por check_and_create")
			elif animals_state.has(hidden_id):
				var saved_scene_index = animals_state[hidden_id].get("scene_index", -1)
				var saved_is_hidden = animals_state[hidden_id].get("is_hidden", false)
				if saved_scene_index == this_scene_index and saved_is_hidden:
					# Verificar se o animal pertence a ESTA moita ou a outra.
					# Se foi arrastado para outra moita (bush_id diferente), este nativo é inválido.
					var saved_bush_id = animals_state[hidden_id].get("bush_id", "")
					var this_bush_id = get_bush_unique_id(bush)
					if saved_bush_id == "" or saved_bush_id == this_bush_id:
						# Estado pertence a este segmento E a esta moita — nativo pode reclamar o slot
						animals_state[hidden_id + "_active_node"] = hidden_animal
						print("[RESTORE BUSH] ", bush.name, " -> active node set for ", hidden_id, " (scene match, is_hidden:true, bush match)")
					else:
						# Animal está hidden mas foi arrastado para outra moita (bush_id:", saved_bush_id, ")
						# Descartar este nativo para que check_and_create_missing o recrie na moita correta
						print("[RESTORE BUSH] ", bush.name, " -> descartando nativo ", hidden_id,
							": is_hidden=true mas pertence à moita ", saved_bush_id, " (esta moita: ", this_bush_id, ")")
						if hidden_animal.get_parent():
							hidden_animal.get_parent().remove_child(hidden_animal)
						hidden_animal.queue_free()
						bush.current_hidden_animal = null
						bush.is_occupied = false
				elif saved_scene_index == this_scene_index and not saved_is_hidden:
					# Animal está LIVRE (is_hidden:false) — o bush foi revelado mas is_revealed não foi salvo corretamente.
					# Descartar nativo e tratar bush como revelado para que check_and_create_missing restaure o animal livre.
					print("[RESTORE BUSH] ", bush.name, " -> descartando nativo ", hidden_id,
						": estado salvo is_hidden:false (animal está livre)")
					# remove_child imediato antes de queue_free para que o nome fique livre
					# ainda neste frame — evita rename ao recriar animal com mesmo nome.
					if hidden_animal.get_parent():
						hidden_animal.get_parent().remove_child(hidden_animal)
					hidden_animal.queue_free()
					bush.current_hidden_animal = null
					bush.is_revealed = true
					bush.is_occupied = false
					bush.area.set_deferred("monitoring", true)
				else:
					# Estado pertence a outro segmento: usuário arrastou o animal para outra moita.
					# Este nativo é uma cópia obsoleta — descartá-lo para não bloquear o animal real.
					print("[RESTORE BUSH] ", bush.name, " -> descartando nativo obsoleto ", hidden_id,
						" (saved_scene:", saved_scene_index, " != this:", this_scene_index, ")")
					# remove_child imediato antes de queue_free para que o nome fique livre
					# ainda neste frame — evita rename ao recriar animal com mesmo nome.
					if hidden_animal.get_parent():
						hidden_animal.get_parent().remove_child(hidden_animal)
					hidden_animal.queue_free()
					bush.current_hidden_animal = null
					bush.is_occupied = false
					bush.area.set_deferred("monitoring", true)
			else:
				# Nenhum estado salvo — animal nativo inédito, registrar normalmente
				animals_state[hidden_id + "_active_node"] = hidden_animal
				print("[RESTORE BUSH] ", bush.name, " -> active node set for ", hidden_id, " (sem estado salvo)")
		else:
			# Sem animal filho — verificar se havia um animal arrastado que deve ser re-escondido
			var hidden_animal_id = state.get("hidden_animal_id", "")
			var is_dragged_in = state.get("is_dragged_in", false)
			if hidden_animal_id != "" and is_dragged_in:
				# Há um animal arrastado que pertence a esta moita — re-escondê-lo
				var active_key = hidden_animal_id + "_active_node"
				if animals_state.has(active_key):
					var the_animal = animals_state[active_key]
					if is_instance_valid(the_animal):
						print("[RESTORE BUSH] ", bush.name, " -> re-escondendo animal arrastado:", hidden_animal_id)
						_rehide_animal_in_bush(bush, the_animal)
					else:
						# Nó foi destruído com o segmento anterior.
						# Limpar active_node → check_and_create_missing vai recriar e colocar na moita certa.
						animals_state.erase(active_key)
						print("[RESTORE BUSH] ", bush.name, " -> active_node destruído, apagado para recriação: ", hidden_animal_id)
				else:
					print("[RESTORE BUSH] ", bush.name, " -> animal arrastado sem active_node:", hidden_animal_id)
			else:
				print("[RESTORE BUSH] ", bush.name, " -> não revelado mas sem animal")
	connect_bush_signals_for(bush)

func _rehide_animal_in_bush(bush, animal):
	"""Re-esconde um animal dentro da moita após recycle do segmento (sem animação)"""
	bush.current_hidden_animal = animal
	bush.is_occupied = true
	bush.is_revealed = false
	animal.visible = false
	animal.is_hidden = true
	animal.set_meta("managed_by_bush", true)
	if animal.has_node("Area2D"):
		animal.get_node("Area2D").set_deferred("monitoring", false)
	# Registrar como active_node para que check_and_create_missing não crie duplicata
	var animal_id = get_animal_unique_id(animal)
	animals_state[animal_id + "_active_node"] = animal
	# Atualizar local_position com a posição atual do animal (relativa ao seu Plane).
	# Isso garante que o animals_state reflita a posição correta no novo segmento.
	if animals_state.has(animal_id):
		animals_state[animal_id]["local_position"] = animal.position
		animals_state[animal_id]["is_hidden"] = true
		animals_state[animal_id]["plane"] = animal.current_plane
		animals_state[animal_id]["scale"] = animal.scale
		print("[REHIDE] ", animal.name, " em ", bush.name, " | local_pos:", animal.position, " | active_node+state atualizados")
	else:
		print("[REHIDE] ", animal.name, " em ", bush.name, " | local_pos:", animal.position, " | active_node registrado (sem state prev)")

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
	# Always determine the target segment by global position so that animals
	# that have crossed a segment boundary (local_pos out of [0, world_width))
	# are saved to the correct neighbour segment regardless of their current parent.
	var target_segment = find_segment_containing_position(animal_global_pos)
	# Fallback to current parent segment if position-based lookup failed
	if not target_segment:
		target_segment = current_segment
	
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

func move_animal_to_segment(animal, target_segment: Node2D, _target_local_pos: Vector2):
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
	
	# Log total de entradas para detectar acumulo de IDs 
	var total_state_entries = 0
	for k in animals_state:
		if not k.ends_with("_active_node") and animals_state[k] is Dictionary:
			total_state_entries += 1
	print("[CHECK MISSING START] scene_index:", segment_scene_index, " | total animals_state entries:", total_state_entries)
	# Executar validação no início de check_and_create para detectar estado
	# corrompido que chegou aqui via restore_bush_state ou restore_animal_state.
	validate_state("before_check_create s" + str(segment_scene_index))
	
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
				var scene_path = state.get("scene_path", "")
				var bush_animal = find_animal_inside_bush(segment, animal_name, scene_path)
				if bush_animal:
					print("[CREATE MISSING] Found ", animal_id, " hiding in bush (name:", bush_animal.name, ") - extracting instead of creating new")
					extract_animal_from_bush(bush_animal, segment, state)
					continue
				
				# No existing instance anywhere - create it
				print("[CREATE MISSING] scene_index:", segment_scene_index, " needs animal:", animal_id)
				create_animal_in_segment(segment, animal_id, state)

func find_animal_inside_bush(segment: Node2D, animal_name: String, scene_path: String = "") -> Animal:
	"""Search inside all bushes of a segment for an animal matching by name OR scene_path"""
	var bushes = []
	if infinite_scroller.has_method("find_bushes_recursive"):
		infinite_scroller.find_bushes_recursive(segment, bushes)
	for bush in bushes:
		var hidden_animal = bush.get("current_hidden_animal")
		if not hidden_animal:
			continue
		var name_match = (hidden_animal.name == animal_name)
		var path_match = (scene_path != "" and hidden_animal.scene_file_path == scene_path)
		print("[FIND IN BUSH] bush:", bush.name, " | hidden.name:", hidden_animal.name,
			" | looking_for:", animal_name, " | name_match:", name_match,
			" | path_match:", path_match)
		if name_match or path_match:
			return hidden_animal
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
	var _global_pos_before = animal.global_position
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
	# Verificar gravidade após extrair da moita (animal pode estar acima da terra).
	if animal.has_method("apply_gravity"):
		animal.apply_gravity()

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
	
	# Se o animal deve ficar escondido em uma moita específica, colocá-lo na moita diretamente.
	# Isso acontece quando o nó foi destruído com o segmento anterior e precisa ser recriado.
	if state.get("is_hidden", false) and state.has("bush_id"):
		var target_bush_name = state["bush_id"].trim_prefix("bush/")
		var target_bush = segment.find_child(target_bush_name, true, false)
		if target_bush and not target_bush.is_occupied:
			plane.add_child(animal)
			animal.name = animal_name
			animal.current_plane = state["plane"]
			animal.scale = state["scale"]
			animal.position = state["local_position"]
			_rehide_animal_in_bush(target_bush, animal)
			animals_state[animal_id + "_active_node"] = animal
			await get_tree().process_frame
			reconnect_animal_signals(animal)
			print("[CREATE MISSING HIDDEN] ", animal_name, " recriado e escondido em ", target_bush_name,
				" | scene_index:", segment.get_meta("scene_index", -1))
			return
		else:
			print("[CREATE MISSING HIDDEN] Bush '", target_bush_name, "' não disponível — criando visível")

	# Add to plane (animal visível ou bush não disponível)
	var name_before_add = animal.name
	# Proactively rename any same-named node that is pending queue_free.
	# queue_free is deferred, so the old node stays in the tree until next frame.
	# If we add our new node with the same name, Godot renames ours to @NodeX@N,
	# which later gets purged as an orphan ID and the animal permanently disappears.
	var conflicting = plane.get_node_or_null(animal_name)
	if conflicting and conflicting != animal:
		conflicting.name = "__freeing__"
		print("[CREATE RENAME PREVENT] Renamed conflicting node '", animal_name,
			"' to '__freeing__' before adding new instance")
	plane.add_child(animal)

	# Godot pode renomear o nó ao adicioná-lo se já existe outro filho com o mesmo nome
	# (ex: nativo marcado com queue_free mas ainda na árvore). Quando isso ocorre,
	# o animal_id (baseado no nome original) fica inconsistente com o nome real do nó,
	# causando entradas orphan em animals_state que se acumulam a cada recycle.
	# Solução: migrar o entry de animals_state para a nova chave e apagar a antiga.
	if animal.name != name_before_add:
		var new_id: String = "animal/" + animal.name
		print("[CREATE RENAME FIX] ", animal_id, " renomeado para ", new_id,
			" — migrando animals_state")
		# Migrar state dict para a nova chave
		if animals_state.has(animal_id):
			animals_state[new_id] = animals_state[animal_id]
			animals_state.erase(animal_id)
		# Apagar _active_node fantasma da chave antiga, se existir
		var old_active_key := animal_id + "_active_node"
		if animals_state.has(old_active_key):
			animals_state.erase(old_active_key)
		# Usar o novo ID daqui em diante
		animal_id = new_id

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

	# Mark as active usando o animal_id atual (já corrigido se houve rename)
	var active_key := animal_id + "_active_node"
	animals_state[active_key] = animal
	
	# Connect signals
	await get_tree().process_frame
	reconnect_animal_signals(animal)
	# Verificar gravidade após criar animal (pode ter sido criado acima da linha de terra).
	if is_instance_valid(animal) and animal.has_method("apply_gravity") and animal.visible:
		animal.apply_gravity()
	
	print("[CREATE MISSING] Created ", animal_name, " in scene_index:", segment.get_meta("scene_index", -1), " | local_pos:", animal.position, " | global_pos:", animal.global_position)

func save_animal_state_for_recycle(animal):
	var animal_id = get_animal_unique_id(animal)
	
	# IDs com '@' são nomes autogenerated pelo Godot: o animal foi renomeado porque
	# dois nós com o mesmo nome foram adicionados ao mesmo pai.
	# Salvar sob esse ID causaria entradas órfãs que se acumulam a cada recycle.
	# A solução correta é purgar a entrada existente e ignorar este animal.
	var raw_name = animal_id.trim_prefix("animal/")
	if "@" in raw_name or raw_name.begins_with("_"):
		print("[SAVE RECYCLE] PURGE autogenerated id:", animal_id, " | pos:", animal.position)
		animals_state.erase(animal_id)
		animals_state.erase(animal_id + "_active_node")
		return

	# Skip invisible animals. Animals inside a bush are invisible, but their
	# pre-bush free state was already saved at drag end. Overwriting it now would
	# corrupt it with is_hidden=true and the bush position. Preserve the free state.
	if not animal.visible:
		print("[SAVE RECYCLE] SKIP invisible:", animal_id, "| in_bush:", animal.has_meta("managed_by_bush"))
		return

	# Get which scene is being recycled
	var segment = get_segment_for_animal(animal)
	if not segment:
		print("[SAVE RECYCLE] SKIP no segment for:", animal_id)
		return

	var segment_scene_index = segment.get_meta("scene_index", -1)

	# If animal was moved to a different scene, don't overwrite with old segment data
	if animals_state.has(animal_id):
		var saved_scene_index = animals_state[animal_id].get("scene_index", -1)
		if saved_scene_index != segment_scene_index:
			print("[SAVE RECYCLE] SKIP - animal belongs to scene:", saved_scene_index, "| this segment:", segment_scene_index)
			return

	# Get the animal's scene path
	var scene_path = animal.scene_file_path
	if not scene_path:
		scene_path = "res://scenes/components/capivara.tscn"

	animals_state[animal_id] = {
		"plane": animal.current_plane,
		"scene_index": segment_scene_index,
		"local_position": animal.position,
		"scale": animal.scale,
		"is_hidden": animal.is_hidden,
		"scene_path": scene_path
	}
	print("[SAVE RECYCLE] id:", animal_id, "| scene_index:", segment_scene_index, "| local_pos:", animal.position)

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
		# Verificar gravidade após restaurar a posição (animal pode estar acima da terra).
		if animal.has_method("apply_gravity"):
			animal.apply_gravity()
		return true
	else:
		# First time - save initial state based on which segment animal was created in
		var segment = get_segment_for_animal(animal)
		if segment:
			var scene_index = segment.get_meta("scene_index", -1)
			var _this_scene_index = scene_index
			
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
			# Verificar gravidade para animal inicial (pode estar acima da terra na cena).
			if animal.has_method("apply_gravity"):
				animal.apply_gravity()
			return true
		else:
			print("[RESTORE ERROR] First time but no segment found")
			return false

func clear_active_animal(animal):
	"""Clear active reference when animal's segment is being destroyed"""
	var animal_id = get_animal_unique_id(animal)
	var active_key = animal_id + "_active_node"

	# IDs autogenerated pelo Godot (@) nunca devem persistir — purgá-los diretamente.
	var raw_name = animal_id.trim_prefix("animal/")
	if "@" in raw_name or raw_name.begins_with("_"):
		print("[CLEAR ACTIVE] PURGE autogenerated id:", animal_id)
		animals_state.erase(animal_id)
		animals_state.erase(active_key)
		return

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
		else:
			# O _active_node aponta para um nó DIFERENTE — provavelmente o animal foi
			# renomeado pelo Godot ao entrar na árvore, então a chave nunca correspondeu.
			print("[CLEAR ACTIVE MISMATCH] id:", animal_id,
				" | active_node é outro nó:", (active_animal.name if is_instance_valid(active_animal) else "DESTRUÍDO"),
				" | este animal:", animal.name,
				" \u2014 entrada ÓRFÃ em animals_state não será limpa!")
	else:
		print("[CLEAR ACTIVE NO KEY] id:", animal_id, " | active_key não existe em animals_state",
			" \u2014 este animal nunca teve _active_node registrado com este ID (possível rename).")

func find_replacement_animal(animal_id: String):
	"""Find a visible animal to become the new active one"""
	var all_animals = get_tree().get_nodes_in_group("animals")
	
	for animal in all_animals:
		if get_animal_unique_id(animal) == animal_id and animal.visible:
			animals_state[animal_id + "_active_node"] = animal
			print("[REPLACEMENT] id:", animal_id, "| new active animal found")
			return

func _log_reveal_next_frame(animal, animal_id: String):
	"""Log estado do animal 1 frame depois do reveal (após set_deferred aplicar)."""
	if not is_instance_valid(animal):
		print("[REVEAL +1 FRAME] ", animal_id, " -> nó destruído")
		return
	var area = animal.get_node_or_null("Area2D")
	var parent = animal.get_parent()
	var parent_z_rel: String = str(parent.z_as_relative) if parent else "N/A"
	var parent_z: String = str(parent.z_index) if parent else "N/A"
	# Calcula z efetivo simplificado para Area2D do animal
	var effective_z: int = animal.z_index
	if parent and parent.z_as_relative:
		effective_z = parent.z_index + animal.z_index
	print("[REVEAL +1 FRAME] ", animal_id,
		" | z_index:", animal.z_index,
		" | effective_z_approx:", effective_z,
		" | parent:", (parent.name if parent else "NULL"),
		" | parent.z_index:", parent_z,
		" | parent.z_as_relative:", parent_z_rel,
		" | area.monitoring:", (str(area.monitoring) if area else "NO_AREA"),
		" | area.input_pickable:", (str(area.input_pickable) if area else "NO_AREA"),
		" | visible:", animal.visible,
		" | is_hidden:", animal.is_hidden,
		" | position:", animal.position,
		" | global_pos:", animal.global_position)

func reconnect_animal_signals(animal):
	"""Reconectar sinais de um animal (usado após reciclagem de segmento)"""
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

# ─── Debug: validação de invariantes ─────────────────────────────────────────

## Valida todas as invariantes internas do WorldManager.
## Só executa em builds de debug (OS.is_debug_build()). Retorna true se OK.
## Registra erros via push_error() e imprime resumo no Output.
func validate_state(label: String = "") -> bool:
	if not OS.is_debug_build():
		return true
	if not _validator:
		var ValidatorScript = load("res://scripts/world_state_validator.gd")
		if ValidatorScript:
			_validator = ValidatorScript.new()
		else:
			push_error("[VALIDATOR] Não foi possível carregar world_state_validator.gd")
			return true
	return _validator.validate(self, label)

# ─────────────────────────────────────────────────────────────────────────────

func _on_animal_clicked(_animal):
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

func notify_press_intercepted():
	"""Chamado por Area2D de animal/arbusto quando captura um press.
	Impede que o próximo Motion event inicie o drag da câmera."""
	press_intercepted_by_area = true
	print("[WM] press_intercepted_by_area = true")

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if mouse_pressed or is_dragging:
				print("[WM _input] LEFT RELEASE | mouse_pressed:", mouse_pressed, " is_dragging:", is_dragging, " -> reset")
			mouse_pressed = false
			is_dragging = false

func _unhandled_input(event):
	if is_animal_being_dragged:
		if mouse_pressed or is_dragging:
			print("[WM _unhandled] animal dragging -> reset cam state")
			mouse_pressed = false
			is_dragging = false
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Resetar flag de interceptação a cada novo press
				press_intercepted_by_area = false
				print("[WM _unhandled] LEFT PRESS -> mouse_pressed=true | press_intercepted reset")
				mouse_pressed = true
				last_mouse_pos = event.position
			else:
				print("[WM _unhandled] LEFT RELEASE | was_dragging:", is_dragging, " -> reset")
				mouse_pressed = false
				is_dragging = false
				press_intercepted_by_area = false
	
	elif event is InputEventMouseMotion and mouse_pressed:
		if is_animal_being_dragged:
			print("[WM _unhandled] MOTION but animal dragging -> cancel cam")
			mouse_pressed = false
			is_dragging = false
			return
		
		if press_intercepted_by_area:
			print("[WM _unhandled] MOTION blocked: area intercepted the press")
			return
		
		if not is_dragging:
			print("[WM _unhandled] MOTION -> cam drag START")
			is_dragging = true
		
		var delta_x = event.position.x - last_mouse_pos.x
		camera_position -= delta_x * DRAG_SPEED
		last_mouse_pos = event.position

func _process(delta: float):
	camera.position.x = lerp(camera.position.x, camera_position, delta * 10.0)
	
	if infinite_scroller:
		infinite_scroller.update_camera_position(camera.position.x)
