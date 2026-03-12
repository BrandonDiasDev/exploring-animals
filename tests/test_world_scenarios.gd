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

	# ── Grupo 8: Accepted animal names (allowlist) ──────────────────────────────
	await _run("G8-A — allowlist vazia aceita qualquer animal",              _g8a_allowlist_empty_accepts_any)
	await _run("G8-B — allowlist rejeita animal com nome errado",            _g8b_allowlist_rejects_wrong_animal)
	await _run("G8-C — allowlist aceita animal com nome correto",            _g8c_allowlist_accepts_matching_animal)
	await _run("G8-D — validador OK após rejeição por allowlist",            _g8d_validator_ok_after_rejection)

	# ── Grupo 9: hidden_animal_scene spawn inicial ───────────────────────────────
	await _run("G9-A — animal inicial: is_hidden=true, visible=false, meta", _g9a_hidden_animal_meta_state)
	await _run("G9-B — animal inicial: pai é o pai do arbusto",              _g9b_hidden_animal_parent)
	await _run("G9-C — animal inicial: position igual à do arbusto",         _g9c_hidden_animal_position)

	# ── Grupo 10: Holes ──────────────────────────────────────────────────────────
	await _run("G10-A — holes usam classe Bush",                             _g10a_holes_use_bush_class)
	await _run("G10-B — hole rejeita segundo animal (ocupado)",              _g10b_hole_double_occupation)

	# ── Grupo 11: Multi-hop ciclo reveal/accept ──────────────────────────────────
	await _run("G11-A — dois hops: bush_id coerente, sem órfãos",            _g11a_multihop_cycle)

	# ── Grupo 12: Transição Dia/Noite ─────────────────────────────────────────────
	await _run("G12-A — WorldConfig.is_day field existe",                    _g12a_world_config_is_day_field)
	await _run("G12-B — WorldConfig.clip_overlay_night_color field existe",  _g12b_world_config_night_color_field)
	await _run("G12-C — segment snap para dia: BackgroundNight.alpha=0.0",   _g12c_segment_snap_to_day)
	await _run("G12-D — segment snap para noite: BackgroundNight.alpha=1.0", _g12d_segment_snap_to_night)
	await _run("G12-E — segmentos têm BackgroundDay e BackgroundNight",       _g12e_segments_have_background_nodes)
	await _run("G12-F — alpha coerente com WorldConfig.is_day no estado atual", _g12f_segments_alpha_coherent)
	await _run("G12-G — recycle snapa para noite (is_day=false)",             _g12g_recycle_snap_to_night)
	await _run("G12-H — recycle snapa para dia (is_day=true)",                _g12h_recycle_snap_to_day)
	await _run("G12-I — ClipOverlay transiciona em direção à cor noite",      _g12i_clip_overlay_to_night)
	await _run("G12-J — ClipOverlay transiciona em direção à cor dia",        _g12j_clip_overlay_to_day)
	await _run("G12-K — WorldManager propaga snap noite para segmentos",      _g12k_wm_propagates_night)
	await _run("G12-L — WorldManager propaga snap dia para segmentos",        _g12l_wm_propagates_day)
	await _run("G12-M — SunMoon emite sinal com parâmetros corretos",         _g12m_sun_moon_emits_signal)

	# ── Grupo 13: FSM Invariants ──────────────────────────────────────────────────
	await _run("G13-A — animal sempre normalizado para IDLE após transition_to(IDLE)", _g13a_idle_transition)
	await _run("G13-B — can_fly=false usa FALL, não FLY, ao chamar apply_gravity",     _g13b_no_fly_for_ground_animal)
	await _run("G13-C — fly_duration curto: FLY → FALL → IDLE automaticamente",        _g13c_fly_duration_lands)
	await _run("G13-D — animal aceito na moita está em IDLE",                          _g13d_hidden_animal_is_idle)
	await _run("G13-E — notify_day_night_changed atualiza idle_visual em IDLE",        _g13e_day_night_idle_visual)
	await _run("G13-F — can_fly=true a nível do chão: apply_gravity retorna false (sem FLY)", _g13f_fly_no_fly_at_ground)

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


# ── Grupo 8: Accepted animal names (allowlist) ──────────────────────────────

# G8-A: arbusto com accepted_animal_names=[] deve aceitar qualquer animal
func _g8a_allowlist_empty_accepts_any() -> void:
	var test_bush := _instantiate_test_bush()
	if not test_bush:
		_skip_test("não foi possível instanciar arbusto de teste")
		return
	# Limpar allowlist explicitamente: o fixture (hole01.tscn) usa ["Tatu"],
	# mas este teste valida o comportamento de allowlist VAZIA.
	test_bush.accepted_animal_names = [] as Array[String]
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		test_bush.queue_free()
		_skip_test("não foi possível instanciar animal de teste")
		return

	var result: bool = test_bush.try_accept_animal(dummy)
	_assert(result, "arbusto com allowlist vazia deveria aceitar qualquer animal")

	# Aguardar animação de entrada antes de destruir o nó
	await get_tree().create_timer(0.30).timeout
	dummy.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# G8-B: arbusto com allowlist ["Capivara"] deve rejeitar animal com nome "Onça"
