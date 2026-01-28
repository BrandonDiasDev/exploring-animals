# Coding Guidelines
# Exploring Animals

**Version**: 0.1.0  
**Last Updated**: January 2026

---

## 1. Overview

This document establishes coding standards and best practices for the Exploring Animals project. Following these guidelines ensures code consistency, maintainability, and quality across the codebase.

### 1.1 Goals
- **Readability**: Code should be easy to read and understand
- **Consistency**: Uniform style across the entire project
- **Maintainability**: Easy to modify and extend
- **Quality**: Minimize bugs through good practices
- **Collaboration**: Enable smooth teamwork

---

## 2. GDScript Style Guide

### 2.1 Naming Conventions

#### 2.1.1 Files
- **Scripts**: `PascalCase.gd` (e.g., `BaseEntity.gd`, `GameManager.gd`)
- **Scenes**: `PascalCase.tscn` (e.g., `World.tscn`, `MainMenu.tscn`)
- **Resources**: `snake_case` with descriptive names (e.g., `elephant_sprite.png`)

#### 2.1.2 Classes
```gdscript
# Use PascalCase for class names
class_name BaseEntity
class_name GameManager
class_name AnimalData
```

#### 2.1.3 Variables
```gdscript
# Use snake_case for variables
var entity_name: String
var is_discovered: bool
var max_health: int

# Use SCREAMING_SNAKE_CASE for constants
const MAX_ANIMALS: int = 50
const DEFAULT_SPEED: float = 100.0
const SAVE_FILE_PATH: String = "user://save_game.json"
```

#### 2.1.4 Functions
```gdscript
# Use snake_case for function names
func interact() -> void:
	pass

func get_state() -> Dictionary:
	return {}

func calculate_distance(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to)
```

#### 2.1.5 Signals
```gdscript
# Use snake_case with descriptive names
signal animal_discovered(animal_name: String)
signal interaction_started
signal game_state_changed(new_state: String)
```

#### 2.1.6 Private/Internal Members
```gdscript
# Prefix with underscore for private/internal use
var _internal_state: int = 0
func _calculate_internal_value() -> float:
	return 0.0
```

### 2.2 Code Formatting

#### 2.2.1 Indentation
- Use **tabs** (Godot default)
- One indentation level = one tab

#### 2.2.2 Line Length
- Aim for **100 characters** maximum
- Break long lines for readability:
```gdscript
# Good
var long_calculation: float = (
	some_value * another_value
	+ third_value - fourth_value
)

# Avoid
var long_calculation: float = some_value * another_value + third_value - fourth_value
```

#### 2.2.3 Spacing
```gdscript
# Space after colons in type hints
var health: int = 100

# Space around operators
var result = a + b * c

# No space for function calls
my_function(parameter1, parameter2)

# Space after commas
var array = [1, 2, 3, 4]
```

#### 2.2.4 Blank Lines
```gdscript
# Two blank lines between functions
func first_function() -> void:
	pass


func second_function() -> void:
	pass


# One blank line within functions for logical separation
func complex_function() -> void:
	var setup_value = 10
	
	if setup_value > 5:
		do_something()
	
	return
```

### 2.3 Type Hints

#### 2.3.1 Always Use Type Hints
```gdscript
# Good
var entity_name: String = "Entity"
var health: int = 100
var is_alive: bool = true

func calculate_damage(base: int, multiplier: float) -> int:
	return int(base * multiplier)

# Avoid
var entity_name = "Entity"
var health = 100
func calculate_damage(base, multiplier):
	return base * multiplier
```

#### 2.3.2 Return Types
```gdscript
# Always specify return type
func get_name() -> String:
	return entity_name

func process_data() -> void:
	# void for functions with no return value
	pass

func get_optional_value() -> Variant:
	# Use Variant when return type can vary
	return null
```

---

## 3. Code Structure

### 3.1 Script Organization

