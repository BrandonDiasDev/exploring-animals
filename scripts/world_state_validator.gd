# world_state_validator.gd
#
# Validador de invariantes internas do WorldManager.
# Detecta corrupção de estado *antes* que ela vire bug visível.
#
# Uso rápido:
#   const _WorldStateValidator := preload("res://scripts/world_state_validator.gd")
#   var _validator = _WorldStateValidator.new()
#   _validator.validate(world_manager, "após reveal")
#
# Integrado automaticamente via WorldManager.validate_state() em builds de debug.

extends RefCounted

# ─── Resultado da última chamada ──────────────────────────────────────────────

var errors: Array[String] = []
var warnings: Array[String] = []


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

## Executa todas as verificações de invariante.
## Retorna true se zero erros foram encontrados.
## Erros são emitidos via push_error(); avisos via push_warning().
## silent=true: apenas coleta erros/avisos sem emitir nada no console (útil em testes).
func validate(wm: Node, label: String = "", silent: bool = false) -> bool:
	errors.clear()
	warnings.clear()

	_check_orphan_ids(wm)
	_check_active_nodes_alive(wm)
	_check_duplicate_bush_ids(wm)
	_check_drag_flag_consistency(wm)
	_check_hidden_state_node_consistency(wm)
	_check_no_double_hiding(wm)
	_check_double_bush_claim(wm)
	_check_state_count_sanity(wm)
	_check_local_pos_in_bounds(wm)
	_check_allowlist_consistency(wm)
	_check_fsm_hidden_idle(wm)
	_check_fsm_no_fly_for_ground(wm)
	_check_fsm_state_valid(wm)
	_check_water_idle_mismatch(wm)

	var prefix := "[VALIDATOR%s]" % (" <%s>" % label if label != "" else "")

	if errors.is_empty() and warnings.is_empty():
		if not silent:
			print(prefix, " ✓ todas as invariantes OK")
		return true

	if not silent:
		for err in errors:
			push_error(prefix + " ERRO: " + err)
		for warn in warnings:
			push_warning(prefix + " AVISO: " + warn)

	return errors.is_empty()


# ─── Verificação 1 — IDs órfãos / renomeados ──────────────────────────────────

func _check_orphan_ids(wm: Node) -> void:
	## IDs com '@' são artefatos de renomeação automática do Godot.
	## Surgem quando dois nós com o mesmo nome são adicionados ao mesmo pai.
	## Cada recycle recria um ID novo, acumulando entradas mortas.
	## Cenários que disparam isso: G1 (arbustos / animais com nome duplicado).
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if "@" in key:
			errors.append(
				("ID órfão em animals_state: '%s'  →  Godot renomeou o nó porque "
				+ "dois nós com o mesmo nome foram adicionados ao mesmo pai. "
				+ "Verifique colisão de nomes nos segmentos.") % key
			)


# ─── Verificação 2 — active_nodes apontando para nós destruídos ───────────────

func _check_active_nodes_alive(wm: Node) -> void:
	## Toda entrada "<id>_active_node" deve referenciar um nó válido e dentro da árvore.
	## Nó inválido (freed) indica que o segmento foi reciclado sem limpar a referência.
	## Nó fora da árvore pode indicar reparentagem incorreta ou remoção manual.
	## Cenários que disparam isso: G5 (recycle durante animação).
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if not key.ends_with("_active_node"):
			continue
		var node = animals_state[key]
		if not is_instance_valid(node):
			errors.append(
				("'%s' aponta para um nó já destruído (freed). "
				+ "O segmento foi reciclado sem limpar este ponteiro.") % key
			)
		elif not node.is_inside_tree():
			warnings.append(
				("'%s' é válido mas não está na árvore de cena. "
				+ "Pode indicar reparentagem pendente (deferred).") % key
			)


# ─── Verificação 3 — IDs de bush duplicados ───────────────────────────────────