func _g8b_allowlist_rejects_wrong_animal() -> void:
	var test_bush := _instantiate_test_bush()
	if not test_bush:
		_skip_test("não foi possível instanciar arbusto de teste")
		return
	test_bush.accepted_animal_names = ["Capivara"] as Array[String]

	var dummy := _instantiate_dummy_animal("Onça")
	if not dummy:
		test_bush.queue_free()
		_skip_test("não foi possível instanciar animal de teste")
		return

	var result: bool = test_bush.try_accept_animal(dummy)
	_assert(not result, "allowlist [\"Capivara\"] deveria rejeitar animal \"Onça\"")
	_assert(not test_bush.is_occupied, "is_occupied deve ser false após rejeição por allowlist")

	await get_tree().process_frame
	dummy.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# G8-C: arbusto com allowlist ["Capivara"] deve aceitar animal com nome "Capivara"
func _g8c_allowlist_accepts_matching_animal() -> void:
	var test_bush := _instantiate_test_bush()
	if not test_bush:
		_skip_test("não foi possível instanciar arbusto de teste")
		return
	test_bush.accepted_animal_names = ["Capivara"] as Array[String]

	var dummy := _instantiate_dummy_animal("Capivara")
	if not dummy:
		test_bush.queue_free()
		_skip_test("não foi possível instanciar animal de teste")
		return

	var result: bool = test_bush.try_accept_animal(dummy)
	_assert(result, "allowlist [\"Capivara\"] deveria aceitar animal \"Capivara\"")

	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	dummy.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# G8-D: após rejeição por allowlist, validador não deve detectar corrupção de estado
func _g8d_validator_ok_after_rejection() -> void:
	var test_bush := _instantiate_test_bush()
	if not test_bush:
		_skip_test("não foi possível instanciar arbusto de teste")
		return
	test_bush.accepted_animal_names = ["Capivara"] as Array[String]

	var dummy := _instantiate_dummy_animal("Onça")
	if not dummy:
		test_bush.queue_free()
		_skip_test("não foi possível instanciar animal de teste")
		return

	# Executar rejeição (resultado descartado intencionalmente)
	test_bush.try_accept_animal(dummy)
	await get_tree().process_frame

	var ok: bool = _validator.validate(_wm, "G8-D após rejeição allowlist")
	_assert(ok, "invariantes violadas após rejeição por allowlist (detalhes acima)")

	dummy.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# ── Grupo 9: hidden_animal_scene spawn inicial ───────────────────────────────

# G9-A: animais criados por hidden_animal_scene devem estar ocultos e marcados
func _g9a_hidden_animal_meta_state() -> void:
	var occupied_bushes: Array = []
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if b.get("is_occupied"):
			occupied_bushes.append(b)

	if occupied_bushes.is_empty():
		_skip_test("nenhum arbusto ocupado encontrado na cena")
		return

	var failures: Array[String] = []
	for bush: Node in occupied_bushes:
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			failures.append("%s: current_hidden_animal inválido" % bush.name)
			continue
		if not hidden.get("is_hidden"):
			failures.append("%s: animal.is_hidden=false" % bush.name)
		if hidden.visible:
			failures.append("%s: animal.visible=true" % bush.name)
		if not hidden.has_meta("managed_by_bush"):
			failures.append("%s: meta managed_by_bush ausente" % bush.name)

	_assert(failures.is_empty(),
		"animais iniciais com estado incorreto: %s" % str(failures))


# G9-B: animal criado por hidden_animal_scene deve ter o PAI DO ARBUSTO como pai
func _g9b_hidden_animal_parent() -> void:
	var occupied_bushes: Array = []
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if b.get("is_occupied"):
			occupied_bushes.append(b)

	if occupied_bushes.is_empty():
		_skip_test("nenhum arbusto ocupado encontrado na cena")
		return

	var failures: Array[String] = []
	for bush: Node in occupied_bushes:
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			continue
		var expected_parent: Node = bush.get_parent()
		var actual_parent: Node = hidden.get_parent()
		if actual_parent != expected_parent:
			var exp_name: String = str(expected_parent.name) if expected_parent else "NULL"
			var act_name: String = str(actual_parent.name) if actual_parent else "NULL"
			failures.append("%s: esperado pai='%s', real='%s'" % [bush.name, exp_name, act_name])

	_assert(failures.is_empty(),
		"animais iniciais com pai errado: %s" % str(failures))


# G9-C: animal criado por hidden_animal_scene deve ter a mesma position do arbusto
func _g9c_hidden_animal_position() -> void:
	var occupied_bushes: Array = []
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if b.get("is_occupied"):
			occupied_bushes.append(b)

	if occupied_bushes.is_empty():
		_skip_test("nenhum arbusto ocupado encontrado na cena")
		return

	var EPSILON := 1.0
	var failures: Array[String] = []
	for bush: Node in occupied_bushes:
		var hidden: Node = bush.get("current_hidden_animal")
		if not hidden or not is_instance_valid(hidden):
			continue
		var dist: float = hidden.position.distance_to(bush.position)
		if dist > EPSILON:
			failures.append("%s: distância=%.2f (esperado < %.1f)" % [bush.name, dist, EPSILON])

	_assert(failures.is_empty(),
		"animais iniciais desalinhados do arbusto: %s" % str(failures))


