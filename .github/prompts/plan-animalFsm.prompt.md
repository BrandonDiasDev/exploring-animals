# Plan: Animal FSM (Idle / Fly / Fall + Day-Night Idle Visual)

## TL;DR
Formalize the implicit animal state currently scattered across `is_falling`, `can_fly` flags and ad-hoc tweens into a proper 3-state FSM (`IDLE`, `FLY`, `FALL`). Sleep is not a 4th state — it is IDLE+Night rendered with a different sprite. The FSM is the source of truth for all animal behavior; day/night changes the _visual_ of IDLE. A `fly_duration` config per animal auto-lands flyers after a timeout. State is always persisted as IDLE to prevent scroll-clone ghosts.

---

## Confirmed FSM

```
IDLE (awake sprite if day)
IDLE (sleep sprite if night) <-- same state, different visual
  |     |
  |     +--- FLY (can_fly=true only; auto-lands after fly_duration OR drag to ground)
  |
  +--------- FALL (can_fly=false only; tween to earth_y then land)
```

**Transitions:**
- IDLE → FLY : gravity triggered AND can_fly=true  (replaces old "skip gravity" path)
- FLY  → IDLE: fly_duration expires  OR  drag released near ground
- IDLE → FALL: gravity triggered AND can_fly=false
- FALL → IDLE: tween lands at background_earth_y
- Click on IDLE (night) = click on IDLE (day): same behavior — sound, zoom, camera

---

## Phase 0 — Pre-Work: Read & Baseline

**Steps:**
1. Read the full source of `animal.gd`, `world_manager.gd`, `world_state_validator.gd`, `debug_log_singleton.gd`, `debug_overlay.gd`, `test_world_scenarios.gd` verbatim to confirm all line-level details. *(Needed before editing anything.)*
2. Run existing tests (F8 in-game) to capture before-state pass/fail baseline.

---

## Phase 1 — FSM Core in `animal.gd`

**Steps (all in one file):**
1. Add `enum AnimalState { IDLE, FLY, FALL }` near top.
2. Replace `is_falling: bool` with `current_state: AnimalState = AnimalState.IDLE`.
3. Add exported vars: `idle_awake_texture: Texture2D`, `idle_sleep_texture: Texture2D`, `fly_duration: float = 5.0`.
4. Add `_fly_timer: float = 0.0` (tracks time in FLY state).
5. Add **single entry point**: `transition_to(new_state: AnimalState)`:
   - Guards: no transition if already in that state.
   - Calls `_exit_state(current_state)` then sets `current_state = new_state` then calls `_enter_state(new_state)`.
   - Logs via DebugLogger if `animal_fsm` category is on.
6. Implement `_exit_state(state)`:
   - FALL: kill `fall_tween` if alive.
   - FLY: reset `_fly_timer`.
   - IDLE: no-op.
7. Implement `_enter_state(state)`:
   - IDLE: call `_update_idle_visual()`; snap any running tween.
   - FLY: reset `_fly_timer = 0.0`; start fly animation on AnimationPlayer.
   - FALL: start fall tween (move to earth_y); on complete call `transition_to(IDLE)`.
8. Refactor `apply_gravity()`:
   - If `can_fly=true` → `transition_to(AnimalState.FLY)`.
   - Else → `transition_to(AnimalState.FALL)`.
9. Refactor `_cancel_fall()` → `_cancel_transition()`: works for both FALL (kill tween) and FLY (stop timer); calls `transition_to(IDLE)` if called while not already IDLE.
10. Update `_process(delta)`:
    - If current_state == FLY: increment `_fly_timer`; when `_fly_timer >= fly_duration` → `transition_to(IDLE)` (soft landing).
11. Add `_update_idle_visual()`: reads `WorldConfig.is_day`; if `idle_sleep_texture != null` and not day → set `Sprite2D.texture = idle_sleep_texture`; else if `idle_awake_texture != null` → `Sprite2D.texture = idle_awake_texture`.
12. Add `notify_day_night_changed(to_day: bool)`: if `current_state == IDLE` → `_update_idle_visual()`.
13. Update `reveal()` (from bush): ensure it calls `transition_to(IDLE)` (not raw `apply_gravity()`).
14. Update `end_drag()` / `handle_mouse_release()`: drop released mid-air for can_fly animal → does NOT call `apply_gravity()` directly; the existing check will reach `apply_gravity()` which now correctly transitions to FLY.

**Relevant files:** `scripts/animal.gd` — `apply_gravity()`, `_on_fall_finished()`, `_cancel_fall()`, `reveal()`, `_process()`, `end_drag()`

---

## Phase 2 — Day/Night Propagation to Animals in `world_manager.gd`