func _check_duplicate_bush_ids(wm: Node) -> void:
	## get_bush_unique_id() usa apenas o nome do nó.
	## Dois Bush com o mesmo nome → mesmo ID → bushes_state de um sobrescreve o outro.
	## Cenários que disparam isso: G1 ("Bush" e "Bush" em segmentos diferentes),
	## G2 (arrastar entre segmentos com IDs colidindo).
	if not wm.get_tree():
		return
	var scroller = wm.get("infinite_scroller")
	var active_segment_ids: Dictionary = {}
	if scroller and scroller.get("segments") != null:
		for seg_data in scroller.segments:
			var seg = seg_data.get("node")
			if is_instance_valid(seg):
				active_segment_ids[seg.get_instance_id()] = true
	var bushes: Array = wm.get_tree().get_nodes_in_group("bushes")
	var seen: Dictionary = {}  # bush_id -> NodePath
	for bush: Node in bushes:
		# Ignorar arbustos fora dos segmentos ativos (ex.: nós pendentes de queue_free
		# durante recycle). Sem esse filtro o validador pode acusar duplicidade transitória.
		if scroller:
			var bush_segment := _find_segment_for_node_in_scroller(bush, scroller)
			if not bush_segment:
				continue
			if not active_segment_ids.has(bush_segment.get_instance_id()):
				continue
		var bid: String = wm.get_bush_unique_id(bush)
		if seen.has(bid):
			errors.append(
				("bush_id duplicado '%s': nós '%s' e '%s'. "
				+ "Renomeie um deles para evitar sobrescrita de estado em bushes_state.")
				% [bid, str(seen[bid]), str(bush.get_path())]
			)
		else:
			seen[bid] = bush.get_path()


func _find_segment_for_node_in_scroller(node: Node, scroller: Node) -> Node:
	var current: Node = node
	while current:
		if current.get_parent() == scroller:
			return current
		current = current.get_parent()
	return null


# ─── Verificação 4 — flag de drag vazada ──────────────────────────────────────

func _check_drag_flag_consistency(wm: Node) -> void:
	## Se wm.is_animal_being_dragged=true, deve existir exatamente 1 animal
	## com is_being_dragged=true na árvore.
	## Flag vazada bloqueia o drag da câmera permanentemente.
	## Cenários que disparam isso: G6 (release sem arrastar, exit_tree durante drag).
	if not wm.get("is_animal_being_dragged"):
		return
	if not wm.get_tree():
		return
	var dragging: Array = []
	for animal: Node in wm.get_tree().get_nodes_in_group("animals"):
		if animal.get("is_being_dragged"):
			dragging.append(animal.name)
	if dragging.is_empty():
		errors.append(
			"is_animal_being_dragged=true mas nenhum animal tem is_being_dragged=true. "
			+ "A flag vazou — a câmera está bloqueada indefinidamente. "
			+ "Verifique _exit_tree() e handle_mouse_release() em animal.gd."
		)
	elif dragging.size() > 1:
		errors.append(
			("%d animais com is_being_dragged=true simultaneamente: %s. "
			+ "Apenas 1 deveria estar sendo arrastado por vez.") % [dragging.size(), str(dragging)]
		)


# ─── Verificação 5 — consistência is_hidden entre dicionário e nó ─────────────

