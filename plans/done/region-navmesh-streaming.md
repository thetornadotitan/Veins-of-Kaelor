# Region-Based NavMesh Streaming Plan

## TL;DR

Switch from per-chunk (40m) to per-region (320m) navmesh baking and streaming. This reduces navmesh count from 16,384 to 1,024, eliminates the O(n^2) edge-connection cost that makes per-chunk regions pathological at scale, produces cleaner meshes with no chunk-boundary artifacts, and simplifies NPC pathfinding across long distances. The tradeoff is coarser load granularity (~128KB per region navmesh vs ~2KB per chunk), which is acceptable given navmeshes are compact.

## Current State

| Property | Value |
|----------|-------|
| Chunk size | 40m x 40m |
| Region size | 8x8 chunks = 320m x 320m |
| World size | 128x128 chunks = 5,120m x 5,120m |
| Current navmeshes | 16,384 (1 per chunk) |
| Current navmesh disk total | ~32.7 MB (~2 KB each) |
| Region data files | 256 (~463 KB each) |
| Load radius | 5 chunks (~200m) |
| Unload distance | 7 chunks (~280m) |
| Steady-state loaded chunks | ~121 |
| Steady-state loaded nav regions | ~4-9 |

## Why Per-Chunk Navmeshes Are a Problem

### 1. NavigationServer3D Edge Connection is O(free_edges^2)

This is the critical finding. From Godot source `nav_map_builder_3d.cpp:_build_step_edge_connection_margin_connections`:

```cpp
for (uint32_t i = 0; i < free_edges.size(); i++) {
    for (uint32_t j = 0; j < free_edges.size(); j++) {
        if (i == j || free_edge.polygon->owner == other_edge.polygon->owner)
            continue;
        // distance checks, projection math...
    }
}
```

This is a brute-force double loop. Every "free edge" (boundary edge not already merged with a same-region neighbor) is compared against every free edge from a *different* region. There is **no spatial index**.

Per-chunk navmeshes have **proportionally more boundary edges than interior polygons**. A 40m chunk navmesh might have ~200 polygons and ~60 free edges on its perimeter. With 16,384 regions, the free_edges array during sync can contain 100k+ entries, making this loop catastrophic.

Per-region (8x8) navmeshes have the same total polygon count, but 93.75% of what were inter-region boundary edges become **internal edges** that get merged in O(1) via HashMap lookup in `_build_step_merge_edge_connection_pairs`. Only the 4 edges of each 320m region boundary enter the O(n^2) loop.

