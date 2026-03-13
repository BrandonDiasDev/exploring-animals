extends Node2D

## Camada global de nuvens (parallax horizontal, dia-only).
## Deve viver em WorldContainer (fora dos segmentos recicláveis) para evitar popping.

const CLOUD_TEXTURE_PATHS := [
	"res://assets/backgrounds/nuvem1.png",
	"res://assets/backgrounds/nuvem2.png",
	"res://assets/backgrounds/nuvem3.png"
]

var _rng := RandomNumberGenerator.new()
var _camera: Camera2D = null
var _sun_moon: Node = null
var _cfg: Node = null
var _transition_tween: Tween = null

var _clouds: Array[Sprite2D] = []
var _speeds: Dictionary = {}
var _directions: Dictionary = {}

var _last_camera_x: float = 0.0
var _is_day_visible: bool = true
var _debug_log_accum: float = 0.0
var _debug_prev_x: Dictionary = {}
var _debug_prev_y: Dictionary = {}

# Métricas de debug/testes
var _wrap_events: int = 0
var _reset_events: int = 0

func _ready() -> void:
	_rng.randomize()
	_cfg = get_node_or_null("/root/WorldConfig")
	_camera = get_viewport().get_camera_2d()
	_sun_moon = get_node_or_null("/root/World/Sky/SunMoon")
	
	if _sun_moon and _sun_moon.has_signal("day_night_transition_started"):
		_sun_moon.day_night_transition_started.connect(_on_day_night_transition_started)

	if _cfg:
		_is_day_visible = bool(_cfg.get("is_day"))
	else:
		_is_day_visible = true

	visible = _is_day_visible
	modulate.a = 1.0 if _is_day_visible else 0.0

	_rebuild_clouds()
	if _camera:
		_last_camera_x = _camera.global_position.x
	_log_clouds_bootstrap()
	_log_worldcontainer_draw_order()

func _process(delta: float) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
		if not _camera:
			return

	var cam_x := _camera.global_position.x
	var cam_dx := cam_x - _last_camera_x
	_last_camera_x = cam_x

	if _clouds.is_empty():
		return

	var parallax_factor := _get_cfg_float("cloud_parallax_factor", 0.20)
	var offscreen_buffer := _get_cfg_float("cloud_offscreen_buffer", 420.0)
	var view_bounds := _get_view_bounds_world()
	var left_bound := view_bounds.x - offscreen_buffer
	var right_bound := view_bounds.y + offscreen_buffer
	_debug_log_accum += delta

	for cloud in _clouds:
		if not is_instance_valid(cloud):
			continue
		var cloud_id := cloud.get_instance_id()
		var speed := float(_speeds.get(cloud_id, _get_cfg_float("cloud_speed_min", 18.0)))
		var direction := float(_directions.get(cloud_id, 1.0))
		var prev_x := float(_debug_prev_x.get(cloud_id, cloud.position.x))
		var prev_y := float(_debug_prev_y.get(cloud_id, cloud.position.y))
		
		# Horizontal only
		cloud.position.x += cam_dx * parallax_factor + direction * speed * delta
		var dx := cloud.position.x - prev_x
		var dy := cloud.position.y - prev_y
		_debug_prev_x[cloud_id] = cloud.position.x
		_debug_prev_y[cloud_id] = cloud.position.y
		if DebugLogger.enabled and DebugLogger.clouds and absf(dy) > 0.001:
			print("[CLOUD DRIFT-Y] id:", cloud_id,
				" | dy:", dy,
				" | prev_y:", prev_y,
				" | y:", cloud.position.y,
				" | dx:", dx,
				" | cam_dx:", cam_dx,
				" | speed:", speed,
				" | dir:", direction)
		
		var half_width := _get_cloud_half_width(cloud)
		if direction > 0.0 and cloud.position.x - half_width > right_bound:
			_wrap_events += 1
			if DebugLogger.enabled and DebugLogger.clouds:
				print("[CLOUD WRAP] id:", cloud_id,
					" | dir:+1 right->left",
					" | x:", cloud.position.x,
					" | y:", cloud.position.y,
					" | right_bound:", right_bound,
					" | half_w:", half_width)
			_reset_cloud(cloud, left_bound - half_width, true, true)
		elif direction < 0.0 and cloud.position.x + half_width < left_bound:
			_wrap_events += 1
			if DebugLogger.enabled and DebugLogger.clouds:
				print("[CLOUD WRAP] id:", cloud_id,
					" | dir:-1 left->right",
					" | x:", cloud.position.x,
					" | y:", cloud.position.y,
					" | left_bound:", left_bound,
					" | half_w:", half_width)
			_reset_cloud(cloud, right_bound + half_width, true, true)

	if DebugLogger.enabled and DebugLogger.clouds and _debug_log_accum >= 1.0:
		_debug_log_accum = 0.0
		print("[CLOUD TICK] cam_x:", cam_x,
			" | cam_dx:", cam_dx,
			" | bounds:[", left_bound, ",", right_bound, "]",
			" | clouds:", _clouds.size(),
			" | wraps:", _wrap_events,
			" | resets:", _reset_events)