func _check_hidden_state_node_consistency(wm: Node) -> void:
	## Para cada animal cujo estado salvo tem is_hidden=true, o nó ativo
	## correspondente também deve ter is_hidden=true e visible=false.
	##
	## NOTA DE TIMING: _on_bush_accepted_animal atualiza o dict para is_hidden=true
	## ANTES de await move_tween.finished em _accept_animal. Durante a animação
	## (~0.22 s), o nó ainda tem is_hidden=false e visible=true — isso é esperado.
	## O nó em transição sempre tem a meta "managed_by_bush" setada.
	## Só flagamos como ERRO quando o nó está visível E sem "managed_by_bush"
	## (= já saiu da fila de esconde mas o dict não foi atualizado — bug real).
	## Qualquer outra divergência é registrada como AVISO transitório.
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if key.ends_with("_active_node"):
			continue
		var state = animals_state[key]
		if not state is Dictionary:
			continue
		if not state.get("is_hidden", false):
			continue
		var active_key := key + "_active_node"
		if not animals_state.has(active_key):
			continue
		var node = animals_state[active_key]  # untyped: typed assignment throws on freed instances before is_instance_valid runs
		if not is_instance_valid(node):
			continue
		var node_is_hidden: bool = node.get("is_hidden")
		var node_visible: bool   = node.get("visible") == true
		var in_transition: bool  = node.has_meta("managed_by_bush")
		if not node_is_hidden and node_visible and not in_transition:
			# Nó visível, sem meta de transição → divergência real
			errors.append(
				("animals_state['%s'].is_hidden=true mas o nó '%s' está visível e livre "
				+ "(sem managed_by_bush). Estado do dicionário e do nó divergiram.") % [key, node.name]
			)
		elif not node_is_hidden and not in_transition:
			# Nó não está escondido mas também não está em transição — estado incoerente
			warnings.append(
				("animals_state['%s'].is_hidden=true mas o nó '%s' ainda tem is_hidden=false "
				+ "e não está em transição (sem managed_by_bush).") % [key, node.name]
			)
		# Se in_transition=true: animação _accept_animal em curso, divergência esperada — sem aviso.


# ─── Verificação 6 — animal escondido em dois arbustos simultâneos ────────────

func _check_no_double_hiding(wm: Node) -> void:
	## Nenhum animal deve ser o current_hidden_animal de dois arbustos ao mesmo tempo.
	## Causaria: ao revelar um, o outro arbusto fica apontando para um nó já livre.
	## Cenários que disparam isso: G3 (aceitar animal no próprio arbusto de origem).
	if not wm.get_tree():
		return
	var bushes: Array = wm.get_tree().get_nodes_in_group("bushes")
	var animal_to_bush: Dictionary = {}  # instance_id -> bush name
	for bush: Node in bushes:
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			continue
		var nid: int = hidden.get_instance_id()
		if animal_to_bush.has(nid):
			errors.append(
				("Animal '%s' é current_hidden_animal de DOIS arbustos ao mesmo tempo: "
				+ "'%s' e '%s'.") % [hidden.name, animal_to_bush[nid], bush.name]
			)
		else:
			animal_to_bush[nid] = bush.name


# ─── Verificação 8 — dois animais reivindicando a mesma moita ────────────────

func _check_double_bush_claim(wm: Node) -> void:
	## Dois animais com is_hidden=true e mesmo bush_id em animals_state
	## indica race condition: restore colocou is_occupied=false transitoriamente,
	## outro animal foi aceito, o original também reclama o slot
	## → duplicação ao recriar o segmento.
	## Cenários: G2/G3 (arrastar enquanto segmento recria animal na moita).
	var animals_state: Dictionary = wm.animals_state
	var bush_claims: Dictionary = {}  # bush_id -> animal_id
	for key: String in animals_state.keys():
		if key.ends_with("_active_node"):
			continue
		var state = animals_state[key]
		if not state is Dictionary:
			continue
		if not state.get("is_hidden", false):
			continue
		var bid: String = state.get("bush_id", "")
		if bid == "":
			continue
		if bush_claims.has(bid):
			errors.append(
				("Dois animais reivindicam a mesma moita '%s' com is_hidden=true: '%s' e '%s'. "
				+ "Race condition restore+drop — um deles seria duplicado no próximo recycle. "
				+ "Prevenido por is_occupied=true em restore_bush_state e limpeza em _on_bush_accepted_animal.") \
				% [bid, bush_claims[bid], key]
			)
		else:
			bush_claims[bid] = key


# ─── Verificação 10 — local_pos dentro dos limites do segmento ──────────────