#### 3.1.1 Recommended Order
```gdscript
# 1. Tool directive (if needed)
@tool

# 2. Class name
class_name EntityName

# 3. Extends clause
extends Node2D

# 4. Documentation comments
## Brief description of the class
##
## Detailed explanation if needed

# 5. Signals
signal entity_changed

# 6. Enums
enum State { IDLE, MOVING, INTERACTING }

# 7. Constants
const MAX_SPEED: float = 200.0

# 8. Exported variables
@export var entity_name: String = "Default"
@export_range(0, 100) var health: int = 100

# 9. Public variables
var current_state: State = State.IDLE

# 10. Private variables (prefixed with _)
var _internal_timer: float = 0.0

# 11. Onready variables
@onready var sprite: Sprite2D = $Sprite2D

# 12. Built-in virtual functions (_init, _ready, _process, etc.)
func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass

# 13. Public functions
func interact() -> void:
	pass

# 14. Private functions
func _update_internal_state() -> void:
	pass

# 15. Signal callbacks
func _on_timer_timeout() -> void:
	pass
```

### 3.2 Comments and Documentation

#### 3.2.1 Documentation Comments
```gdscript
## Brief one-line summary of the class
##
## More detailed explanation spanning multiple lines
## if needed to explain complex behavior
class_name WellDocumented

## Brief description of the function
##
## @param parameter_name: Description of the parameter
## @return: Description of what is returned
func documented_function(parameter_name: String) -> int:
	return 0
```

#### 3.2.2 Inline Comments
```gdscript
# Use inline comments to explain WHY, not WHAT
func complex_calculation() -> float:
	# Apply inverse square law for distance attenuation
	var distance_factor = 1.0 / (distance * distance)
	
	return base_value * distance_factor
```

#### 3.2.3 TODO Comments
```gdscript
# TODO: Add animation support
# FIXME: This breaks with negative values
# HACK: Temporary workaround until Godot fixes bug
# NOTE: This must be called after _ready()
```

### 3.3 Functions

#### 3.3.1 Function Length
- Keep functions **short and focused** (ideally < 30 lines)
- One function should do **one thing**
- Extract complex logic into helper functions

```gdscript
# Good - focused, single responsibility
func take_damage(amount: int) -> void:
	health -= amount
	_check_if_defeated()
	emit_signal("health_changed", health)

func _check_if_defeated() -> void:
	if health <= 0:
		_handle_defeat()

# Avoid - doing too much in one function
func take_damage_and_check_defeat_and_update_ui(amount: int) -> void:
	health -= amount
	if health <= 0:
		is_alive = false
		play_defeat_animation()
		update_game_state()
		notify_game_manager()
	update_health_bar()
	play_damage_sound()
```

#### 3.3.2 Function Parameters
- Limit to **4 parameters maximum**
- Use dictionaries or custom classes for complex parameter sets

```gdscript
# Good
func initialize(config: Dictionary) -> void:
	entity_name = config.get("name", "Default")
	health = config.get("health", 100)
	speed = config.get("speed", 50.0)

# Avoid
func initialize(name: String, health: int, speed: float, damage: int, defense: int) -> void:
	# Too many parameters
	pass
```

#### 3.3.3 Return Early
```gdscript
# Good - early return for guard clauses
func interact() -> void:
	if not is_interactable:
		return
	
	if is_discovered:
		return
	
	_perform_interaction()

# Avoid - deeply nested conditions
func interact() -> void:
	if is_interactable:
		if not is_discovered:
			_perform_interaction()
```

---

## 4. Best Practices

### 4.1 Godot-Specific

#### 4.1.1 Node References
```gdscript
# Use @onready for node references
@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer

# Alternative: Get nodes in _ready() if needed
var sprite: Sprite2D

func _ready() -> void:
	sprite = $Sprite2D
```

#### 4.1.2 Signals
```gdscript
# Connect signals in code for clarity
func _ready() -> void:
	button.pressed.connect(_on_button_pressed)
	timer.timeout.connect(_on_timer_timeout)

# Name signal callbacks with _on_ prefix
func _on_button_pressed() -> void:
	pass
```

#### 4.1.3 Node Lifecycle
```gdscript
# Override built-in functions correctly
func _ready() -> void:
	# Initialize here
	pass

func _process(delta: float) -> void:
	# Per-frame updates
	pass

func _physics_process(delta: float) -> void:
	# Physics updates
	pass
```

### 4.2 Performance

#### 4.2.1 Cache Node References
```gdscript
# Good - cache in _ready()
var sprite: Sprite2D

func _ready() -> void:
	sprite = $Sprite2D

func _process(delta: float) -> void:
	sprite.modulate = Color.RED

# Avoid - getting node every frame
func _process(delta: float) -> void:
	$Sprite2D.modulate = Color.RED  # Slower
```

