# Architecture Documentation
# Exploring Animals

**Version**: 0.1.0  
**Last Updated**: January 2026  
**Engine**: Godot 4.5

---

## 1. Overview

This document outlines the technical architecture of the Exploring Animals game, including project structure, design patterns, and core systems.

### 1.1 Design Principles
- **Simplicity**: Keep systems simple and easy to understand
- **Modularity**: Components should be reusable and loosely coupled
- **Extensibility**: Easy to add new animals, environments, and features
- **Performance**: Maintain 60 FPS on target hardware
- **Maintainability**: Clear code structure with comprehensive documentation

---

## 2. Project Structure

### 2.1 Directory Organization

```
exploring-animals/
│
├── assets/                     # All game assets
│   ├── sprites/                # 2D graphics and animations
│   │   ├── animals/            # Animal sprites
│   │   ├── environments/       # Background and terrain
│   │   └── ui/                 # UI elements
│   ├── sounds/                 # Audio files
│   │   ├── music/              # Background music
│   │   ├── sfx/                # Sound effects
│   │   └── animals/            # Animal sounds
│   └── fonts/                  # Custom fonts
│
├── scenes/                     # Godot scene files (.tscn)
│   ├── World.tscn              # Main world scene
│   ├── environments/           # Individual environment scenes
│   ├── entities/               # Reusable entity scenes
│   │   └── animals/            # Animal scenes
│   └── ui/                     # UI scenes
│       ├── MainMenu.tscn       # (planned)
│       └── AnimalJournal.tscn  # (planned)
│
├── scripts/                    # GDScript files (.gd)
│   ├── BaseEntity.gd           # Base class for all entities
│   ├── entities/               # Entity-specific scripts
│   ├── managers/               # Game system managers
│   │   ├── GameManager.gd      # (planned) Main game controller
│   │   └── SaveManager.gd      # (planned) Save/load system
│   ├── ui/                     # UI scripts
│   └── utils/                  # Utility scripts and helpers
│
├── docs/                       # Documentation
│   ├── GDD.md                  # Game Design Document
│   ├── ARCHITECTURE.md         # This file
│   └── CODING_GUIDELINES.md    # Code standards
│
└── project.godot               # Godot project configuration
```

### 2.2 Naming Conventions
- **Scenes**: PascalCase (e.g., `World.tscn`, `AnimalJournal.tscn`)
- **Scripts**: PascalCase (e.g., `BaseEntity.gd`, `GameManager.gd`)
- **Assets**: snake_case (e.g., `elephant_sprite.png`, `discovery_sound.ogg`)
- **Directories**: snake_case (e.g., `animals/`, `sound_effects/`)

---

## 3. Core Systems

### 3.1 Entity System

#### 3.1.1 BaseEntity Class
The `BaseEntity` class serves as the foundation for all interactive game objects.

**Purpose**:
- Provide common functionality for all entities
- Standardize interaction patterns
- Enable polymorphic handling of different entity types

**Key Features**:
- Discovery state management
- Interaction handling
- State serialization for save/load
- Extensible through virtual methods

**Inheritance Hierarchy** (Planned):
```
Node2D
  └── BaseEntity
        ├── Animal (base class for all animals)
        │     ├── Elephant
        │     ├── Lion
        │     └── [other animals]
        └── InteractiveObject (for non-animal interactables)
```

#### 3.1.2 Entity Lifecycle
1. **Initialization** (`_ready()`): Set up entity properties
2. **Update** (`_process(delta)`): Handle per-frame logic
3. **Interaction** (`interact()`): Respond to player actions
4. **Discovery** (`discover()`): Handle discovery events
5. **Serialization** (`get_state()`/`set_state()`): Save/load state

### 3.2 Scene Management (Planned)

#### 3.2.1 World Scene
The main `World.tscn` serves as the root scene and container for environments.

**Components**:
- Camera2D for viewport control
- Environment containers
- UI layer
- Background music player

#### 3.2.2 Environment Scenes
Each environment (Grasslands, Forest, Ocean, etc.) is a separate scene.

**Benefits**:
- Load/unload environments as needed
- Independent development of environments
- Easier performance optimization
- Reusable environment templates

### 3.3 Game Manager System (Planned)

#### 3.3.1 GameManager
Singleton autoload script that manages global game state.

**Responsibilities**:
- Track overall game progress
- Coordinate between systems
- Handle scene transitions
- Manage game settings

#### 3.3.2 SaveManager
Handles persistence of game data.

**Responsibilities**:
- Save/load game state
- Manage multiple save slots
- Handle save file versioning
- Validate save data integrity

### 3.4 UI System (Planned)

#### 3.4.1 UI Structure
- **MainMenu**: Entry point, load game, settings
- **HUD**: In-game UI (discovery counter, buttons)
- **AnimalJournal**: Collection view of discovered animals
- **InfoPanel**: Displays animal information

#### 3.4.2 UI Communication
- Signals for UI events
- Observer pattern for state updates
- Centralized UI manager for coordination

---

## 4. Design Patterns

### 4.1 Patterns in Use

#### 4.1.1 Singleton Pattern
Used for manager classes that need global access:
- `GameManager`
- `SaveManager`
- `AudioManager` (planned)

**Implementation**: Godot's autoload system

