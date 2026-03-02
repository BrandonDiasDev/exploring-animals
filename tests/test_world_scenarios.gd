# tests/test_world_scenarios.gd
#
# Suite de testes de simulação para WorldManager / Animal / Bush.
# NÃO simula eventos de mouse — chama as APIs diretamente.
# Funciona sem nenhum addon externo (basta adicionar este script a um Node na cena).
#
# Como usar:
#   1. Adicione um Node à cena world.tscn chamado "TestRunner"
#   2. Atribua este script a ele
#   3. Ative "Run On Ready" no Inspector para rodar ao iniciar
#      — OU chame run_all() de qualquer ponto do código
#   4. Veja os resultados no Output (filtrar por "[TEST]")
#
# Atalho de teclado: pressione F8 durante o jogo para rodar a suite completa.

extends Node

# ── Configuração ──────────────────────────────────────────────────────────────

## Roda automaticamente quando a cena inicia.
@export var run_on_ready: bool = false

## Tecla para disparar a suite durante o jogo (só em debug builds).
@export var hotkey: Key = KEY_F8

# ── Estado interno ────────────────────────────────────────────────────────────

var _wm: Node = null
var _validator = null
var _pass := 0
var _fail := 0
var _skip := 0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if not OS.is_debug_build():
		return
	if run_on_ready:
		# Aguardar a cena estar completamente pronta
		await get_tree().process_frame
		await get_tree().process_frame
		await run_all()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == hotkey:
			run_all()


# ── Ponto de entrada ──────────────────────────────────────────────────────────

func run_all() -> void:
	_setup()
	if not _wm:
		push_error("[TEST] WorldManager não encontrado — suite abortada.")
		return

	_header("SUITE DE TESTES — WorldManager / Animal / Bush")

	# ── Grupo 1: IDs de moita duplicados / estado corrompido ────────────────────
	await _run("G1-A — bush_ids únicos entre segmentos",           _g1a_unique_bush_ids)
	await _run("G1-B — sem IDs órfãos (@) em animals_state",       _g1b_no_orphan_ids)
	await _run("G1-C — sem dois animais reivindicando mesma moita", _g1c_no_double_bush_claim)

	# ── Grupo 2: Drag entre segmentos ─────────────────────────────────────────
	await _run("G2-A — animal salvo com scene_index correto",       _g2a_save_scene_index)
	await _run("G2-B — active_node atualizado após save",           _g2b_active_node_after_save)

	# ── Grupo 3: Ciclos reveal / hide ─────────────────────────────────────────
	await _run("G3-A — estado válido após reveal_animal",           _g3a_valid_after_reveal)
	await _run("G3-B — estado válido após try_accept_animal",       _g3b_valid_after_accept)
	await _run("G3-C — arbusto rejeita segundo animal (ocupado)",   _g3c_rejection_when_occupied)
	await _run("G3-D — aceitar animal no próprio arbusto de origem",_g3d_accept_own_origin_bush)

	# ── Grupo 4: Múltiplas voltas ─────────────────────────────────────────────
	await _run("G4-A — contagem de entradas dentro do limite",      _g4a_state_count)

	# ── Grupo 5: Posicionamento entre segmentos (boundary crossing) ────────────
	await _run("G5-A — nenhum local_pos fora dos limites no state atual",     _g5a_no_out_of_bounds_local_pos)
	await _run("G5-B — validador detecta local_pos injetado além da borda",   _g5b_boundary_injection_detected)
	await _run("G5-C — save_animal_state corrige cruzamento de borda real",   _g5c_boundary_save_correction)

	# ── Grupo 6: Estados inconsistentes ──────────────────────────────────────
	await _run("G6-A — is_animal_being_dragged não vazou",          _g6a_no_drag_flag_leak)
	await _run("G6-B — nenhum animal escondido em dois arbustos",   _g6b_no_double_hiding)

	# ── Grupo 7: Ciclo de recycle ──────────────────────────────────────────────
	await _run("G7-A — nenhum _active_node freed após recycle",            _g7a_no_freed_active_node_after_recycle)
	await _run("G7-B — sem IDs órfãos após recycle (colisão de nomes)",    _g7b_no_orphan_ids_after_recycle)
	await _run("G7-C — validador OK após dois recycles consecutivos",      _g7c_validator_ok_after_two_recycles)

	_footer()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup() -> void:
	_wm = get_tree().get_first_node_in_group("world_manager")
	var ValidatorScript = load("res://scripts/world_state_validator.gd")
	if ValidatorScript:
		_validator = ValidatorScript.new()
	_pass = 0
	_fail = 0
	_skip = 0


