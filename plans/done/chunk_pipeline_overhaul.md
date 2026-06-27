# Chaos Chunk Pipeline — Stutter-Free Chunk Loading

## Problem

Every chunk load is a synchronous wall of work on the main thread:

```
_load_chunk() per chunk:
  1. get_chunk_data()          → ~0.1ms (cached) or 5-50ms (sync ResourceLoader fallback!)
  2. TerrainMeshBuilder        → 2-8ms LOD0 (1600 quads + normals + skirt + commit)
  3. CollisionGenerator        → 1-3ms (1600 faces → ConcavePolygonShape3D BVH build)
  4. MeshInstance3D.new()      → ~0.3ms
  5. StaticBody3D + CollisionShape3D  → ~0.5ms
  6. NavigationRegion3D        → ~0.1ms
  7. add_child ×4              → ~0.4ms
  8. Foliage queue             → ~0.1ms (queued, not immediate)
  ────────────────────────────────────
  Total per chunk:             ~4-13ms (LOD0) → guaranteed stutter at 2/frame

Current mitigation: DATA_GEN_PER_FRAME=2, NODE_APPLY_PER_FRAME=2
→ 2 chunks × 4-13ms = 8-26ms of main thread blocking = dropped frames
```

And this is BEFORE adding buildings, resource nodes, instance entrances, texturing, etc.

## Root Causes

1. **Mesh building is synchronous** — `build_chunk_mesh_arrays()` + `_arrays_to_mesh()` run on main thread, consuming 2-8ms per chunk
2. **Collision shape BVH is synchronous** — `ConcavePolygonShape3D.set_faces()` triggers internal BVH build on main thread
3. **Node tree operations are synchronous** — 4× `add_child()` per chunk, 3× `new()` for nodes
4. **LOD transitions are synchronous** — `update_lod()` immediately rebuilds the mesh
5. **Region loading can block** — fallback to `ResourceLoader.load()` is synchronous
6. **Navmesh baking is expensive** — `parse_source_geometry_data()` + `bake()` runs on main thread (deferred by 1 frame only)
7. **No pooling** — every load creates fresh nodes, every unload calls `queue_free()`

## Architecture: The Pipeline

Split chunk loading into three independent stages with frame budgets. Heavy CPU work (mesh arrays, collision faces) runs on a worker thread. Scene tree work (node creation, add_child) runs on main thread in tiny bites.

```
 ┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
 │  STAGE 1: DATA  │ ──► │  STAGE 2: BUILD   │ ──► │  STAGE 3: APPLY  │
 │  (main thread)  │     │  (worker thread)  │     │  (main thread)   │
 │                  │     │                    │     │                   │
 │ • get_chunk_data │     │ • build_mesh_arrays│     │ • create RIDs     │
 │ • queue work     │     │ • build_collision  │     │   via Servers     │
 │                  │     │ • build_foliage     │     │ • set transforms  │
 └─────────────────┘     └──────────────────┘     └──────────────────┘
       <1ms                    OFF-THREAD               <1ms
```

**Stage 1** (main thread, <1ms): Fetch `ChunkData` from cache, push to worker queue.
**Stage 2** (worker thread, 3-10ms): Build PackedArrays for mesh/collision/foliage off-thread.
**Stage 3** (main thread, <1ms): Create RIDs via RenderingServer/PhysicsServer3D directly — no scene tree nodes.

## Key Design Decisions

### K1: Server API directly — bypass scene tree nodes entirely

**Current**: 4 nodes per chunk (MeshInstance3D, StaticBody3D, CollisionShape3D, NavigationRegion3D) × add_child × queue_free.

**New**: Use `RenderingServer` and `PhysicsServer3D` RIDs directly. Zero scene tree nodes per chunk. Each chunk is a data record holding RIDs, not a node tree.

```gdsl
# Instead of:
var mi := MeshInstance3D.new()
mi.mesh = mesh
add_child(mi)

# Do:
var instance_rid := RenderingServer.instance_create()
RenderingServer.instance_set_base(instance_rid, mesh_rid)
RenderingServer.instance_set_scenario(instance_rid, scenario_rid)
RenderingServer.instance_set_transform(instance_rid, chunk_transform)
```