# ── Grupo 10: Holes ──────────────────────────────────────────────────────────

# G10-A: todo nó do grupo "bushes" cujo nome contém "hole" deve usar a classe Bush
func _g10a_holes_use_bush_class() -> void:
	var hole_nodes: Array = []
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		if b.name.to_lower().contains("hole"):
			hole_nodes.append(b)

	if hole_nodes.is_empty():
		_skip_test("nenhum nó com 'hole' no nome encontrado no grupo bushes")
		return

	var wrong: Array[String] = []
	for node: Node in hole_nodes:
		if not node is Bush:
			wrong.append(node.name)

	_assert(wrong.is_empty(),
		"nodes hole sem classe Bush: %s" % str(wrong))


# G10-B: hole rejeita segundo animal quando já está ocupado
func _g10b_hole_double_occupation() -> void:
	var test_bush := _instantiate_test_bush()
	if not test_bush:
		_skip_test("não foi possível instanciar arbusto de teste (hole01.tscn)")
		return

	# hole01.tscn só aceita "Tatu" — usar nome correto nos dummies.
	var dummy1 := _instantiate_dummy_animal("Tatu")
	if not dummy1:
		test_bush.queue_free()
		_skip_test("não foi possível instanciar primeiro animal de teste")
		return

	var result1: bool = test_bush.try_accept_animal(dummy1)
	_assert(result1, "hole deveria aceitar o primeiro animal (slot vazio)")

	# Aguardar animação para is_occupied=true ser consolidado
	await get_tree().create_timer(0.30).timeout
	await get_tree().process_frame

	var dummy2 := _instantiate_dummy_animal("Tatu")
	if not dummy2:
		dummy1.queue_free()
		test_bush.queue_free()
		_skip_test("não foi possível instanciar segundo animal de teste")
		return

	var result2: bool = test_bush.try_accept_animal(dummy2)
	_assert(not result2, "hole deveria rejeitar segundo animal (is_occupied=true)")
	_assert(test_bush.is_occupied, "is_occupied deve permanecer true após segunda tentativa")

	await get_tree().process_frame
	dummy1.queue_free()
	dummy2.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# ── Grupo 11: Multi-hop ciclo reveal/accept ──────────────────────────────────

# G11-A: revelar de A → aceitar em B → revelar de B → validar estado coerente
func _g11a_multihop_cycle() -> void:
	var bush_a := _find_occupied_unrevealed_bush()
	if not bush_a:
		_skip_test("nenhum arbusto ocupado disponível para o hop 1")
		return

	# Hop 1: revelar de A
	bush_a.reveal_animal()
	await get_tree().create_timer(0.50).timeout
	await get_tree().process_frame

	if not is_instance_valid(bush_a):
		_skip_test("arbusto A foi destruído durante o reveal (segmento reciclado)")
		return

	var animal := _find_free_animal()
	if not animal:
		_skip_test("animal não estava livre após reveal de A")
		return

	var bush_b := _find_empty_unoccupied_bush_except(bush_a)
	if not bush_b:
		_skip_test("sem outra moita livre para o hop 2")
		return

	# Hop 2: aceitar em B
	bush_b.try_accept_animal(animal)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var aid: String = _wm.get_animal_unique_id(animal)
	var saved_bid: String = _wm.animals_state.get(aid, {}).get("bush_id", "")
	var expected_bid: String = _wm.get_bush_unique_id(bush_b)
	_assert(saved_bid == expected_bid,
		"após hop 2: bush_id='%s', esperado='%s'" % [saved_bid, expected_bid])

	if not is_instance_valid(bush_b):
		_skip_test("arbusto B foi destruído antes do reveal (segmento reciclado)")
		return

	# Hop 3: revelar de B
	bush_b.reveal_animal()
	await get_tree().create_timer(0.50).timeout
	await get_tree().process_frame

	var ok: bool = _validator.validate(_wm, "G11-A multi-hop")
	_assert(ok, "invariantes violadas após ciclo multi-hop (detalhes acima)")


# ── Grupo 12: Transição Dia/Noite ─────────────────────────────────────────────

# G12-A: WorldConfig deve expor a propriedade is_day
func _g12a_world_config_is_day_field() -> void:
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return
	_assert(cfg.get("is_day") != null,
		"WorldConfig não tem campo 'is_day'")


# G12-B: WorldConfig deve expor a propriedade clip_overlay_night_color
func _g12b_world_config_night_color_field() -> void:
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return
	_assert(cfg.get("clip_overlay_night_color") != null,
		"WorldConfig não tem campo 'clip_overlay_night_color'")


