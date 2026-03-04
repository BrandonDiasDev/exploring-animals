extends Node2D
## Segmento do mundo — gerencia a transição dia/noite do background.
##
## Cada segmento possui dois Sprite2D sobrepostos:
##   • BackgroundDay   — sempre visível, textura de dia.
##   • BackgroundNight — sobreposto ao dia; opacidade 0 = dia, 1 = noite.
##
## A transição é feita interpolando `modulate.a` de BackgroundNight com
## TRANS_SINE + EASE_IN_OUT, produzindo um escurecer/clarear suave.

@onready var background_day:   Sprite2D = $BackgroundDay
@onready var background_night: Sprite2D = $BackgroundNight

const TRANSITION_TRANS := Tween.TRANS_SINE
const TRANSITION_EASE  := Tween.EASE_IN_OUT

var _tween: Tween = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Snap imediato para o estado global atual (sem animação).
	var cfg        := get_node_or_null("/root/WorldConfig")
	var is_day: bool = cfg.is_day if cfg else true
	apply_day_night(is_day, false, 0.0)

# ─────────────────────────────────────────────────────────────────────────────
## Aplica o estado dia/noite ao background deste segmento.
##
## `is_day`   — true = dia (BackgroundNight transparente).
## `animated` — se false, a mudança é instantânea.
## `duration` — segundos da interpolação (ignorado se animated=false).
func apply_day_night(is_day: bool, animated: bool, duration: float) -> void:
	if not is_instance_valid(background_night):
		return

	var target_alpha := 0.0 if is_day else 1.0

	# Cancela tween anterior, se existir
	if _tween:
		_tween.kill()
		_tween = null

	if not animated or duration <= 0.0:
		background_night.modulate.a = target_alpha
		return

	_tween = create_tween()
	_tween.tween_property(
		background_night, "modulate:a", target_alpha, duration
	).set_trans(TRANSITION_TRANS).set_ease(TRANSITION_EASE)
