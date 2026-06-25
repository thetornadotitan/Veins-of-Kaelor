# Plan: Deterministic Game Initialization Pipeline

## Problem

When a player hosts or joins, three systems race each other with no coordination:

1. **Map generation/loading** — progressive, frame-budgeted, depends on player position
2. **Player spawning** — immediate in `_ready()`, but placement needs terrain height
3. **Multiplayer sync** — signal-driven, fires at unpredictable times relative to scene load

Current anti-patterns:
- `WorldManager._ready()` spawns the player **before terrain exists** (`chunk_manager.gd:21-27` loads meta only, no chunks)
- `_place_player_on_terrain_deferred()` (`world_manager.gd:55`) uses a polling loop (up to 3s) waiting for height data
- `PlayerController._ready()` (`player_controller.gd:23`) and `CameraController._ready()` (`camera_controller.gd:16`) each `await process_frame` creating a 3-frame minimum init delay
- `main_menu.gd:39` uses a hardcoded 1-second timer before scene change — no actual readiness check
- `GhostManager` (`ghost_manager.gd:10`) sets `PROCESS_MODE_DISABLED` in `_ready()` and nothing ever calls `start()` — dead code
- `initial_sync` RPC (`world_manager.gd:75`) fires before remote player nodes may exist
- `ChunkManager._get_player_world_position()` (`chunk_manager.gd:247`) returns `Vector3.ZERO` when no player exists yet, creating a chicken-and-egg dependency (chunks need player position, player needs chunks for terrain height)

## Design Principles

- **DRY**: Eliminate the scattered `await process_frame` / `call_deferred` / polling-patterns — one pipeline owns ordering
- **KISS**: A simple linear state machine. No event soup. Each phase completes before the next starts.
- **Clean Code**: Systems don't reach across responsibilities. Map loading doesn't query "players" group. Sync logic isn't embedded in the player entity.
- **Data-Driven**: Phase configuration (what loads, spawn point, loading thresholds) comes from data, not hardcoded constants.

---

## Architecture: GameStateController

A single **autoload** (`GameStateController`) that owns the initialization pipeline and exposes a deterministic API for transition. Every other system becomes a passive participant that responds to state changes rather than driving them.

### Why an autoload?

Current problem: `WorldManager` (a scene child) tries to orchestrate spawn + multiplayer wiring, but it doesn't control when the scene loads, when chunks are ready, or when WebRTC connects. An autoload **exists across scene transitions** and can coordinate the full lifecycle: menu → loading → world → gameplay.

### State Machine

```
MENU → CONNECTING → LOADING → WORLD_READY → PLAYING
```

| State | What happens | Trigger to advance |
|---|---|---|
| `MENU` | Main menu visible, no world loaded | User clicks Host or Join |
| `CONNECTING` | Signaling + WebRTC setup, no scene change | `connection_succeeded` from MultiplayerManager |
| `LOADING` | World scene loaded **behind a loading screen**. Chunks generate around spawn point. No player exists yet. No physics runs. | All required chunks ready + terrain height queryable at spawn |
| `WORLD_READY` | Players spawned at known-good positions. Authority applied. Sync enabled. Short hold (~0.5s) for WebRTC peers to confirm. | All local players initialized + all known peers have player nodes |
| `PLAYING` | Loading screen dismissed. Input enabled. Physics and sync running. | Automatic from WORLD_READY |

### Key rule: Each phase is a hard gate

No phase starts until the previous one **reports completion**. No polling loops, no `await create_timer(0.1)` spinning. Systems expose `is_ready() -> bool` and the controller checks them each frame.

---

## Phase-by-Phase Detail

### Phase 1: CONNECTING (replaces current menu→world timer)

**Current flow:**
```
connection_succeeded → 1s timer → change_scene_to_file(world.tscn)
```
This timer is meaningless — it doesn't guarantee anything about WebRTC state.

**New flow:**
```
connection_succeeded → GameStateController enters CONNECTING
                    → MultiplayerManager ensures WebRTC mesh is active
                    → For host: immediately advance (host has no peers to wait for)
                    → For client: wait until at least one WebRTC peer is connected
                    → Advance to LOADING
```

The menu stays visible during CONNECTING. No scene change yet.

**MultiplayerManager changes:**
- Add `is_webrtc_ready() -> bool` that returns true when `multiplayer.multiplayer_peer` is set AND at least one peer is connected (or is host with no peers yet)
- `connection_succeeded` no longer triggers scene change — it signals `GameStateController`