# ── Implementações dos cenários ───────────────────────────────────────────────

# G1-A: todos os bush_ids em uso devem ser únicos
func _g1a_unique_bush_ids() -> void:
	var bushes := get_tree().get_nodes_in_group("bushes")
	var seen: Dictionary = {}
	var duplicates: Array = []
	for bush: Node in bushes:
		var bid: String = _wm.get_bush_unique_id(bush)
		if seen.has(bid):
			duplicates.append("%s ↔ %s" % [bid, str(bush.get_path())])
		else:
			seen[bid] = true
	_assert(duplicates.is_empty(),
		"IDs duplicados encontrados: %s" % str(duplicates))


# G1-B: nenhuma chave com '@' em animals_state
func _g1b_no_orphan_ids() -> void:
	var orphans: Array = []
	for key: String in _wm.animals_state.keys():
		if "@" in key:
			orphans.append(key)
	_assert(orphans.is_empty(),
		"IDs órfãos encontrados: %s" % str(orphans))

# G1-C: nenhum dois animais reivindicam a mesma moita com is_hidden=true
# Valida o invariante em dois passos:
#   A) Estado atual real do jogo não tem double-claim
#   B) Injeta estado corrompido → validador deve detectar → limpa
func _g1c_no_double_bush_claim() -> void:
	# Passo A: verificar estado real
	var real_ok: bool = _validator.validate(_wm, "G1-C atual")
	if not real_ok:
		_assert(false, "invariante double_bush_claim já violada no estado atual (detalhes acima)")
		return

	# Passo B: injetar double-claim e verificar que o validador detecta
	var fake_bush_id := "bush/__test_fake_bush__"
	var fake_id_a  := "animal/__test_double_a__"
	var fake_id_b  := "animal/__test_double_b__"
	_wm.animals_state[fake_id_a] = {"is_hidden": true, "bush_id": fake_bush_id,
		"scene_index": 0, "plane": "plane1", "local_position": Vector2.ZERO,
		"scale": Vector2.ONE, "scene_path": ""}
	_wm.animals_state[fake_id_b] = {"is_hidden": true, "bush_id": fake_bush_id,
		"scene_index": 0, "plane": "plane1", "local_position": Vector2.ZERO,
		"scale": Vector2.ONE, "scene_path": ""}

	# Rodar validador em modo silencioso — esperamos erro, não queremos poluir o console
	var inject_detected: bool = not _validator.validate(_wm, "G1-C injetado", true)

	# Limpar antes do assert para não poluir o estado do jogo
	_wm.animals_state.erase(fake_id_a)
	_wm.animals_state.erase(fake_id_b)

	_assert(inject_detected, "validador NÃO detectou a double-claim injetada — check _check_double_bush_claim falhou")

# G2-A: após save_animal_state, scene_index registrado deve bater com o segmento real
func _g2a_save_scene_index() -> void:
	var animal := _find_free_animal()
	if not animal:
		_skip_test("nenhum animal livre disponível")
		return

	var seg: Node2D = _wm.get_segment_for_animal(animal)
	if not seg:
		_skip_test("animal livre sem segmento")
		return

	var expected_idx: int = seg.get_meta("scene_index", -1)
	_wm.save_animal_state(animal)

	var aid: String = _wm.get_animal_unique_id(animal)
	var saved_idx: int = _wm.animals_state.get(aid, {}).get("scene_index", -999)
	_assert(saved_idx == expected_idx,
		"scene_index salvo=%d, esperado=%d para '%s'" % [saved_idx, expected_idx, aid])


# G2-B: após save, _active_node deve apontar para o mesmo nó
func _g2b_active_node_after_save() -> void:
	var animal := _find_free_animal()
	if not animal:
		_skip_test("nenhum animal livre disponível")
		return

	_wm.save_animal_state(animal)
	var aid2: String = _wm.get_animal_unique_id(animal)
	var stored: Variant = _wm.animals_state.get(aid2 + "_active_node", null)
	_assert(stored == animal,
		"_active_node é '%s', esperado '%s'" % [
			str(stored.name if stored != null and is_instance_valid(stored) else stored),
			animal.name
		])


# G3-A: estado de invariantes passa após reveal
func _g3a_valid_after_reveal() -> void:
	var bush := _find_occupied_unrevealed_bush()
	if not bush:
		_skip_test("nenhum arbusto com animal disponível")
		return

	bush.reveal_animal()
	# Aguardar animações do arbusto (0.41s) + 2 frames de processo
	await get_tree().create_timer(0.50).timeout
	await get_tree().process_frame

	var ok: bool = _validator.validate(_wm, "G3-A após reveal")
	_assert(ok, "invariantes violadas após reveal (detalhes acima)")


