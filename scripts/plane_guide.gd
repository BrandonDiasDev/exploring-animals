extends Control

func _ready():
	pass

func _draw():
	# Pegar a câmera para calcular posição correta
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var viewport_size = get_viewport_rect().size
	var camera_pos = camera.global_position
	
	# Calcular limites visíveis
	var camera_top = camera_pos.y - (viewport_size.y / (2.0 * camera.zoom.y))
	var camera_bottom = camera_pos.y + (viewport_size.y / (2.0 * camera.zoom.y))
	
	# Divisão em 60%
	var division_y = camera_top + (camera_bottom - camera_top) * 0.6
	
	# Converter coordenada global para coordenada de tela
	var screen_y = (division_y - camera_top) * camera.zoom.y
	
	# Desenhar linha
	draw_line(
		Vector2(0, screen_y),
		Vector2(viewport_size.x, screen_y),
		Color(1, 1, 0, 0.5),
		3.0
	)
	
	# Textos
	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, screen_y - 20),
		"PLANO 2 (Fundo) - Animais menores",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(1, 1, 0, 0.8)
	)
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, screen_y + 40),
		"PLANO 1 (Frente) - Animais maiores",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(1, 1, 0, 0.8)
	)

func _process(_delta):
	queue_redraw()  # Redesenhar a cada frame para acompanhar a câmera
