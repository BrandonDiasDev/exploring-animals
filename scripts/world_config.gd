extends Node
## Configurações globais do mundo — este é o arquivo central de configuração.
## Modifique aqui para alterar comportamentos visuais e de gameplay.
## Registrado como Autoload com o nome "WorldConfig" (acessível de qualquer script).

# ── Dimensões do mundo ─────────────────────────────────────────────────────────
## Limite superior do mundo em coordenadas de mundo (Y negativo = cima).
## Deve ser metade negativa de viewport_height (ex: 1400px → -700).
@export var world_top_y: float = -700.0

## Limite inferior do mundo em coordenadas de mundo (Y positivo = baixo).
@export var world_bottom_y: float = 700.0

# ── Divisão de planos ─────────────────────────────────────────────────────────
## Porcentagem da altura do mundo onde termina o Plano 2 e começa o Plano 1.
## 0.0 = topo, 1.0 = base.  Ex: 0.6 → Plano 2 ocupa 60% do topo.
@export_range(0.0, 1.0, 0.01) var plane_division_pct: float = 0.6

# ── Escalas dos planos ────────────────────────────────────────────────────────
## Escala dos animais no Plano 1 (frente — maior, mais próximo).
@export var plane1_scale: Vector2 = Vector2(1.0, 1.0)

## Escala dos animais no Plano 2 (fundo — menor, mais distante).
@export var plane2_scale: Vector2 = Vector2(0.6, 0.6)

# ── Guia visual de planos (PlaneGuide) ────────────────────────────────────────
## Ativa ou desativa o guia visual de planos e dimensões em tela.
@export var show_plane_guide: bool = true

## Ativa/desativa visualizações de debug em runtime (ex.: linhas e zonas do PlaneGuide).
## Não altera a jogabilidade; apenas o desenho dos overlays de debug.
@export var debug_visuals_enabled: bool = true

## Cor do preenchimento da zona do Plano 2 (fundo).
@export var guide_plane2_color: Color = Color(0.2, 0.4, 0.9, 0.12)

## Cor do preenchimento da zona do Plano 1 (frente).
@export var guide_plane1_color: Color = Color(0.2, 0.8, 0.3, 0.12)

## Cor da linha de divisão entre os planos.
@export var guide_division_color: Color = Color(1.0, 1.0, 0.0, 0.9)

## Cor das linhas de borda (topo e base do mundo).
@export var guide_border_color: Color = Color(1.0, 0.35, 0.35, 0.95)

## Cor do cruzeiro central (centro da tela).
@export var guide_center_color: Color = Color(1.0, 1.0, 1.0, 0.65)

# ── Skyline ───────────────────────────────────────────────────────────────────
## Posição Y da skyline em coordenadas de mundo.
## 0 = centro do mundo; negativo = acima.  Ex: -444 fica ~444 px acima do centro.
@export var skyline_y: float = -444.0

## Cor da linha de skyline.
@export var guide_skyline_color: Color = Color(0.4, 0.85, 1.0, 0.9)

# ── Background Earth ────────────────────────────────────────────────────────
## Posição Y da linha "background earth" em coordenadas de mundo.
## Por padrão fica 250 px abaixo da skyline (-444 + 250 = -194).
@export var background_earth_y: float = -194.0

## Cor da linha de background earth.
@export var guide_earth_color: Color = Color(0.6, 0.42, 0.2, 0.9)

## Cor dos textos/rótulos do guia.
@export var guide_label_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Espessura das linhas do guia (pixels).
@export var guide_line_width: float = 2.0

## Tamanho da fonte dos rótulos do guia.
@export var guide_font_size: int = 14

# ── Overlay de clip (ClipOverlay) ─────────────────────────────────────────────
## Cor dos painéis que cobrem as áreas acima/abaixo do mundo.
## Deve combinar com a cor de fundo da janela do projeto.
@export var clip_overlay_color: Color = Color(0.114, 0.114, 0.114, 1.0)
## Cor dos painéis durante a noite (interpola a partir de clip_overlay_color).
@export var clip_overlay_night_color: Color = Color(0.04, 0.04, 0.07, 1.0)

# ── Nuvens (parallax) ─────────────────────────────────────────────────────────
## Quantidade de nuvens ativas na camada global.
@export_range(1, 32, 1) var cloud_count: int = 8

## Velocidade horizontal mínima/máxima das nuvens (px/s).
@export var cloud_speed_min: float = 18.0
@export var cloud_speed_max: float = 42.0

## Direção das nuvens: "mixed" (ambos os sentidos), "left" ou "right".
@export_enum("mixed", "left", "right") var cloud_direction_mode: String = "mixed"

## Fator de parallax relativo ao deslocamento da câmera (0..1).
@export_range(0.0, 1.0, 0.01) var cloud_parallax_factor: float = 0.20

## Faixa de escala aleatória aplicada por nuvem no spawn/reset.
@export var cloud_scale_min: float = 0.65
@export var cloud_scale_max: float = 1.35

## Faixa vertical (Y mundo) para spawn das nuvens.
@export var cloud_spawn_y_min: float = -560.0
@export var cloud_spawn_y_max: float = -350.0

## Buffer fora da tela para wrap/reposicionamento sem pop visível.
@export var cloud_offscreen_buffer: float = 420.0

## Faixa de alpha das nuvens para variação visual suave.
@export var cloud_alpha_min: float = 0.65
@export var cloud_alpha_max: float = 0.95

# ── Estado global dia/noite ───────────────────────────────────────────────────
## `true` enquanto for dia; `false` enquanto for noite.
## Atualizado por sun_moon.gd no início de cada transição.
var is_day: bool = true

## Duração padrão de voo (segundos) — fallback quando a cena do animal não sobrescreve fly_duration.
@export var default_fly_duration: float = 5.0
