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

const GROUND_EPSILON := 3.0


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

	# ── Grupo Cloud: Parallax / Layering / Dia-Noite ─────────────────────────────
	await _run("GCloud-A — CloudsLayer existe e inicializa",                    _gclouda_layer_exists)
	await _run("GCloud-B — hierarquia de z-order (bg < clouds < gameplay)",    _gcloudb_z_order)
	await _run("GCloud-C — nuvens não entram em grupos animals/bushes",         _gcloudc_group_isolation)
	await _run("GCloud-D — CloudsLayer persiste após recycle",                  _gcloudd_persists_after_recycle)
	await _run("GCloud-E — nuvens só no dia (snap dia/noite)",                  _gcloude_day_only_transition)
	await _run("GCloud-F — movimento horizontal + wrap sem drift vertical",     _gcloudf_horizontal_and_wrap)

	# ── Grupo 13: FSM Invariants ──────────────────────────────────────────────────
	await _run("G13-A — animal sempre normalizado para IDLE após transition_to(IDLE)", _g13a_idle_transition)
	await _run("G13-B — can_fly=false usa FALL, não FLY, ao chamar apply_gravity",     _g13b_no_fly_for_ground_animal)
	await _run("G13-C — fly_duration curto: FLY → FALL → IDLE automaticamente",        _g13c_fly_duration_lands)
	await _run("G13-D — animal aceito na moita está em IDLE",                          _g13d_hidden_animal_is_idle)
	await _run("G13-E — notify_day_night_changed atualiza idle_visual em IDLE",        _g13e_day_night_idle_visual)
	await _run("G13-F — can_fly=true a nível do chão: apply_gravity retorna false (sem FLY)", _g13f_fly_no_fly_at_ground)

	# ── Grupo 14: Sleep Disturbance ───────────────────────────────────────────────
	await _run("G14-A — clique acorda animal dormindo (is_temporarily_awake)",  _g14a_click_wakes_sleeping)
	await _run("G14-B — wake_duration expirado retorna textura de sono",          _g14b_wake_timer_expires)

	# ── Grupo 15: Regressão textura-altura + recycle/restore ─────────────────────
	await _run("G15-A — swap awake→sleep no chão mantém pés alinhados",            _g15a_grounded_texture_swap_keeps_feet)
	await _run("G15-B — recycle/restore não auto-dispara FLY após sleep",          _g15b_recycle_restore_no_unintended_fly)
	await _run("G15-C — caso Siriema (378→208) não volta voando",                  _g15c_siriema_height_regression)
	await _run("G15-D — acima do chão ainda dispara transição válida",             _g15d_negative_control_above_ground)
	await _run("G15-E — notify dia/noite + recycle preserva IDLE no chão",         _g15e_day_night_notify_then_recycle)

	# ── Grupo 16: Água / Submerso ───────────────────────────────────────────────
	await _run("G16-A — entrar em water zone muda para SUBMERSO",                  _g16a_enter_water_sets_submerso)
	await _run("G16-B — textura submersa vem de assets/extras",                    _g16b_submerged_texture_from_extras)
	await _run("G16-C — múltiplas entradas mantêm textura válida",                 _g16c_reentry_keeps_valid_submerged_texture)
	await _run("G16-D — sair da água volta para fluxo FLY/FALL/IDLE",              _g16d_exit_water_restores_flow)
	await _run("G16-E — notify dia/noite não sobrescreve visual submerso",         _g16e_day_night_does_not_override_submerged)
	await _run("G16-F — recycle com SUBMERSO mantém validador OK",                 _g16f_recycle_after_submerged_keeps_validator_ok)
	await _run("G16-G — area_entered duplicado não infla overlap",                  _g16g_duplicate_enter_does_not_inflate_overlap)
	await _run("G16-H — resync restaura SUBMERSO quando ainda em água",             _g16h_resync_restores_submerged_state)
	await _run("G16-I — centro na água sem pé não entra em SUBMERSO",               _g16i_center_overlap_without_feet_does_not_submerge)

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
		if not _is_bush_in_active_segment(bush):
			continue
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
	var other_bush := _find_empty_unoccupied_bush_except(bush, animal)
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

	var bush_b := _find_empty_unoccupied_bush_except(bush_a, animal)
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


# ── Grupo Cloud: Parallax / Layering / Dia-Noite ─────────────────────────────

func _gclouda_layer_exists() -> void:
	var clouds = _get_clouds_layer()
	if not clouds:
		_skip_test("CloudsLayer não encontrada em WorldContainer/CloudsLayer")
		return
	var has_api := clouds.has_method("apply_day_night") and clouds.has_method("get_cloud_count")
	_assert(has_api, "CloudsLayer sem API esperada (apply_day_night/get_cloud_count)")
	_assert(int(clouds.call("get_cloud_count")) > 0, "CloudsLayer sem nuvens instanciadas")