# G12-C: apply_day_night(true, false) — snap imediato para dia, alpha deve ser 0.0
func _g12c_segment_snap_to_day() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller or scroller.segments.is_empty():
		_skip_test("nenhum segmento ativo")
		return
	var seg = scroller.segments[0].get("node")
	if not is_instance_valid(seg) or not seg.has_method("apply_day_night"):
		_skip_test("segmento não tem apply_day_night")
		return
	var bg_night = seg.get_node_or_null("BackgroundNight")
	if not bg_night:
		_skip_test("BackgroundNight não encontrado no segmento")
		return
	# Salvar estado original e aplicar snap para dia
	var orig_alpha: float = bg_night.modulate.a
	seg.apply_day_night(true, false, 0.0)
	var result_ok := is_equal_approx(bg_night.modulate.a, 0.0)
	# Restaurar
	bg_night.modulate.a = orig_alpha
	_assert(result_ok,
		"BackgroundNight.modulate.a=%.3f (esperado 0.0)" % bg_night.modulate.a)


# G12-D: apply_day_night(false, false) — snap imediato para noite, alpha deve ser 1.0
func _g12d_segment_snap_to_night() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller or scroller.segments.is_empty():
		_skip_test("nenhum segmento ativo")
		return
	var seg = scroller.segments[0].get("node")
	if not is_instance_valid(seg) or not seg.has_method("apply_day_night"):
		_skip_test("segmento não tem apply_day_night")
		return
	var bg_night = seg.get_node_or_null("BackgroundNight")
	if not bg_night:
		_skip_test("BackgroundNight não encontrado no segmento")
		return
	var orig_alpha: float = bg_night.modulate.a
	seg.apply_day_night(false, false, 0.0)
	var result_ok := is_equal_approx(bg_night.modulate.a, 1.0)
	# Restaurar
	seg.apply_day_night(true, false, 0.0)
	bg_night.modulate.a = orig_alpha
	_assert(result_ok,
		"BackgroundNight.modulate.a=%.3f (esperado 1.0)" % bg_night.modulate.a)


# G12-E: todos os segmentos ativos devem ter os filhos BackgroundDay e BackgroundNight
func _g12e_segments_have_background_nodes() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller or scroller.segments.is_empty():
		_skip_test("nenhum segmento ativo")
		return
	var missing: Array[String] = []
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if not is_instance_valid(seg):
			continue
		if not seg.get_node_or_null("BackgroundDay"):
			missing.append("%s: sem BackgroundDay" % seg.name)
		if not seg.get_node_or_null("BackgroundNight"):
			missing.append("%s: sem BackgroundNight" % seg.name)
	_assert(missing.is_empty(),
		"segmentos sem nós de background: %s" % str(missing))


# G12-F: alpha de BackgroundNight em cada segmento deve bater com WorldConfig.is_day
# Aplica snap em todos antes de medir — elimina qualquer tween em voo.
func _g12f_segments_alpha_coherent() -> void:
	var cfg := get_node_or_null("/root/WorldConfig")
	var scroller = _wm.get("infinite_scroller")
	if not cfg or not scroller or scroller.segments.is_empty():
		_skip_test("WorldConfig ou scroller não disponíveis")
		return
	var is_day: bool = cfg.is_day
	var expected_alpha := 0.0 if is_day else 1.0
	# Forçar snap em todos para garantir estado limpo
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if is_instance_valid(seg) and seg.has_method("apply_day_night"):
			seg.apply_day_night(is_day, false, 0.0)
	var mismatched: Array[String] = []
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if not is_instance_valid(seg):
			continue
		var bg_night = seg.get_node_or_null("BackgroundNight")
		if not bg_night:
			continue
		if not is_equal_approx(bg_night.modulate.a, expected_alpha):
			mismatched.append("%s: alpha=%.3f (esperado %.1f)" % [seg.name, bg_night.modulate.a, expected_alpha])
	_assert(mismatched.is_empty(),
		"alpha inconsistente com is_day=%s: %s" % [str(is_day), str(mismatched)])


# G12-G: segmento reciclado com WorldConfig.is_day=false deve ter BackgroundNight.alpha=1.0
func _g12g_recycle_snap_to_night() -> void:
	var scroller = _wm.get("infinite_scroller")
	var cfg := get_node_or_null("/root/WorldConfig")
	if not scroller or not cfg:
		_skip_test("scroller ou WorldConfig não disponíveis")
		return
	if scroller.segments.size() < 2:
		_skip_test("menos de 2 segmentos ativos")
		return
	var orig_is_day: bool = cfg.is_day
	cfg.is_day = false
	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(0, rightmost_x + scroller.world_width)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	# O slot 0 agora contém o segmento recém-criado
	var new_seg = scroller.segments[0].get("node")
	var passed := false
	var detail := "segmento reciclado inválido"
	if is_instance_valid(new_seg):
		var bg_night = new_seg.get_node_or_null("BackgroundNight")
		if bg_night:
			passed = is_equal_approx(bg_night.modulate.a, 1.0)
			detail = "BackgroundNight.alpha=%.3f (esperado 1.0)" % bg_night.modulate.a
		else:
			detail = "BackgroundNight não encontrado no segmento reciclado"
	# Restaurar estado global
	cfg.is_day = orig_is_day
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if is_instance_valid(seg) and seg.has_method("apply_day_night"):
			seg.apply_day_night(orig_is_day, false, 0.0)
	_assert(passed, detail)