**Benefits**:
- No `Node.new()`, no `add_child()`, no `queue_free()` — eliminates ALL scene tree overhead
- RID creation is ~0.01ms vs ~0.3ms for node + add_child
- PhysicsServer3D.body_create() + body_add_shape() is direct, no node overhead
- RenderingServer.instance_create() is direct, no node overhead
- Total stage 3: ~0.1ms per chunk instead of ~1.3ms

**Web-compatible**: Yes. RenderingServer and PhysicsServer3D are core engine APIs, available on all platforms including web/WASM.

### K2: Single worker thread for data generation

Use one `Thread` for Stage 2. The thread-safe APIs doc confirms:
- Creating resources off-tree is safe
- Manipulating PackedArrays (resizing elements, not the container) is safe
- `ArrayMesh.add_surface_from_arrays()` is safe on a worker thread (no GPU interaction)
- `ConcavePolygonShape3D.new()` + `set_faces()` is safe (pure CPU BVH build, no scene tree)

**NOT safe on worker** (must be on main thread):
- `RenderingServer.instance_create()` — needs scenario RID
- `PhysicsServer3D.body_create()` + `body_set_space()` — needs space RID
- Any `add_child()` or tree manipulation

**Web-compatible**: Yes. `Thread` works in Godot's WASM export (WebWorkers polyfill).

### K3: One ArrayMesh + ConcavePolygonShape3D per chunk, built off-thread

The worker thread produces:
- `mesh_arrays: Dictionary` (verts, normals, uvs, colors, indices)
- `collision_faces: PackedVector3Array`
- `foliage_data: Dictionary`

These are pure data — no RIDs, no nodes. Worker builds the `ArrayMesh` and `ConcavePolygonShape3D` (RefCounted, no tree dependency) and passes them back. Main thread applies in <1ms by creating RIDs that reference these objects.

### K4: ChunkRecord replaces TerrainChunk node

Instead of `TerrainChunk extends Node3D`, use a plain `RefCounted`:

```gdsl
class_name ChunkRecord
extends RefCounted

var chunk_pos: Vector2i
var mesh: ArrayMesh
var shape: ConcavePolygonShape3D
var instance_rid: RID
var body_rid: RID
var shape_rid: RID
var nav_region_rid: RID
var nav_mesh_rid: RID
var current_lod: int = -1
```

No scene tree node. No children. No `_ready()`, no `_process()`. Pure data + RIDs.

**Unloading**: Call `RenderingServer.free_rid(instance_rid)`, `PhysicsServer3D.free_rid(body_rid)`, etc. Zero queue_free, zero node tree walking.

### K5: Lazy collision — only chunks near the player get physics

LOD2+ chunks (>200m) get visual mesh only, no collision body. This eliminates:
- ~1-3ms of collision face generation per distant chunk
- PhysicsServer3D body + shape creation
- Physics simulation overhead for unreachable terrain

When a chunk transitions from LOD2→LOD1 (player walks closer), add collision.
When LOD1→LOD2, remove collision.

**Rationale**: Player can't walk on terrain they can't reach in <2 seconds. ~200m at ~10m/s = 20s away. Collision is wasted.

### K6: Lazy navmesh — only LOD0 chunks get navmesh

Navmesh baking is the most expensive per-chunk operation (~5-50ms). Only bake for chunks where AI will actually pathfind. LOD0 chunks within 80m of player = reasonable navmesh range.

### K7: LOD transition debouncing

Current: player crosses threshold → instant mesh rebuild (synchronous, 2-8ms stutter).

New: LOD changes are queued but not applied immediately. The worker thread builds the new mesh in the background. The old mesh is displayed until the new one is ready, then swapped in a single frame (`RenderingServer.instance_set_base()` is instant — ~0.01ms).

This eliminates ALL LOD transition stutters.

### K8: Frame budget driven by time, not count

