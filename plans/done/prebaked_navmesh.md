# Pre-Baked NavMesh at Generation Time

## TL;DR

**Yes, this is possible and already partially implemented.** The runtime code already tries `load_cached_navmesh()` before falling back to baking. The missing piece: `WorldGenerator.generate_world()` doesn't bake navmeshes during world generation. Adding that step eliminates runtime navmesh baking entirely for pre-generated worlds — saving **4-65ms per chunk**, the single largest remaining stutter source.

## Proof That Pre-Baked NavigationMesh Loads Correctly

### Godot 4.x NavigationMesh Serialization

1. **`NavigationMesh` extends `Resource`** — it inherits `ResourceSaver.save()` / `ResourceLoader.load()` support natively.
2. **Baked data is stored as PackedArrays** — `get_vertices()` returns `PackedVector3Array`, `get_polygons()` returns `PackedInt32Array`. These are primitive types that serialize perfectly via Godot's resource system.
3. **`ResourceSaver.FLAG_COMPRESS`** produces a `.res` binary — smaller and faster to load than `.tres` text format.
4. **Already proven in our own codebase**: `NavMeshGenerator.bake_and_save_navmesh()` saves with `ResourceSaver.save(navmesh, path, ResourceSaver.FLAG_COMPRESS)` and `NavMeshGenerator.load_cached_navmesh()` loads with `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)`. This round-trips correctly.
5. **Godot's own navigation demo does this** — the official "Navigation Mesh Chunks" demo saves baked navmeshes per chunk and loads them at runtime.

### Key Constraint: No Scene Tree Required

Our `NavMeshGenerator.bake_and_save_navmesh()` uses `NavigationServer3D.bake_from_source_geometry_data()` with `NavigationMeshSourceGeometryData3D.add_faces()` — this is the **headless path**. It does NOT require a `StaticBody3D` in the scene tree. This means it works perfectly during world generation in the editor, outside of gameplay.

## Performance Analysis

### Current State (Runtime Baking)

| Step | Time | Notes |
|------|------|-------|
| `build_collision_faces()` | ~0.1ms | Reuses existing collision data |
| `add_faces()` + source geometry | ~0.01ms | Trivial |
| `bake_from_source_geometry_data()` | **4-65ms** | Recast detour, bounded by chunk complexity |
| Total per chunk | **4-65ms** | Unbounded, unpredictable |

For 225 spawn chunks, worst case: 225 × 65ms = ~14.6 seconds of staggered stutter during LOADING phase. Even with budget-gating (8ms nav budget during loading, 2ms during play), this is the dominant frame-time consumer.

### After Pre-Baking (Disk Load)

| Step | Time | Notes |
|------|------|-------|
| `ResourceLoader.load(.res compressed)` | **0.1-1ms** | Binary deserialization of PackedArrays |
| `region_set_navigation_mesh()` | ~0.01ms | Server API, no scene tree |
| Total per chunk | **~0.1-1ms** | Predictable, deterministic |

**Speedup: 10-500x per chunk.** For 225 spawn chunks: ~0.2-1.1 seconds total navmesh time vs ~14.6 seconds worst case.

### Will This Eliminate the Stutter?

**Yes, substantially:**

- During **LOADING phase**: Navmesh goes from being the single biggest time sink (4-65ms/chunk) to trivial disk I/O (~0.1-1ms/chunk). The 8ms `NAV_BUDGET_LOAD_USEC` can process many more chunks per frame, meaning spawn area becomes ready much faster.
- During **PLAYING phase**: Navmesh goes from "must budget-gate 4-65ms bakes to idle frames" to "sub-millisecond loads that fit within any frame budget." The 2ms `NAV_BUDGET_PLAY_USEC` becomes generous enough to process multiple navmeshes per frame without stutter.
- **Runtime bake becomes a fallback only** — only fires if the cache file is missing (e.g., dev testing, generated world with missing navmeshes, or deliberately truncated export).

### Remaining Stutter Sources After This Change

| Source | Time | Status |
|--------|------|--------|
| ~~Navmesh bake~~ | ~~4-65ms~~ | **Eliminated** → ~0.1-1ms disk load |
| Worker mesh build | 2-8ms | Off-thread (no stutter) |
| Render apply (instance_set_base) | 0.01-0.1ms | Already fast |
| Collision body creation | ~2ms | Deferred + budget-gated |
| Region data loading | 5-50ms | Threaded (no stutter) |