# G12-H: segmento reciclado com WorldConfig.is_day=true deve ter BackgroundNight.alpha=0.0
func _g12h_recycle_snap_to_day() -> void:
	var scroller = _wm.get("infinite_scroller")
	var cfg := get_node_or_null("/root/WorldConfig")
	if not scroller or not cfg:
		_skip_test("scroller ou WorldConfig não disponíveis")
		return
	if scroller.segments.size() < 2:
		_skip_test("menos de 2 segmentos ativos")
		return
	var orig_is_day: bool = cfg.is_day
	cfg.is_day = true
	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(0, rightmost_x + scroller.world_width)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	var new_seg = scroller.segments[0].get("node")
	var passed := false
	var detail := "segmento reciclado inválido"
	if is_instance_valid(new_seg):
		var bg_night = new_seg.get_node_or_null("BackgroundNight")
		if bg_night:
			passed = is_equal_approx(bg_night.modulate.a, 0.0)
			detail = "BackgroundNight.alpha=%.3f (esperado 0.0)" % bg_night.modulate.a
		else:
			detail = "BackgroundNight não encontrado no segmento reciclado"
	# Restaurar estado global
	cfg.is_day = orig_is_day
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if is_instance_valid(seg) and seg.has_method("apply_day_night"):
			seg.apply_day_night(orig_is_day, false, 0.0)
	_assert(passed, detail)


# G12-I: ClipOverlay.transition_day_night(false) deve mover _current_color em direção a night color
func _g12i_clip_overlay_to_night() -> void:
	var clip = _wm.get("_clip_overlay") if _wm else null
	var cfg  := get_node_or_null("/root/WorldConfig")
	if not clip or not cfg:
		_skip_test("ClipOverlay ou WorldConfig não disponíveis")
		return
	if not clip.has_method("transition_day_night"):
		_skip_test("ClipOverlay sem método transition_day_night")
		return
	var day_color:   Color = cfg.clip_overlay_color
	var night_color: Color = cfg.clip_overlay_night_color
	var total_dist   := _color_distance(day_color, night_color)
	if total_dist < 0.001:
		_skip_test("clip_overlay_color e clip_overlay_night_color são idênticos — teste sem sentido")
		return
	# Snap para dia e iniciar transição para noite com duração curta
	clip.set("_current_color", day_color)
	await get_tree().process_frame
	clip.transition_day_night(false, 0.15)
	await get_tree().create_timer(0.20).timeout
	await get_tree().process_frame
	var current: Color = clip.get("_current_color")
	# A cor atual deve ter se afastado do day_color em direção ao night_color
	var remaining_dist := _color_distance(current, night_color)
	var moved_past_midpoint := remaining_dist < total_dist * 0.5
	# Restaurar cor de dia
	clip.set("_current_color", day_color)
	_assert(moved_past_midpoint,
		"_current_color não cruzou o ponto médio em direção a night_color (remaining=%.4f, total=%.4f)" % [remaining_dist, total_dist])


# G12-J: ClipOverlay.transition_day_night(true) deve mover _current_color em direção a day color
func _g12j_clip_overlay_to_day() -> void:
	var clip = _wm.get("_clip_overlay") if _wm else null
	var cfg  := get_node_or_null("/root/WorldConfig")
	if not clip or not cfg:
		_skip_test("ClipOverlay ou WorldConfig não disponíveis")
		return
	if not clip.has_method("transition_day_night"):
		_skip_test("ClipOverlay sem método transition_day_night")
		return
	var day_color:   Color = cfg.clip_overlay_color
	var night_color: Color = cfg.clip_overlay_night_color
	var total_dist   := _color_distance(day_color, night_color)
	if total_dist < 0.001:
		_skip_test("clip_overlay_color e clip_overlay_night_color são idênticos — teste sem sentido")
		return
	# Snap para noite e iniciar transição para dia com duração curta
	clip.set("_current_color", night_color)
	await get_tree().process_frame
	clip.transition_day_night(true, 0.15)
	await get_tree().create_timer(0.20).timeout
	await get_tree().process_frame
	var current: Color = clip.get("_current_color")
	var remaining_dist := _color_distance(current, day_color)
	var moved_past_midpoint := remaining_dist < total_dist * 0.5
	# Restaurar cor de dia
	clip.set("_current_color", day_color)
	_assert(moved_past_midpoint,
		"_current_color não cruzou o ponto médio em direção a day_color (remaining=%.4f, total=%.4f)" % [remaining_dist, total_dist])