#### 4.1.2 Observer Pattern (Signals)
Used for event-driven communication:
- Entity discovery events
- UI updates
- State changes

**Implementation**: Godot's built-in signal system

#### 4.1.3 Template Method Pattern
Used in `BaseEntity` for extensible behavior:
- Virtual methods (`_on_interact()`, `_on_discover()`)
- Child classes override specific behavior
- Base class handles common logic

#### 4.1.4 State Pattern (Planned)
For complex entity behaviors:
- Animal states (idle, alert, interacting)
- Player states (moving, interacting)
- Game states (menu, playing, paused)

### 4.2 Anti-Patterns to Avoid
- **Tight Coupling**: Use signals and interfaces instead
- **God Objects**: Keep classes focused and single-purpose
- **Premature Optimization**: Profile before optimizing
- **Deep Inheritance**: Prefer composition over deep hierarchies

---

## 5. Data Management

### 5.1 Entity Data

#### 5.1.1 Static Data
Animal and entity definitions stored as resources or JSON:
```gdscript
{
  "id": "elephant",
  "name": "Elephant",
  "description": "A large mammal with a long trunk...",
  "facts": ["Elephants can weigh up to 6 tons", "..."],
  "habitat": "Grasslands",
  "sound": "res://assets/sounds/animals/elephant.ogg"
}
```

#### 5.1.2 Runtime Data
Player progress and entity states:
```gdscript
{
  "discovered_animals": ["elephant", "lion", "zebra"],
  "entities": {
    "elephant_1": {
      "position": Vector2(100, 200),
      "is_discovered": true
    }
  }
}
```

### 5.2 Save System Architecture (Planned)

#### 5.2.1 Save File Format
- JSON format for human readability
- Versioned for backward compatibility
- Compressed for smaller file size

#### 5.2.2 Save Locations
- User data directory (`user://`)
- Multiple save slots supported
- Auto-save functionality

---

## 6. Performance Considerations

### 6.1 Optimization Strategies

#### 6.1.1 Scene Management
- Lazy loading of resources
- Unload inactive environments
- Object pooling for frequently created objects

#### 6.1.2 Rendering
- Texture atlases to reduce draw calls
- Cull objects outside camera view
- Use CanvasLayer for UI separation

#### 6.1.3 Memory Management
- Preload commonly used resources
- Free unused resources
- Monitor memory usage in development

### 6.2 Target Performance
- **Frame Rate**: 60 FPS stable
- **Load Time**: < 5 seconds to main menu
- **Memory**: < 500 MB RAM usage
- **Storage**: < 200 MB total

---

## 7. Testing Strategy

### 7.1 Testing Approach (Planned)
- **Unit Tests**: Core logic and utility functions
- **Integration Tests**: System interactions
- **Playtesting**: User experience validation
- **Performance Tests**: Frame rate and load times

### 7.2 GDScript Testing
- Use Godot's GUT (Godot Unit Test) framework
- Test critical paths and edge cases
- Automate regression testing

---

## 8. Extensibility

### 8.1 Adding New Animals

To add a new animal:
1. Create animal sprite assets
2. Create a new scene extending `BaseEntity`
3. Attach animal-specific script inheriting from `BaseEntity`
4. Add animal data to the animal database
5. Place in appropriate environment scene
6. Add to animal journal UI

### 8.2 Adding New Environments

To add a new environment:
1. Create environment scene
2. Design and implement background and terrain
3. Place animal entities
4. Configure camera boundaries
5. Add environment-specific audio
6. Link from World scene

### 8.3 Adding New Features

Follow these steps:
1. Design feature in GDD
2. Update architecture if needed
3. Implement with minimal coupling
4. Add comprehensive comments
5. Test thoroughly
6. Document in appropriate docs

---

## 9. Dependencies

### 9.1 Godot Version
- **Required**: Godot 4.5 or later
- **Rendering**: Forward+ renderer
- **Features**: GDScript 2.0

### 9.2 External Assets (Planned)
- Consider open-source asset packs
- Ensure child-friendly licenses
- Document attribution

### 9.3 Plugins (None Currently)
- Keep dependencies minimal
- Evaluate thoroughly before adding

---

## 10. Build & Deployment

### 10.1 Export Presets (Planned)
- **Windows**: 64-bit executable
- **macOS**: Universal binary
- **Linux**: 64-bit executable

### 10.2 Distribution
- Direct download from website
- Potential future: Steam, itch.io
- Consider web export for accessibility

---

## 11. Version Control

### 11.1 Git Strategy
- **main**: Stable, release-ready code
- **develop**: Integration branch
- **feature/***: Individual features
- **hotfix/***: Critical fixes

### 11.2 Godot-Specific Ignore
- `.godot/` directory (build cache)
- `.import/` directory (import cache)
- `*.translation` files (can be regenerated)
- Export builds and templates

---

## 12. Future Architecture Considerations

### 12.1 Scalability
- Support for more complex animations
- Advanced particle effects
- Dynamic weather systems
- Day/night cycle

### 12.2 Localization
- String externalization
- Translation system integration
- Cultural adaptation of content

### 12.3 Accessibility
- Screen reader support
- Colorblind modes
- Adjustable UI scaling
- Input remapping

---

**Document Status**: Living document, will be updated as architecture evolves.