# G3-B: estado de invariantes passa após try_accept_animal
func _g3b_valid_after_accept() -> void:
	var animal := _find_free_animal()
	var bush   := _find_empty_unoccupied_bush()
	if not animal or not bush:
		_skip_test("animal livre ou arbusto livre indisponível")
		return

	bush.try_accept_animal(animal)
	# Aguardar animação de entrada (0.22s) + 2 frames
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var ok: bool = _validator.validate(_wm, "G3-B após accept")
	_assert(ok, "invariantes violadas após accept (detalhes acima)")


# G3-C: arbusto ocupado deve rejeitar segundo animal
func _g3c_rejection_when_occupied() -> void:
	var bush := _find_occupied_unrevealed_bush()
	if not bush:
		_skip_test("nenhum arbusto ocupado disponível")
		return

	# Criar um animal temporário só para testar a rejeição
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível instanciar animal de teste")
		return

	var result: bool = bush.try_accept_animal(dummy)
	_assert(not result, "arbusto deveria rejeitar (is_occupied=true)")
	_assert(bush.get("is_occupied"), "is_occupied deve continuar true após rejeição")

	# Limpar o dummy sem afetar o estado do wm
	dummy.queue_free()
	await get_tree().process_frame


# G3-D: aceitar animal no seu próprio arbusto de origem não deve duplicar état
func _g3d_accept_own_origin_bush() -> void:
	# Revelar um animal de uma moita para ter uma moita "de origem"
	var bush := _find_occupied_unrevealed_bush()
	if not bush:
		_skip_test("nenhum arbusto com animal disponível")
		return

	bush.reveal_animal()
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame

	# O animal revelado deve estar livre agora
	var animal := _find_free_animal()
	if not animal:
		_skip_test("animal não estava livre após reveal")
		return

	# Encontrar uma moita DIFERENTE e livre
	# Após o await, o nó pode ter sido reciclado — verificar validade antes de usar.
	if not is_instance_valid(bush):
		_skip_test("arbusto de origem foi destruído durante o reveal (segmento reciclado)")
		return
	var other_bush := _find_empty_unoccupied_bush_except(bush)
	if not other_bush:
		_skip_test("sem outra moita livre para testar o ciclo")
		return

	# Aceitar no outro arbusto
	other_bush.try_accept_animal(animal)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var aid: String = _wm.get_animal_unique_id(animal)
	var saved_bush_id: String = _wm.animals_state.get(aid, {}).get("bush_id", "")
	var expected_bid: String  = _wm.get_bush_unique_id(other_bush)
	_assert(saved_bush_id == expected_bid,
		"bush_id salvo='%s', esperado='%s'" % [saved_bush_id, expected_bid])

	var ok: bool = _validator.validate(_wm, "G3-D após aceitar em outra moita")
	_assert(ok, "invariantes violadas (detalhes acima)")


# G4-A: número de entradas de dados não deve estar acima do limite
func _g4a_state_count() -> void:
	var count := 0
	for key: String in _wm.animals_state.keys():
		if not key.ends_with("_active_node") and _wm.animals_state[key] is Dictionary:
			count += 1
	# IDs de animal são por espécie (únicos), não por instância.
	# Com 4 espécies o máximo real é 4; LIMIT=12 dá margem 3× antes de alertar acúmulo.
	var LIMIT := 12
	_assert(count <= LIMIT,
		"animals_state tem %d entradas (limite=%d) — possível acúmulo por IDs órfãos" % [count, LIMIT])


# ── G5: Posicionamento entre segmentos ──────────────────────────────────────

# G5-A: nenhum local_pos além de [0, world_width) no state atual
func _g5a_no_out_of_bounds_local_pos() -> void:
	if not _wm.get("infinite_scroller"):
		_skip_test("infinite_scroller não disponível")
		return
	var ww: float = _wm.infinite_scroller.world_width
	var bad: Array[String] = []
	for key: String in _wm.animals_state.keys():
		if key.ends_with("_active_node"):
			continue
		var state = _wm.animals_state[key]
		if not state is Dictionary:
			continue
		if state.get("is_hidden", false):
			continue
		var lpos: Vector2 = state.get("local_position", Vector2.ZERO)
		if lpos.x < 0.0 or lpos.x >= ww:
			bad.append("'%s' local_x=%.1f" % [key, lpos.x])
	_assert(bad.is_empty(),
		"local_pos fora de [0, %.0f): %s" % [ww, str(bad)])