# G12-K: _on_day_night_transition_started(false, 0.0) deve fazer snap de todos os segmentos para noite
func _g12k_wm_propagates_night() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller or scroller.segments.is_empty():
		_skip_test("nenhum segmento ativo")
		return
	if not _wm.has_method("_on_day_night_transition_started"):
		_skip_test("WorldManager sem _on_day_night_transition_started")
		return
	# Salvar alphas originais
	var orig_alphas: Dictionary = {}
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if is_instance_valid(seg):
			var bg = seg.get_node_or_null("BackgroundNight")
			if bg:
				orig_alphas[seg.get_instance_id()] = bg.modulate.a
	# Chamar com duration=0.0 → snap imediato para noite
	_wm._on_day_night_transition_started(false, 0.0)
	await get_tree().process_frame
	var mismatched: Array[String] = []
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if not is_instance_valid(seg):
			continue
		var bg = seg.get_node_or_null("BackgroundNight")
		if not bg:
			continue
		if not is_equal_approx(bg.modulate.a, 1.0):
			mismatched.append("%s: alpha=%.3f" % [seg.name, bg.modulate.a])
	# Restaurar estado original
	var restore_cfg := get_node_or_null("/root/WorldConfig")
	var restore_is_day: bool = restore_cfg.is_day if restore_cfg else true
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if is_instance_valid(seg) and seg.has_method("apply_day_night"):
			seg.apply_day_night(restore_is_day, false, 0.0)
	_assert(mismatched.is_empty(),
		"segmentos não fizeram snap para noite via _on_day_night_transition_started: %s" % str(mismatched))


# G12-L: ciclo noite→dia via _on_day_night_transition_started deve restaurar alpha=0.0
func _g12l_wm_propagates_day() -> void:
	var scroller = _wm.get("infinite_scroller")
	if not scroller or scroller.segments.is_empty():
		_skip_test("nenhum segmento ativo")
		return
	if not _wm.has_method("_on_day_night_transition_started"):
		_skip_test("WorldManager sem _on_day_night_transition_started")
		return
	# Forçar noite com snap e depois reverter para dia
	_wm._on_day_night_transition_started(false, 0.0)
	await get_tree().process_frame
	_wm._on_day_night_transition_started(true, 0.0)
	await get_tree().process_frame
	var mismatched: Array[String] = []
	for seg_data in scroller.segments:
		var seg = seg_data.get("node")
		if not is_instance_valid(seg):
			continue
		var bg = seg.get_node_or_null("BackgroundNight")
		if not bg:
			continue
		if not is_equal_approx(bg.modulate.a, 0.0):
			mismatched.append("%s: alpha=%.3f" % [seg.name, bg.modulate.a])
	_assert(mismatched.is_empty(),
		"segmentos não fizeram snap de volta para dia: %s" % str(mismatched))


# G12-M: SunMoon deve emitir day_night_transition_started com to_day e BG_TRANSITION_DURATION corretos.
# Chama _animate_transition diretamente e captura o sinal com CONNECT_ONE_SHOT.
# Aguarda a animação completa (~1.5s) e restaura visualmente o estado original.
func _g12m_sun_moon_emits_signal() -> void:
	var sun_moon := _wm.get_node_or_null("Sky/SunMoon") if _wm else null
	if not sun_moon:
		_skip_test("SunMoon não encontrado em Sky/SunMoon")
		return
	if not sun_moon.has_signal("day_night_transition_started"):
		_skip_test("SunMoon sem sinal day_night_transition_started")
		return
	if sun_moon.get("_animating"):
		_skip_test("SunMoon já está animando — aguardar antes de testar")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	var orig_is_day: bool = cfg.is_day if cfg else true
	# Garantir que o SunMoon esteja em estado de dia para disparar dia→noite
	sun_moon.set("_is_day", true)
	if cfg:
		cfg.is_day = true
	# Instalar spy de sinal (one-shot)
	# Usa um Array como container mutável — lambdas GDScript capturam por valor,
	# então reatribuir variáveis locais dentro da lambda não afeta o escopo externo.
	var capture := [false, null, null]  # [captured, to_day, duration]
	var capture_fn := func(to_day, duration):
		capture[0] = true
		capture[1] = to_day
		capture[2] = duration
	sun_moon.day_night_transition_started.connect(capture_fn, CONNECT_ONE_SHOT)
	# Disparar transição dia→noite
	sun_moon.call("_animate_transition", false)
	# O sinal é emitido de forma síncrona antes do primeiro await — aguardar 1 frame para confirmar.
	await get_tree().process_frame
	# Aguardar a animação dos ícones (ANIM_DURATION * 2 = ~1.3s)
	await get_tree().create_timer(1.5).timeout
	# Restaurar estado visual: forçar de volta ao estado original sem animação
	var sun_icon  = sun_moon.get("_sun")
	var moon_icon = sun_moon.get("_moon")
	if sun_icon and moon_icon:
		sun_icon.visible    = orig_is_day
		sun_icon.modulate.a = 1.0
		moon_icon.visible    = not orig_is_day
		moon_icon.modulate.a = 1.0
	sun_moon.set("_is_day", orig_is_day)
	sun_moon.set("_animating", false)
	if cfg:
		cfg.is_day = orig_is_day
	# Restaurar todos os segmentos — matar tweens de background e fazer snap para o estado original.
	var scroller = _wm.get("infinite_scroller") if _wm else null
	if scroller:
		for seg_data in scroller.segments:
			var seg = seg_data.get("node")
			if is_instance_valid(seg) and seg.has_method("apply_day_night"):
				seg.apply_day_night(orig_is_day, false, 0.0)
	# Restaurar cor do overlay — matar o tween de 4.5s que o sinal disparou, depois fazer snap.
	var clip = _wm.get("_clip_overlay") if _wm else null
	if clip and cfg:
		var active_tween = clip.get("_tween")
		if active_tween:
			active_tween.kill()
			clip.set("_tween", null)
		clip.set("_current_color", cfg.clip_overlay_color if orig_is_day else cfg.clip_overlay_night_color)
	# Verificações
	_assert(capture[0],
		"sinal day_night_transition_started não foi emitido")
	if capture[0]:
		_assert(capture[1] == false,
			"to_day=%s (esperado false)" % str(capture[1]))
		var expected_dur: float = sun_moon.get("BG_TRANSITION_DURATION") if sun_moon.get("BG_TRANSITION_DURATION") else 4.5
		_assert(is_equal_approx(float(capture[2]), expected_dur),
			"duration=%.2f (esperado %.2f)" % [float(capture[2]), expected_dur])


