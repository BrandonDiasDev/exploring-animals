## BaseEntity.gd
## Base class for all interactive entities in the game (animals, objects, etc.)
##
## This class provides common functionality for entities that can be:
## - Discovered and interacted with by the player
## - Display information when selected
## - Animate and respond to player actions
##
## All game entities should extend this class to inherit shared behavior.

extends Node2D

class_name BaseEntity

## The display name of this entity (e.g., "Elephant", "Tree")
@export var entity_name: String = "Entity"

## A brief description shown when the entity is examined
@export_multiline var description: String = "An interesting discovery!"

## Whether this entity has been discovered by the player
var is_discovered: bool = false

## Whether this entity can currently be interacted with
var is_interactable: bool = true


## Called when the node enters the scene tree for the first time.
## Override this in child classes to set up entity-specific initialization.
func _ready() -> void:
	pass


## Called every frame. 'delta' is the elapsed time since the previous frame.
## Override this in child classes for entity-specific behavior.
func _process(delta: float) -> void:
	pass


## Called when the player interacts with this entity.
## Override this to define what happens when the entity is clicked/touched.
func interact() -> void:
	if not is_interactable:
		return
	
	is_discovered = true
	_on_interact()


## Virtual method to be overridden by child classes.
## Define custom interaction behavior here.
func _on_interact() -> void:
	pass


## Called when the entity becomes visible/discovered to the player.
## Override this to add discovery animations or effects.
func discover() -> void:
	is_discovered = true
	_on_discover()


## Virtual method to be overridden by child classes.
## Define custom discovery behavior here.
func _on_discover() -> void:
	pass


## Returns the current state of the entity for saving/loading.
## Override this to include entity-specific state data.
func get_state() -> Dictionary:
	return {
		"entity_name": entity_name,
		"is_discovered": is_discovered,
		"position": position
	}


## Restores the entity state from a saved dictionary.
## Override this to restore entity-specific state data.
func set_state(state: Dictionary) -> void:
	if state.has("entity_name"):
		entity_name = state["entity_name"]
	if state.has("is_discovered"):
		is_discovered = state["is_discovered"]
	if state.has("position"):
		position = state["position"]
