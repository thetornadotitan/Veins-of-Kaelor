# Map Research Plan — Phase 2

## Research Sources

- `docs/last_research_save.md` — WebGL2 perf limits, LOD stitching, multi-layer noise, water rendering
- `docs/research-multimesh-foliage.md` — MultiMesh foliage architecture, instance budgets, entity spawning
- `docs/gdd/03-world-generation.md` — World gen goals, terrain features, water planes, biomes
- `docs/gdd/10-technical-architecture.md` — Architecture principles, web constraints, perf targets
- `docs/gdd/02-game-overview.md` — Game vision, web-first mandate

## Code References

- `scripts/world/heightmap_generator.gd` — single FBM pass, torus mapping (`heightmap_generator.gd:36-63`)
- `scripts/world/terrain_mesh_builder.gd` — LOD distances `[80, 240, INF]`, SurfaceTool mesh gen (`terrain_mesh_builder.gd:11`)
- `scripts/world/chunk_manager.gd` — load radius=3, LOD update loop (`chunk_manager.gd:4,164-178`)
- `scripts/world/terrain_chunk.gd` — LOD swap via rebuild mesh (`terrain_chunk.gd:57-64`)
- `scripts/world/chunk_data.gd` — CHUNK_SIZE=40, GRID_RESOLUTION=41 (`chunk_data.gd:5-6`)
- `scripts/data/noise_params.gd` — single FBM params, no multi-layer support (`noise_params.gd:5-13`)
- `data/world_gen_config.json` — current config: height_scale=4, octaves=4, persistence=0.5

---

## T1: World Size & View Distance (Question → Answer)

**Question:** Map is ~5km²? How far can view distance be pushed?

**Answer (from research):**
- Current world: 128×128 chunks × 40 units = 5120×5120 world units. At "1 unit ≈ 1 meter" this is ~26 km². At a tighter 2 units/m it's ~6.5 km². The actual scale is a design choice.
- Current LOD distances: `[80, 240, INF]` — LOD0 to 80m, LOD1 to 240m, LOD2 to infinity (`terrain_mesh_builder.gd:11`)
- Current LOAD_RADIUS: 3 chunks = ~120m visible radius (`chunk_manager.gd:4`)
- **Web triangle budget for terrain alone:** 50K-150K tris in view at once
- 33×33 chunk at LOD0: ~2304 tris. 41×41 grid = 3200 tris per chunk at LOD0
- 9 chunks (3×3) at LOD0: ~28,800 tris — only 10-20% of web budget
- **Can increase view distance significantly.** At current LOD0 density (3200 tris/chunk), you can show ~16 chunks (4×4) in LOD0 for ~51K tris, plus an outer ring at LOD1/2
- Recommended: increase LOAD_RADIUS to 5 (~200m radius), LOD distances to `[100, 300, 600, INF]` (4 tiers)
- At radius 5: ~25 chunks nearest at LOD0 = ~80K tris + outer ring LOD1/2 = ~30K tris = ~110K total — comfortably under 150K
- **Constraint:** draw calls. Each chunk = 1 draw call. 25 chunks = 25 draw calls. Fine for web (target <300).

**Implementation:** Increase `LOAD_RADIUS`, extend `LOD_DISTANCES` array, tune per web profiling.

---

## T2: Terrain LOD View Distance Increase (Requested)

**Goal:** Push terrain view distance on web given low resolution of detail.

**Findings:**
- Current terrain uses vertex-colored `StandardMaterial3D` (no textures) — minimal fill rate
- Each chunk is a single draw call regardless of LOD level — not draw-call bound
- The bottleneck is vertex count, and current budget leaves massive headroom
- LOD2 at 240m+ still renders full detail for distant chunks — wasteful
- Adding LOD3/LOD4 tiers with aggressive decimation would cut distant tri counts dramatically

**Plan:**
1. Extend `LOD_DISTANCES` from `[80, 240, INF]` to `[80, 200, 400, 700, INF]` — 5 LOD tiers
2. Each LOD step halves the grid: spacing = `1 << lod` (already implemented `terrain_mesh_builder.gd:26`)
3. At LOD4 spacing=16: 41→~2.5 vertices per axis ≈ very few tris for far chunks
4. Increase `LOAD_RADIUS` from 3 to 5 (or 6 with profiling)
5. LOD selection stays distance-based (`chunk_manager.gd:164-178`), just more tiers
6. **Web budget check:** ~36 chunks (6×6) at mixed LOD ≈ 60-80K tris — safe

**Also investigate:** Can we skip mesh rebuild on LOD change? Pre-build all LOD meshes at chunk load and swap via `MeshInstance3D.mesh` reference (already done but triggered per-frame — cache them).

---

