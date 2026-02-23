extends CanvasLayer

## Limites vertical do mundo em coordenadas de mundo (world space).
## A câmera começa em (0,0) e o design tem 1400px de altura,
## portanto os limites padrão são -700 (topo) e +700 (base).
@export var world_top_y: float = -700.0
@export var world_bottom_y: float = 700.0

## Cor do overlay — deve bater com a cor de fundo do projeto.
@export var overlay_color: Color = Color(0.3, 0.3, 0.3, 1.0)

var _top_panel: ColorRect
var _bottom_panel: ColorRect

func _ready():
	# Cria os painéis de overlay em código para não poluir a cena
	_top_panel = _make_panel()
	_bottom_panel = _make_panel()
	add_child(_top_panel)
	add_child(_bottom_panel)

func _make_panel() -> ColorRect:
	var r = ColorRect.new()
	r.color = overlay_color
	# IGNORE: não bloqueia clique nem hover nos animais abaixo
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _process(_delta: float):
	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	var vp_size := get_viewport().get_visible_rect().size

	# Converte Y do mundo para Y da tela usando a transformação da câmera
	var screen_top    := _world_y_to_screen_y(world_top_y,    camera, vp_size)
	var screen_bottom := _world_y_to_screen_y(world_bottom_y, camera, vp_size)

	# Painel de cima: cobre de y=0 até onde o mundo começa
	_top_panel.position = Vector2.ZERO
	_top_panel.size     = Vector2(vp_size.x, maxf(0.0, screen_top))

	# Painel de baixo: cobre de onde o mundo termina até o fim da tela
	_bottom_panel.position = Vector2(0.0, screen_bottom)
	_bottom_panel.size     = Vector2(vp_size.x, maxf(0.0, vp_size.y - screen_bottom))

func _world_y_to_screen_y(world_y: float, camera: Camera2D, vp_size: Vector2) -> float:
	# Fórmula padrão de projeção do Camera2D para coordenadas de tela
	return (world_y - camera.global_position.y) * camera.zoom.y + vp_size.y * 0.5
