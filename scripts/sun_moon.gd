extends Control
## Sol e Lua — elementos do céu que acompanham a câmera (CanvasLayer).
##
## Comportamento:
##   • Apenas um deles está visível por vez (sol de dia, lua de noite).
##   • Clicar no sol → anima o pôr-do-sol → troca para a lua.
##   • Clicar na lua → anima o pôr-da-lua → troca para o sol.
##   • A posição na tela é calculada em relação ao tamanho da viewport,
##     por isso funcionará em qualquer resolução.

# ── Caminhos dos assets ────────────────────────────────────────────────────────
const SUN_PATH  := "res://assets/backgrounds/sun.png"
const MOON_PATH := "res://assets/backgrounds/moon.png"

# ── Parâmetros visuais ────────────────────────────────────────────────────────
## Tamanho da lua em pixels.
const MOON_SIZE := Vector2(80.0, 80.0)
## Tamanho do sol em pixels. Ajuste livremente — a transição continuará centrada.
## Referência: 1.5× a lua = 120 px, 2× = 160 px.
const SUN_SIZE  := Vector2(120.0, 120.0)

# ── Parâmetros de posicionamento ─────────────────────────────────────────────
## Margem em relação à borda direita da tela (pixels).
const MARGIN_RIGHT         := 450.0
## Quantos pixels o ícone fica abaixo do topo da tela (mínimo).
const MARGIN_TOP           := 30.0
## Quantos pixels o centro do ícone fica ACIMA da skyline.
## Aumente se o ícone ficar próximo demais da skyline; diminua para afastar do topo.
const MARGIN_ABOVE_SKYLINE := 150.0

# ── Parâmetros de animação ────────────────────────────────────────────────────
## Duração do pôr/nascer em segundos.
const ANIM_DURATION := 0.65

## Distância (px) que o astro "desce" ao se pôr / "sobe" ao nascer.
const SET_OFFSET_Y := 90.0

## Easing da saída (pôr) e da entrada (nascer).
const EASE_OUT_CURVE := Tween.EASE_IN
const EASE_IN_CURVE  := Tween.EASE_OUT

## Duração da transição de fundo (backgrounds dos segmentos do mundo).
const BG_TRANSITION_DURATION := 4.5

# ── Sinal ─────────────────────────────────────────────────────────────────────
## Disparado no início da transição dia↔noite.
## `duration` indica em segundos quanto tempo o background deve levar.
signal day_night_transition_started(to_day: bool, duration: float)

# ── Nós criados em código ─────────────────────────────────────────────────────
var _sun:  TextureRect
var _moon: TextureRect

# ── Estado ────────────────────────────────────────────────────────────────────
var _is_day:    bool  = true
var _animating: bool  = false

## Centro compartilhado dos astros na tela (recalculado ao redimensionar / por frame).
var _base_center: Vector2 = Vector2.ZERO

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Ocupa toda a área da CanvasLayer para ter coordenadas de tela disponíveis.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sun  = _make_icon(SUN_PATH,  "Sun",  SUN_SIZE)
	_moon = _make_icon(MOON_PATH, "Moon", MOON_SIZE)
	add_child(_sun)
	add_child(_moon)
	# Re-assert size after entering the tree — TextureRect can inflate to texture's
	# native pixel size otherwise, breaking all position math.
	_sun.size  = SUN_SIZE
	_moon.size = MOON_SIZE

	# Estado inicial: dia
	_moon.modulate.a = 0.0
	_moon.visible    = false

	_sun.gui_input.connect(_on_sun_input)
	_moon.gui_input.connect(_on_moon_input)

	# Aguarda um frame para que `size` e a câmera reflitam a cena real.
	await get_tree().process_frame
	_place_icons()

# ─────────────────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	# Recalcula posição a cada frame — garante que zoom/câmera sejam respeitados.
	# Se não estiver animando, move os ícones junto.
	var new_center := _compute_position()
	if new_center != _base_center:
		_base_center = new_center
		if not _animating:
			_sun.position  = new_center - _sun.size * 0.5
			_moon.position = new_center - _moon.size * 0.5
		if DebugLogger.enabled and DebugLogger.sun_moon:
			var cam := get_viewport().get_camera_2d()
			var vp  := get_viewport_rect().size
			print("[SunMoon] _process: center changed → new_center=%s  animating=%s  cam.pos=%s  cam.zoom=%s  vp=%s" % [new_center, _animating, (cam.global_position if cam else "NO CAM"), (cam.zoom if cam else "NO CAM"), vp])

# ─────────────────────────────────────────────────────────────────────────────
func _make_icon(path: String, node_name: String, icon_size: Vector2) -> TextureRect:
	var rect          := TextureRect.new()
	rect.name         = node_name
	rect.texture      = load(path)
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = icon_size
	rect.size         = icon_size
	rect.pivot_offset = icon_size * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if DebugLogger.enabled and DebugLogger.sun_moon:
		print("[SunMoon] _make_icon '%s'  size=%s  pivot_offset=%s" % [node_name, rect.size, rect.pivot_offset])
	return rect

