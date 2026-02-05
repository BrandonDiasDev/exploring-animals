extends Node2D
class_name InteractiveElement

signal clicked(element: InteractiveElement)
signal drag_started(element: InteractiveElement)
signal drag_ended(element: InteractiveElement, new_plane: String)

@export var element_name := "elemento"
@export var sound_path := ""
@export_enum("plane1", "plane2") var current_plane := "plane1"

var is_pressed := false
var press_timer := 0.0
const LONG_PRESS_TIME = 0.5

@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

func _ready():
	# Garantir que tem CollisionShape2D para detectar cliques
	if not has_node("Area2D"):
		var area = Area2D.new()
		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		
		add_child(area)
		area.add_child(collision)
		collision.shape = shape
		
		if sprite:
			shape.size = sprite.texture.get_size() if sprite.texture else Vector2(100, 100)
		
		area.input_event.connect(_on_input_event)

func _on_input_event(_viewport, event: InputEvent, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_pressed = true
			press_timer = 0.0
		else:
			if press_timer < LONG_PRESS_TIME:
				# Clique simples
				emit_signal("clicked", self)
				on_clicked()
			else:
				# Long press terminou
				emit_signal("drag_ended", self, current_plane)
			is_pressed = false
			press_timer = 0.0

func _process(delta):
	if is_pressed:
		press_timer += delta
		if press_timer >= LONG_PRESS_TIME:
			# Iniciou drag
			emit_signal("drag_started", self)
			# Aqui implementaremos o drag visual depois

func on_clicked():
	print(element_name, " foi clicado!")
	play_sound()
	play_animation()
	zoom_camera()

func play_sound():
	if sound_path != "":
		# Implementar depois com AudioStreamPlayer
		pass

func play_animation():
	# Animação básica de "pulo"
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func zoom_camera():
	var camera = get_viewport().get_camera_2d()
	if camera:
		var tween = create_tween()
		tween.tween_property(camera, "zoom", Vector2(1.5, 1.5), 0.3)
		await tween.finished
		await get_tree().create_timer(0.5).timeout
		var tween2 = create_tween()
		tween2.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.3)