func _check_local_pos_in_bounds(wm: Node) -> void:
	## local_position.x de animais livres deve estar em [0, world_width).
	## Se estiver fora, o animal será recriado fora da câmera após o próximo recycle.
	## Cenários: arrastar um animal além da borda de um segmento sem detecção de cruzamento.
	var infinite_scroller = wm.get("infinite_scroller")
	if not infinite_scroller:
		return
	var ww: float = infinite_scroller.get("world_width")
	if ww <= 0.0:
		return
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if key.ends_with("_active_node"):
			continue
		var state = animals_state[key]
		if not state is Dictionary:
			continue
		if state.get("is_hidden", false):
			continue  # animal escondido numa moita — position relativa ao nó do bush, não ao segmento
		var lpos: Vector2 = state.get("local_position", Vector2.ZERO)
		if lpos.x <= -ww or lpos.x >= ww:
			errors.append(
				("ID '%s' tem local_position.x=%.1f fora de (%.0f, %.0f). "
				+ "Animal ficará invisível ao ser recriado — cruzou borda do segmento sem correção.") \
				% [key, lpos.x, -ww, ww]
			)


# ─── Verificação 9 — acúmulo excessivo de entradas em animals_state ──────────

func _check_state_count_sanity(wm: Node) -> void:
	## Conta entradas de dados (excluindo _active_node) em animals_state.
	## Um número alto indica acúmulo de IDs órfãos (Grupo 4 — múltiplas voltas).
	## O limite "normal" é: nº de species × nº de segmentos × 2 (com margem).
	var animals_state: Dictionary = wm.animals_state
	var data_count := 0
	var node_count := 0
	for key: String in animals_state.keys():
		if key.ends_with("_active_node"):
			node_count += 1
		elif animals_state[key] is Dictionary:
			data_count += 1

	# Heurística: IDs são por espécie (não por instância), então o máximo real é
	# o número de espécies do projeto. WARN_THRESHOLD = 12 dá margem 3× para 4 espécies.
	var WARN_THRESHOLD := 12
	if data_count > WARN_THRESHOLD:
		warnings.append(
			("animals_state tem %d entradas de dados (normal ≤ %d). "
			+ "Possível acúmulo de IDs após múltiplas voltas. "
			+ "Verifique IDs com '@' (Verificação 1).") % [data_count, WARN_THRESHOLD]
		)

	print("[VALIDATOR] Contagem: %d data entries, %d active_node entries em animals_state" \
		% [data_count, node_count])


# ─── Verificação 11 — allowlist consistency ──────────────────────────────────────────
func _check_allowlist_consistency(wm: Node) -> void:
	## Para cada arbusto ocupado com accepted_animal_names não-vazio, o animal
	## escondido deve ter animal_name dentro dessa lista.
	## Mismatch indica configuração incorreta na cena (bug de autoria de conteúdo),
	## não corrupção de estado em tempo de execução — por isso é AVISO, não ERRO.
	if not wm.get_tree():
		return
	var bushes: Array = wm.get_tree().get_nodes_in_group("bushes")
	for bush: Node in bushes:
		if not bush.get("is_occupied"):
			continue
		var allowlist: Array = bush.get("accepted_animal_names")
		if allowlist == null or allowlist.size() == 0:
			continue  # lista vazia = aceita tudo, sem verificação
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			continue
		var aname: String = hidden.get("animal_name")
		if aname not in allowlist:
			warnings.append(
				("Arbusto '%s' está ocupado por '%s' (animal_name='%s') mas "
				+ "accepted_animal_names=%s não inclui esse animal. "
				+ "Verifique a configuração da cena.")
				% [bush.name, hidden.name, aname, str(allowlist)]
			)