### Phase 2: LOADING (replaces current "hope terrain loads" pattern)

**Current flow:**
```
world.tscn loads → ChunkManager._ready() → no chunks loaded
                 → WorldManager._ready() → spawn player immediately
                 → player falls through void
                 → _place_player_on_terrain polls for 3s waiting for height
```

**New flow:**
```
GameStateController changes to world.tscn (behind loading overlay)
→ ChunkManager._ready() loads meta as before
→ ChunkManager receives explicit spawn point (not from player position)
→ Chunks load until spawn-area radius is satisfied
→ GameStateController polls ChunkManager.is_spawn_area_ready()
→ Only then advance to WORLD_READY
```

**ChunkManager changes:**

Remove the dependency on player position for initial load. Instead:

```gdscript
var _spawn_point: Vector2i = Vector2i(0, 0)  # set by GameStateController before scene load
var _spawn_area_ready: bool = false

func is_spawn_area_ready() -> bool:
    return _spawn_area_ready

func _update_chunks() -> void:
    if not _spawn_area_ready:
        # Use spawn point as reference until player exists
        _player_chunk = _world_to_chunk(Vector3(
            float(_spawn_point.x) * float(ChunkData.CHUNK_SIZE) + float(ChunkData.CHUNK_SIZE) * 0.5,
            0.0,
            float(_spawn_point.y) * float(ChunkData.CHUNK_SIZE) + float(ChunkData.CHUNK_SIZE) * 0.5
        ))
        _update_loaded_chunks()
        # Check if all chunks in spawn radius are loaded
        _check_spawn_area_readiness()
        return
    # Normal player-tracking behavior
    var player_pos: Vector3 = _get_player_world_position()
    ...
```

This eliminates the chicken-and-egg problem. Chunks load around a known spawn coordinate. The player isn't needed for chunk loading to start.

`_check_spawn_area_readiness()` iterates all chunks within `LOAD_RADIUS` of spawn and verifies they're in `_loaded_chunks` with terrain height available.

**Spawn point as data:**

The spawn point comes from `world_meta.res` or a configurable default. It's a chunk coordinate, not a player position. Data-driven.

### Phase 3: WORLD_READY (replaces current scattered spawn + sync)

**Current flow:**
```
WorldManager._ready() spawns player → player _ready() awaits frame → _apply_authority()
→ _place_player_on_terrain polling → initial_sync RPC sent (maybe before remote node exists)
```

**New flow:**
```
GameStateController signals WORLD_READY
→ WorldManager spawns local player(s)
→ Player placed at terrain height (guaranteed available now)
→ PlayerController._apply_authority() runs (no await needed — we control the timing)
→ CameraController activates (no await needed)
→ Enable SyncComponent on each player
→ For each known peer: spawn their player node
→ Short hold to confirm RPC paths exist on all peers
→ Advance to PLAYING
```

Because we waited for `is_spawn_area_ready()`, terrain height is guaranteed. No polling loop. No `call_deferred`. No `await process_frame`.

**PlayerController changes:**

Remove `await get_tree().process_frame` from `_ready()`. The controller calls `_apply_authority()` explicitly after spawn, or `_ready()` just calls it directly since by this point we know the tree is stable.

Actually — simpler: `_apply_authority()` still runs in `_ready()` but **without the await**. The only reason the await existed was that `set_multiplayer_authority()` needed a frame to propagate. In Godot 4.x, authority is set before `add_child` in `WorldManager._spawn_player()` (line 38), so it's available by `_ready()` time. The `await` was defensive but unnecessary given our new ordering.

Same for `CameraController._ready()` — remove the `await process_frame`.

### Phase 4: PLAYING

- Loading overlay fades / hides
- `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)` 
- Player physics enabled
- RPC sync active

---

## Extracting Sync Logic from PlayerController

### Current Coupling

`PlayerController` contains 4 RPC methods and sync scheduling:
- `sync_transform()` (line 133) — unreliable position broadcast
- `initial_sync()` (line 144) — reliable spawn position
- `equip_item()` (line 155) — reliable equipment action
- `sync_equipment()` (line 163) — reliable equipment state
- `_sync_transform_if_needed()` (line 107) — scheduling logic called every physics frame

### What Should Move

The **positional sync** (`sync_transform`, `initial_sync`, `_sync_transform_if_needed`) is generic — any entity that moves and needs to be networked would use the same pattern. This belongs in a `NetworkSync` component.

The **equipment RPCs** (`equip_item`, `sync_equipment`) are player-specific but the RPC mechanism is boilerplate. These can stay for now — they're not causing the init race.