func _gcloudb_z_order() -> void:
	var world_container := _wm.get_node_or_null("WorldContainer") if _wm else null
	if not world_container:
		_skip_test("WorldContainer não encontrado")
		return
	var bg := world_container.get_node_or_null("Background")
	var clouds = world_container.get_node_or_null("CloudsLayer")
	var plane2 := world_container.get_node_or_null("Plane2")
	if not bg or not clouds or not plane2:
		_skip_test("Background/CloudsLayer/Plane2 ausente")
		return

	_assert(bg.z_index < clouds.z_index,
		"Background.z_index (%d) deve ser menor que CloudsLayer.z_index (%d)" % [bg.z_index, clouds.z_index])
	_assert(clouds.z_index < plane2.z_index,
		"CloudsLayer.z_index (%d) deve ser menor que Plane2.z_index (%d)" % [clouds.z_index, plane2.z_index])

	_assert(clouds.z_as_relative,
		"CloudsLayer deve usar z_as_relative=true para garantir z-order relativo no WorldContainer")

	var scroller = _wm.get("infinite_scroller") if _wm else null
	if scroller and scroller.has_method("get"):
		for seg_data in scroller.segments:
			var seg = seg_data.get("node")
			if not is_instance_valid(seg):
				continue
			var seg_bg_day = seg.get_node_or_null("BackgroundDay")
			var seg_bg_night = seg.get_node_or_null("BackgroundNight")
			var seg_plane1 = seg.get_node_or_null("Plane1")
			var seg_plane2 = seg.get_node_or_null("Plane2")
			if not seg_bg_day or not seg_bg_night or not seg_plane1 or not seg_plane2:
				continue

			_assert(seg_bg_day.z_index < clouds.z_index,
				"Segment BackgroundDay.z_index (%d) deve ser menor que CloudsLayer.z_index (%d)" % [seg_bg_day.z_index, clouds.z_index])
			_assert(seg_bg_night.z_index < clouds.z_index,
				"Segment BackgroundNight.z_index (%d) deve ser menor que CloudsLayer.z_index (%d)" % [seg_bg_night.z_index, clouds.z_index])
			_assert(seg_plane1.z_index > seg_plane2.z_index,
				"Segment Plane1.z_index (%d) deve ser maior que Plane2.z_index (%d)" % [seg_plane1.z_index, seg_plane2.z_index])
			_assert(seg_plane2.z_as_relative == false and seg_plane1.z_as_relative == false,
				"Segment Plane1/Plane2 devem usar z_as_relative=false para contrato de camada estável")

	var min_animal_z := INF
	for a: Node in get_tree().get_nodes_in_group("animals"):
		if a and is_instance_valid(a):
			min_animal_z = minf(min_animal_z, float(a.z_index))
	if min_animal_z < INF:
		_assert(clouds.z_index < int(min_animal_z),
			"CloudsLayer.z_index (%d) deve ser menor que z mínimo dos animais (%.0f)" % [clouds.z_index, min_animal_z])


func _gcloudc_group_isolation() -> void:
	var clouds = _get_clouds_layer()
	if not clouds:
		_skip_test("CloudsLayer não encontrada")
		return
	var leaked: Array[String] = []
	for child in clouds.get_children():
		if child.is_in_group("animals") or child.is_in_group("bushes"):
			leaked.append(child.name)
	_assert(leaked.is_empty(), "nuvens não devem pertencer a groups animals/bushes: %s" % str(leaked))


func _gcloudd_persists_after_recycle() -> void:
	var clouds = _get_clouds_layer()
	var scroller = _wm.get("infinite_scroller") if _wm else null
	if not clouds or not scroller:
		_skip_test("CloudsLayer ou InfiniteScroller indisponível")
		return
	if scroller.segments.size() < 2:
		_skip_test("menos de 2 segmentos ativos")
		return

	var id_before := clouds.get_instance_id()
	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(0, rightmost_x + scroller.world_width)
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame

	var clouds_after = _get_clouds_layer()
	_assert(clouds_after != null and is_instance_valid(clouds_after),
		"CloudsLayer deveria continuar válida após recycle")
	if clouds_after:
		_assert(clouds_after.get_instance_id() == id_before,
			"CloudsLayer não deveria ser recriada no recycle de segmento")


func _gcloude_day_only_transition() -> void:
	var clouds = _get_clouds_layer()
	if not clouds:
		_skip_test("CloudsLayer não encontrada")
		return
	if not _wm or not _wm.has_method("_on_day_night_transition_started"):
		_skip_test("WorldManager sem hook de transição")
		return

	_wm._on_day_night_transition_started(false, 0.0)
	await get_tree().process_frame
	_assert(not clouds.visible and is_equal_approx(float(clouds.modulate.a), 0.0),
		"à noite, nuvens devem ficar invisíveis")

	_wm._on_day_night_transition_started(true, 0.0)
	await get_tree().process_frame
	_assert(clouds.visible and is_equal_approx(float(clouds.modulate.a), 1.0),
		"de dia, nuvens devem ficar visíveis")


