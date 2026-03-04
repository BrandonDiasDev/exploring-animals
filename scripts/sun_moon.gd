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
## Tamanho dos ícones em pixels.
const ICON_SIZE := Vector2(80.0, 80.0)

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

## Y base dos astros na tela (recalculado ao redimensionar / por frame).
var _base_y: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Ocupa toda a área da CanvasLayer para ter coordenadas de tela disponíveis.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sun  = _make_icon(SUN_PATH,  "Sun")
	_moon = _make_icon(MOON_PATH, "Moon")
	add_child(_sun)
	add_child(_moon)

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
	var new_pos := _compute_position()
	if new_pos != Vector2(_sun.position.x, _base_y):
		_base_y = new_pos.y
		if not _animating:
			_sun.position  = new_pos
			_moon.position = new_pos

# ─────────────────────────────────────────────────────────────────────────────
func _make_icon(path: String, node_name: String) -> TextureRect:
	var rect          := TextureRect.new()
	rect.name         = node_name
	rect.texture      = load(path)
	rect.size         = ICON_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return rect

# ─────────────────────────────────────────────────────────────────────────────
## Calcula a posição-alvo do ícone em coordenadas de tela.
func _compute_position() -> Vector2:
	var vp  := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()

	var icon_x := vp.x - MARGIN_RIGHT - ICON_SIZE.x
	var icon_y : float

	if cam:
		var cfg       := get_node_or_null("/root/WorldConfig")
		var skyline_y : float = cfg.skyline_y if cfg else -444.0
		# Converte Y do mundo para Y da tela
		var screen_sky_y := (skyline_y - cam.global_position.y) * cam.zoom.y + vp.y * 0.5
		icon_y = screen_sky_y - MARGIN_ABOVE_SKYLINE - ICON_SIZE.y
	else:
		icon_y = vp.y * 0.10  # fallback sem câmera

	# Garante que nunca sai pela parte de cima da tela
	icon_y = maxf(icon_y, MARGIN_TOP)

	return Vector2(icon_x, icon_y)

func _place_icons() -> void:
	var pos    := _compute_position()
	_base_y    = pos.y
	_sun.position  = pos
	_moon.position = pos

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_icons()

# ─────────────────────────────────────────────────────────────────────────────
func _on_sun_input(event: InputEvent) -> void:
	if _animating or not _is_day:
		return
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_animate_transition(false)   # dia → noite

func _on_moon_input(event: InputEvent) -> void:
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


	var leaving  : TextureRect = _sun  if not to_day else _moon
	var arriving : TextureRect = _moon if not to_day else _sun
	var base_y   : float       = _base_y

	# ── 1. Pôr: desce e desaparece ────────────────────────────────────────────
	var tw_out := create_tween()
	tw_out.set_parallel(true)
	tw_out.tween_property(leaving, "position:y", base_y + SET_OFFSET_Y, ANIM_DURATION) \
		.set_ease(EASE_OUT_CURVE).set_trans(Tween.TRANS_QUAD)
	tw_out.tween_property(leaving, "modulate:a", 0.0, ANIM_DURATION)
	await tw_out.finished

	leaving.visible    = false
	leaving.position.y = _base_y   # reseta para a posição base (pode ter mudado)
	leaving.modulate.a = 1.0

	# ── 2. Nascer: sobe e aparece ─────────────────────────────────────────────
	arriving.position.y = base_y + SET_OFFSET_Y
	arriving.modulate.a = 0.0
	arriving.visible    = true

	var tw_in := create_tween()
	tw_in.set_parallel(true)
	tw_in.tween_property(arriving, "position:y", base_y, ANIM_DURATION) \
		.set_ease(EASE_IN_CURVE).set_trans(Tween.TRANS_QUAD)
	tw_in.tween_property(arriving, "modulate:a", 1.0, ANIM_DURATION)
	await tw_in.finished

	_is_day    = to_day
	_animating = false