# G5-B: validador (check 10) detecta local_pos injetado além da borda
func _g5b_boundary_injection_detected() -> void:
	if not _wm.get("infinite_scroller"):
		_skip_test("infinite_scroller não disponível")
		return
	var ww: float = _wm.infinite_scroller.world_width

	# Verificar estado atual sem injeção
	var real_ok: bool = _validator.validate(_wm, "G5-B atual")
	if not real_ok:
		_assert(false, "invariante já violada antes da injeção")
		return

	# Injetar estado com local_pos fora dos limites
	var fake_id := "animal/__test_boundary_oob__"
	_wm.animals_state[fake_id] = {
		"plane": "plane1", "scene_index": 0,
		"local_position": Vector2(ww + 500.0, 300.0),
		"scale": Vector2.ONE, "is_hidden": false, "scene_path": ""
	}

	var detected: bool = not _validator.validate(_wm, "G5-B injetado", true)
	_wm.animals_state.erase(fake_id)

	_assert(detected, "validador NÃO detectou local_pos além de [0, %.0f) — check 10 falhou" % ww)


# G5-C: save_animal_state corrige fisicamente o cruzamento de borda
# — move o animal além da borda, chama save, verifica que local_pos salvo voltou para [0, ww)
func _g5c_boundary_save_correction() -> void:
	var animal := _find_free_animal()
	if not animal:
		_skip_test("nenhum animal livre disponível")
		return
	if not _wm.get("infinite_scroller"):
		_skip_test("infinite_scroller não disponível")
		return
	var ww: float = _wm.infinite_scroller.world_width
	var original_parent: Node = animal.get_parent()
	var original_local_pos: Vector2 = animal.position
	var aid: String = _wm.get_animal_unique_id(animal)

	# Guardar state original para restaurar ao final
	_wm.save_animal_state(animal)
	var original_state: Dictionary = _wm.animals_state.get(aid, {}).duplicate()

	# Mover além da borda direita (ainda filho do mesmo segmento)
	animal.position = Vector2(ww + 200.0, original_local_pos.y)

	# save deve detectar o cruzamento e redirecionar para o segmento vizinho
	_wm.save_animal_state(animal)

	var saved_state: Dictionary = _wm.animals_state.get(aid, {})
	var saved_lpos: Vector2 = saved_state.get("local_position", Vector2(-1.0, -1.0))
	var correction_ok: bool = saved_lpos.x >= 0.0 and saved_lpos.x < ww

	# Restaurar posição e parent originais
	if is_instance_valid(animal) and animal.get_parent() != original_parent:
		if animal.get_parent():
			animal.get_parent().remove_child(animal)
		original_parent.add_child(animal)
	if is_instance_valid(animal):
		animal.position = original_local_pos
	_wm.animals_state[aid] = original_state
	_wm.animals_state[aid + "_active_node"] = animal

	_assert(correction_ok,
		"save_animal_state: local_pos.x=%.1f ainda fora de [0, %.0f) após correção" % [saved_lpos.x, ww])


# G6-A: flag de drag não deve estar vazada
func _g6a_no_drag_flag_leak() -> void:
	var flag: bool = _wm.get("is_animal_being_dragged")
	if not flag:
		_assert(true, "")  # OK, flag não está setada
		return
	# Flag está true — verificar se algum animal realmente está arrastando
	var dragging_count := 0
	for animal: Node in get_tree().get_nodes_in_group("animals"):
		if animal.get("is_being_dragged"):
			dragging_count += 1
	_assert(dragging_count > 0,
		"is_animal_being_dragged=true mas nenhum animal.is_being_dragged=true (flag vazada)")


# ── G7: Ciclo de recycle ─────────────────────────────────────────────────────

# G7-A: após recycle de um segmento, nenhum _active_node aponta para nó destruído.
# Cobre o bug onde clear_active_animal não era chamado para animais dentro de moitas.
func _g7a_no_freed_active_node_after_recycle() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller:
		_skip_test("infinite_scroller não disponível")
		return
	if scroller.segments.size() < 2:
		_skip_test("menos de 2 segmentos ativos")
		return

	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(0, rightmost_x + scroller.world_width)

	# Aguardar restore_segment_animals (deferred + frame de processo)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var freed_refs: Array[String] = []
	for key: String in _wm.animals_state.keys():
		if not key.ends_with("_active_node"):
			continue
		var node = _wm.animals_state[key]
		if not is_instance_valid(node):
			freed_refs.append(key)

	_assert(freed_refs.is_empty(),
		"_active_node(s) apontando para nó destruído após recycle: %s" % str(freed_refs))