func _gcloudf_horizontal_and_wrap() -> void:
	var clouds = _get_clouds_layer()
	if not clouds:
		_skip_test("CloudsLayer não encontrada")
		return
	if not clouds.has_method("get_wrap_count"):
		_skip_test("CloudsLayer sem métrica de wrap")
		return
	var children = clouds.get_children()
	if children.is_empty():
		_skip_test("CloudsLayer sem children")
		return

	var cloud0: Node2D = children[0]
	var y_before: float = cloud0.position.y
	var skyline_y: float = float(clouds.call("_get_cfg_float", "skyline_y", -444.0))
	for cloud_child in children:
		var cloud_node := cloud_child as Node2D
		if cloud_node:
			_assert(cloud_node.position.y <= skyline_y,
				"nuvem '%s' em y=%.2f abaixo da skyline=%.2f" % [cloud_node.name, cloud_node.position.y, skyline_y])

	# Forçar wrap da primeira nuvem via estado interno de direção + posição fora da tela.
	var dir_map: Dictionary = clouds.get("_directions")
	var speed_map: Dictionary = clouds.get("_speeds")
	var cid := cloud0.get_instance_id()
	dir_map[cid] = 1.0
	speed_map[cid] = 50.0
	cloud0.position.x = 100000.0
	var wraps_before: int = int(clouds.call("get_wrap_count"))
	clouds.call("_process", 0.016)
	var wraps_after: int = int(clouds.call("get_wrap_count"))

	_assert(wraps_after > wraps_before,
		"wrap_count deveria aumentar quando nuvem sai da área visível")
	_assert(is_equal_approx(cloud0.position.y, y_before),
		"movimento de nuvem deve ser horizontal (y não deve variar no _process)")


func _get_clouds_layer() -> Node:
	if not _wm:
		return null
	return _wm.get_node_or_null("WorldContainer/CloudsLayer")


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
	# Verificar que pousou na zona de chão (comparar pés, não âncora do sprite)
	var landed_feet_y: float = dummy.get_feet_y()
	_assert(landed_feet_y >= cfg.background_earth_y - 10.0,
		"deveria ter pousado na zona de chão (>= background_earth_y - 10), pés em y: " + str(landed_feet_y))
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


# G14-A: clicar num animal dormindo deve definir is_temporarily_awake=true e mostrar textura acordado.
func _g14a_click_wakes_sleeping() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("is_temporarily_awake") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem is_temporarily_awake (não implementado)")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	var orig_is_day: bool = cfg.is_day if cfg else true
	# Criar texturas distintas para sono e vigília
	var sleep_tex := ImageTexture.new()
	var awake_tex := ImageTexture.new()
	dummy.set("idle_sleep_texture", sleep_tex)
	dummy.set("idle_awake_texture", awake_tex)
	# Colocar em noite para ativar sono
	if cfg:
		cfg.is_day = false
	# Garantir IDLE com visual de sono.
	# transition_to(IDLE) é no-op se o animal já estiver em IDLE, por isso
	# chamamos notify_day_night_changed para forçar a atualização do visual.
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	if dummy.has_method("notify_day_night_changed"):
		dummy.notify_day_night_changed(false)
	var sprite := dummy.get_node_or_null("Sprite2D")
	_assert(sprite != null and sprite.texture == sleep_tex,
		"antes do clique deveria mostrar sleep_tex à noite")
	# Simular clique
	if dummy.has_method("on_click"):
		dummy.on_click()
	_assert(dummy.get("is_temporarily_awake") == true,
		"is_temporarily_awake deveria ser true após on_click()")
	_assert(sprite != null and sprite.texture == awake_tex,
		"após clique deveria mostrar awake_tex mesmo à noite")
	# Restaurar
	if cfg:
		cfg.is_day = orig_is_day
	dummy.queue_free()
	await get_tree().process_frame


# G14-B: após wake_duration expirar, animal volta para textura de sono automaticamente.
func _g14b_wake_timer_expires() -> void:
	var dummy := _instantiate_dummy_animal()
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	if dummy.get("is_temporarily_awake") == null:
		dummy.queue_free()
		_skip_test("animal de teste não tem is_temporarily_awake (não implementado)")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	var orig_is_day: bool = cfg.is_day if cfg else true
	# Criar texturas distintas para sono e vigília
	var sleep_tex := ImageTexture.new()
	var awake_tex := ImageTexture.new()
	dummy.set("idle_sleep_texture", sleep_tex)
	dummy.set("idle_awake_texture", awake_tex)
	dummy.set("wake_duration", 0.05)
	# Colocar em noite
	if cfg:
		cfg.is_day = false
	if dummy.has_method("transition_to"):
		dummy.transition_to(Animal.AnimalState.IDLE)
	# Perturbar
	if dummy.has_method("_disturbance_wake"):
		dummy._disturbance_wake()
	var sprite := dummy.get_node_or_null("Sprite2D")
	_assert(sprite != null and sprite.texture == awake_tex,
		"imediatamente após _disturbance_wake() deveria mostrar awake_tex")
	# Aguardar expirar (0.05s + buffer)
	await get_tree().create_timer(0.20).timeout
	_assert(dummy.get("is_temporarily_awake") == false,
		"is_temporarily_awake deveria ser false após wake_duration expirar")
	_assert(sprite != null and sprite.texture == sleep_tex,
		"após wake_duration deveria voltar para sleep_tex")
	# Restaurar
	if cfg:
		cfg.is_day = orig_is_day
	dummy.queue_free()
	await get_tree().process_frame


