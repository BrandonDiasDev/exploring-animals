extends Node
# DebugLogger — autoload singleton (registered as "DebugLogger" in project.godot).
# Controls which log categories are printed to the Output panel.
# Use the in-game overlay (F1) to toggle categories at runtime.
# Access from any script as:  DebugLogger.bush,  DebugLogger.gravity, etc.

# ─── Master switch ─────────────────────────────────────────────────────────────
## When false, ALL categories are silenced regardless of individual flags.
var enabled: bool = false

# ─── Per-category flags ────────────────────────────────────────────────────────
## Moita: reveal, accept, attach, save/restore bush state, rehide, +1 frame log.
var bush: bool = false

## Animal state: save, restore, move between segments, clear_active, replacement, extract.
var animal_state: bool = false

## Animal creation: check_missing, create_missing, find_in_bush, rename_fix.
var animal_create: bool = false

## Drag & high-level input: drag start/end, bounce, click/hold, bush_drop check.
var drag: bool = false

## Area input callbacks (verbose): animal_area_input, bush_area_input, press state.
var input: bool = false

## Plane: sync_to_plane, plane_change, reparent_to_plane.
var plane: bool = false

## Gravity: fall start, cancel, land.
var gravity: bool = false

## Infinite scroller: segment create and recycle.
var scroller: bool = false

## Hole (buraco): accept/reject check, animal vs allowed list.
var hole: bool = false

## Sun/Moon: icon creation (size, pivot), position computation (viewport, cam, skyline), place_icons.
var sun_moon: bool = false

## FSM do animal: transition_to, _enter/_exit_state, idle_visual (awake/sleep).
var animal_fsm: bool = false

## Água/submerso: detecção de trigger, overlap, decisões de transição e contexto posicional.
var water: bool = false

## Troca de sprite: seleção/aplicação de textura (inclui submerso).
var sprite: bool = false

## Nuvens/parallax: spawn, reset, wrap, direção, bounds, camada e skyline.
var clouds: bool = false

## Overlay/input de debug: rastreia o caminho da tecla F1 no pipeline de input.
var debug_input: bool = false

# ─── Helpers ───────────────────────────────────────────────────────────────────

## Enable all individual categories (and master switch).
func enable_all() -> void:
	enabled = true
	bush = true
	animal_state = true
	animal_create = true
	drag = true
	input = true
	plane = true
	gravity = true
	scroller = true
	hole = true
	sun_moon = true
	animal_fsm = true
	water = true
	sprite = true
	clouds = true
	debug_input = true

## Disable all individual categories (master switch stays true).
func disable_all() -> void:
	bush = false
	animal_state = false
	animal_create = false
	drag = false
	input = false
	plane = false
	gravity = false
	scroller = false
	hole = false
	sun_moon = false
	animal_fsm = false
	water = false
	sprite = false
	clouds = false
	debug_input = false

## Get raw flag value for a category by name (for UI display — ignores master switch).
func get_category(category: String) -> bool:
	match category:
		"bush": return bush
		"animal_state": return animal_state
		"animal_create": return animal_create
		"drag": return drag
		"input": return input
		"plane": return plane
		"gravity": return gravity
		"scroller": return scroller
		"hole": return hole
		"sun_moon": return sun_moon
		"animal_fsm": return animal_fsm
		"water": return water
		"sprite": return sprite
		"clouds": return clouds
		"debug_input": return debug_input
	return false

## Set a category flag by name.
func set_category(category: String, value: bool) -> void:
	match category:
		"bush": bush = value
		"animal_state": animal_state = value
		"animal_create": animal_create = value
		"drag": drag = value
		"input": input = value
		"plane": plane = value
		"gravity": gravity = value
		"scroller": scroller = value
		"hole": hole = value
		"sun_moon": sun_moon = value
		"animal_fsm": animal_fsm = value
		"water": water = value
		"sprite": sprite = value
		"clouds": clouds = value
		"debug_input": debug_input = value