# G7-B: após recycle, nenhum ID com '@' (colisão de nomes — nó renomeado pelo Godot).
# Cobre o bug onde queue_free deferred deixava o nó antigo na árvore durante o add_child.
func _g7b_no_orphan_ids_after_recycle() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller:
		_skip_test("infinite_scroller não disponível")
		return
	if scroller.segments.size() < 2:
		_skip_test("menos de 2 segmentos ativos")
		return

	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(0, rightmost_x + scroller.world_width)

	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var orphans: Array[String] = []
	for key: String in _wm.animals_state.keys():
		if "@" in key:
			orphans.append(key)
	_assert(orphans.is_empty(),
		"IDs órfãos após recycle (colisão de nomes): %s" % str(orphans))


# G7-C: validador passa completamente após dois recycles consecutivos.
func _g7c_validator_ok_after_two_recycles() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller:
		_skip_test("infinite_scroller não disponível")
		return

	for _i in range(2):
		var rightmost_x: float = scroller.get_rightmost_segment_x()
		scroller.recycle_segment(0, rightmost_x + scroller.world_width)
		await get_tree().create_timer(0.30).timeout
		await get_tree().process_frame

	var ok: bool = _validator.validate(_wm, "G7-C após dois recycles")
	_assert(ok, "invariantes violadas após dois recycles consecutivos (detalhes acima)")


# G6-B: nenhum animal duplicado em dois arbustos
func _g6b_no_double_hiding() -> void:
	var bushes := get_tree().get_nodes_in_group("bushes")
	var seen: Dictionary = {}
	var doubles: Array = []
	for bush: Node in bushes:
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			continue
		var nid := hidden.get_instance_id()
		if seen.has(nid):
			doubles.append("'%s' em '%s' e '%s'" % [hidden.name, seen[nid], bush.name])
		else:
			seen[nid] = bush.name
	_assert(doubles.is_empty(),
		"Animals escondidos em dois arbustos: %s" % str(doubles))


# ── Helpers de busca ──────────────────────────────────────────────────────────

func _find_free_animal() -> Node:
	for a: Node in get_tree().get_nodes_in_group("animals"):
		if not a.get("is_hidden") and a.visible and not a.has_meta("managed_by_bush"):
			return a
	return null


func _find_occupied_unrevealed_bush() -> Node:
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if b.get("is_occupied") and not b.get("is_revealed"):
			return b
	return null


func _find_empty_unoccupied_bush() -> Node:
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if not b.get("is_occupied") and not b.get("is_revealed"):
			return b
	return null


func _find_empty_unoccupied_bush_except(excluded: Node) -> Node:
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		var is_excluded := is_instance_valid(excluded) and b == excluded
		if not is_excluded and not b.get("is_occupied") and not b.get("is_revealed"):
			return b
	return null


func _instantiate_dummy_animal() -> Node:
	# Usar a primeira cena de animal conhecida como dummy
	var path := "res://scenes/components/capivara.tscn"
	var scene := load(path) as PackedScene
	if not scene:
		return null
	var node := scene.instantiate()
	node.name = "__test_dummy__"
	add_child(node)
	return node


# ── Infraestrutura de assert / report ─────────────────────────────────────────

func _run(test_name: String, fn: Callable) -> void:
	print("\n[TEST] ▶ ", test_name)
	await fn.call()


func _assert(condition: bool, fail_message: String = "") -> void:
	if condition:
		_pass += 1
		print("[TEST]   ✓ PASSOU")
	else:
		_fail += 1
		var msg := "  ✗ FALHOU"
		if fail_message != "":
			msg += ": " + fail_message
		push_error("[TEST]" + msg)


func _skip_test(reason: String) -> void:
	_skip += 1
	print("[TEST]   ⚠ PULADO — ", reason)


func _header(title: String) -> void:
	print("\n══════════════════════════════════════════════════")
	print("[TEST] ", title)
	print("══════════════════════════════════════════════════")


func _footer() -> void:
	print("\n══════════════════════════════════════════════════")
	print("[TEST] Resultado final:  %d ✓  %d ✗  %d ⚠" % [_pass, _fail, _skip])
	print("══════════════════════════════════════════════════\n")
	if _fail > 0:
		push_error("[TEST] %d teste(s) falharam — veja detalhes acima." % _fail)