# ── Grupo 15: Regressão textura-altura + recycle/restore ─────────────────────

# G15-A: trocar textura (awake alto -> sleep baixo) enquanto no chão deve manter os pés alinhados.
func _g15a_grounded_texture_swap_keeps_feet() -> void:
	var dummy := _instantiate_dummy_animal("__test_g15a__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		dummy.queue_free()
		_skip_test("WorldConfig não disponível")
		return

	var awake_tex := _create_colored_texture(200, 378, Color(1.0, 0.8, 0.2, 1.0))
	var sleep_tex := _create_colored_texture(200, 208, Color(0.2, 0.6, 1.0, 1.0))

	dummy.idle_awake_texture = awake_tex
	dummy.idle_sleep_texture = sleep_tex
	dummy.sleeps_at_night = true
	dummy.is_temporarily_awake = false
	dummy.current_state = Animal.AnimalState.IDLE

	var orig_is_day: bool = cfg.is_day
	cfg.is_day = true
	dummy.notify_day_night_changed(true)
	var snapped_ok := _snap_animal_feet_to_ground(dummy, cfg.background_earth_y)
	_assert(snapped_ok, "pré-condição: não foi possível snapar pés no chão")

	var feet_day: float = dummy.get_feet_y()
	_assert(absf(feet_day - cfg.background_earth_y) <= GROUND_EPSILON,
		"pré-condição falhou: pés no dia desalinhados (feet=%.2f, ground=%.2f)" % [feet_day, cfg.background_earth_y])

	cfg.is_day = false
	dummy.notify_day_night_changed(false)
	var feet_night: float = dummy.get_feet_y()
	_assert(absf(feet_night - cfg.background_earth_y) <= GROUND_EPSILON,
		"após swap para sleep, pés deveriam permanecer alinhados (feet=%.2f, ground=%.2f)" % [feet_night, cfg.background_earth_y])

	# Mesmo com can_fly=true, estando no chão apply_gravity não deve transicionar.
	dummy.can_fly = true
	var gravity_result: bool = dummy.apply_gravity()
	_assert(not gravity_result, "apply_gravity não deveria iniciar transição com pés no chão")
	_assert(dummy.current_state == Animal.AnimalState.IDLE,
		"estado deveria permanecer IDLE, atual=%s" % str(dummy.current_state))

	cfg.is_day = orig_is_day
	dummy.queue_free()
	await get_tree().process_frame


# G15-B: após recycle/restore com textura sleep mais baixa, animal não deve voltar em FLY.
func _g15b_recycle_restore_no_unintended_fly() -> void:
	var animal := _find_free_flying_animal()
	if not animal:
		_skip_test("nenhum animal livre com can_fly=true disponível")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return

	var aid: String = _wm.get_animal_unique_id(animal)
	var orig_is_day: bool = cfg.is_day
	var old_awake = animal.idle_awake_texture
	var old_sleep = animal.idle_sleep_texture
	var old_sleeps: bool = animal.sleeps_at_night
	var old_can_fly: bool = animal.can_fly

	var awake_tex := _create_colored_texture(180, 360, Color(0.9, 0.9, 0.2, 1.0))
	var sleep_tex := _create_colored_texture(180, 200, Color(0.3, 0.5, 1.0, 1.0))

	animal.transition_to(Animal.AnimalState.IDLE)
	animal.idle_awake_texture = awake_tex
	animal.idle_sleep_texture = sleep_tex
	animal.sleeps_at_night = true
	animal.is_temporarily_awake = false
	animal.can_fly = true

	cfg.is_day = true
	animal.notify_day_night_changed(true)
	var snapped_ok := _snap_animal_feet_to_ground(animal, cfg.background_earth_y)
	_assert(snapped_ok, "pré-condição: falha ao snapar no chão")

	# Entrar em sleep sem ajustar posição manualmente — reproduz caminho real.
	cfg.is_day = false
	animal.notify_day_night_changed(false)
	_wm.save_animal_state(animal)

	var recycled := await _recycle_segment_containing_animal(animal)
	_assert(recycled, "não foi possível reciclar segmento do animal")

	var restored := _find_active_animal_by_id(aid)
	_assert(restored != null, "animal restaurado não encontrado para id '%s'" % aid)
	if restored:
		_assert(restored.current_state != Animal.AnimalState.FLY,
			"regressão: restore/apply_gravity não deve colocar animal em FLY sem interação")
		_assert(restored.current_state == Animal.AnimalState.IDLE,
			"animal restaurado deveria permanecer IDLE no chão, atual=%s" % str(restored.current_state))
		var feet_restored: float = restored.get_feet_y()
		_assert(absf(feet_restored - cfg.background_earth_y) <= GROUND_EPSILON,
			"pés após restore desalinhados (feet=%.2f, ground=%.2f)" % [feet_restored, cfg.background_earth_y])

	# Restaurar propriedades (no nó ativo atual).
	if restored:
		restored.idle_awake_texture = old_awake
		restored.idle_sleep_texture = old_sleep
		restored.sleeps_at_night = old_sleeps
		restored.can_fly = old_can_fly
		restored.notify_day_night_changed(orig_is_day)
	cfg.is_day = orig_is_day


# G15-C: regressão específica Siriema (altura awake 378 -> sleep 208) não deve auto-voar.
func _g15c_siriema_height_regression() -> void:
	var animal := _find_free_flying_animal()
	if not animal:
		_skip_test("nenhum animal livre com can_fly=true disponível")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return

	var aid: String = _wm.get_animal_unique_id(animal)
	var orig_is_day: bool = cfg.is_day
	var old_awake = animal.idle_awake_texture
	var old_sleep = animal.idle_sleep_texture
	var old_sleeps: bool = animal.sleeps_at_night

	var awake_tex := _create_colored_texture(220, 378, Color(0.9, 0.7, 0.3, 1.0))
	var sleep_tex := _create_colored_texture(220, 208, Color(0.4, 0.4, 0.9, 1.0))

	animal.transition_to(Animal.AnimalState.IDLE)
	animal.idle_awake_texture = awake_tex
	animal.idle_sleep_texture = sleep_tex
	animal.sleeps_at_night = true
	animal.is_temporarily_awake = false
	animal.can_fly = true

	cfg.is_day = true
	animal.notify_day_night_changed(true)
	var snapped_ok := _snap_animal_feet_to_ground(animal, cfg.background_earth_y)
	_assert(snapped_ok, "pré-condição: falha ao snapar no chão")

	# Sequência da regressão: dormir e depois recycle/restore.
	cfg.is_day = false
	animal.notify_day_night_changed(false)
	_wm.save_animal_state(animal)
	var recycled := await _recycle_segment_containing_animal(animal)
	_assert(recycled, "não foi possível reciclar segmento do caso Siriema")

	var restored := _find_active_animal_by_id(aid)
	_assert(restored != null, "animal restaurado não encontrado para id '%s'" % aid)
	if restored:
		_assert(restored.current_state == Animal.AnimalState.IDLE,
			"caso Siriema: esperado IDLE após restore, atual=%s" % str(restored.current_state))
		_assert(restored.current_state != Animal.AnimalState.FLY,
			"caso Siriema: não deveria voltar voando sem interação")

	if restored:
		restored.idle_awake_texture = old_awake
		restored.idle_sleep_texture = old_sleep
		restored.sleeps_at_night = old_sleeps
		restored.notify_day_night_changed(orig_is_day)
	cfg.is_day = orig_is_day


# G15-D: controle negativo — estando genuinamente acima do chão, gravidade deve acionar transição.
func _g15d_negative_control_above_ground() -> void:
	var dummy := _instantiate_dummy_animal("__test_g15d__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		dummy.queue_free()
		_skip_test("WorldConfig não disponível")
		return

	dummy.transition_to(Animal.AnimalState.IDLE)
	dummy.can_fly = true
	dummy.global_position.y = cfg.background_earth_y - 400.0
	var result_fly: bool = dummy.apply_gravity()
	_assert(result_fly, "acima do chão, apply_gravity deveria iniciar transição")
	_assert(dummy.current_state == Animal.AnimalState.FLY,
		"can_fly=true acima do chão deveria entrar em FLY")

	dummy.transition_to(Animal.AnimalState.IDLE)
	dummy.can_fly = false
	dummy.global_position.y = cfg.background_earth_y - 400.0
	var result_fall: bool = dummy.apply_gravity()
	_assert(result_fall, "acima do chão, apply_gravity deveria iniciar transição")
	_assert(dummy.current_state == Animal.AnimalState.FALL,
		"can_fly=false acima do chão deveria entrar em FALL")

	dummy.transition_to(Animal.AnimalState.IDLE)
	dummy.queue_free()
	await get_tree().process_frame


# G15-E: notify_day_night_changed (swap de textura) + recycle deve preservar invariantes no restore.
func _g15e_day_night_notify_then_recycle() -> void:
	var animal := _find_free_flying_animal()
	if not animal:
		_skip_test("nenhum animal livre com can_fly=true disponível")
		return
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return

	var aid: String = _wm.get_animal_unique_id(animal)
	var orig_is_day: bool = cfg.is_day
	var old_awake = animal.idle_awake_texture
	var old_sleep = animal.idle_sleep_texture
	var old_sleeps: bool = animal.sleeps_at_night

	var awake_tex := _create_colored_texture(160, 300, Color(0.8, 0.9, 0.3, 1.0))
	var sleep_tex := _create_colored_texture(160, 180, Color(0.3, 0.4, 0.9, 1.0))

	animal.transition_to(Animal.AnimalState.IDLE)
	animal.idle_awake_texture = awake_tex
	animal.idle_sleep_texture = sleep_tex
	animal.sleeps_at_night = true
	animal.is_temporarily_awake = false
	animal.can_fly = true

	cfg.is_day = true
	animal.notify_day_night_changed(true)
	var snapped_ok := _snap_animal_feet_to_ground(animal, cfg.background_earth_y)
	_assert(snapped_ok, "pré-condição: falha ao snapar no chão")

	# Trocar ciclo via notify (caminho oficial do WM)
	cfg.is_day = false
	animal.notify_day_night_changed(false)
	_wm.save_animal_state(animal)

	var recycled := await _recycle_segment_containing_animal(animal)
	_assert(recycled, "não foi possível reciclar segmento")

	var restored := _find_active_animal_by_id(aid)
	_assert(restored != null, "animal restaurado não encontrado para id '%s'" % aid)
	if restored:
		var sprite := restored.get_node_or_null("Sprite2D")
		_assert(sprite != null and sprite.texture == sleep_tex,
			"restore deveria preservar visual sleep no ciclo noturno")
		_assert(restored.current_state == Animal.AnimalState.IDLE,
			"após notify+recycle, estado esperado é IDLE")
		_assert(restored.current_state != Animal.AnimalState.FLY,
			"não deve entrar em FLY sem interação do usuário")

	if restored:
		restored.idle_awake_texture = old_awake
		restored.idle_sleep_texture = old_sleep
		restored.sleeps_at_night = old_sleeps
		restored.notify_day_night_changed(orig_is_day)
	cfg.is_day = orig_is_day


# ── Grupo 16: Água / Submerso ─────────────────────────────────────────────────

func _g16a_enter_water_sets_submerso() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16a__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, dummy)
	dummy.resync_water_state("test_g16a")
	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"ao entrar na água, estado esperado SUBMERSO")

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16b_submerged_texture_from_extras() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16b__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, dummy)
	dummy.resync_water_state("test_g16b")
	var sprite := dummy.get_node_or_null("Sprite2D") as Sprite2D
	var valid_paths := {
		"res://assets/extras/olhin-1.png": true,
		"res://assets/extras/olhin-2.png": true,
		"res://assets/extras/olhin-3.png": true,
		"res://assets/extras/olhin-4.png": true,
	}
	var tex_path := sprite.texture.resource_path if sprite and sprite.texture else ""
	_assert(valid_paths.has(tex_path),
		"textura submersa deve vir de assets/extras/olhin-[1..4].png, atual='%s'" % tex_path)

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16c_reentry_keeps_valid_submerged_texture() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16c__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	var valid_paths := {
		"res://assets/extras/olhin-1.png": true,
		"res://assets/extras/olhin-2.png": true,
		"res://assets/extras/olhin-3.png": true,
		"res://assets/extras/olhin-4.png": true,
	}
	var all_valid := true
	for _i in range(6):
		_move_water_zone_to_feet(zone, dummy)
		dummy.resync_water_state("test_g16c_enter_%d" % _i)
		var sprite := dummy.get_node_or_null("Sprite2D") as Sprite2D
		var tex_path := sprite.texture.resource_path if sprite and sprite.texture else ""
		if not valid_paths.has(tex_path):
			all_valid = false
		zone.global_position = dummy.global_position + Vector2(0.0, -420.0)
		dummy.resync_water_state("test_g16c_exit_%d" % _i)

	_assert(all_valid, "todas as entradas na água devem usar uma textura válida de extras")

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16d_exit_water_restores_flow() -> void:
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		_skip_test("WorldConfig não disponível")
		return

	# Caso 1: can_fly=true e acima do chão -> FLY
	var fly_dummy := _instantiate_dummy_animal("__test_g16d_fly__")
	var zone1 := _instantiate_test_water_zone(Vector2.ZERO)
	if not fly_dummy or not zone1:
		if fly_dummy: fly_dummy.queue_free()
		if zone1: zone1.queue_free()
		_skip_test("falha ao criar fixtures do caso FLY")
		return
	fly_dummy.can_fly = true
	fly_dummy.position.y = cfg.background_earth_y - 300.0
	_move_water_zone_to_feet(zone1, fly_dummy)
	fly_dummy.resync_water_state("test_g16d_fly_enter")
	zone1.global_position = fly_dummy.global_position + Vector2(0.0, -420.0)
	fly_dummy.resync_water_state("test_g16d_fly_exit")
	_assert(fly_dummy.current_state == Animal.AnimalState.FLY,
		"ao sair da água acima do chão com can_fly=true, esperado FLY")

	# Caso 2: can_fly=false e acima do chão -> FALL
	var fall_dummy := _instantiate_dummy_animal("__test_g16d_fall__")
	var zone2 := _instantiate_test_water_zone(Vector2.ZERO)
	if not fall_dummy or not zone2:
		fly_dummy.queue_free()
		zone1.queue_free()
		if fall_dummy: fall_dummy.queue_free()
		if zone2: zone2.queue_free()
		_skip_test("falha ao criar fixtures do caso FALL")
		return
	fall_dummy.can_fly = false
	fall_dummy.position.y = cfg.background_earth_y - 300.0
	_move_water_zone_to_feet(zone2, fall_dummy)
	fall_dummy.resync_water_state("test_g16d_fall_enter")
	zone2.global_position = fall_dummy.global_position + Vector2(0.0, -420.0)
	fall_dummy.resync_water_state("test_g16d_fall_exit")
	_assert(fall_dummy.current_state == Animal.AnimalState.FALL,
		"ao sair da água acima do chão com can_fly=false, esperado FALL")

	# Caso 3: no chão -> IDLE
	var idle_dummy := _instantiate_dummy_animal("__test_g16d_idle__")
	var zone3 := _instantiate_test_water_zone(Vector2.ZERO)
	if not idle_dummy or not zone3:
		fly_dummy.queue_free()
		zone1.queue_free()
		fall_dummy.queue_free()
		zone2.queue_free()
		if idle_dummy: idle_dummy.queue_free()
		if zone3: zone3.queue_free()
		_skip_test("falha ao criar fixtures do caso IDLE")
		return
	idle_dummy.can_fly = true
	idle_dummy.position.y = cfg.background_earth_y + 240.0
	_move_water_zone_to_feet(zone3, idle_dummy)
	idle_dummy.resync_water_state("test_g16d_idle_enter")
	zone3.global_position = idle_dummy.global_position + Vector2(0.0, -420.0)
	idle_dummy.resync_water_state("test_g16d_idle_exit")
	_assert(idle_dummy.current_state == Animal.AnimalState.IDLE,
		"ao sair da água no chão, esperado IDLE")

	zone1.queue_free()
	zone2.queue_free()
	zone3.queue_free()
	fly_dummy.queue_free()
	fall_dummy.queue_free()
	idle_dummy.queue_free()
	await get_tree().process_frame