# ── Grupo 13: FSM Invariants ──────────────────────────────────────────────────

# G13-A: transition_to(IDLE) zera o estado, mata tweens, e chama _update_idle_visual.
# Verifica que current_state == IDLE após a chamada, independente do estado anterior.
func _g13a_idle_transition() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("current_state") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem current_state (FSM não implementado)")
		return
	# Estado inicial deve ser IDLE = 0
	_assert(dummy.get("current_state") == 0,
		"estado inicial deveria ser IDLE (0), está em: " + str(dummy.get("current_state")))
	# Forçar FALL simulando queda (se acima da terra)
	var cfg := get_node_or_null("/root/WorldConfig")
	if cfg:
		dummy.position.y = cfg.background_earth_y - 200.0
	dummy.set("can_fly", false)
	dummy.apply_gravity()
	await get_tree().process_frame
	var _state_after_gravity: int = dummy.get("current_state")
	# Cancelar via transition_to(IDLE)
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	_assert(dummy.get("current_state") == 0,
		"current_state deveria ser IDLE (0) após transition_to(IDLE), está em: " + str(dummy.get("current_state")))
	_assert(dummy.get("fall_tween") == null or not dummy.get("fall_tween").is_valid(),
		"fall_tween deveria ter sido morto ao sair do estado FALL")
	dummy.queue_free()
	await get_tree().process_frame


# G13-B: apply_gravity() com can_fly=false deve usar FALL (2), nunca FLY (1).
func _g13b_no_fly_for_ground_animal() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("current_state") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem current_state (FSM não implementado)")
		return
	dummy.set("can_fly", false)
	# Posicionar acima da linha de terra para garantir que apply_gravity() dispare
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		dummy.queue_free()
		_skip_test("WorldConfig não disponível")
		return
	dummy.position.y = cfg.background_earth_y - 300.0
	var result: bool = dummy.apply_gravity()
	var fsm_state: int = dummy.get("current_state")
	_assert(result, "apply_gravity() deveria retornar true (animal acima da linha de terra com can_fly=false)")
	_assert(fsm_state == 2,
		"can_fly=false deveria resultar em FALL (2), got: " + str(fsm_state))
	_assert(fsm_state != 1, "can_fly=false nunca deve resultar em FLY (1)")
	# Cancelar queda antes de destruir
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	dummy.queue_free()
	await get_tree().process_frame


# G13-C: animal com can_fly=true e fly_duration muito curto deve pousar em IDLE automaticamente.
func _g13c_fly_duration_lands() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("current_state") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem current_state (FSM não implementado)")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		dummy.queue_free()
		_skip_test("WorldConfig não disponível")
		return
	# Posicionar no céu para que apply_gravity() acione FLY
	dummy.position.y = cfg.background_earth_y - 400.0
	dummy.set("can_fly", true)
	dummy.set("fly_duration", 0.05)  # 50ms — expira quase instantaneamente
	dummy.apply_gravity()
	var state_after_fly: int = dummy.get("current_state")
	_assert(state_after_fly == 1,
		"deveria estar em FLY (1) após apply_gravity com can_fly=true, está em: " + str(state_after_fly))
	# Aguardar fly_duration expirar → deve entrar em FALL (não IDLE)
	await get_tree().create_timer(0.15).timeout
	var state_after_fly_timer: int = dummy.get("current_state")
	_assert(state_after_fly_timer == 2,
		"deveria estar em FALL (2) após fly_duration expirar, está em: " + str(state_after_fly_timer))
	# Aguardar o tween de queda completar (max 1.2s + buffer)
	await get_tree().create_timer(1.5).timeout
	await get_tree().process_frame
	var state_after_land: int = dummy.get("current_state")
	_assert(state_after_land == 0,
		"deveria estar em IDLE (0) após pousar, está em: " + str(state_after_land))
	# Verificar que pousou na zona de chão
	var landed_y: float = dummy.global_position.y
	_assert(landed_y >= cfg.background_earth_y - 10.0,
		"deveria ter pousado na zona de chão (>= background_earth_y - 10), pousou em y: " + str(landed_y))
	dummy.queue_free()
	await get_tree().process_frame