**Steps:**
1. In `_on_day_night_transition_started(to_day, duration)`: after propagating to segments, call new helper `_notify_all_animals_day_night(to_day)`.
2. `_notify_all_animals_day_night(to_day)`: iterate `animals_state`, for each key ending in `_active_node` that is a valid living node, cast to Animal and call `animal.notify_day_night_changed(to_day)`.
3. In `save_animal_state(animal)` and `save_animal_state_for_recycle(animal)`: add `"state": "IDLE"` to saved dict (always normalize to IDLE at save time). If animal.current_state != IDLE, call `animal.transition_to(AnimalState.IDLE)` BEFORE saving so the position is at ground.
4. In `restore_animal_state(animal)`: set `animal.current_state = AnimalState.IDLE` after restoring (always restored as IDLE).
5. In `create_animal_in_segment()`: after instantiation, confirm animal starts in IDLE.

**Relevant files:** `scripts/world_manager.gd` — `_on_day_night_transition_started`, `save_animal_state`, `save_animal_state_for_recycle`, `restore_animal_state`, `create_animal_in_segment`

---

## Phase 3 — State Normalization in `infinite_scroller.gd`

**Steps:**
1. In `recycle_segment(index, new_x)`: before calling `save_animal_state_for_recycle()` for each animal, if animal is in FLY or FALL state → force-snap to earth Y and `transition_to(IDLE)`. This prevents ghost animals appearing mid-air on segment recreation.
2. (*Parallel with Phase 3, no dependency*) In `find_animals_recursive()`: verify it doesn't need to exclude animals in FLY state — confirm it already skips `managed_by_bush`. No change likely needed.

**Relevant files:** `scripts/infinite_scroller.gd` — `recycle_segment`, `find_animals_recursive`

---

## Phase 4 — Bush Interaction Safety

**Steps:**
1. In `bush.gd` `try_accept_animal(dropped_animal)`: before `_accept_animal()`, check `dropped_animal.current_state != AnimalState.IDLE` → force `transition_to(IDLE)` first. Animals must be IDLE before entering a bush.
2. In `_accept_animal(animal)`: no change needed if Phase 4.1 guarantees IDLE entry.
3. In `reveal_animal()`: at the moment of emitting `animal_revealed`, animal is already at IDLE (popping out); no forced transition needed here as world_manager's `_on_bush_animal_revealed` calls `apply_gravity()` which now correctly fires FSM.

**Relevant files:** `scenes/components` all bush scenes, `scripts/bush.gd` — `try_accept_animal`, `_accept_animal`, `reveal_animal`

---

## Phase 5 — Debug Infrastructure

**Steps (parallel with Phase 1–4):**
1. In `debug_log_singleton.gd`: add `var animal_fsm: bool = false` alongside the other category flags.
2. In `debug_overlay.gd`: add a checkbox for `animal_fsm` in `_build_ui()`.
3. Standard FSM log pattern in `animal.gd` `transition_to()`:
   ```
   if DebugLogger.animal_fsm:
       print("[FSM] %s: %s → %s" % [animal_name, AnimalState.keys()[old_state], AnimalState.keys()[new_state]])
   ```
4. Day/night visual log:
   ```
   if DebugLogger.animal_fsm:
       print("[FSM] %s: idle_visual = %s" % [animal_name, "sleep" if !WorldConfig.is_day else "awake"])
   ```

**Relevant files:** `scripts/debug_log_singleton.gd`, `scripts/debug_overlay.gd`, `scripts/animal.gd`

---

## Phase 6 — Validator Invariants

**Steps:**
1. In `world_state_validator.gd`, add 3 new invariant checks after existing 11:
   - **Check 12 — Hidden animals must be IDLE**: for each key with `is_hidden=true`, find active_node; `node.current_state` must equal IDLE. Error = `push_error`.
   - **Check 13 — No FLY for ground animals**: for each active animal with `can_fly=false`, state must not be FLY. Error.
   - **Check 14 — State enum consistency**: `current_state` must be a valid `AnimalState` value (0, 1, 2). Error if garbage.
2. Keep total silent suppression contract (skips if not `OS.is_debug_build()`).

**Relevant files:** `scripts/world_state_validator.gd`

---

## Phase 7 — Test Group G13

**Steps:**
1. In `test_world_scenarios.gd`, add group **G13 — FSM Invariants** (5 tests):
   - `_g13a_idle_on_restore()`: save a flying-capable animal mid-FLY in state dict as IDLE; restore; verify state is IDLE.
   - `_g13b_no_fly_for_ground_animal()`: force `apply_gravity()` on a capivara (can_fly=false); verify state is FALL not FLY.
   - `_g13c_fly_duration_lands()`: create tucano with `fly_duration=0.01`; trigger FLY; await 1 frame; verify state is IDLE.
   - `_g13d_hidden_animal_is_idle()`: put animal in bush; verify `current_state == IDLE`.
   - `_g13e_day_night_idle_visual()`: set `idle_sleep_texture` on dummy animal; switch to night; verify Sprite2D.texture changed.
