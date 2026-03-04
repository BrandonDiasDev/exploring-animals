extends CanvasLayer
## Overlay que cobre as faixas acima e abaixo do mundo visível.
## Todas as configurações (cor, limites Y) vêm de WorldConfig (scripts/world_config.gd).

const _WorldConfig := preload("res://scripts/world_config.gd")

var _top_panel: ColorRect
var _bottom_panel: ColorRect

## Cor interpolada atual dos painéis (transiciona entre day e night).
var _current_color: Color
var _tween: Tween = null

func _ready() -> void:
	_top_panel    = _make_panel()
	_bottom_panel = _make_panel()
	add_child(_top_panel)
	add_child(_bottom_panel)

	# Inicializa com a cor de dia
	var cfg := get_node_or_null("/root/WorldConfig")
	_current_color = cfg.clip_overlay_color if cfg else Color(0.114, 0.114, 0.114, 1.0)

func _make_panel() -> ColorRect:
	var r := ColorRect.new()
	# MOUSE_FILTER_IGNORE: não bloqueia cliques nem hover nos elementos abaixo
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _process(_delta: float) -> void:
	var cfg    := get_node_or_null("/root/WorldConfig") as _WorldConfig
	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	# Lê valores de WorldConfig, com fallback para os defaults originais
	var world_top_y    : float = cfg.world_top_y    if cfg else -700.0
	var world_bottom_y : float = cfg.world_bottom_y if cfg else  700.0

	_top_panel.color    = _current_color
	_bottom_panel.color = _current_color

	var vp_size := get_viewport().get_visible_rect().size

	var screen_top    := _world_y_to_screen_y(world_top_y,    camera, vp_size)
	var screen_bottom := _world_y_to_screen_y(world_bottom_y, camera, vp_size)

	# Painel de cima: cobre de y=0 até onde o mundo começa
	_top_panel.position = Vector2.ZERO
	_top_panel.size     = Vector2(vp_size.x, maxf(0.0, screen_top))

	# Painel de baixo: cobre de onde o mundo termina até o fim da tela
	_bottom_panel.position = Vector2(0.0, screen_bottom)
	_bottom_panel.size     = Vector2(vp_size.x, maxf(0.0, vp_size.y - screen_bottom))

## Interpola a cor do overlay entre dia e noite.
func transition_day_night(to_day: bool, duration: float) -> void:
	var cfg := get_node_or_null("/root/WorldConfig")
	if not cfg:
		return
	var target_color: Color = cfg.clip_overlay_color if to_day else cfg.clip_overlay_night_color

	if _tween:
		_tween.kill()
		_tween = null

	_tween = create_tween()
	_tween.tween_property(self, "_current_color", target_color, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _world_y_to_screen_y(world_y: float, camera: Camera2D, vp_size: Vector2) -> float:
	return (world_y - camera.global_position.y) * camera.zoom.y + vp_size.y * 0.5
