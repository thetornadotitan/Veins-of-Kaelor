# Supplemental: Torus World Wrapping — Multiplayer Seam Handling

*Plan version: 2.0 | Created: 2026-06-21 | Updated: 2026-06-21 | Supplement to: Phase 3*

---

## Table of Contents

1. [The Problem Statement](#1-the-problem-statement)
2. [Validity of Concerns — What's Real vs. Hypothetical](#2-validity-of-concerns)
3. [The Core Architecture Decision: Bounded Coordinates](#3-core-architecture-decision)
4. [Current System Bugs](#4-current-system-bugs)
5. [The Fix Plan](#5-the-fix-plan)
6. [Ghost Entity System — Players and Projectiles Across Seams](#6-ghost-entity-system)
7. [Projectile Wrapping Architecture](#7-projectile-wrapping-architecture)
8. [Minimap / World Map on a Torus](#8-minimap--world-map-on-a-torus)
9. [Floating Point Precision Analysis](#9-floating-point-precision-analysis)
10. [Implementation Priority](#10-implementation-priority)

---

## 1. The Problem Statement

The world is topologically a torus — 5120×5120 units. The terrain data wraps seamlessly (4D noise on a torus). Visually, chunks now render at the nearest copy relative to the player. But several systems break at world boundaries:

**Core question:** How do player transforms, multiplayer sync, physics, and interaction work across the seam where x=0 meets x=5120?

**Specific concerns raised:**
- Players should be bounded to world limits (no walking to -1,-1 or infinite drift)
- Players should still see each other across the seam
- A player at (0,0) and a player at (5119,5119) are actually adjacent — how do they interact?
- Projectiles need to cross the seam seamlessly
- A minimap needs to represent the torus correctly
- What about float precision at large coords?

---

## 2. Validity of Concerns

| Concern | Validity | Severity |
|---------|----------|----------|
| Player at -1,-1 drifting infinitely | **VALID** — Current `_wrap_world_coordinates()` wraps to `[0, 5120)` every frame, so this is already handled for the local player. **But remote players receive raw coords via RPC without unwrapping, creating a different problem.** | Medium |
| Players can't see each other across seam | **VALID** — Remote player at x=0 appears at x=0 in world space, even when the local player is at x=5100 with chunks loaded at x=-20 to x=200 range. The remote player is 5100 units away visually. | **Critical** |
| Multiplayer desync at boundary | **VALID** — When a player wraps from 5119→0, their `sync_transform` sends pos.x=0. The receiver places the remote player at x=0, which is 5000+ units from where they just were. The remote player "teleports" from the receiver's perspective. | **Critical** |
| Projectiles crossing seam | **VALID** — A bullet at x=5119 heading +X needs to hit a target at x=1. Godot physics can't do this natively. | **High** |
| Minimap shows discontinuity | **VALID** — A flat minimap will show the player jump from one edge to the other, and entities near opposite edges will appear far apart. | **High** |
| Float precision degradation | **Not a real concern** — The world is 5120×5120 units. Float32 has 7 significant digits. At 5120, precision is ~0.5 units. Since positions wrap to [0, 5120), they never accumulate. | **Low** |
| Physics glitch on wrap frame | **Minor** — `move_and_slide()` runs before `_wrap_world_coordinates()`. On the wrap frame, position jumps ~5120 units. The next `move_and_slide` call sees a massive position delta, potentially causing velocity glitches for one frame. | Low |

**Key realization:** The biggest real problems are **multiplayer sync at boundaries** and **the need for ghost entities to support projectiles and minimap**. Float precision is a non-issue due to the bounded torus.

---

## 3. The Core Architecture Decision: Bounded Coordinates

### Rule: All authoritative positions MUST stay in [0, world_size)

This is already true for local players (via `_wrap_world_coordinates()`). The architecture enforces:

1. **Authority entity** — position stays in `[0, 5120)` after each physics frame
2. **Remote entity representation** — position is rendered relative to the local player's coordinate frame (which CAN be negative or exceed world_size for visual purposes)
3. **Network protocol** — positions are transmitted in canonical `[0, world_size)` space; the receiver unwraps to their local frame
4. **Projectiles** — authority position wraps through `[0, world_size)`; ghost copies handle collision on both sides of the seam

### Why NOT let entities go to -1,-1:

- Entities at `-1,-1` and `5119,5119` are "the same place" on a torus but different floats
- Two remote entities could drift to different integer-multiple offsets: one at `x=5` and another at `x=5125` — both representing the same world point
- Interaction logic (is entity A near entity B?) would need toroidal distance calculations everywhere
- Physics/collision can't natively understand wrapping
- RPC sync becomes ambiguous — which "copy" of the position was intended?

**The canonical coordinate space `[0, world_size)` is the single source of truth.** All authority positions are normalized. All receiving clients unwrap to their local frame.

---

## 4. Current System Bugs

### Bug 1: `sync_transform` doesn't unwrap (CRITICAL)

```gdscript
# CURRENT (broken at boundaries):
@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, yaw: float) -> void:
    if not is_multiplayer_authority():
        global_transform.origin = pos  # Raw canonical pos — no unwrap!
        camera_yaw = yaw
```

**Failure scenario:** Player A at x=5119 wraps to x=0. Sends `pos.x=0`. Player B (at x=5100) receives x=0, places the remote player 5100 units away. Player A "vanishes."

**Fix:** Receiver unwraps incoming position to nearest copy relative to itself:
```gdscript
@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, yaw: float) -> void:
    if not is_multiplayer_authority():
        pos = TorusUtils.wrap_vector3_near(pos, global_position, _get_world_data())
        global_transform.origin = pos
        camera_yaw = yaw
```

### Bug 2: `get_terrain_height()` broken at negative coords

```gdscript
# CURRENT (broken for negative input):
var local_x: float = world_x - float(chunk_x * ChunkData.CHUNK_SIZE)
# e.g. world_x = -1, chunk_x = 127 → local_x = -1 - 5080 = -5081 (WRONG, should be 39)
```

**Fix:** Use modular arithmetic for local coords:
```gdscript
var local_x: float = fposmod(world_x, float(ChunkData.CHUNK_SIZE))
var local_z: float = fposmod(world_z, float(ChunkData.CHUNK_SIZE))
```

### Bug 3: No reliable initial position sync for remote players

When a remote player spawns, they're at `(0,0,0)` until the first unreliable `sync_transform` arrives. If the packet is lost, they stay at the origin.

**Fix:** Add a reliable initial sync RPC, called once after spawn:
```gdscript
@rpc("authority", "reliable")
func initial_sync(pos: Vector3, yaw: float) -> void:
    if not is_multiplayer_authority():
        pos = TorusUtils.wrap_vector3_near(pos, global_position, _get_world_data())
        global_transform.origin = pos
        camera_yaw = yaw
```

### Bug 4: Remote player position not unwrapped after local-player wrap

When the local player wraps (5119→0), all chunks reposition via `_refresh_chunk_positions()`, but remote players' representations are NOT repositioned. They stay at their old absolute coordinates, which are now 5000+ units from the newly-positioned chunks.

**Fix:** After `_wrap_world_coordinates()` fires (and actually wraps), WorldManager re-unwraps all remote player nodes using `TorusUtils.wrap_vector3_near()`.

---

## 5. The Fix Plan

### Step 1: Toroidal Utility Class

Create a shared utility that ALL wrapping systems use — player sync, chunk positioning, ghost spawning, projectile wrapping, and minimap coordinates:

```gdscript
# scripts/world/torus_utils.gd
class_name TorusUtils
extends RefCounted

static func wrap_near(value: float, ref: float, size: float) -> float:
    var d := value - ref
    while d > size * 0.5:
        value -= size
        d = value - ref
    while d < -size * 0.5:
        value += size
        d = value - ref
    return value

static func wrap_vector3_near(pos: Vector3, ref: Vector3, wd: WorldData) -> Vector3:
    pos.x = wrap_near(pos.x, ref.x, wd.world_size_x)
    pos.z = wrap_near(pos.z, ref.z, wd.world_size_z)
    return pos

static func toroidal_delta(a: float, b: float, size: float) -> float:
    var d := b - a
    while d > size * 0.5: d -= size
    while d < -size * 0.5: d += size
    return d

static func toroidal_distance_sq(a: Vector3, b: Vector3, wsx: float, wsz: float) -> float:
    var dx := toroidal_delta(a.x, b.x, wsx)
    var dz := toroidal_delta(a.z, b.z, wsz)
    var dy := a.y - b.y
    return dx * dx + dy * dy + dz * dz

static func toroidal_distance(a: Vector3, b: Vector3, wsx: float, wsz: float) -> float:
    return sqrt(toroidal_distance_sq(a, b, wsx, wsz))

static func is_near_boundary(pos: Vector3, wd: WorldData, margin: float) -> bool:
    return pos.x < margin or pos.x > wd.world_size_x - margin \
        or pos.z < margin or pos.z > wd.world_size_z - margin

static func wrapf(value: float, size: float) -> float:
    return fposmod(value, size)

static func canonical_position(pos: Vector3, wd: WorldData) -> Vector3:
    pos.x = fposmod(pos.x, wd.world_size_x)
    pos.z = fposmod(pos.z, wd.world_size_z)
    return pos
```

### Step 2: Fix `sync_transform` + Add `initial_sync`

Update `player_controller.gd` to unwrap incoming positions.

### Step 3: Fix `get_terrain_height`

Replace broken local_x/local_z with `fposmod()`.

### Step 4: Re-unwrap Remote Players After Local Wrap

When `_wrap_world_coordinates()` actually wraps the player, WorldManager re-unwraps all remote player nodes.

### Step 5: ChunkManager Uses `TorusUtils`

Replace the duplicate while-loop logic in `_chunk_to_nearest_world_position()` with `TorusUtils.wrap_near()`.

### Step 6: Ghost Entity System

See [Section 6](#6-ghost-entity-system).

### Step 7: Projectile Wrapping

See [Section 7](#7-projectile-wrapping-architecture).

### Step 8: Minimap Coordinate Mapping

See [Section 8](#8-minimap--world-map-on-a-torus).

---

## 6. Ghost Entity System — Players and Projectiles Across Seams

### Why Ghosts Are Needed

The "unwrap fix" (Step 2) ensures remote players appear at the nearest copy relative to the local player. This works for 3rd-person camera with limited draw distance. **But it fails for:**

1. **Projectiles** — A bullet at x=5119 heading +X needs a physics body at x=5119 AND a ghost physics body at x=-1 (the wrapped copy). Otherwise, the bullet leaves the world without hitting a target at x=1.

2. **Minimap** — A minimap renders the world as a flat rectangle. A player at x=10 and a player at x=5110 should appear adjacent on the minimap edge. This requires the minimap to handle wrap-around rendering, which is effectively a 2D ghost system.

3. **Area-of-effect** — An explosion at x=5115 with radius 20 should damage a player at x=3 (toroidal distance = 8). The explosion needs ghost collision at the wrapped position.

### Ghost System Architecture

```
┌──────────────────────────────────────────────┐
│ GhostManager (Autoload / child of WorldManager) │
│                                              │
│ Tracks all "ghostable" entities near world   │
│ boundaries. For each entity within margin     │
│ distance of a seam, spawns a ghost copy      │
│ at the wrapped position.                     │
└──────────────────────────────────────────────┘

Ghostable entities implement:
  - get_canonical_position() -> Vector3  (always in [0, world_size))
  - get_ghost_type() -> GhostType { PLAYER, PROJECTILE, AOE }
  - on_ghost_hit(hit_result)  # callback when a ghost's physics fires
```

### Ghost Computation

For any entity at canonical position `P` in `[0, world_size)`:
- If `P.x < SEAM_MARGIN`: spawn ghost at `(P.x + world_size_x, P.y, P.z)`
- If `P.x > world_size_x - SEAM_MARGIN`: spawn ghost at `(P.x - world_size_x, P.y, P.z)`
- Same for Z axis
- Corner case: entity near BOTH edges → up to 4 ghosts (x-wrap, z-wrap, xz-corner-wrap)

`SEAM_MARGIN` = the maximum interaction range in the game (projectile max range, AoE max radius, etc.). For now: **160 units** (4 chunks, slightly more than the LOD distance).

### Ghost Types

| Type | Has Physics Body? | Visual? | Sync'd? | Purpose |
|------|-------------------|---------|---------|---------|
| PLAYER_GHOST | No (visual only) | Yes (mirrors source) | Follows source's sync_transform | So remote players appear on both sides of the minimap seam |
| PROJECTILE_GHOST | Yes (collision) | Yes (mirrors source) | Authority on source projectile | So bullets crossing the seam hit targets on the wrapped side |
| AOE_GHOST | Yes (Area3D overlap) | Maybe (particles) | One-shot, no sync | So explosions near the seam damage wrapped-side entities |

### Ghost Lifecycle

```
1. Entity enters SEAM_MARGIN → GhostManager.spawn_ghosts(entity)
2. Ghost mirrors the entity's visual state each frame
3. If the ghost's physics fires (collision/overlap), the event is forwarded to the canonical entity
4. Entity leaves SEAM_MARGIN → GhostManager.despawn_ghosts(entity)
5. On the wrap frame itself: entity teleports from 5119→0, ghosts are recycled
```

### Ghost For Players — Detail

A player ghost is a **visual-only** duplicate used exclusively by the minimap system. In the 3D viewport, players already look correct (thanks to the unwrap fix). The ghost player exists so the minimap can render them at both their canonical position AND the wrapped position near the seam.

Implementation: `GhostPlayer` node is a lightweight `Node3D` with a `Sprite3D` or simple mesh. It reads the canonical player's position each frame and renders at the wrapped offset. No physics body.

### Ghost For Projectiles — Detail

See [Section 7](#7-projectile-wrapping-architecture).

### GhostManager Implementation Sketch

```gdscript
class_name GhostManager
extends Node

const SEAM_MARGIN: float = 160.0

var _ghosts: Dictionary = {}  # entity_instance_id -> Array[GhostNode]
var _world_data: WorldData

func _process(_delta: float) -> void:
    for entity in get_tree().get_nodes_in_group("ghostable"):
        var canonical := entity.get_canonical_position()
        var near_seam := TorusUtils.is_near_boundary(canonical, _world_data, SEAM_MARGIN)
        var has_ghosts := _ghosts.has(entity.get_instance_id())
        if near_seam and not has_ghosts:
            _spawn_ghosts(entity)
        elif not near_seam and has_ghosts:
            _despawn_ghosts(entity)
        elif has_ghosts:
            _update_ghosts(entity)

func _spawn_ghosts(entity: Node3D) -> void:
    var ghosts: Array[Node3D] = []
    var pos := entity.get_canonical_position()
    # +X ghost
    if pos.x > _world_data.world_size_x - SEAM_MARGIN:
        ghosts.append(_create_ghost(entity, Vector3(pos.x - _world_data.world_size_x, pos.y, pos.z)))
    # -X ghost
    if pos.x < SEAM_MARGIN:
        ghosts.append(_create_ghost(entity, Vector3(pos.x + _world_data.world_size_x, pos.y, pos.z)))
    # +Z, -Z, and corner ghosts similarly...
    _ghosts[entity.get_instance_id()] = ghosts

func _create_ghost(source: Node3D, wrapped_pos: Vector3) -> Node3D:
    var ghost: Node3D = source.create_ghost()
    ghost.position = wrapped_pos
    add_child(ghost)
    return ghost
```

Each ghostable entity type implements `create_ghost()` returning the appropriate ghost node type:
- Player: returns a visual-only replica
- Projectile: returns a physics-enabled replica with collision forwarding
- AOE: returns an Area3D replica with overlap forwarding

---

## 7. Projectile Wrapping Architecture

### The Core Problem

A projectile fired from x=5119 toward +X must hit a target at x=3. Godot's physics engine tests collision in Euclidean space — the projectile at x=5119 and the target at x=3 are 5116 units apart in scene coordinates, even though they're 4 units apart on the torus.

### Solution: Ghost Projectile + Authority Wrapping

The projectile system uses TWO mechanisms:

#### Mechanism 1: Authority Position Wrapping

The projectile's **canonical** position is always in `[0, world_size)`. When a projectile at x=5119 moves +5 units, its authority position becomes:

```
x = 5119 + 5 = 5124 → fposmod(5124, 5120) = 4
```

The projectile wraps its authority position every frame, just like players. This ensures:
- Network sync stays in canonical space
- Position never drifts outside bounds
- The projectile is always "legally" positioned

#### Mechanism 2: Ghost At The Wrapped Position

When the projectile is near a seam, the GhostManager spawns a ghost at the wrapped position. This ghost has a **real physics body** and **real collision detection**.

Scenario:
```
1. Fire projectile at (5119, 22, 100) in +X direction
2. Projectile is near seam (within SEAM_MARGIN=160)
3. GhostManager spawns ghost at (5119 - 5120, 22, 100) = (-1, 22, 100)
4. Both the authority projectile AND the ghost move +5 units per frame
5. Ghost is now at (4, 22, 100), authority is at (5124→4, 22, 100)
6. Target at (3, 22, 100) collides with the ghost at (4, 22, 100)
7. Ghost collision is forwarded to the authority projectile
8. Authority projectile handles hit logic (damage, despawn, etc.)
9. Ghost is cleaned up
```

### Projectile Wrap Frame

On the frame the authority position wraps (5119→0):
- The projectile teleports from x=5119 to x=0
- The ghost at x=-1 is no longer needed (or IS the new authority position)
- The GhostManager handles the transition seamlessly because it refreshes ghost positions each frame

**Key insight:** Since the ghost exists at the wrapped position BEFORE the wrap happens, there's no gap in collision coverage. The ghost covers the "other side" of the seam continuously.

### Projectile Implementation Pattern

```gdscript
class_name Projectile
extends CharacterBody3D

var velocity: Vector3
var _canonical_pos: Vector3
var _ghost: ProjectileGhost = null

func _physics_process(delta: float) -> void:
    position += velocity * delta
    _canonical_pos = TorusUtils.canonical_position(position, _get_world_data())
    position = _canonical_pos
    # GhostManager handles ghost lifecycle

func create_ghost() -> Node3D:
    var ghost := ProjectileGhost.new()
    ghost.velocity = velocity
    ghost.source = self
    return ghost

func on_ghost_hit(hit: Dictionary) -> void:
    # Forwarded from ghost collision — handle damage, effects, despawn
    _handle_hit(hit)
```

```gdscript
class_name ProjectileGhost
extends CharacterBody3D

var velocity: Vector3
var source: Projectile  # The authority projectile

func _physics_process(delta: float) -> void:
    position += velocity * delta
    # Position is set by GhostManager at the wrapped offset

func _on_body_entered(body: Node3D) -> void:
    source.on_ghost_hit({"body": body, "position": global_position})
    queue_free()
```

### Collision Forwarding Rules

To prevent double-hits (authority projectile AND ghost both hitting the same target):

1. **Only the ghost has a collision body when near a seam.** The authority projectile's collision is disabled while ghosts exist.
2. **If no ghosts exist** (projectile is far from all seams), the authority projectile uses its own collision normally.
3. **Hit targets are tracked in a Set** on the authority projectile. Once a target is hit (by either body), it's ignored for the projectile's lifetime.

---

## 8. Minimap / World Map on a Torus

### The Problem

A flat minimap shows the world as a 2D rectangle. At the seam, entities jump from one edge to the other. Two players at x=1 and x=5119 appear at opposite corners of the minimap despite being 2 units apart.

### Solution: Toroidal Minimap Rendering

The minimap renders the world as a **repeating tile**, showing the local area centered on the player with wrap-around at edges.

#### Approach 1: SubViewport Tiling (Recommended)

Use a `SubViewport` to render the minimap content, then display it tiled in a `TextureRect`:

```
1. Minimap camera is centered on the local player's canonical position
2. The SubViewport renders a 2D top-down view of the world around the player
3. The minimap UI displays this as a rectangle
4. Entities near the opposite seam are rendered at their wrapped positions
   (this happens naturally because their 3D positions are already unwrapped
   relative to the local player by the sync_transform fix)
5. For entities in the GhostManager, their ghost copies also appear on the minimap
   at the wrapped position, ensuring visibility across the seam
```

Because all entity positions (players, projectiles, etc.) are unwrapped to the local player's coordinate frame, and ghosts exist at the wrapped position near seams, the minimap naturally shows a seamless view.

#### Approach 2: Texture-Based World Map

For a full-world map (not just local area):
- Render the world once as a static texture (using the heightmap data)
- Overlay entity icons using toroidal coordinate mapping
- For entities near seams, render duplicate icons at both positions

```gdscript
func _draw_minimap_entity(entity_pos: Vector2i, entity_icon: Texture2D) -> void:
    var map_size := minimap_rect.size
    var scale := map_size.x / world_size_x
    var base_pos := Vector2(entity_pos.x * scale, entity_pos.y * scale)
    draw_texture(entity_icon, base_pos)
    # Draw wrapped copies if near seam
    if base_pos.x < icon_size:
        draw_texture(entity_icon, base_pos + Vector2(map_size.x, 0))
    if base_pos.x > map_size.x - icon_size:
        draw_texture(entity_icon, base_pos - Vector2(map_size.x, 0))
    # Same for Y axis...
```

#### Minimap Player Markers

Player markers on the minimap use the **canonical position** mapped through `TorusUtils.wrap_near()`:
```gdscript
func get_minimap_position(world_pos: Vector3) -> Vector2:
    var local_pos := TorusUtils.wrap_vector3_near(world_pos, player_position, world_data)
    # local_pos is now relative to the player, in the same frame as chunks
    # Map to minimap coordinates
    return Vector2(
        (local_pos.x - player_position.x + minimap_half_size) / minimap_range * minimap_size,
        (local_pos.z - player_position.z + minimap_half_size) / minimap_range * minimap_size
    )
```

This ensures that a remote player at (5119, y, 100) whose position is unwrapped to (-1, y, 100) relative to the local player at (10, y, 100) appears at the left edge of the minimap — adjacent to the local player — which is correct.

### Ghost Players on the Minimap

Since the minimap shows a local area centered on the player, ghost player nodes serve the purpose of making remote players visible at the seam boundary on the minimap. A remote player at x=5110 will have their 3D ghost at x=5110-5120=-10, which maps to the left edge of the minimap — seamlessly adjacent to the local player at x=10.

**No special minimap wrap logic needed** — the ghost system + coordinate unwrapping handles it.

---

## 9. Floating Point Precision Analysis

### World Size: 5120 × 5120 units

| Metric | Value | Concern? |
|--------|-------|----------|
| Max coordinate | 5120.0 | No |
| Float32 precision at 5120 | ~0.5 units | Fine for player movement |
| Float32 precision at 0 | ~0.0001 units | Perfect |
| Coordinate range after wrap | Always [0, 5120) | Never accumulates |
| Negative coordinates (for rendering) | Down to ~-2560 (half-world) | Fine — float32 handles this easily |
| Ghost coordinates | Can be -160 to 5280 | Fine — still well within float32 safe range |

### The Infinite Drift Concern

**Not a problem.** The `_wrap_world_coordinates()` function enforces `[0, world_size)` every physics frame. A player CANNOT accumulate position beyond 5120. They wrap. The torus world is inherently bounded.

Projectiles also wrap their authority position every frame. No entity ever grows beyond `[0, 5120)`.

### During Wrap Frame

Position can briefly be off-range for one frame:
```
1. move_and_slide() → pos.x = -0.5 (player stepped past x=0)
2. _wrap_world_coordinates() → pos.x = 5119.5
3. sync_transform sends 5119.5 (canonical, in range)
```

The brief negative value exists for one frame and is corrected before sync. No downstream system should rely on it. The `get_terrain_height()` bug (Bug 2) is the only system that misbehaves with negative input, and it's a standalone fix.

### Double Precision: Unnecessary

Godot supports `precision=double` compilation, but for a 5120-unit bounded world, float32 is more than adequate. The precision concern is only relevant for open-world games with 100km+ continuous space.

**Verdict:** No float precision work needed. The torus architecture is self-correcting.

---

## 10. Implementation Priority

### P0: Must-Have (Blocking — breaks multiplayer at boundaries NOW)

| Task | File | Effort |
|------|------|--------|
| Add `TorusUtils` class | `scripts/world/torus_utils.gd` | Small |
| Fix `sync_transform` to unwrap remote positions | `scripts/player/player_controller.gd` | Small |
| Fix `get_terrain_height` for negative/wrapped coords | `scripts/world/chunk_manager.gd` | Trivial |
| Add reliable `initial_sync` RPC for remote player spawn | `scripts/player/player_controller.gd`, `scripts/world/world_manager.gd` | Small |
| Re-unwrap remote players when local player wraps | `scripts/player/player_controller.gd`, `scripts/world/world_manager.gd` | Medium |
| Refactor `_chunk_to_nearest_world_position` to use `TorusUtils` | `scripts/world/chunk_manager.gd` | Trivial |

### P1: Ghost Entity System (Needed before projectiles and minimap)

| Task | File | Effort |
|------|------|--------|
| Create `GhostManager` autoload | `scripts/world/ghost_manager.gd` | Medium |
| Add `"ghostable"` group and `get_canonical_position()`/`create_ghost()` interface | `scripts/player/player_controller.gd`, future projectile/AOE scripts | Small |
| Implement `GhostPlayer` (visual-only ghost for minimap) | `scripts/world/ghost_player.gd` | Small |
| Implement `ProjectileGhost` (physics ghost for seam collision) | `scripts/world/projectile_ghost.gd` | Medium |
| GhostManager tracks seam-margin entities, spawns/despawns ghosts per frame | `scripts/world/ghost_manager.gd` | Medium |
| Collision forwarding from ghost → authority entity | `scripts/world/projectile_ghost.gd` | Small |
| Double-hit prevention (authority collision disabled while ghost active) | `scripts/world/ghost_manager.gd` | Small |

### P2: Projectile Wrapping (When projectiles are implemented)

| Task | File | Effort |
|------|------|--------|
| Projectile base class with `_wrap_world_coordinates()` | `scripts/combat/projectile.gd` | Small |
| Projectile integrates with GhostManager (joins "ghostable" group) | `scripts/combat/projectile.gd` | Small |
| `ProjectileGhost` collision forwards to authority | `scripts/world/projectile_ghost.gd` | Small |
| Authority projectile collision disabled while ghost exists | `scripts/world/ghost_manager.gd` | Trivial |
| Hit tracking Set to prevent double-hits | `scripts/combat/projectile.gd` | Trivial |

### P3: Minimap (When minimap is implemented)

| Task | File | Effort |
|------|------|--------|
| Minimap SubViewport centered on player | `scripts/ui/minimap.gd` | Medium |
| Entity markers use `TorusUtils.wrap_vector3_near()` for positioning | `scripts/ui/minimap.gd` | Small |
| Ghost player nodes render on minimap at seam edges | `scripts/ui/minimap.gd` | Trivial (free from ghost system) |
| Full-world map texture from heightmap data | `scripts/ui/world_map.gd` | Medium |
| Entity duplicate icons at seam edges on full-world map | `scripts/ui/world_map.gd` | Small |

---

## Appendix A: How the Complete Data Flow Works (After All Fixes)

### Local Player Walks Across Boundary

```
Frame N:
  Player at (5119, 22, 100)
  Chunks loaded: nearest copies relative to (5119,22,100)
  Remote player at (-20, 22, 100) [unwrapped near local player]
  Ghost of remote player at (5100, 22, 100) [for minimap seam visibility]

Frame N+1:
  move_and_slide() → position = (5120.5, 22, 100) [past boundary]
  _wrap_world_coordinates() → position = (0.5, 22, 100)
  WorldManager re-unwrap remote players → remote player at (5100,22,100) → re-unwrap to (-20,22,100)
  _sync_transform_if_needed() → rpc("sync_transform", Vector3(0.5, 22, 100), yaw)
  
  ChunkManager._process():
    _update_chunks():
      _world_to_chunk((0.5,22,100)) = chunk (0,2)
      Player chunk changed! → _update_loaded_chunks()
      _refresh_chunk_positions() → all chunks snap relative to (0.5,22,100)
  
  GhostManager._process():
    Remote player now at (-20, 22, 100), which is within SEAM_MARGIN of x=0
    → spawn ghost of remote player at (-20+5120, 22, 100) = (5100, 22, 100)
    (Minimap sees remote player at both positions near the seam)
```

### Projectile Crossing Seam

```
Frame N:
  Fire projectile at (5119, 22, 100) in +X direction at 50 units/sec
  GhostManager detects projectile near seam → spawns ghost at (-1, 22, 100)
  Authority collision disabled. Ghost collision enabled.
  
Frame N+1:
  Authority: 5119 + 50*dt → wraps to canonical position (still near 0)
  Ghost: -1 + 50*dt → moves forward in the wrapped frame
  Ghost at (1.83, 22, 100) collides with target at (3, 22, 100) [if close enough]
  Ghost.on_body_entered(target) → source.on_ghost_hit(target)
  Authority projectile despawns, ghost cleaned up
```

### Remote Player on Minimap

```
Local player at (10, 22, 10). Minimap shows 160-unit radius around player.

Remote player canonical position: (5110, 22, 100)
3D unwrapped position (relative to local player): (-10, 22, 100)
→ Appears at left edge of minimap ✓

Ghost of remote player (spawned because near seam): (5110, 22, 100) in world
→ Minimap tile rendering shows this ghost at right edge ✓

Both icons represent the same player — adjacent across the seam ✓
```

---

## Appendix B: What NOT To Do

### Don't: Let positions accumulate without bound
The "infinite coordinate" approach (let entities drift to -100000, +100000) breaks float precision, physics accuracy, multiplayer reconciliation, and collision queries.

### Don't: Use multiple coordinate frames simultaneously
Sending positions in "local frame" over the network means different clients have different "locals" and can't reconcile. Canonical `[0, world_size)` is the only frame for network communication.

### Don't: Rely on Godot's built-in physics for toroidal collision
Godot physics uses Euclidean distance. It cannot detect collisions across the seam. Ghost entities with real physics bodies at wrapped positions are the only way to make this work.

### Don't: Make ghosts for everything
Only entities near the seam need ghosts. The `SEAM_MARGIN` constant limits ghost creation to entities within interaction range of a boundary. At 160 units, typically only 0-3 entities need ghosts at any time.

### Don't: Make ghosts authoritative
Ghosts are always mirrors of the authority entity. They never have their own state. All game logic runs on the authority entity. Ghosts only exist for rendering and physics-collision-forwarding.

### Don't: Skip the GhostManager and try per-system wrapping
Without a centralized GhostManager, each system (projectiles, AoE, minimap) would independently implement seam logic, leading to bugs and inconsistency. The GhostManager is the single source of truth for "which entities need ghosts right now."