2. Update test count header comments.

**Relevant files:** `tests/test_world_scenarios.gd`

---

## Phase 8 — Scene & Export Var Plumbing

**Steps:**
1. `scenes/components/animal.tscn` (base): exported vars `idle_awake_texture` and `idle_sleep_texture` will auto-appear in Inspector once added to `animal.gd` — no tscn edit needed.
2. Individual animal scenes (capivara, tucano, coruja, onca, pato, tamandua, tatu, ema, siriema, uruatu): set `fly_duration` where `can_fly=true` (tucano, coruja, uruatu). Sleeping textures are **null / placeholder for now** — architecture is ready for assets.
3. `world_config.gd`: optionally add `default_fly_duration: float = 5.0` as a fallback.

**Relevant files:** All `.tscn` files in `scenes/components/`, `scripts/world_config.gd`

---

## Scrolling/Clone Guard Summary (explicitly mapped)

| Risk | Source | Mitigation |
|------|--------|------------|
| FLY animal's segment recycles mid-flight | `infinite_scroller.recycle_segment` | Force IDLE + snap to earth_y before save (Phase 3.1) |
| Restored animal shows mid-air texture | `world_manager.restore_animal_state` | Always restore as IDLE; `_update_idle_visual()` picks correct sprite (Phase 2.4) |
| Day changes while many animals restored across segments | `world_manager._on_day_night_transition_started` | `_notify_all_animals_day_night()` iterates all active_nodes (Phase 2.1) |
| FLY timer survives segment recycle (accumulates) | `animal._fly_timer` | Timer is in-memory; new instance starts at 0; no persistence needed |
| Bush hides flying animal (corrupt state) | `bush.try_accept_animal` | Force IDLE before accept (Phase 4.1) |
| Orphan state entries (fly state saved) | `world_manager.save_*` | Always save state="IDLE"; validator Check 14 catches garbage (Phase 2.3, Phase 6.3) |

---

## Relevant files (full list)

- `scripts/animal.gd` — **Primary**: FSM enum, transition_to, idle visual, fly timer
- `scripts/world_manager.gd` — Day/night propagation to animals, save normalization
- `scripts/infinite_scroller.gd` — Force IDLE before recycle
- `scripts/bush.gd` — Force IDLE before accept
- `scripts/debug_log_singleton.gd` — Add `animal_fsm` category
- `scripts/debug_overlay.gd` — Add FSM checkbox
- `scripts/world_state_validator.gd` — 3 new FSM invariants
- `scripts/world_config.gd` — Optional `default_fly_duration`
- `tests/test_world_scenarios.gd` — G13 test group (5 tests)
- `scenes/components/*.tscn` — fly_duration on can_fly animals

---

## Verification

1. G1–G12 tests still pass (no regressions): run F8.
2. G13 all 5 new tests pass.
3. Enable `animal_fsm` log via F1 overlay; drag and release a tucano — `[FSM] Tucano: IDLE → FLY` logged; after `fly_duration` → `[FSM] Tucano: FLY → IDLE` logged.
4. Switch to Night via sun click → all IDLE animals call `_update_idle_visual()` (logs `[FSM] X: idle_visual = sleep`).
5. Scroll camera so current segment recycles while tucano is in FLY → no mid-air ghost on new segment; animal appears at earth_y in IDLE.
6. Drag capivara (can_fly=false) to air, release → FALL state logged; lands → IDLE.
7. Drop tucano onto bush while in FLY → state forced to IDLE first; bush accepts cleanly.

---

## Decisions

- **Sleep = IDLE + night visual** (no 4th state). Simplifies FSM and state persistence.
- **Always save as IDLE**: transient states (FLY, FALL) are never persisted; segment recycle always snaps to ground.
- **fly_duration is per-animal** exported float; `WorldConfig.default_fly_duration` provides fallback.
- **Sleeping sprites**: architecture ready; textures are null placeholders until assets are created.
- **Drag modifier is orthogonal to FSM**: drag is not a state; when drag releases, it calls `apply_gravity()` which dispatches to FLY or FALL depending on can_fly.
- **FLY → FALL is not a valid transition**: flying animals transition FLY → IDLE directly (soft landing).

## Excluded scope
- Actual sleeping sprite assets (placeholder null for now).
- Flying path/trajectory animation (out of scope for this iteration; FLY state just suppresses gravity for now; animation TBD).
- `plane2` + FLY interaction (birds in plane2 can still fly; plane logic unchanged).