### Design: NetworkSync Node

A **child node** added to any entity that needs position sync:

```gdscript
class_name NetworkSync
extends Node

var _entity: Node3D
var _sync_enabled: bool = false

func setup(entity: Node3D) -> void:
    _entity = entity

func enable_sync() -> void:
    _sync_enabled = true

func disable_sync() -> void:
    _sync_enabled = false

func _physics_process(_delta: float) -> void:
    if not _sync_enabled: return
    if not _entity.is_multiplayer_authority(): return
    if not _is_connected(): return
    rpc("sync_transform", _entity.global_transform.origin, _entity.camera_yaw)

@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, yaw: float) -> void:
    if _entity.is_multiplayer_authority(): return
    # ... toroidal wrapping, apply position

@rpc("authority", "reliable")
func initial_sync(pos: Vector3, yaw: float) -> void:
    if _entity.is_multiplayer_authority(): return
    # ... set position
```

**Benefits:**
- `PlayerController._physics_process` no longer calls `_sync_transform_if_needed()` — sync is self-contained
- `GameStateController` controls when sync is enabled: `player.network_sync.enable_sync()` only in `PLAYING` state
- Same component can be attached to NPCs, projectiles, etc.
- `PlayerController` goes from 233 lines to ~170 lines

**What stays on PlayerController:**
- `is_multiplayer_authority()` gates (these MUST be on the entity — they control which peer runs physics)
- Equipment RPCs (player-specific)
- Toroidal wrapping logic (entity movement concern, not sync)

### Is this an over-correction?

**No.** The sync extraction is proportional to the problem. The init race is caused by RPCs firing before systems are ready. By giving the controller a `sync_enabled` flag and having the pipeline enable it at the right time, we solve the race AND clean up the entity. The component is ~60 lines, not a framework.

If we only extracted sync logic but didn't add the pipeline, we'd still have the timing problem — so both changes are needed. If we only added the pipeline but left sync in the player, we could gate it with a boolean there — but that's the same logic in the wrong place, and it makes the player harder to test/reuse.

### What about `equip_item` / `sync_equipment`?

Leave them. They're action RPCs, not continuous sync. They don't fire during init. Moving them would be over-engineering for no gain.

---

## GhostManager Bug Fix

`GhostManager` (`ghost_manager.gd:10`) has a bug: it sets `process_mode = PROCESS_MODE_DISABLED` in `_ready()`, which prevents `_process()` from ever running. The self-start pattern in `_try_get_world_data()` (line 46-50) was designed to poll for `ChunkManager`, find it, then call `start()` which sets `process_mode = PROCESS_MODE_ALWAYS`. But since processing is disabled, this code path can never execute — the torus-seam ghost system (0,0↔127,127 wrapping) never activates.

The ghost system itself is sound and needed. The fix is removing line 10.

**Fix: Remove `process_mode = PROCESS_MODE_DISABLED` from `_ready()`** — the node's `_process()` will run, `_try_get_world_data()` will find `ChunkManager` once the world loads, and `start()` will set the proper mode. One line removal. The torus ghost feature works as designed after this.

---

## Loading Overlay

A simple `Control` scene added as a child of the `GameStateController` autoload (or a scene it manages). Structure:

```
Panel (full screen, dark color)
  └─ VBoxContainer (centered)
       ├─ Label "Loading..."
       └─ ProgressBar (indeterminate or chunk-count-based)
```

Visible during `LOADING` and `WORLD_READY`. Hidden on `PLAYING`.

The progress bar can report real progress from `ChunkManager`:
```gdscript
func get_spawn_area_progress() -> float:
    # returns 0.0..1.0 for chunks loaded within spawn radius
```

This is a nice-to-have. A simple "Loading..." text is sufficient for MVP.

---

## Implementation Order

### Step 1: Fix GhostManager bug (1 line, independent)
- Remove `process_mode = PROCESS_MODE_DISABLED` from `ghost_manager.gd:10`

### Step 2: Add spawn-point-driven chunk loading to ChunkManager
- Add `_spawn_point` config (defaults to `(0, 0)`)
- In `_update_chunks()`, use spawn point when no player exists yet
- Add `is_spawn_area_ready() -> bool`
- Add `get_spawn_area_progress() -> float`