func _g16e_day_night_does_not_override_submerged() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16e__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, dummy)
	dummy.resync_water_state("test_g16e")
	var sprite := dummy.get_node_or_null("Sprite2D") as Sprite2D
	var before_path := sprite.texture.resource_path if sprite and sprite.texture else ""
	dummy.notify_day_night_changed(false)
	var after_path := sprite.texture.resource_path if sprite and sprite.texture else ""
	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"animal deveria permanecer em SUBMERSO durante notify_day_night_changed")
	_assert(before_path == after_path,
		"notify_day_night_changed não deve trocar textura enquanto SUBMERSO")

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16f_recycle_after_submerged_keeps_validator_ok() -> void:
	var animal := _find_free_animal()
	if not animal:
		_skip_test("nenhum animal livre disponível")
		return

	var zone := _instantiate_test_water_zone(animal.global_position)
	if not zone:
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, animal)
	animal.resync_water_state("test_g16f")
	_assert(animal.current_state == Animal.AnimalState.SUBMERSO,
		"pré-condição: animal deve entrar em SUBMERSO antes do recycle")

	var recycled := await _recycle_segment_containing_animal(animal)
	_assert(recycled, "não foi possível reciclar segmento no cenário G16-F")

	var ok: bool = _validator.validate(_wm, "G16-F após recycle com SUBMERSO")
	_assert(ok, "validador falhou após recycle com animal submerso")

	zone.queue_free()
	await get_tree().process_frame


