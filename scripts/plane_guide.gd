extends Control
## Guia visual de planos — lê todas as configurações de WorldConfig.
## Para alterar cores, espessuras e posições, edite scripts/world_config.gd.

const _WorldConfig := preload("res://scripts/world_config.gd")

func _draw() -> void:
	var cfg := get_node_or_null("/root/WorldConfig") as _WorldConfig
	if not cfg or not cfg.show_plane_guide or not cfg.debug_visuals_enabled:
		return

	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	var vp    := get_viewport_rect().size
	var cam_y := camera.global_position.y
	var zm_y  := camera.zoom.y

	# Converte Y do mundo para Y da tela (inlined para manter tipos)
	var y_top    : float = (cfg.world_top_y    - cam_y) * zm_y + vp.y * 0.5
	var y_bottom : float = (cfg.world_bottom_y - cam_y) * zm_y + vp.y * 0.5
	var y_div    : float = y_top + (y_bottom - y_top) * cfg.plane_division_pct

	# Clamp p/ desenhar apenas dentro da viewport
	var y_top_c    := clampf(y_top,    0.0, vp.y)
	var y_bottom_c := clampf(y_bottom, 0.0, vp.y)
	var y_div_c    := clampf(y_div,    0.0, vp.y)

	# ── Preenchimento das zonas ───────────────────────────────────────────────
	if y_top_c < y_div_c:
		draw_rect(Rect2(0.0, y_top_c, vp.x, y_div_c - y_top_c), cfg.guide_plane2_color)
	if y_div_c < y_bottom_c:
		draw_rect(Rect2(0.0, y_div_c, vp.x, y_bottom_c - y_div_c), cfg.guide_plane1_color)

	var lw   : float  = cfg.guide_line_width
	var font          := ThemeDB.fallback_font
	var fs   : int    = cfg.guide_font_size
	var lc   : Color  = cfg.guide_label_color
	const PAD := 10.0

	# ── Borda superior do mundo ───────────────────────────────────────────────
	draw_line(Vector2(0.0, y_top), Vector2(vp.x, y_top), cfg.guide_border_color, lw)
	var world_h : float = cfg.world_bottom_y - cfg.world_top_y
	draw_string(font,
		Vector2(PAD, y_top + fs + PAD),
		"↑ topo   y = %.0f     altura: %.0f px" % [cfg.world_top_y, world_h],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cfg.guide_border_color)

	# ── Borda inferior do mundo ───────────────────────────────────────────────
	draw_line(Vector2(0.0, y_bottom), Vector2(vp.x, y_bottom), cfg.guide_border_color, lw)
	draw_string(font,
		Vector2(PAD, y_bottom - PAD * 0.5),
		"↓ base   y = %.0f" % cfg.world_bottom_y,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cfg.guide_border_color)

	# ── Linha de divisão de planos ────────────────────────────────────────────
	draw_line(Vector2(0.0, y_div), Vector2(vp.x, y_div), cfg.guide_division_color, lw)

	# Rótulo zona Plano 2 (centro vertical da zona)
	var p2_cy : float = (y_top + y_div) * 0.5
	draw_string(font,
		Vector2(PAD, p2_cy - fs * 0.5 - 2.0),
		"PLANO 2   fundo   escala %.0f%%" % (cfg.plane2_scale.x * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)

	# Rótulo zona Plano 1 (centro vertical da zona)
	var p1_cy : float = (y_div + y_bottom) * 0.5
	draw_string(font,
		Vector2(PAD, p1_cy - fs * 0.5 - 2.0),
		"PLANO 1   frente   escala %.0f%%" % (cfg.plane1_scale.x * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)

	# Rótulo da linha de divisão (centrado horizontalmente)
	var div_y_world : float = cfg.world_top_y + world_h * cfg.plane_division_pct
	draw_string(font,
		Vector2(vp.x * 0.5, y_div - PAD * 0.5),
		"── divisão   %.0f%%   y ≈ %.0f" % [cfg.plane_division_pct * 100.0, div_y_world],
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs, cfg.guide_division_color)

	# ── Cruzeiro central ─────────────────────────────────────────────────────
	var cx  := vp.x * 0.5
	var cy  := vp.y * 0.5
	const ARM := 26.0
	var cc  : Color = cfg.guide_center_color
	draw_line(Vector2(cx - ARM, cy), Vector2(cx + ARM, cy), cc, lw)
	draw_line(Vector2(cx, cy - ARM), Vector2(cx, cy + ARM), cc, lw)
	draw_arc(Vector2(cx, cy), 7.0, 0.0, TAU, 24, cc, lw)

	# Rótulo viewport (à direita do cruzeiro)
	draw_string(font,
		Vector2(cx + ARM + 8.0, cy - fs * 0.5 - 3.0),
		"viewport   %.0f × %.0f" % [vp.x, vp.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, cc)
	draw_string(font,
		Vector2(cx + ARM + 8.0, cy + fs * 0.5 + 3.0),
		"centro   (0, 0)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, cc)

	# ── Skyline ────────────────────────────────────────────────────────
	var y_sky : float = (cfg.skyline_y - cam_y) * zm_y + vp.y * 0.5
	var sc    : Color = cfg.guide_skyline_color
	# Preenchimento apenas acima da skyline (zona de céu)
	var y_sky_top : float = clampf(y_sky, 0.0, vp.y)
	if y_top_c < y_sky_top:
		draw_rect(Rect2(0.0, y_top_c, vp.x, y_sky_top - y_top_c),
			Color(sc.r, sc.g, sc.b, 0.13))
	draw_line(Vector2(0.0, y_sky), Vector2(vp.x, y_sky), sc, lw)
	draw_string(font,
		Vector2(PAD, y_sky - PAD * 0.5),
		"skyline   y = %.0f" % cfg.skyline_y,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sc)

	# ── Background Earth ──────────────────────────────────────────────
	var y_earth : float = (cfg.background_earth_y - cam_y) * zm_y + vp.y * 0.5
	var ec      : Color = cfg.guide_earth_color
	draw_line(Vector2(0.0, y_earth), Vector2(vp.x, y_earth), ec, lw)
	draw_string(font,
		Vector2(PAD, y_earth - PAD * 0.5),
		"background earth   y = %.0f" % cfg.background_earth_y,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ec)


func _process(_delta: float) -> void:
	queue_redraw()