**Evidence:** GitHub issue [#90623](https://github.com/godotengine/godot/issues/90623) explicitly warns that edge_connection_margin with many unmergeable edges becomes prohibitive.

### 2. Map Sync Rebuilds Scale With Region Count

`NavMap::_build_iteration()` iterates all enabled regions and copies their polygon data into the iteration buffer. Every `sync()` call (triggered by ANY region change -- load, unload, enable, disable, transform change) rebuilds the entire iteration.

With async iterations (default since Godot 4.3+, PR [#100497](https://github.com/godotengine/godot/pull/100497)), this work is offloaded to a thread. But the total work is still O(regions) + O(free_edges^2). During streaming, regions change frequently. Per-chunk = 121 regions changing during a 5-chunk-radius walk. Per-region = 4-9 regions.

**Evidence:** GitHub issue [#96483](https://github.com/godotengine/godot/issues/96483) reports sync as a bottleneck with many regions.

### 3. Chunk-Boundary Artifacts

Per-chunk baking with `border_size` produces overlapping edges between chunks. The border gives Recast neighbor data so edges *should* merge at runtime, but in practice:

- Tiny gaps appear where border_size was insufficient
- Polygons split oddly at chunk boundaries because the baker only sees one chunk's geometry
- Portals generate between chunks that could have been single polygons
- Extra triangles in border overlap zones

A region bake sees 320m x 320m of contiguous terrain at once. Interior chunk boundaries don't exist in the navmesh at all. The resulting mesh is structurally cleaner.

### 4. Per-Chunk Bake Overhead During World Generation

Recast has significant per-call overhead: voxelization setup, heightfield allocation, context initialization, region partitioning setup. Currently you're paying this 16,384 times. Per-region: 1,024 times. Same total world area, 16x fewer setup/teardown cycles.

Current `_bake_all_navmeshes()` in `world_generator.gd:179` already takes significant time. This improvement applies at generation time only, but reduces world generation from potentially 30-60 minutes to 10-30 minutes.

## Why Per-Region Navmeshes Work

### 1. Navmeshes Are Compact

Current per-chunk navmeshes average ~2 KB compressed. A 320m x 320m region navmesh would contain roughly 64x the polygon data of a chunk navmesh (same density, 64x area). Estimate:

- Per-chunk: ~200-800 polygons, ~2 KB
- Per-region: ~12,800-51,200 polygons, ~128 KB compressed

At steady state with ~4-9 regions loaded: ~0.5-1.2 MB of navmesh data in memory. This is trivial.

### 2. Streaming Is Still Easy

The streaming logic becomes simpler, not harder:

```
Player enters region (5,7):
  - Load terrain chunks around player (same as now)
  - Load nav_region_05_07.res

Player walks near edge of region:
  - Load nav_region_06_07.res
  - Unload nav_region_03_07.res when sufficiently far
```

Instead of managing 121 individual chunk navmeshes in/out, you manage 4-9 region navmeshes. Each region navmesh is loaded as a single `NavigationServer3D.region_create()` + `region_set_navigation_mesh()` call.

### 3. NPCs Pathfind Across Chunk Boundaries Seamlessly

Currently, an NPC crossing a chunk boundary must path across two navigation regions connected by edge_connection_margin links. These links are approximate and can produce suboptimal paths. With per-region navmeshes, an NPC stays on one navigation mesh for 320m before needing a region transition. Most NPC AI never leaves its current navigation region.

### 4. Industry Pattern Matches

| Engine | Navmesh Granularity | Notes |
|--------|---------------------|-------|
| Unreal | 128-512 Tu tiles | Navigation Invokers load tiles around actors |
| Unity | Scene-scale (hundreds of meters) | NavMeshBuildingComponents for streaming |
| Recast/Detour native | Configurable tiles, typically 32-128m | dtNavMesh tiles are moderate-sized |
| Our proposed | 320m per region | Matches industry range |

## Concerns and Counter-Evidence

### "Loading a larger navmesh will cause stutter"

Per-region navmeshes at ~128 KB compressed will load in ~0.5-2 ms from disk. This is comparable to current per-chunk navmesh loads (~0.1-1 ms each x 4-9 chunks at a time). The total is similar, but you do it 4-9 times instead of 121 times.

More importantly: you load a region navmesh **once when entering a region**, not every time you cross a chunk boundary. The amortized cost is lower.

### "Memory usage will spike"

4-9 regions at ~128 KB each = 0.5-1.2 MB. This is negligible. The terrain mesh and collision data for 121 chunks dwarfs this by orders of magnitude.

### "What if a region navmesh is too large for Recast to handle?"

320m x 320m at cell_size 0.25 = 1,280 x 1,280 cells. Recast handles this fine -- it's designed for meshes up to several thousand cells on each axis. The Recast demo handles 2,048 x 2,048+ cells. 1,280 x 1,280 is well within safe range.

### "We already have 16,384 per-chunk navmeshes baked"

We'd need to re-bake. But this is a one-time offline cost (estimated 10-30 minutes), and we already have a `rebuild_navmeshes()` function in `world_generator.gd:261`. The old `navmeshes/` directory gets replaced by a `nav_regions/` directory with 1,024 files.

### "Torus wrapping makes region boundaries wrap around"

Currently handled for terrain and data regions. Same logic applies: when the player is near the world edge, we load the wrapped region's navmesh just like we load wrapped terrain chunks. The `posmod` wrapping in `chunk_manager.gd` and `world_data.gd` already handles this.

## What This Does NOT Change

- Terrain still streams in 40m chunks (same as now)
- RegionData files stay the same (256 files, 8x8 chunks each)
- Collision still per-chunk (CollisionGenerator stays per-chunk)
- LOD system unchanged (terrain LOD per chunk)
- Foliage system unchanged (per-chunk)
- Only the **navigation mesh** moves from per-chunk to per-region

## Architecture After Change

### Separate Streaming Systems

```
Terrain Streaming (unchanged)
  40m chunks, load radius 5, unload distance 7
  Managed by ChunkManager

Navigation Streaming (new)
  320m regions, load when any chunk in region is loaded
  Unload when no chunk in region is within radius+buffer
  Managed by NavRegionManager (new class)
```

### New Files

| File | Purpose |
|------|---------|
| `scripts/world/nav_region_manager.gd` | Streams nav region .res files in/out as player moves |
| `scripts/world/nav_region_data.gd` | Resource subclass holding a pre-baked region NavigationMesh |

### Modified Files

| File | Change |
|------|--------|
| `scripts/world/navmesh_generator.gd` | Add region-level bake functions (bake all 64 chunks in a region as one navmesh) |
| `scripts/world/world_generator.gd` | Change `_bake_all_navmeshes()` from per-chunk to per-region baking |
| `scripts/world/chunk_manager.gd` | Remove per-chunk navmesh queue; delegate nav streaming to NavRegionManager |
| `scripts/world/chunk_record.gd` | Remove nav-related fields (nav_mesh, nav_region_rid, nav_mesh_rid, has_nav) |
| `scripts/world/world_data.gd` | Add nav region path helper, optional: threaded nav region loading |
| `data/worlds/{name}/world_meta.res` | No change (region_size already = 8) |

### Removed After Migration

- All 16,384 files in `data/worlds/{name}/navmeshes/` (replaced by 1,024 files in `nav_regions/`)
- Per-chunk nav fields in ChunkRecord
- Per-chunk nav queue in ChunkManager
- `NAVMESH_PER_FRAME` constant

## Implementation Phases

### Phase 1: Region-Level NavMesh Baking

Modify `NavMeshGenerator` and `WorldGenerator` to bake one navmesh per region (8x8 chunks) instead of per-chunk.

**Key change in NavMeshGenerator:**
- New `bake_region_navmesh(region: RegionData, world_name: String, rrx: int, rrz: int)` function
- Builds source geometry from all 64 chunk collision faces in the region, offset to world positions
- Single `filter_baking_aabb` covering the full 320m x 320m region
- `border_size` = chunk_size (40m) to handle region-boundary edge connections -- much smaller proportionally than per-chunk where border_size = chunk_size
- Saves as `nav_regions/nav_region_{rrx}_{rrz}.res`

**Key change in WorldGenerator:**
- Replace `_bake_all_navmeshes()` which iterates all chunks with a region-based loop
- 1,024 bakes instead of 16,384
- Should take ~8-16x less total time due to reduced per-call overhead
- Progress reporting remains the same

### Phase 2: NavRegionManager

New autoload or child node of ChunkManager that:

```gdscript
class_name NavRegionManager
extends Node

const NAV_UNLOAD_BUFFER: int = 2  # extra region-distance before unload

var _loaded_nav_regions: Dictionary = {}  # Vector2i -> NavRegionRecord
var _nav_map_rid: RID

func update_for_player_chunk(player_chunk: Vector2i, world_data: WorldData) -> void:
    # Determine which nav regions are needed
    # Load missing ones (ResourceLoader.load or load_threaded)
    # Unload distant ones

func get_nav_region_rid(region_key: Vector2i) -> RID:
    # Returns the NavigationServer3D region RID for a loaded nav region

func _load_nav_region(rrx: int, rrz: int) -> void:
    # Load .res, create NavigationServer3D.region, set navmesh

func _unload_nav_region(key: Vector2i) -> void:
    # Free NavigationServer3D.region RID
```

**Load triggering:** When `ChunkManager._update_loaded_chunks()` determines which chunks to load, it also notifies NavRegionManager which regions need navmeshes. NavRegionManager tracks which regions it has loaded and handles the rest.

**Unload logic:** Unload a nav region when no loaded chunk belongs to that region AND the player is > `NAV_UNLOAD_BUFFER` regions away.

### Phase 3: Modify ChunkManager

Remove all per-chunk nav code:

- Remove `_navmesh_queue`, `NAVMESH_PER_FRAME`, `_process_navmesh_queue()`, `_apply_navmesh_to_chunk()`
- Remove nav fields from `ChunkRecord` (nav_mesh, nav_region_rid, nav_mesh_rid, has_nav, remove_nav())
- Remove nav transform updates from `_refresh_chunk_positions()`
- Remove nav region RID creation from `_apply_load_result()`
- Add NavRegionManager child node, call its update in `_update_loaded_chunks()`

### Phase 4: Torus Wrapping for Nav Regions

Handle the case where the player is near the world edge and needs nav regions from the "other side" of the torus. This mirrors the existing chunk wrapping in `_chunk_to_nearest_world_position()`:

- When loading a wrapped nav region, set its `NavigationServer3D.region_set_transform()` to the wrapped position
- Same pattern as terrain chunk wrapping, just at region granularity

### Phase 5: NPC Pathfinding Across Regions

For NPCs that need to path beyond their current nav region:

- Two adjacent nav regions on the same `navigation_map` will auto-connect via `edge_connection_margin` (this is Godot's default behavior for regions on the same map)
- The O(free_edges^2) cost for 1,024 regions is manageable
- For very long paths, consider a hierarchical approach later (region-level graph on top of polygon-level A*) -- but this is an optimization, not a requirement

## Estimated Impact

| Metric | Before (Per-Chunk) | After (Per-Region) |
|--------|--------------------|--------------------|
| Navmesh files | 16,384 | 1,024 |
| Navmesh disk total | ~32.7 MB | ~33-40 MB (similar) |
| Nav region objects at steady state | ~121 | ~4-9 |
| Nav sync O(free_edges^2) input | ~6,000+ free edges | ~200-400 free edges |
| Edge-connection comparisons | ~18-36 million | ~40-160 thousand |
| Nav loaded per frame during streaming | 0-3 chunk navmeshes | 0-1 region navmesh |
| Nav transform updates per rewrap | 121 | 4-9 |
| NPC cross-boundary path quality | Degraded at chunk edges | Clean for 320m |
| World gen navmesh bake time | 30-60 min (estimated) | 10-30 min (estimated) |

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Region navmesh load stutter on first enter | Low | ~0.5-2ms per region; use `load_threaded_request()` like regions do |
| Recast fails on very flat/large regions | Low | 320m is well within Recast limits; fallback to per-chunk if bake fails for a specific region |
| Edge connections between regions still imperfect | Low | 16x fewer edges = 256x fewer comparisons; remaining edges are long straight region boundaries that connect cleanly |
| Memory spike loading 9 regions at startup | Negligible | ~1.2 MB total |
| Need to re-bake all navmeshes | One-time | `rebuild_navmeshes()` already exists; modify to use region baking |
| Web export size | Same | Total navmesh disk size is similar (~33 MB vs ~32.7 MB); on web this is in the .pck |

## What to Validate Before Implementing

1. **Bake a single 320m region navmesh in the editor** -- confirm Recast handles it without errors
2. **Measure bake time** for one region vs 64 chunks -- confirm the ~8-16x speedup estimate
3. **Measure load time** for one region .res file -- confirm <2ms
4. **Load 2 adjacent region navmeshes** on the same nav_map -- confirm edge_connection_margin connects them cleanly
5. **Path across 2 loaded region navmeshes** -- confirm NavigationServer3D.find_path() produces a correct cross-region path

## Key Evidence Sources

| Source | Key Finding |
|--------|-------------|
| Godot `nav_map_builder_3d.cpp` | Edge connection is O(free_edges^2) with no spatial index |
| GitHub #90623 | Explicit warning about edge_connection_margin with many small regions |
| GitHub #96483 | NavServer sync is bottleneck with many regions; PRs #100497 and #106670 mitigated but didn't eliminate the O(n^2) core |
| Unreal Navigation docs | Industry uses 128-512m nav tiles, not per-mesh-chunk |
| Recast/Detour source | Per-call overhead is significant; fewer bakes = less total time |
| Current project data | 16,384 navmeshes @ 2KB each = 32.7 MB; 256 regions @ 463KB each = 115.8 MB |