# ─── Verificação 12 — animais ocultos devem estar em IDLE ────────────────────
func _check_fsm_hidden_idle(wm: Node) -> void:
	## Todo animal com is_hidden=true deve ter current_state == IDLE (0).
	## FLY ou FALL enquanto escondido numa moita é corrupção: a moita jamais
	## exibe um animal voando ou caindo.
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if key.ends_with("_active_node"):
			continue
		var state = animals_state[key]
		if not state is Dictionary:
			continue
		if not state.get("is_hidden", false):
			continue
		var active_key := key + "_active_node"
		if not animals_state.has(active_key):
			continue
		var node = animals_state[active_key]
		if not is_instance_valid(node):
			continue
		var fsm_state = node.get("current_state")
		if fsm_state == null:
			continue  # Script sem FSM — pular
		if fsm_state != 0:  # 0 = AnimalState.IDLE
			errors.append(
				"'%s' é is_hidden=true mas current_state=%d (esperado IDLE=0). "
				% [key, fsm_state]
				+ "Animal não pode estar em FLY/FALL enquanto escondido numa moita."
			)


# ─── Verificação 13 — animais sem asas não voam ───────────────────────────────
func _check_fsm_no_fly_for_ground(wm: Node) -> void:
	## Animais com can_fly=false nunca devem estar em estado FLY (1).
	## Indica que apply_gravity() despachou para FLY sem permissão.
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if not key.ends_with("_active_node"):
			continue
		var node = animals_state[key]
		if not is_instance_valid(node):
			continue
		var can_fly = node.get("can_fly")
		if can_fly == null or can_fly == true:
			continue  # Sem restrição de voo
		var fsm_state = node.get("current_state")
		if fsm_state == null:
			continue
		if fsm_state == 1:  # 1 = AnimalState.FLY
			errors.append(
				"'%s' tem can_fly=false mas current_state=FLY (1). "
				% [key.trim_suffix("_active_node")]
				+ "apply_gravity() não deveria ter despachado para FLY."
			)


# ─── Verificação 14 — valor do enum FSM é válido ─────────────────────────────
func _check_fsm_state_valid(wm: Node) -> void:
	## current_state deve ser um valor válido de AnimalState: 0 (IDLE), 1 (FLY), 2 (FALL) ou 3 (SUBMERSO).
	## Valor inválido indica corrupção (ex: atribuição direta sem passar por transition_to).
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if not key.ends_with("_active_node"):
			continue
		var node = animals_state[key]
		if not is_instance_valid(node):
			continue
		var fsm_state = node.get("current_state")
		if fsm_state == null:
			continue  # Script sem FSM — pular
		if not (fsm_state == 0 or fsm_state == 1 or fsm_state == 2 or fsm_state == 3):
			errors.append(
				"'%s' tem current_state=%s que não é um valor válido de AnimalState (0, 1, 2, 3). "
				% [key.trim_suffix("_active_node"), str(fsm_state)]
				+ "Atribuição direta ao campo sem usar transition_to()?"
			)


# ─── Verificação 15 — animal IDLE sobre água ───────────────────────────────
func _check_water_idle_mismatch(wm: Node) -> void:
	## Animal visível em IDLE não pode permanecer sobre água.
	## Essa checagem captura desync entre overlap real e FSM.
	var animals_state: Dictionary = wm.animals_state
	for key: String in animals_state.keys():
		if not key.ends_with("_active_node"):
			continue
		var node = animals_state[key]
		if not is_instance_valid(node):
			continue
		if node.get("is_hidden"):
			continue
		if not node.get("visible"):
			continue
		var fsm_state = node.get("current_state")
		if fsm_state == null or int(fsm_state) != 0: # 0 = IDLE
			continue
		var area = node.get_node_or_null("Area2D")
		if not area:
			continue
		var overlaps: Array = area.get_overlapping_areas()
		var has_water_overlap := false
		for overlap in overlaps:
			var overlap_area := overlap as Area2D
			if not overlap_area:
				continue
			if overlap_area.is_in_group("water_zones"):
				has_water_overlap = true
				break
		if has_water_overlap:
			errors.append(
				("'%s' está em IDLE mas Area2D sobrepõe water_zones. "
				+ "Esperado SUBMERSO após reconciliação.")
				% [key.trim_suffix("_active_node")]
			)
