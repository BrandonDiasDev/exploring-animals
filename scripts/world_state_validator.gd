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
	var bushes: Array = wm.get_tree().get_nodes_in_group("bushes")
	var seen: Dictionary = {}  # bush_id -> NodePath
	for bush: Node in bushes:
		var bid: String = wm.get_bush_unique_id(bush)
		if seen.has(bid):
			errors.append(
				"bush_id duplicado '%s': nós '%s' e '%s'. "
				+ "Renomeie um deles para evitar sobrescrita de estado em bushes_state." \
				% [bid, str(seen[bid]), str(bush.get_path())]
			)
		else:
			seen[bid] = bush.get_path()


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
			"%d animais com is_being_dragged=true simultaneamente: %s. "
			+ "Apenas 1 deveria estar sendo arrastado por vez." % [dragging.size(), str(dragging)]
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
		var node: Node = animals_state[active_key]
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
		elif not node_is_hidden:
			# Divergência durante animação de entrada na moita — transitório
			warnings.append(
				("animals_state['%s'].is_hidden=true mas o nó '%s' ainda tem is_hidden=false. "
				+ "in_transition(managed_by_bush)=%s — provavelmente animação _accept_animal em curso.") \
				% [key, node.name, str(in_transition)]
			)


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
				"Animal '%s' é current_hidden_animal de DOIS arbustos ao mesmo tempo: "
				+ "'%s' e '%s'." % [hidden.name, animal_to_bush[nid], bush.name]
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

	# Heurística: mais de 30 entradas de dados provavelmente indica acúmulo.
	# Ajuste conforme o número de animais do projeto.
	var WARN_THRESHOLD := 30
	if data_count > WARN_THRESHOLD:
		warnings.append(
			"animals_state tem %d entradas de dados (normal ≤ %d). "
			+ "Possível acúmulo de IDs após múltiplas voltas. "
			+ "Verifique IDs com '@' (Verificação 1)." % [data_count, WARN_THRESHOLD]
		)

	print("[VALIDATOR] Contagem: %d data entries, %d active_node entries em animals_state" \
		% [data_count, node_count])