## T3: MultiMesh Foliage / Towns / Monster Spawns Feasibility (Question → Answer)

**Question:** Is mesh-instance foliage, towns, monster spawns feasible on web? Can it load from data fast enough?

**Answer: Yes, with the right architecture.**

**Foliage (MultiMesh):**
- Per 40×40 chunk on web: ~1,500 grass cards (4-tri), ~30 bushes (50-100 tri), ~10 trees (200 tri)
- One `MultiMeshInstance3D` per chunk per foliage type = 1 draw call each
- 9 visible chunks × 3 foliage types = 27 draw calls — well within web budget
- Total grass tris: 9 × 1500 × 4 = 54K. Trees: 9 × 10 × 200 = 18K. Total: ~80K — acceptable
- Data-driven: foliage positions stored per chunk in `RegionData`, populated into `MultiMesh` at load time
- Bulk upload via `RenderingServer.multimesh_set_buffer()` or `MultiMesh.buffer` PackedFloat32Array
- Pool `MultiMeshInstance3D` nodes — reset `visible_instance_count` on unload, repopulate on load
- Set `custom_aabb` per chunk for engine frustum culling

**Towns/Buildings (PackedScene instances):**
- Static, no animation needed — instance `PackedScene` per building from chunk data
- Pool building nodes: hide/unhide rather than free/allocate
- Use `VisibilityRange` (HLOD) for distant buildings → billboard imposter
- Budget: ~5-10 buildings per chunk in town areas, 0 in wilderness
- Draw calls: each unique building = 1 draw call. With material reuse, keep under 50 active

**Monster Spawns (entity nodes):**
- Dynamic, need AI/physics — must be real `CharacterBody3D` nodes
- Pool mobs: pre-allocate per type, `process_mode = DISABLED` when off-screen
- Budget: max ~10 active mobs per chunk, ~90 total visible — web CPU-bound limit
- Store spawn data per chunk: `{type, position, patrol_route}`
- On load: acquire from pool, place, enable. On unload: persist state, release to pool
- `process_mode = DISABLED` for mobs beyond ~2 chunks — critical for web CPU

**Loading speed:**
- MultiMesh buffer upload is O(N) — ~1,500 instances × 12 floats = 18KB per chunk, trivial
- PackedScene instancing: ~5-10 scenes per chunk, fast
- Mob spawning: deferred over a few frames to avoid hitching

**Architecture (fits existing code):**
```
ChunkManager._load_chunk()
  → load terrain (existing)
  → FoliageRenderer.populate(chunk_pos, foliage_data)
  → BuildingSpawner.populate(chunk_pos, building_data)
  → EntitySpawner.populate(chunk_pos, entity_data)  # staggered
```

---

## T4: LOD Seam Elimination via Border-LOD0 Ring (Requested)

**Goal:** Force chunk border vertices to always render at LOD0 so all stitches are perfect. Interior verts match chunk LOD.

**Research conclusion (from `last_research_save.md:222-299`):**
- "Border Always LOD0" approach: every chunk's outermost row/column of vertices stays at full LOD0 density regardless of the chunk's LOD level
- Interior vertices simplify freely per LOD
- Adjacent chunks always share the same border vertex positions → no T-junctions, no cracks, perfect seams by construction
- 20-40% more vertices per chunk vs free simplification, but eliminates ALL seam artifacts

**Implementation changes to `terrain_mesh_builder.gd`:**

Current mesh gen iterates `range(0, resolution-1, spacing)` uniformly. New approach:
1. Generate the border ring separately — iterate lx/lz at spacing=1 for border rows/columns
2. Generate the interior at the chunk's LOD spacing
3. Connect border ring to interior with filler triangles at the boundary
4. Add a 1-vertex skirt (duplicate border verts, offset Y downward) as safety net against sub-pixel cracks

**Impact analysis:**
- **Vertex cost:** At LOD0, overhead is 0 (border IS the edge). At LOD2 (spacing=4): border ring adds 4×40 = 160 verts vs ~100 interior verts ≈ +160% vertices, but the chunk total is still tiny (820×2 tris = 1640)
- **No index buffer variants needed** — each LOD level still has one fixed index pattern
- **Eliminates need for:** stitch strips, neighbor LOD tracking, crack-filling geometry
- **Interaction with other tasks:**
  - T2 (view distance increase): More LOD tiers = more seam boundaries = more value from border-ring
  - T5 (multi-layer noise): No interaction — noise affects heightmap values, not mesh topology
  - T3 (foliage): No interaction — foliage sits on terrain independently
  - T6 (water): Border ring ensures terrain mesh is watertight at all LOD levels — helps prevent water clipping through seam cracks