func _g16g_duplicate_enter_does_not_inflate_overlap() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16g__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, dummy)
	dummy._on_area_area_entered(zone)
	dummy._on_area_area_entered(zone)
	dummy.resync_water_state("test_g16g")
	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"com entrada duplicada, estado deve permanecer SUBMERSO")
	_assert(dummy._water_overlap_count == 1,
		"entrada duplicada não deve inflar overlap_count (esperado 1, atual=%d)" % dummy._water_overlap_count)

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16h_resync_restores_submerged_state() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16h__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	_move_water_zone_to_feet(zone, dummy)
	dummy.resync_water_state("test_g16h_enter")
	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"pré-condição: animal deveria estar SUBMERSO")

	# Simula dessicronização de FSM (ex.: normalização indevida durante recycle)
	dummy.transition_to(Animal.AnimalState.IDLE)
	dummy._water_overlap_count = 0
	dummy._water_overlap_ids.clear()
	dummy.resync_water_state("test_g16h")

	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"resync deveria restaurar SUBMERSO quando ainda existe overlap de água")
	_assert(dummy._water_overlap_count == 1,
		"resync deveria recomputar overlap_count=1 (atual=%d)" % dummy._water_overlap_count)

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


func _g16i_center_overlap_without_feet_does_not_submerge() -> void:
	var dummy := _instantiate_dummy_animal("__test_g16i__")
	if not dummy:
		_skip_test("não foi possível criar animal de teste")
		return
	var zone := _instantiate_test_water_zone(dummy.global_position)
	if not zone:
		dummy.queue_free()
		_skip_test("não foi possível criar water zone de teste")
		return

	# Zona no centro: pode cobrir tronco/corpo, mas não deve cobrir o ponto dos pés.
	zone.global_position = dummy.global_position
	dummy.resync_water_state("test_g16i_center")
	_assert(dummy.current_state != Animal.AnimalState.SUBMERSO,
		"com água apenas no centro e pé fora, não deveria entrar em SUBMERSO")
	_assert(dummy._water_overlap_count == 0,
		"com pé fora da água, overlap_count esperado=0 (atual=%d)" % dummy._water_overlap_count)

	# Controle positivo: ao mover a água para o pé, deve submergir.
	_move_water_zone_to_feet(zone, dummy)
	dummy.resync_water_state("test_g16i_feet")
	_assert(dummy.current_state == Animal.AnimalState.SUBMERSO,
		"ao mover a zona para o pé, deveria entrar em SUBMERSO")

	zone.queue_free()
	dummy.queue_free()
	await get_tree().process_frame