**Navmesh was the last unbounded synchronous operation on the main thread.** After pre-baking, all remaining work is either off-thread, sub-millisecond, or budget-gated with small worst-case bounds.

## Implementation Plan

### Phase 1: Add NavMesh Baking to World Generation

**File: `scripts/world/world_generator.gd`**

Add a navmesh bake pass after region generation:

```
generate_world():
  1. For each region (existing loop):
     - Generate heightmaps → save region.res (unchanged)
  2. NEW: After all regions saved:
     - Create navmeshes/ directory
     - For each region:
       - Load region.res back
       - For each chunk in region:
         - Build ChunkData from region
         - Call NavMeshGenerator.bake_and_save_navmesh()
       - Free region reference
     - Emit progress per chunk
```

This runs in the editor during world generation. Could take 15-60 minutes for a 128×128 world (16384 chunks × 4-65ms each), but that's a **one-time cost** at generation time, not at runtime.

**Progress reporting**: Add a second progress phase (0-100% for regions, then 0-100% for navmeshes).

### Phase 2: Simplify Runtime NavMesh Path in ChunkManager

Now that navmeshes are guaranteed to exist at generation time:

1. **Remove runtime bake from hot path** — `_process_navmesh_queue()` should only try `load_cached_navmesh()`. If it returns null, chunk stays in queue for retry (not bake).
2. **Remove `_nav_bake_pending` and `_finish_navmesh_bake()`** — these exist solely for deferred runtime baking. No longer needed.
3. **Increase `NAVMESH_PER_FRAME`** — since disk loads are ~0.1-1ms, we can process multiple per frame. Change from 1 to `max(3, budget_allows)` or remove the cap entirely and rely on budget alone.
4. **Reduce or remove `NAV_BUDGET_*_USEC` constants** — disk loads are fast enough that these become less critical. Could simplify to a single `NAV_BUDGET_USEC = 4000`.
5. **Remove `bake_navmesh_runtime()` from `NavMeshGenerator`** — dead code after this change.
6. **Remove `PLAY_NAV_BAKE_FRAME_HEADROOM_USEC`** — was specifically for gating bake starts.

### Phase 3: Optional — Editor Tool for Re-Baking

Add a button in `WorldEditorUI` to re-bake navmeshes for an existing world (e.g., after changing agent parameters). This would:
1. Delete existing `navmeshes/` directory
2. Iterate all regions/chunks and re-bake with current agent settings
3. Useful if `AGENT_RADIUS`, `AGENT_HEIGHT`, etc. change after world generation

### Phase 4: Verify — No Web Pitfalls

The navmesh `.res` files live under `res://data/worlds/`. On web exports:
- Godot packs `res://` into the `.pck` file — navmesh files will be included automatically.
- `ResourceLoader.exists()` and `ResourceLoader.load()` work on `.pck` contents.
- No special handling needed for web.

**However**: If the world is too large, the `.pck` could grow significantly. A 128×128 world = 16384 navmesh files. Estimated at ~5-15KB each compressed, that's ~80-245MB added to the export. This is worth testing. If size is a concern, navmeshes could be excluded from export and downloaded on-demand, but that's a future optimization.

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| Navmesh time per chunk (runtime) | 4-65ms (bake) | 0.1-1ms (load) |
| Navmesh time for 225 spawn chunks | ~1-14.6s staggered | ~0.2-1.1s total |
| Frame stutter from navmesh during PLAYING | Yes (4-65ms spikes) | No (sub-ms) |
| Main thread blocking from navmesh | Unbounded | ~1ms max |
| Export size increase | N/A | ~80-245MB for 128×128 world |
| World generation time increase | N/A | +15-60 min one-time |
| Runtime bake code path | Primary | Fallback only |

## Risks & Mitigations

1. **Large export size**: 80-245MB of navmesh data per world. Mitigation: compressed `.res` is efficient; could add lazy download for web.
2. **Stale navmeshes**: If agent params change but navmeshes aren't re-baked. Mitigation: store agent params in `world_meta.res`, validate on load, add re-bake button.
3. **Missing navmesh files**: Corrupted/incomplete generation. Mitigation: keep runtime bake as fallback (just not on the hot path).
4. **Generation time**: Adding 15-60 minutes to world generation. Mitigation: progress bar, cancellable, runs once.