### Step 3: Create GameStateController autoload
- State enum: `MENU, CONNECTING, LOADING, WORLD_READY, PLAYING`
- In `MENU`: listen for host/join actions (or have main_menu call `GameStateController.begin_connecting()`)
- In `CONNECTING`: wait for `MultiplayerManager.is_webrtc_ready()` then `change_scene_to_file`
- In `LOADING`: show loading overlay, poll `ChunkManager.is_spawn_area_ready()`, then advance
- In `WORLD_READY`: call `WorldManager.spawn_initial_players()`, wait one frame, enable sync, advance
- In `PLAYING`: hide overlay

### Step 4: Refactor WorldManager to be called, not self-driving
- Remove the _ready() auto-spawn and signal connections
- Add `spawn_initial_players()` called by GameStateController
- `_spawn_player()` stays the same
- `_place_player_on_terrain()` simplified: no `call_deferred`, no polling loop (terrain height is guaranteed)
- Remove `connection_succeeded` handler (GameStateController handles connection flow)

### Step 5: Fix PlayerController / CameraController
- Remove `await get_tree().process_frame` from both `_ready()` methods
- Move sync logic to `NetworkSync` component
- Remove `_sync_transform_if_needed()`, `sync_transform()`, `initial_sync()` from PlayerController

### Step 6: Update main_menu.gd
- Remove the 1-second timer + `_change_to_world`
- On Host/Join: call `GameStateController.begin_connecting()` instead
- GameStateController owns the scene transition

### Step 7: Create NetworkSync component
- New script: `scripts/multiplayer/network_sync.gd`
- Handles `sync_transform` and `initial_sync` RPCs
- `enable_sync()` / `disable_sync()` controlled by GameStateController
- Add as child node to player in `WorldManager._spawn_player()`

### Step 8: Loading overlay scene
- Simple `Control` scene with label
- Added/managed by GameStateController

---

## What This Does NOT Change

- `MultiplayerManager` signaling architecture (works fine, just gate when RPCs fire)
- `ChunkManager._process()` budget system (2 chunks/frame is good)
- `FoliageRenderer` queue pattern (works fine, just a consumer)
- Equipment RPCs on PlayerController (not causing the problem)
- World generation pipeline (offline, unrelated)
- `WorldData` region threading (works, `ChunkManager.is_spawn_area_ready()` accounts for threaded loads by checking `_loaded_chunks`)

---

## Risk Assessment

| Concern | Mitigation |
|---|---|
| ChunkManager spawn-point change might break existing chunk tracking | The change is small: use `_spawn_point` when no player is in tree, then switch to player tracking once `PLAYING`. The existing `_update_loaded_chunks()` logic is untouched. |
| Removing `await process_frame` from player/camera _ready | Authority is set before `add_child()` (line 38 of world_manager.gd), so it propagates before `_ready()`. The await was never required — it was defensive. |
| NetworkSync component adds complexity | It removes more complexity than it adds. PlayerController drops ~60 lines of sync code. The component is self-contained. |
| GameStateController as autoload creates global state | It's a thin state machine with no gameplay logic. It coordinates initialization — exactly what autoloads are for. Every system it calls already exists. |
| WebRTC peers might not be connected by WORLD_READY | For the host (no peers yet), this is fine. For clients with existing peers, we check `MultiplayerManager.is_peer_webrtc_connected()` for known peers. For peers that connect later, the existing `peer_connected` signal still spawns their player — that path doesn't change. |

---

## File Change Summary

| File | Change |
|---|---|
| `scripts/world/ghost_manager.gd` | Remove line 10 (`process_mode = DISABLED`) |
| `scripts/world/chunk_manager.gd` | Add `_spawn_point`, `is_spawn_area_ready()`, `get_spawn_area_progress()`, use spawn point when no player exists |
| `scripts/multiplayer/game_state_controller.gd` | **NEW** — state machine autoload |
| `scripts/multiplayer/multiplayer_manager.gd` | Add `is_webrtc_ready() -> bool` |
| `scripts/world/world_manager.gd` | Remove _ready() auto-spawn, add `spawn_initial_players()`, simplify terrain placement |
| `scripts/player/player_controller.gd` | Remove `await process_frame`, remove sync methods, remove `_sync_transform_if_needed()` |
| `scripts/player/camera_controller.gd` | Remove `await process_frame` |
| `scripts/multiplayer/network_sync.gd` | **NEW** — extracted position sync component |
| `scripts/ui/main_menu.gd` | Remove timer + `_change_to_world`, call `GameStateController.begin_connecting()` |
| `scenes/ui/loading_overlay.tscn` | **NEW** — simple loading screen |
| `project.godot` | Register `GameStateController` autoload |