# ── Helpers de busca ──────────────────────────────────────────────────────────

func _create_colored_texture(width: int, height: int, color: Color) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _snap_animal_feet_to_ground(animal: Node, ground_y: float) -> bool:
	if not animal:
		return false
	var sprite := animal.get_node_or_null("Sprite2D") as Sprite2D
	if not sprite or not sprite.texture:
		return false
	var parent_node := animal.get_parent() as Node2D
	var parent_global_y: float = parent_node.global_position.y if parent_node else 0.0
	const FEET_OFFSET := 20.0
	var feet_offset: float = sprite.texture.get_height() / 2.0 * animal.scale.y + FEET_OFFSET
	animal.position.y = ground_y - feet_offset - parent_global_y
	return true


func _find_free_flying_animal() -> Node:
	for a: Node in get_tree().get_nodes_in_group("animals"):
		if not a.get("is_hidden") and a.visible and not a.has_meta("managed_by_bush") and a.get("can_fly"):
			return a
	return null


func _find_active_animal_by_id(animal_id: String) -> Node:
	if _wm:
		var key := animal_id + "_active_node"
		if _wm.animals_state.has(key):
			var active = _wm.animals_state[key]
			if is_instance_valid(active):
				return active
	for a: Node in get_tree().get_nodes_in_group("animals"):
		if _wm and _wm.get_animal_unique_id(a) == animal_id and a.visible:
			return a
	return null