# ─────────────────────────────────────────────────────────────────────────────
## Retorna o CENTRO compartilhado dos astros em coordenadas de tela.
## Cada ícone é posicionado em (centro - tamanho/2) para ficar centralizado.
func _compute_position() -> Vector2:
	var vp  := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()

	# center_x: distância da borda direita até o centro do ícone.
	var center_x := vp.x - MARGIN_RIGHT
	var center_y : float

	if cam:
		var cfg       := get_node_or_null("/root/WorldConfig")
		var skyline_y : float = cfg.skyline_y if cfg else -444.0
		# Converte Y do mundo para Y da tela
		var screen_sky_y := (skyline_y - cam.global_position.y) * cam.zoom.y + vp.y * 0.5
		center_y = screen_sky_y - MARGIN_ABOVE_SKYLINE
	else:
		center_y = vp.y * 0.10  # fallback sem câmera

	# Garante que o centro nunca sai pela parte de cima da tela
	center_y = maxf(center_y, MARGIN_TOP)

	return Vector2(center_x, center_y)

func _place_icons() -> void:
	var center     := _compute_position()
	_base_center   = center
	_sun.position  = center - _sun.size * 0.5
	_moon.position = center - _moon.size * 0.5
	if DebugLogger.enabled and DebugLogger.sun_moon:
		print("[SunMoon] _place_icons  center=%s  sun.pos=%s  sun.size=%s  moon.pos=%s  moon.size=%s" % [center, _sun.position, _sun.size, _moon.position, _moon.size])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_icons()

# ─────────────────────────────────────────────────────────────────────────────
func _on_sun_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if DebugLogger.enabled and DebugLogger.sun_moon:
			print("[SunMoon] SUN clicked  _animating=%s  _is_day=%s  sun.pos=%s  sun.size=%s  sun.pivot_offset=%s" % [_animating, _is_day, _sun.position, _sun.size, _sun.pivot_offset])
	if _animating or not _is_day:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_animate_transition(false)   # dia → noite

func _on_moon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if DebugLogger.enabled and DebugLogger.sun_moon:
			print("[SunMoon] MOON clicked  _animating=%s  _is_day=%s  moon.pos=%s  moon.size=%s  moon.pivot_offset=%s" % [_animating, _is_day, _moon.position, _moon.size, _moon.pivot_offset])
	if _animating or _is_day:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_animate_transition(true)    # noite → dia

# ─────────────────────────────────────────────────────────────────────────────
## Anima a transição dia↔noite.
## `to_day = true`  → lua se põe, sol nasce.
## `to_day = false` → sol se põe, lua nasce.
func _animate_transition(to_day: bool) -> void:
	_animating = true

	# Atualiza o estado global ANTES de qualquer animação — segmentos reciclados
	# durante a transição já nascerão com o estado correto (snap instantâneo).
	var cfg := get_node_or_null("/root/WorldConfig")
	if cfg:
		cfg.is_day = to_day
	day_night_transition_started.emit(to_day, BG_TRANSITION_DURATION)

	var leaving     : TextureRect = _sun  if not to_day else _moon
	var arriving    : TextureRect = _moon if not to_day else _sun
	var base_center : Vector2     = _base_center

	if DebugLogger.enabled and DebugLogger.sun_moon:
		print("[SunMoon] _animate_transition  to_day=%s  _base_center=%s" % [to_day, base_center])
		print("[SunMoon]   leaving  ('%s')  pos=%s  size=%s  pivot_offset=%s  modulate.a=%.2f" % [leaving.name,  leaving.position,  leaving.size,  leaving.pivot_offset,  leaving.modulate.a])
		print("[SunMoon]   arriving ('%s')  pos=%s  size=%s  pivot_offset=%s  modulate.a=%.2f" % [arriving.name, arriving.position, arriving.size, arriving.pivot_offset, arriving.modulate.a])

	# ── 1. Pôr: desce e desaparece ────────────────────────────────────────────
	var tw_out := create_tween()
	tw_out.set_parallel(true)
	tw_out.tween_property(leaving, "position:y",
			base_center.y + SET_OFFSET_Y - leaving.size.y * 0.5, ANIM_DURATION) \
		.set_ease(EASE_OUT_CURVE).set_trans(Tween.TRANS_QUAD)
	tw_out.tween_property(leaving, "modulate:a", 0.0, ANIM_DURATION)
	await tw_out.finished

	leaving.visible    = false
	leaving.position   = _base_center - leaving.size * 0.5   # reseta (pode ter mudado)
	leaving.modulate.a = 1.0

	# ── 2. Nascer: sobe e aparece ─────────────────────────────────────────────
	arriving.position   = Vector2(base_center.x - arriving.size.x * 0.5,
								  base_center.y + SET_OFFSET_Y - arriving.size.y * 0.5)
	arriving.modulate.a = 0.0
	arriving.visible    = true

	var tw_in := create_tween()
	tw_in.set_parallel(true)
	tw_in.tween_property(arriving, "position:y",
			base_center.y - arriving.size.y * 0.5, ANIM_DURATION) \
		.set_ease(EASE_IN_CURVE).set_trans(Tween.TRANS_QUAD)
	tw_in.tween_property(arriving, "modulate:a", 1.0, ANIM_DURATION)
	await tw_in.finished

	_is_day    = to_day
	_animating = false