**Also add:** Spatial geomorphing for interior vertices — store both `z_fine` and `z_coarse` in vertex data via `ARRAY_CUSTOM0`, blend in vertex shader based on distance. Eliminates LOD pop. Not viable for web vertex texture fetches, so bake both heights into vertex attributes.

---

## T5: Multi-Layer Noise for Varied Terrain (Requested)

**Goal:** Mountains, plains, valleys, fine details. Current: smooth small hills from single FBM.

**Problem:** `heightmap_generator.gd:46-61` uses a single `noise_4d_fbm()` call with persistence=0.5, producing uniform rolling hills.

**Recommended approach — 5-layer composition:**

```
Layer 1: Continental       — low freq, 2 oct, shapes landmass variation
Layer 2: Mountain mask     — medium freq, 2 oct, determines WHERE mountains appear
Layer 3: Mountain ridges   — ridged multifractal, 6-8 oct, sharp peaks
Layer 4: Plains/hills      — standard FBM, 4 oct, low persistence = gentle
Layer 5: Detail            — high freq, 2 oct, bumps and texture
```

**Composition formula:**
```gdscript
var continental = fbm(nx, ny, nz, nw, 2, continental_freq, 0.5, 2.0)
var mountain_mask = fbm(nx+offset, ny+offset, nz+offset, nw+offset, 2, mask_freq, 0.5, 2.0)
mountain_mask = smoothstep(0.3, 0.7, mountain_mask * 0.5 + 0.5)
var mountains = ridged_fbm(nx, ny, nz, nw, 6, mountain_freq, 0.55, 2.2)
var plains = fbm(nx, ny, nz, nw, 4, plain_freq, 0.35, 2.0)
var elevation = lerp(plains, mountains, mountain_mask) + 0.3 * continental
var detail = fbm(nx+off2, ny+off2, nz+off2, nw+off2, 2, detail_freq, 0.3, 2.5)
elevation += detail * 0.1
elevation = pow(max(0, elevation), 2.5)  # flatten valleys, sharpen peaks
```

**Frequency calibration for 4D torus (world_size=5120):**
- Continental freq: ~2.5 (features ~2000 units wide)
- Mountain mask freq: ~5.0
- Mountain ridge freq: ~10.0 (features ~500 units wide)
- Plains freq: ~8.0
- Detail freq: ~200.0 (features ~25 units wide)

Current `height_scale=4.0` is the frequency sent to `noise_4d_fbm`. This only produces continental-scale variation on a torus of radius 1.0. The multi-layer approach uses appropriate frequencies for each feature scale.

**Required code changes:**
1. Add `ridged_fbm()` to `simplex_noise_4d.gd` / native extension (1.0 - abs(noise), weighted octave accumulation)
2. Expand `NoiseParams` to include per-layer parameters: continental, mountain_mask, mountain, plains, detail
3. Rewrite `HeightmapGenerator.generate_chunk_heightmap()` to compose layers instead of single FBM
4. Optionally add `smoothstep` helper and ` pow()` redistribution
5. Update `world_gen_config.json` and `WorldGenConfig` with new parameters
6. All layers share the same torus mapping `(nx, ny, nz, nw)` — use large offsets to differentiate seeds

**Optional enhancement:** Runevision pseudo-erosion filter (point-evaluable, works with 4D torus) for realistic gullies and ridges. Add as post-process on the heightmap after layer composition.

**Impact on other tasks:**
- T6 (water): Higher mountains and deeper valleys make water level more visually important — water in valleys between mountains
- T4 (seams): Multi-layer noise doesn't change mesh topology, just heightmap values. No interaction.
- T3 (foliage): Mountain mask can double as foliage type selector — no trees above treeline, grass on plains, dense forest in valleys

---

## T6: Water Plane with Shaders, Swimming, and Terrain Clipping Prevention (Requested)

**Goal:** Water plane at water_level, wave displacement shader, no clipping under ground, player swimming.

**Approach: Depth-based water shader on a flat plane**

**Rendering:**
1. `MeshInstance3D` with `PlaneMesh` at Y=water_level, sized to cover terrain area
2. Custom `ShaderMaterial` with `hint_depth_texture` for terrain masking
3. Vertex shader: Gerstner waves or simple sine wave displacement (3-4 wave components)
4. Fragment shader:
   - Reconstruct scene depth from `depth_texture` (Compatibility NDC: `vec3(SCREEN_UV, depth) * 2.0 - 1.0`)
   - Compare scene depth vs water depth → `water_thickness`
   - If `water_thickness < 0`: terrain is above water → `ALPHA = 0.0` (no water visible)
   - Depth-based color: `mix(shallow_color, deep_color, depth_factor)`
   - Foam at edges: high alpha where `water_thickness < foam_threshold`
   - Scrolling normal maps (2 layers) for surface detail
