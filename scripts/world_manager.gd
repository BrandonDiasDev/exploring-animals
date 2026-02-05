extends Node2D

const DRAG_SPEED = 1.5

@onready var camera: Camera2D = $Camera2D
@onready var infinite_scroller: Node2D = $InfiniteScroller

var camera_position: float = 0.0  # IMPORTANTE: definir tipo explícito
var is_dragging := false
var last_mouse_pos := Vector2.ZERO

func _ready():
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2.ZERO
	camera_position = 0.0  # Inicializar explicitamente

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				last_mouse_pos = event.position
			else:
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		var delta_x = event.position.x - last_mouse_pos.x
		camera_position -= delta_x * DRAG_SPEED
		last_mouse_pos = event.position

func _process(delta: float):
	# Suavizar movimento
	camera.position.x = lerp(camera.position.x, camera_position, delta * 10.0)
	
	# Passar posição para o scroller
	if infinite_scroller:
		infinite_scroller.update_camera_position(camera.position.x)
