extends CanvasLayer
## Overlay que cobre as faixas acima e abaixo do mundo visível.
## Todas as configurações (cor, limites Y) vêm de WorldConfig (scripts/world_config.gd).

const _WorldConfig := preload("res://scripts/world_config.gd")

var _top_panel: ColorRect
var _bottom_panel: ColorRect

func _ready() -> void:
	_top_panel    = _make_panel()
	_bottom_panel = _make_panel()
	add_child(_top_panel)
	add_child(_bottom_panel)

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
	var overlay_color  : Color = cfg.clip_overlay_color if cfg else Color(0.114, 0.114, 0.114, 1.0)
	var world_top_y    : float = cfg.world_top_y         if cfg else -700.0
	var world_bottom_y : float = cfg.world_bottom_y      if cfg else  700.0

	_top_panel.color    = overlay_color
	_bottom_panel.color = overlay_color

	var vp_size := get_viewport().get_visible_rect().size

	var screen_top    := _world_y_to_screen_y(world_top_y,    camera, vp_size)
	var screen_bottom := _world_y_to_screen_y(world_bottom_y, camera, vp_size)

	# Painel de cima: cobre de y=0 até onde o mundo começa
	_top_panel.position = Vector2.ZERO
	_top_panel.size     = Vector2(vp_size.x, maxf(0.0, screen_top))

	# Painel de baixo: cobre de onde o mundo termina até o fim da tela
	_bottom_panel.position = Vector2(0.0, screen_bottom)
	_bottom_panel.size     = Vector2(vp_size.x, maxf(0.0, vp_size.y - screen_bottom))

func _world_y_to_screen_y(world_y: float, camera: Camera2D, vp_size: Vector2) -> float:
	return (world_y - camera.global_position.y) * camera.zoom.y + vp_size.y * 0.5