func _recycle_segment_containing_animal(animal: Node) -> bool:
	if not animal or not _wm:
		return false
	var scroller = _wm.get("infinite_scroller")
	if not scroller:
		return false
	var seg: Node2D = _wm.get_segment_for_animal(animal) as Node2D
	if not seg:
		return false

	var seg_idx := -1
	for i in range(scroller.segments.size()):
		if scroller.segments[i].get("node") == seg:
			seg_idx = i
			break
	if seg_idx < 0:
		return false

	var rightmost_x: float = scroller.get_rightmost_segment_x()
	scroller.recycle_segment(seg_idx, rightmost_x + scroller.world_width)
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	return true

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


func _find_empty_unoccupied_bush_except(excluded: Node, animal: Node = null) -> Node:
	for b: Node in get_tree().get_nodes_in_group("bushes"):
		var is_excluded := is_instance_valid(excluded) and b == excluded
		if is_excluded or b.get("is_occupied") or b.get("is_revealed"):
			continue
		# Se o arbusto usa allowlist, só retornar quando o animal atual for compatível.
		if animal:
			var allowlist: Array = b.get("accepted_animal_names")
			if allowlist != null and allowlist.size() > 0:
				var aname: String = str(animal.get("animal_name"))
				if aname not in allowlist:
					continue
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


func _instantiate_test_water_zone(global_pos: Vector2) -> Area2D:
	var zone := Area2D.new()
	zone.name = "__test_water_zone__"
	zone.input_pickable = false
	zone.monitoring = true
	zone.monitorable = true
	zone.add_to_group("water_zones")

	var cfg := get_node_or_null("/root/WorldConfig")
	var water_mask := 1 << 7
	if cfg and cfg.has_method("get_water_collision_layer_mask"):
		water_mask = int(cfg.get_water_collision_layer_mask())
	zone.collision_layer = water_mask
	zone.collision_mask = 0

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200.0, 120.0)
	shape.shape = rect
	zone.add_child(shape)

	add_child(zone)
	zone.global_position = global_pos
	return zone


func _move_water_zone_to_feet(zone: Area2D, animal: Node, y_offset: float = 0.0) -> void:
	if not zone or not animal:
		return
	var animal_2d := animal as Node2D
	if not animal_2d:
		return
	var feet_y: float = animal_2d.global_position.y
	if animal.has_method("get_feet_y"):
		feet_y = float(animal.get_feet_y())
	zone.global_position = Vector2(animal_2d.global_position.x, feet_y + y_offset)


func _is_bush_in_active_segment(bush: Node) -> bool:
	if not _wm:
		return false
	var scroller = _wm.get("infinite_scroller")
	if not scroller:
		return true
	if not _wm.has_method("get_node_or_null_in_parents"):
		return true
	var seg: Node2D = _wm.get_node_or_null_in_parents(bush)
	if not seg:
		return false
	for seg_data in scroller.segments:
		if seg_data.get("node") == seg:
			return true
	return false


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