#### 4.2.2 Minimize Allocations
```gdscript
# Good - reuse objects
var temp_vector: Vector2 = Vector2.ZERO

func update_position(delta: float) -> void:
	temp_vector.x = velocity.x * delta
	temp_vector.y = velocity.y * delta
	position += temp_vector

# Avoid - creating new objects frequently
func update_position(delta: float) -> void:
	position += Vector2(velocity.x * delta, velocity.y * delta)
```

### 4.3 Error Handling

#### 4.3.1 Null Checks
```gdscript
# Check for null before using objects
func use_reference(obj: Node) -> void:
	if obj == null:
		push_error("Object is null")
		return
	
	obj.queue_free()
```

#### 4.3.2 Assertions
```gdscript
# Use assertions for debugging
func initialize(config: Dictionary) -> void:
	assert(config.has("name"), "Config must have 'name' key")
	assert(config.has("health"), "Config must have 'health' key")
	
	entity_name = config["name"]
	health = config["health"]
```

#### 4.3.3 Error Messages
```gdscript
# Use descriptive error messages
if file_path.is_empty():
	push_error("Cannot load file: path is empty")
	return

if not FileAccess.file_exists(file_path):
	push_error("File not found: " + file_path)
	return
```

---

## 5. Testing

### 5.1 Test Structure (Planned)
```gdscript
# Use GUT (Godot Unit Test) framework
extends GutTest

func test_entity_interaction():
	var entity = BaseEntity.new()
	entity.interact()
	assert_true(entity.is_discovered, "Entity should be discovered after interaction")

func test_entity_state_serialization():
	var entity = BaseEntity.new()
	entity.position = Vector2(100, 200)
	var state = entity.get_state()
	assert_eq(state["position"], Vector2(100, 200), "Position should be saved in state")
```

### 5.2 Testable Code
- Write small, focused functions
- Minimize dependencies
- Use dependency injection where appropriate
- Separate logic from presentation

---

## 6. Version Control

### 6.1 Commit Messages
```
# Format: type(scope): brief description

feat(animals): add elephant entity with sound effects
fix(ui): correct journal scroll behavior
docs(readme): update installation instructions
refactor(entities): simplify interaction system
test(save): add save manager unit tests
```

### 6.2 Commit Types
- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting)
- **refactor**: Code refactoring
- **test**: Adding or updating tests
- **chore**: Maintenance tasks

### 6.3 What to Commit
- **Do commit**: Source code, scenes, documentation, configs
- **Don't commit**: Build artifacts, `.godot/` folder, `.import/` folder, OS-specific files

---

## 7. Code Review Checklist

### 7.1 Before Submitting
- [ ] Code follows style guidelines
- [ ] All functions have type hints
- [ ] Complex logic is commented
- [ ] No debugging code left (print statements, commented code)
- [ ] Tests pass (when applicable)
- [ ] No new warnings in Godot editor

### 7.2 During Review
- [ ] Code is readable and understandable
- [ ] Logic is sound and correct
- [ ] Performance implications considered
- [ ] Edge cases handled
- [ ] Documentation is adequate

---

## 8. Child-Friendly Development

### 8.1 Content Guidelines
- Use **positive language** in all text
- Avoid violent or scary themes
- Use **bright, friendly colors**
- Design for **accessibility**

### 8.2 User Experience
- **Large touch targets** (min 44x44 pixels)
- **Clear feedback** for all interactions
- **No time pressure** or stress
- **Celebrate discoveries** with positive reinforcement

---

## 9. Resources and Tools

### 9.1 Recommended Tools
- **Godot Editor**: Latest stable 4.5+
- **Visual Studio Code**: With Godot Tools extension
- **Git**: For version control
- **GUT**: For unit testing

### 9.2 Learning Resources
- [Godot Documentation](https://docs.godotengine.org/)
- [GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [Godot Best Practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/)

---

## 10. Questions and Clarifications

If you're unsure about any guideline:
1. Check existing code for patterns
2. Consult the Godot documentation
3. Ask in team discussions
4. When in doubt, prioritize **readability**

---

**Document Status**: Living document, guidelines may evolve with project needs.