5. Render mode: `cull_disabled, depth_draw_always, blend_mix`

**Terrain interaction (no clipping):**
- The depth buffer approach automatically handles this: wherever terrain geometry is above water_level, `water_thickness < 0` and water is invisible
- Works for any terrain shape — hills, mountains, valleys — no heightmap lookup needed
- Must use `CURRENT_RENDERER == RENDERER_COMPATIBILITY` branch for correct NDC depth reconstruction
- Add `edge_fade` via `smoothstep(0.0, fade_distance, water_thickness)` for soft shoreline transition

**Swimming:**
1. Simple Y-position check: `is_swimming = global_position.y < water_level`
2. When swimming: apply buoyancy (`velocity.y += buoyancy * delta`), water drag (`velocity *= 1.0 - drag * delta`), reduced gravity
3. Allow vertical movement: jump = swim up, crouch = swim down
4. Switch `motion_mode` to `MOTION_MODE_FLOATING` when submerged
5. Optional: `Area3D` with `BoxShape3D` at water_level for `body_entered`/`body_exited` signals

**Performance for web:**
- Vertex waves: GPU-side, very cheap (3-4 sin calls per vertex)
- Depth texture read: 1 sample per fragment, standard cost
- Scrolling normal maps: 2 texture samples per fragment, moderate cost
- No SSR, no compute, no tessellation — all Compatibility-safe
- PlaneMesh subdivision: 64×64 or 128×128 is enough for wave detail
- Consider: only render water plane around active chunks, not the full world

**Implementation plan:**
1. Create `scripts/world/water_plane.gd` — manages water MeshInstance3D, follows player
2. Create `assets/shaders/water.gdshader` — depth-based water with waves, color, foam
3. Add water_level to `WorldMeta` / `WorldData` (already in `NoiseParams` at `water_level=8.0`)
4. Modify player controller to detect and handle swimming state
5. Water plane follows camera XZ position, sized to visible chunk area + margin

**Interaction with other tasks:**
- T5 (multi-layer noise): With varied terrain, water fills valleys naturally. The mountain mask layer creates natural coastlines and lake basins
- T4 (border ring): Watertight terrain mesh at all LODs prevents water infiltrating through seam cracks
- T2 (view distance): Water plane needs to match terrain view distance — clip or fade water beyond loaded chunks
- GDD `03-world-generation.md:61`: "Water planes at configurable sea level" — this implements that

---

## Task Dependency Graph

```
T5 (multi-layer noise) ─── independent, do first (affects terrain heightmap data)
  ↓
T4 (border LOD0 ring) ─── depends on terrain mesh builder, independent of noise
  ↓
T2 (view distance increase) ─── depends on T4 (more LOD tiers = more seams to fix)
  ↓
T6 (water plane) ─── benefits from T5 (varied terrain makes water meaningful) and T4 (seam-tight mesh)
  ↓
T3 (foliage/entity spawning) ─── depends on terrain heightmap for placement, independent of rendering changes
```

T1 is a question with a direct answer — no implementation needed.

T5 and T4 can be done in parallel (noise affects values; border ring affects topology).

---

## Implementation Priority

1. **T5** — Multi-layer noise. Everything else benefits from better terrain. Changes `heightmap_generator.gd` and `noise_params.gd`. Regenerate world data after.
2. **T4** — Border LOD0 ring. Changes `terrain_mesh_builder.gd`. Must be done before extending LOD tiers.
3. **T2** — View distance increase. Changes `terrain_mesh_builder.gd` LOD_DISTANCES, `chunk_manager.gd` LOAD_RADIUS. Profile on web after.
4. **T6** — Water plane. New files + player controller changes. Can start in parallel with T4.
5. **T3** — Foliage/entity spawning. Largest scope, depends on terrain being finalized. New subsystems.

---

## Open Questions (Not Implementation)

| ID | Question | Answer |
|----|----------|--------|
| Q1 | Is the map ~5km²? | 128×128 chunks × 40 units. If 1unit=1m: 5.12km×5.12km = 26.2km². If 2units=1m: 2.56km×2.56km = 6.5km². Scale is a design choice. |
| Q2 | How far can view distance be pushed? | With current low-poly terrain: ~200-300m radius comfortably on web with 4-5 LOD tiers. Triangle budget allows ~150K tris for terrain + props. |
| Q3 | Is MultiMesh foliage feasible on web? | Yes. ~1,500 grass + 30 bushes + 10 trees per 40×40 chunk. 9 chunks visible = 27 draw calls for foliage. Well within web budget. |
| Q4 | Is data-driven entity spawning feasible on web? | Yes. Pool PackedScene instances, DISABLED process for off-screen mobs. Max ~90 active mobs visible. Stagger loading over frames. |