Current: `DATA_GEN_PER_FRAME=2` is a fixed count. If both chunks are LOD0, budget is blown. If both are LOD4, budget is wasted.

New: Track elapsed microseconds in `_process()`. Process queue items until time budget (e.g., 4ms) is exceeded. This auto-adapts:
- LOD0 chunks → maybe 1 per frame
- LOD4 chunks → maybe 8 per frame
- Total always fits in budget

### K9: Region load guarantee — never block on main thread

`world_data.gd:147` falls back to `ResourceLoader.load()` which blocks. Fix:
- In `_process_data_generation()`, if `is_region_ready_for()` returns false, skip that chunk (don't push_front and stall). Let next frame check again.
- Request threaded load earlier (at queue time, not at process time — already done, but the fallback must not block).

## New Chunk Pipeline Flow

```
ChunkManager._process():
  1. Poll worker results         → apply ready chunks (Stage 3, <1ms each)
  2. Process data queue           → queue chunks for worker (Stage 1, <0.1ms each)
  3. Process LOD transitions     → queue LOD changes for worker
  4. Update chunk status          → load/unload decisions
  5. Budget check                 → stop if >4ms elapsed

Worker thread loop:
  1. Wait for work (Semaphore)
  2. Pop item from queue (Mutex)
  3. Build mesh arrays + ArrayMesh
  4. Build collision faces + ConcavePolygonShape3D
  5. Build foliage data
  6. Push result to completed queue (Mutex)
```

## Implementation Phases

### Phase 1: ChunkRecord + Server API (BIGGEST WIN — eliminates node overhead)
- Create `ChunkRecord` class (RefCounted, holds data + RIDs)
- Replace `TerrainChunk` node with `ChunkRecord`
- Mesh: `RenderingServer.instance_create()` + `instance_set_base()` + `instance_set_scenario()`
- Collision: `PhysicsServer3D.body_create()` + `body_add_shape()` + `body_set_space()`
- Nav: `NavigationServer3D.region_create()` + `region_set_map()` + `region_set_navmesh()`
- Unload: `RenderingServer.free_rid()`, `PhysicsServer3D.free_rid()`, etc.
- **Expected: ~1.3ms → ~0.1ms savings per chunk for node ops**

### Phase 2: Worker Thread for Stage 2 (eliminates mesh/collision build stutter)
- Create `ChunkWorker` class with `Thread` + `Semaphore` + `Mutex`
- Worker builds `ArrayMesh` + `ConcavePolygonShape3D` + foliage data off-thread
- Main thread polls completed queue each frame
- Stage 3 applies RIDs from completed results (<1ms each)
- **Expected: ~4-13ms → 0ms main thread per chunk (mesh/coll now off-thread)**

### Phase 3: Time-Based Budget (adaptive smoothness)
- Replace `DATA_GEN_PER_FRAME` with `_process_budget_usec: int = 4000`
- Track `Time.get_ticks_usec()` at start of each process phase
- Stop processing when budget exceeded
- **Expected: zero dropped frames regardless of LOD distribution**

### Phase 4: Lazy Collision + Navmesh (skip wasted work)
- LOD2+ chunks: skip collision generation entirely
- LOD1+ chunks: skip navmesh baking
- LOD transitions: add/remove collision as needed
- **Expected: 50-70% fewer collision shapes, 80% fewer navmesh bakes**

### Phase 5: LOD Debouncing (eliminate LOD transition stutters)
- LOD changes queue a rebuild request to the worker
- Old mesh stays visible until new one is ready
- Swap is a single `RenderingServer.instance_set_base()` call
- Add hysteresis (LOD distance ±10% buffer to prevent oscillation)
- **Expected: zero stutters on LOD transitions**

### Phase 6: Data-Driven Chunk Content (extensibility for buildings/nodes/entrances)
- Create `ChunkContentConfig` resource: defines what spawns per chunk
  - `buildings: Array[BuildingDef]` — scene paths, placement rules
  - `resource_nodes: Array[ResourceNodeDef]` — types, density, spawn conditions
  - `instance_entrances: Array[InstanceEntranceDef]` — dungeon/cave entries
  - `terrain_texture: TerrainTextureDef` — splatmap, texture layers
- `ChunkRecord` gets `content_spawns: Array[SpawnEntry]` computed by worker
- Spawns applied lazily: only when chunk reaches LOD0 and player is within interaction range
- **Expected: clean, data-driven extensibility without touching pipeline code**

## Per-Chunk Cost Comparison

| Operation | Current (ms) | Phase 1 (ms) | Phase 2+ (ms) |
|-----------|-------------|---------------|----------------|
| get_chunk_data | 0.1-50 | 0.1-50 | 0.1 (cached) |
| build_mesh_arrays | 2-8 | 2-8 | 0 (off-thread) |
| build_collision | 1-3 | 1-3 | 0 (off-thread) |
| node creation ×4 | 1.0 | — | — |
| add_child ×4 | 0.4 | — | — |
| Server RID creation | — | 0.1 | 0.1 |
| apply transform | 0.1 | 0.05 | 0.05 |
| **Main thread total** | **4-13** | **3.3-11.2** | **0.25** |

After Phase 2+: **0.25ms per chunk on main thread**. At 4ms budget, that's 16 chunks/frame. You could load the entire 121-chunk spawn area in ~8 frames = 0.13 seconds.

## Web Compatibility Notes

All proposed changes are fully web-compatible:
- ✅ `Thread` → Godot compiles to WebWorkers in WASM export
- ✅ `RenderingServer` RIDs → core engine, no GDExtension
- ✅ `PhysicsServer3D` RIDs → core engine, no GDExtension
- ✅ `NavigationServer3D` → thread-safe by default
- ✅ `ResourceLoader.load_threaded_request` → works on web (browser fetch)
- ✅ `ArrayMesh.add_surface_from_arrays()` → CPU-only, no GPU interaction, thread-safe
- ✅ `ConcavePolygonShape3D.new()` + `set_faces()` → CPU-only, BVH build, thread-safe

⚠ Web caveat: WASM threads have overhead vs native. Worker thread will be slower on web.
   Mitigation: Time-based budget auto-adapts. On web (slower), fewer chunks process per frame but no stutters.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Server API is lower-level, more code | ChunkRecord encapsulates all RID lifecycle. Unit-testable. |
| Worker thread deadlocks | Single producer/consumer with Mutex+Semaphore. Simple pattern. |
| RID leak on crash/error | ChunkRecord.free_rids() called in destructor AND on unload |
| LOD seams visible with async rebuild | Old mesh stays until new is ready. Swap is atomic. |
| Web thread slower | Time budget adapts. No fixed counts. |
| Foliage still uses nodes (MultiMeshInstance3D) | Phase 1 keeps foliage as-is. Phase 6 can migrate to Server API later. |
| Navmesh baking still expensive | Lazy navmesh (only LOD0). Can move to worker in future. |

## File Changes Preview

### New Files
- `scripts/world/chunk_record.gd` — ChunkRecord class (RefCounted, RID lifecycle)
- `scripts/world/chunk_worker.gd` — Worker thread (Semaphore + Mutex + build loop)
- `scripts/data/chunk_content_config.gd` — Data-driven content definitions (Phase 6)

### Modified Files
- `scripts/world/chunk_manager.gd` — 3-stage pipeline with time budget, ChunkRecord dict
- `scripts/world/terrain_mesh_builder.gd` — Unchanged (already uses pure array functions)
- `scripts/world/collision_generator.gd` — Unchanged (already pure data)
- `scripts/world/foliage_renderer.gd` — Eventually migrate MMI to RenderingServer (later phase)
- `scripts/world/terrain_chunk.gd` — **DELETED** (replaced by ChunkRecord)
- `scenes/world/terrain_chunk.tscn` — **DELETED** (no more per-chunk scene)

### Unchanged Files
- `scripts/world/world_data.gd` — Already has threaded loading (just remove sync fallback)
- `scripts/world/chunk_data.gd` — Pure data, unchanged
- `scripts/world/region_data.gd` — Pure data, unchanged