# G13-D: animal solto numa moita deve estar em IDLE ao ser aceito.
# bush.try_accept_animal deve forçar IDLE antes de chamar _accept_animal.
func _g13d_hidden_animal_is_idle() -> void:
	var dummy_animal := _instantiate_dummy_animal()
	var test_bush := _instantiate_test_bush()
	if not dummy_animal or not test_bush:
		if dummy_animal: dummy_animal.queue_free()
		if test_bush: test_bush.queue_free()
		_skip_test("não foi possível criar animal ou moita de teste")
		return
	if dummy_animal.get("current_state") == null:
		dummy_animal.queue_free()
		test_bush.queue_free()
		_skip_test("animal de teste não tem current_state (FSM não implementado)")
		return
	# Forçar estado FALL artificial
	dummy_animal.set("current_state", Animal.AnimalState.FALL)
	_assert(dummy_animal.get("current_state") == 2,
		"pré-condição: current_state deveria ser FALL (2)")
	# Limpar accepted_animal_names para aceitar qualquer animal
	(test_bush as Bush).accepted_animal_names.clear()
	test_bush.try_accept_animal(dummy_animal)
	await get_tree().process_frame
	var fsm_state: int = dummy_animal.get("current_state")
	_assert(fsm_state == 0,
		"animal aceito na moita deveria estar em IDLE (0), está em: " + str(fsm_state))
	# Cleanup
	var bush_animal: Node = test_bush.get("current_hidden_animal")
	if bush_animal and is_instance_valid(bush_animal):
		bush_animal.queue_free()
	test_bush.queue_free()
	await get_tree().process_frame


# G13-E: notify_day_night_changed deve atualizar idle_visual ao mudar para noite/dia
# quando o animal está em estado IDLE. Animais em FLY/FALL não devem ser afetados.
func _g13e_day_night_idle_visual() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if not dummy.has_method("notify_day_night_changed"):
		dummy.queue_free()
		_skip_test("animal de teste não tem notify_day_night_changed (FSM não implementado)")
		return
	# Criar textura de teste para sleep
	var sleep_tex := ImageTexture.new()
	dummy.set("idle_sleep_texture", sleep_tex)
	# Garantir estado IDLE
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	var cfg := get_node_or_null("/root/WorldConfig")
	var orig_is_day: bool = cfg.is_day if cfg else true
	# Simular transição para noite
	if cfg:
		cfg.is_day = false
	dummy.notify_day_night_changed(false)
	var tex_night: Texture2D = dummy.get_node_or_null("Sprite2D").texture if dummy.get_node_or_null("Sprite2D") else null
	_assert(tex_night == sleep_tex,
		"idle_visual deveria ser idle_sleep_texture durante a noite")
	# Simular transição para FLY e depois mudar dia/noite — textura NÃO deve mudar
	dummy.set("can_fly", true)
	dummy.set("fly_duration", 999.0)
	dummy.transition_to(Animal.AnimalState.FLY)
	if cfg:
		cfg.is_day = true
	dummy.notify_day_night_changed(true)
	var tex_fly: Texture2D = dummy.get_node_or_null("Sprite2D").texture if dummy.get_node_or_null("Sprite2D") else null
	_assert(tex_fly == sleep_tex,
		"idle_visual NÃO deve mudar enquanto animal está em FLY")
	# Restaurar
	if cfg:
		cfg.is_day = orig_is_day
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	dummy.queue_free()
	await get_tree().process_frame


# G13-F: can_fly=true a nível do chão não deve entrar em FLY.
# apply_gravity() deve retornar false e manter IDLE.
func _g13f_fly_no_fly_at_ground() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("current_state") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem current_state (FSM não implementado)")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		dummy.queue_free()
		_skip_test("WorldConfig não disponível")
		return
	dummy.set("can_fly", true)
	# Posicionar abaixo da linha de terra — apply_gravity() não deve acionar FLY
	dummy.position.y = cfg.background_earth_y + 200.0
	var result: bool = dummy.apply_gravity()
	_assert(not result,
		"apply_gravity() deveria retornar false para can_fly=true a nível do chão")
	_assert(dummy.get("current_state") == 0,
		"current_state deveria permanecer IDLE (0), está em: " + str(dummy.get("current_state")))
	dummy.queue_free()
	await get_tree().process_frame


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


func _instantiate_dummy_animal(animal_name_override: String = "") -> Node:
	# Usar a primeira cena de animal conhecida como dummy
	var path := "res://scenes/components/capivara.tscn"
	var scene := load(path) as PackedScene
	if not scene:
		return null
	var node := scene.instantiate()
	node.name = "__test_dummy__"
	if animal_name_override != "":
		node.animal_name = animal_name_override
	add_child(node)
	return node


func _instantiate_test_bush() -> Node:
	# Usa hole01.tscn — tem bush.gd, accepted_animal_names=["Tatu"] e sem hidden_animal_scene.
	# Para testar allowlist vazia, limpe accepted_animal_names após instanciar.
	# Não interfere no WorldManager (não é conectado aos seus sinais).
	var path := "res://scenes/components/hole01.tscn"
	var scene := load(path) as PackedScene
	if not scene:
		return null
	var node := scene.instantiate()
	node.name = "__test_bush__"
	add_child(node)
	return node


# ── Infraestrutura de assert / report ─────────────────────────────────────────

func _color_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	var da := a.a - b.a
	return sqrt(dr*dr + dg*dg + db*db + da*da)


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
