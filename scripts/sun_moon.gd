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
const ICON_SIZE := Vector2(50.0, 50.0)

## Posição relativa à viewport (0–1).  (0.80, 0.06) = topo-direita do céu.
const POS_ANCHOR := Vector2(1, 1)

# ── Parâmetros de animação ────────────────────────────────────────────────────
## Duração do pôr/nascer em segundos.
const ANIM_DURATION := 0.65

## Distância (px) que o astro "desce" ao se pôr / "sobe" ao nascer.
const SET_OFFSET_Y := 90.0

## Easing da saída (pôr) e da entrada (nascer).
const EASE_OUT_CURVE := Tween.EASE_IN
const EASE_IN_CURVE  := Tween.EASE_OUT

# ── Nós criados em código ─────────────────────────────────────────────────────
var _sun:  TextureRect
var _moon: TextureRect

# ── Estado ────────────────────────────────────────────────────────────────────
var _is_day:    bool  = true
var _animating: bool  = false

## Y base de cada astro na tela (recalculado ao redimensionar).
var _sun_base_y:  float = 0.0
var _moon_base_y: float = 0.0

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

	# Aguarda um frame para que `size` reflita a viewport real.
	await get_tree().process_frame
	_place_icons()

# ─────────────────────────────────────────────────────────────────────────────
func _make_icon(path: String, node_name: String) -> TextureRect:
	var tr          := TextureRect.new()
	tr.name         = node_name
	tr.texture      = load(path)
	tr.size         = ICON_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return tr

# ─────────────────────────────────────────────────────────────────────────────
## Posiciona os dois ícones no ponto âncora da viewport.
func _place_icons() -> void:
	var sz  := size  # = tamanho da viewport por cause do PRESET_FULL_RECT
	var pos := Vector2(sz.x * POS_ANCHOR.x, sz.y * POS_ANCHOR.y)
	_sun.position  = pos
	_moon.position = pos
	_sun_base_y    = pos.y
	_moon_base_y   = pos.y

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

	var leaving  : TextureRect = _sun  if not to_day else _moon
	var arriving : TextureRect = _moon if not to_day else _sun
	var base_y   : float       = (_sun_base_y if not to_day else _moon_base_y)

	# ── 1. Pôr: desce e desaparece ────────────────────────────────────────────
	var tw_out := create_tween()
	tw_out.set_parallel(true)
	tw_out.tween_property(leaving, "position:y", base_y + SET_OFFSET_Y, ANIM_DURATION) \
		.set_ease(EASE_OUT_CURVE).set_trans(Tween.TRANS_QUAD)
	tw_out.tween_property(leaving, "modulate:a", 0.0, ANIM_DURATION)
	await tw_out.finished

	leaving.visible    = false
	leaving.position.y = base_y    # reseta para a posição base
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