func apply_day_night(to_day: bool, animated: bool = true, duration: float = 0.0) -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
		_transition_tween = null

	_is_day_visible = to_day
	if not animated or duration <= 0.0:
		visible = to_day
		modulate.a = 1.0 if to_day else 0.0
		return

	if to_day:
		visible = true
	
	_transition_tween = create_tween()
	_transition_tween.tween_property(self, "modulate:a", 1.0 if to_day else 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	if not to_day:
		_transition_tween.finished.connect(func():
			visible = false
		)

func get_wrap_count() -> int:
	return _wrap_events

func get_reset_count() -> int:
	return _reset_events

func get_cloud_count() -> int:
	return _clouds.size()

func is_day_visible() -> bool:
	return _is_day_visible and visible and modulate.a > 0.0

func _rebuild_clouds() -> void:
	for child in get_children():
		child.queue_free()
	_clouds.clear()
	_speeds.clear()
	_directions.clear()
	_debug_prev_x.clear()
	_debug_prev_y.clear()

	var cloud_count := int(_get_cfg_float("cloud_count", 8.0))
	cloud_count = maxi(cloud_count, 1)
	
	var textures := _load_cloud_textures()
	if textures.is_empty():
		push_warning("[CloudsLayer] Nenhuma textura de nuvem encontrada.")
		return

	var view_bounds := _get_view_bounds_world()
	var offscreen_buffer := _get_cfg_float("cloud_offscreen_buffer", 420.0)
	var spawn_left := view_bounds.x - offscreen_buffer
	var spawn_right := view_bounds.y + offscreen_buffer
	
	for i in range(cloud_count):
		var cloud := Sprite2D.new()
		cloud.texture = textures[_rng.randi_range(0, textures.size() - 1)]
		cloud.centered = true
		cloud.z_index = 0
		add_child(cloud)

		var x := _rng.randf_range(spawn_left, spawn_right)
		_reset_cloud(cloud, x, false, false)
		_clouds.append(cloud)

	if DebugLogger.enabled and DebugLogger.clouds:
		var right_count := 0
		var left_count := 0
		for cloud in _clouds:
			if not is_instance_valid(cloud):
				continue
			var cid := cloud.get_instance_id()
			var d := float(_directions.get(cid, 1.0))
			if d >= 0.0:
				right_count += 1
			else:
				left_count += 1
		print("[CLOUD BUILD] count:", _clouds.size(),
			" | direction_mode:", str(_get_cfg_value("cloud_direction_mode", "mixed")),
			" | right:", right_count,
			" | left:", left_count,
			" | y_range:[", _get_cfg_float("cloud_spawn_y_min", -560.0), ",", _get_cfg_float("cloud_spawn_y_max", -350.0), "]")

func _reset_cloud(cloud: Sprite2D, x: float, keep_direction: bool, keep_y: bool) -> void:
	if not is_instance_valid(cloud):
		return
	_reset_events += 1
	
	cloud.position.x = x
	if not keep_y:
		cloud.position.y = _random_spawn_y()
		if DebugLogger.enabled and DebugLogger.clouds:
			var skyline_y := _get_cfg_float("skyline_y", -444.0)
			var below_skyline := cloud.position.y > skyline_y
			print("[CLOUD RESET] id:", cloud.get_instance_id(),
				" | keep_direction:", keep_direction,
				" | keep_y:", keep_y,
				" | x:", cloud.position.x,
				" | y:", cloud.position.y,
				" | skyline:", skyline_y,
				" | below_skyline:", below_skyline)
	
	var min_scale := _get_cfg_float("cloud_scale_min", 0.65)
	var max_scale := _get_cfg_float("cloud_scale_max", 1.35)
	var s := _rng.randf_range(min_scale, max_scale)
	cloud.scale = Vector2(s, s)

	var cloud_id := cloud.get_instance_id()
	if not keep_direction or not _directions.has(cloud_id):
		_directions[cloud_id] = _random_direction()
	
	var min_speed := _get_cfg_float("cloud_speed_min", 18.0)
	var max_speed := _get_cfg_float("cloud_speed_max", 42.0)
	_speeds[cloud_id] = _rng.randf_range(min_speed, max_speed)

	var alpha_min := _get_cfg_float("cloud_alpha_min", 0.65)
	var alpha_max := _get_cfg_float("cloud_alpha_max", 0.95)
	var alpha := _rng.randf_range(alpha_min, alpha_max)
	cloud.modulate = Color(1.0, 1.0, 1.0, alpha)

func _random_spawn_y() -> float:
	var min_y := _get_cfg_float("cloud_spawn_y_min", -560.0)
	var max_y := _get_cfg_float("cloud_spawn_y_max", -350.0)
	var skyline_y := _get_cfg_float("skyline_y", -444.0)
	if max_y >= skyline_y:
		var clamped_max_y := skyline_y - 50.0
		if DebugLogger.enabled and DebugLogger.clouds:
			print("[CLOUD SKYLINE CLAMP] cloud_spawn_y_max (", max_y,
				") >= skyline_y (", skyline_y,
				") | clamped_max_y:", clamped_max_y)
		max_y = clamped_max_y
	if min_y > max_y:
		if DebugLogger.enabled and DebugLogger.clouds:
			print("[CLOUD Y RANGE SWAP] cloud_spawn_y_min (", min_y,
				") > cloud_spawn_y_max (", max_y,
				") | usando faixa corrigida.")
		var tmp := min_y
		min_y = max_y
		max_y = tmp
	return _rng.randf_range(min_y, max_y)

func _random_direction() -> float:
	var mode := str(_get_cfg_value("cloud_direction_mode", "mixed"))
	if mode == "left":
		return -1.0
	if mode == "right":
		return 1.0
	# mixed
	return 1.0 if _rng.randf() >= 0.5 else -1.0

func _on_day_night_transition_started(to_day: bool, duration: float) -> void:
	apply_day_night(to_day, true, duration)

func _get_view_bounds_world() -> Vector2:
	if not _camera:
		return Vector2(-960.0, 960.0)
	var vp_size := get_viewport_rect().size
	var half_width := vp_size.x * 0.5 * _camera.zoom.x
	return Vector2(_camera.global_position.x - half_width, _camera.global_position.x + half_width)

func _get_cloud_half_width(cloud: Sprite2D) -> float:
	if not cloud.texture:
		return 64.0
	return cloud.texture.get_width() * 0.5 * cloud.scale.x

func _load_cloud_textures() -> Array[Texture2D]:
	var loaded: Array[Texture2D] = []
	for path in CLOUD_TEXTURE_PATHS:
		var tex := load(path)
		if tex and tex is Texture2D:
			loaded.append(tex)
	return loaded

func _get_cfg_value(key: String, default_value: Variant) -> Variant:
	if _cfg and _cfg.get(key) != null:
		return _cfg.get(key)
	return default_value

func _get_cfg_float(key: String, default_value: float) -> float:
	var value = _get_cfg_value(key, default_value)
	if value is int or value is float:
		return float(value)
	return default_value

func _log_clouds_bootstrap() -> void:
	if not DebugLogger.enabled or not DebugLogger.clouds:
		return
	print("[CLOUD BOOT] visible:", visible,
		" | alpha:", modulate.a,
		" | is_day_visible:", _is_day_visible,
		" | cloud_count_cfg:", int(_get_cfg_float("cloud_count", 8.0)),
		" | parallax_factor:", _get_cfg_float("cloud_parallax_factor", 0.20),
		" | speed:[", _get_cfg_float("cloud_speed_min", 18.0), ",", _get_cfg_float("cloud_speed_max", 42.0), "]",
		" | direction_mode:", str(_get_cfg_value("cloud_direction_mode", "mixed")),
		" | y_range:[", _get_cfg_float("cloud_spawn_y_min", -560.0), ",", _get_cfg_float("cloud_spawn_y_max", -350.0), "]",
		" | skyline_y:", _get_cfg_float("skyline_y", -444.0),
		" | node_z:", z_index,
		" | z_as_relative:", z_as_relative,
		" | parent:", (str(get_parent().name) if get_parent() else "null"))

func _log_worldcontainer_draw_order() -> void:
	if not DebugLogger.enabled or not DebugLogger.clouds:
		return
	var parent := get_parent()
	if not parent:
		return
	print("[CLOUD LAYER SNAPSHOT] parent:", parent.name, " | child_count:", parent.get_child_count())
	for i in range(parent.get_child_count()):
		var child := parent.get_child(i)
		if child is CanvasItem:
			var item := child as CanvasItem
			print("  [", i, "] ", item.name,
				" | type:", item.get_class(),
				" | z:", item.z_index,
				" | visible:", item.visible)
		else:
			print("  [", i, "] ", child.name, " | type:", child.get_class())
