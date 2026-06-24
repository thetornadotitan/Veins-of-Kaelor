# Godot 4 MultiMesh Foliage/Grass/Prop Rendering Research

## 1. How MultiMesh Works in Godot 4

**Core mechanism:** MultiMesh draws a single mesh N times using **GPU hardware instancing** - one draw call for all instances. Each instance has per-instance data: Transform3D (12 floats), optional Color (4 floats), optional Custom Data (4 floats via `INSTANCE_CUSTOM` in shaders).

**Key properties:**
- `instance_count` — total allocated instances (resizes buffer, clears data)
- `visible_instance_count` — how many to actually draw (-1 = all)
- `transform_format` — TRANSFORM_2D or TRANSFORM_3D
- `use_colors` / `use_custom_data` — must be set BEFORE setting instance_count
- `custom_aabb` — manually set AABB to avoid costly runtime recalculation

**Performance characteristics:**
- Single draw call for thousands to millions of instances
- No per-instance frustum culling (all-or-none visibility for the whole MultiMesh)
- No blend shapes support
- All instances share the same max-lights-per-object limit
- Compatible with automatic mesh LOD (but LOD level is per-node, not per-instance)
- `visible_instance_count` can be changed per-frame without reallocating

**For web (WebGL2/Compatibility renderer):**
- Colors and custom data are packed to 16-bit (vs 32-bit on Forward+/Mobile)
- Reduced precision may cause visual banding on colors

---

## 2. WebGL2 Instance Limits & Performance

**Web constraints:**
- Godot 4 web exports use **Compatibility rendering method only** (WebGL2)
- WebAssembly instead of native code = ~2-5x CPU performance penalty
- Single-threaded export is default (no SharedArrayBuffer headaches)
- WebGL2 maps to OpenGL ES 3.0 feature set

**Concrete numbers (community benchmarks + official docs):**

| Instance Count | Mesh Complexity | Platform | Expected FPS |
|---|---|---|---|
| 1,000-5,000 | 4-8 triangles (grass card) | Native | 60+ |
| 10,000-50,000 | 4-8 triangles (grass card) | Native | 60+ |
| 100,000+ | 4-8 triangles (grass card) | Native | 30-60 (GPU dependent) |
| 1,000 | 4-8 triangles | Web | 60 |
| 5,000-10,000 | 4-8 triangles | Web | 30-60 |
| 20,000-30,000 | 4-8 triangles | Web | 20-40 on mid-range |
| 1,000-2,000 | 50-200 triangles (bush/tree) | Web | 30-60 |
| 10,000+ | 200+ triangles | Web | < 20 (avoid) |

**Web-specific bottlenecks:**
- WebGL2 instanced arrays have driver-dependent limits
- OpenGL ES 3.0 guarantees `MAX_ARRAY_LAYERS` but actual instancing throughput varies by GPU/browser
- Chrome typically outperforms Firefox/Safari for WebGL2 instancing
- Mobile WebGL2: cut above numbers by ~50-70%
- The main bottleneck on web is usually **fill rate** (overdraw from grass cards), not instance count

**Recommendation for web:** Stay under **10,000-15,000 grass instances** and under **2,000-3,000 tree/bush instances** per visible frame. Use aggressive culling and LOD.

---

## 3. Data-Driven Foliage Position Loading

**Standard approach:**

```
Chunk Data (JSON/binary) → Parse → Populate MultiMesh → Render
```

**Data format options:**
1. **JSON per chunk** — easy to edit, slow to parse for large datasets
2. **Binary format** — fast loading, compact (e.g., each instance = 12 floats for Transform3D)
3. **Procedural from seed** — store seed per chunk, generate positions at load time using noise/random

**Typical workflow:**
```gdscript
func load_chunk_foliage(chunk_data: Dictionary):
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true           # for variation
    mm.use_custom_data = true       # for wind/animation phase
    mm.mesh = grass_mesh
    mm.instance_count = len(chunk_data.positions)
    
    for i in range(mm.instance_count):
        var pos = chunk_data.positions[i]
        var t = Transform3D(
            Basis(Vector3.UP, chunk_data.rotations[i]).scaled(chunk_data.scales[i]),
            pos
        )
        mm.set_instance_transform(i, t)
        mm.set_instance_color(i, chunk_data.colors[i])
        mm.set_instance_custom_data(i, Color(randf(), randf(), 0, 0))
    
    mm.custom_aabb = chunk_aabb  # CRITICAL: set manually
    $MultiMeshInstance3D.multimesh = mm
```

**Loading optimizations:**
- Use `RenderingServer.multimesh_set_buffer()` to set all transforms in one call from a PackedFloat32Array
- Pre-compute transforms during world generation, store as raw float arrays
- Load chunk data on background thread (Threaded loading), apply to MultiMesh on main thread
- Pool MultiMeshInstance3D nodes — don't free/allocate per chunk

---

## 4. Per-Chunk Data-Driven Foliage Architecture

**Recommended architecture:**

```
WorldManager
├── ChunkManager (loads/unloads chunks based on player position)
│   ├── Chunk[(x,z)] — data container, loaded from file or generated
│   │   ├── terrain_heightmap
│   │   ├── foliage_data: {grass:[], bushes:[], trees:[], props:[]}
│   │   └── entity_data: {monsters:[], npcs:[], buildings:[]}
│   └── FoliageRenderer — manages MultiMeshInstance3D pool
│       ├── grass_mmi_pool: [MultiMeshInstance3D]  (pre-allocated)
│       ├── bush_mmi_pool: [MultiMeshInstance3D]
│       └── tree_mmi_pool: [MultiMeshInstance3D]
```

**Key design decisions:**
- **One MultiMeshInstance3D per chunk per foliage type** (e.g., chunk_0_0 has its own grass MM, bush MM, tree MM)
- Pre-allocate MultiMeshInstance3D nodes in a pool, reuse them
- When a chunk loads: populate its pooled MMIs from data
- When a chunk unloads: reset `visible_instance_count = 0` and return to pool (don't free)
- Set `custom_aabb` per chunk so the engine can frustum-cull entire chunks

**Buffer approach (fastest):**
```gdscript
# Pre-build the raw float buffer, then set all at once
var buffer = PackedFloat32Array()
buffer.resize(instance_count * 12)  # 12 floats per Transform3D
for i in range(instance_count):
    var offset = i * 12
    # Basis rows + origin (3x vec3 + vec3)
    buffer[offset]      = basis.xx  # etc.
    ...
mm.buffer = buffer  # One-call upload
```

**GDExtension/C++ option:** For truly massive counts (100k+), use `RenderingServer.multimesh_set_buffer()` from C++ with multi-threaded buffer construction.

---

## 5. Per-Chunk Culling of MultiMesh Instances

**Yes, this is the recommended approach.** Since individual instances within a MultiMesh cannot be frustum-culled, the solution is **one MultiMeshInstance3D per chunk**.

**Methods:**

1. **Show/Hide entire MultiMeshInstance3D node** — simplest, works with engine culling
   ```gdscript
   $ChunkGrassMMI.visible = is_chunk_in_frustum
   ```

2. **`visible_instance_count`** — keep data loaded but don't draw
   ```gdscript
   mm.visible_instance_count = 0  # hidden
   mm.visible_instance_count = actual_count  # shown
   ```

3. **Move out of frustum** — move the node's position far away (hack, not recommended)

4. **custom_aabb** — set the AABB to match the chunk bounds so the engine's built-in frustum culling handles it
   ```gdscript
   mm.custom_aabb = AABB(chunk_origin, chunk_size_vector)
   ```

**Best practice:** Use one MultiMeshInstance3D per chunk, set `custom_aabb` to chunk bounds, and let the engine's frustum culling handle visibility automatically. This gives you per-chunk culling for free.

**For occlusion culling:** Each MultiMeshInstance3D participates in occlusion culling as a single object. This works if chunks behind terrain/mountains are culled.

---

## 6. LOD for Foliage

**Method 1: Automatic Mesh LOD (Godot 4 built-in)**
- Works with MultiMeshInstance3D (since 4.x)
- Uses meshoptimizer for automatic mesh decimation
- All instances in a MultiMesh use the same LOD level (determined by node AABB closest point to camera)
- Good for trees/bushes where mesh detail matters at distance
- Configure via `Rendering > Mesh LOD > LOD Change > Threshold Pixels`

**Method 2: Visibility Ranges (HLOD)**
- Set up multiple MultiMeshInstance3D nodes per chunk:
  - Near: high-detail grass mesh (individual blades)
  - Mid: simplified grass mesh (fewer blades per cluster)
  - Far: texture billboard or nothing
- Use `visibility_range_begin` / `visibility_range_end` + fade modes
- Can use `visibility_parent` for hierarchical LOD

**Method 3: Shader-based LOD (most control)**
```glsl
// In vertex shader, use INSTANCE_CUSTOM.x as distance phase
// Phase 0: full mesh, Phase 1: simplified, Phase 2: discard
float dist = distance(VERTEX + INSTANCE_CUSTOM.xyz, camera_position);
if (dist > far_threshold) {
    // Collapse vertices to simplified positions
    VERTEX = mix(VERTEX, simplified_pos, step(simplify_threshold, dist));
}
```

**Method 4: Dither-based fade out**
- Use `BaseMaterial3D.distance_fade = DISTANCE_FADE_OBJECT_DITHER`
- Set `distance_fade_max_distance` / `distance_fade_min_distance`
- Dithering avoids alpha-blend transparency sorting issues
- More performant than alpha fade

**Recommended LOD tiers for grass/foliage:**
| Distance | LOD Level | Approach |
|---|---|---|
| 0-20 units | Full grass mesh | MultiMesh with individual blades (4-8 tris each) |
| 20-50 units | Cluster mesh | MultiMesh with grass clump mesh (12-20 tris) |
| 50-100 units | Billboard | Sprite3D or camera-facing quad (2 tris) |
| 100+ units | Fade out | Dither fade to nothing |

---

## 7. Billboard Imposters for Distant Foliage

**Option A: Sprite3D / AnimatedSprite3D as imposter**
- Replace distant tree MeshInstance3D with Sprite3D
- Use Visibility Ranges to swap
- Render tree from multiple angles to a texture atlas at build time
- Select correct angle frame in shader based on camera direction

**Option B: Shader-based billboarding in MultiMesh**
```glsl
shader_type spatial;

// Billboard that always faces camera, stored as MultiMesh instance
void vertex() {
    if (use_billboard) {
        MODEL_MATRIX = mat4(
            vec4(1, 0, 0, 0),
            vec4(0, 1, 0, 0),
            vec4(0, 0, 1, 0),
            MODEL_MATRIX[3]  // Keep world position
        );
    }
}
```

**Option C: Pre-rendered imposter atlas**
1. At editor time, render tree from N angles (e.g., 8 horizontal × 3 vertical = 24 views)
2. Store as texture atlas
3. At runtime, sample correct slice based on camera angle
4. Render as a single quad in a distant MultiMesh
- Very efficient: 1 quad (2 triangles) per tree vs hundreds of tris
- Used by AAA games (UE4 imposter system, Godot community implementations)

**Godot-specific implementation:**
- Use `visibility_range_begin`/`end` to transition between full mesh and billboard
- Use `Fade Mode: Self` for smooth alpha transition between LODs
- Or use `Fade Mode: Disabled` with dither materials for cheaper transition
- Can use `visibility_parent` to link the billboard to the mesh LOD node

---

## 8. How Veloren and Minetest Handle Massive Foliage

### Veloren (Rust, custom wgpu/gfx-rs renderer)
- **Voxel-based terrain** — everything is voxels, no traditional mesh instances for terrain
- **LOD system** — terrain mesh decimation at distance (uses meshoptimizer-style decimation)
- **Foliage as voxels** — trees, grass, etc. are voxel structures baked into terrain chunks
- **Chunk-based rendering** — terrain divided into chunks (~16x16x64 or similar)
- **Greedy meshing** — adjacent same-type voxels are merged into larger faces
- **Frustum culling** at chunk level
- **No MultiMesh** — uses baked voxel meshes per chunk, foliage is part of the chunk mesh
- **Key insight:** When everything is voxel, foliage isn't separate instances; it's part of the terrain geometry. Very efficient but requires voxel art pipeline.
- Written in Rust with custom rendering pipeline (not Godot)

### Minetest / Luanti (C++, Irrlicht-based custom renderer)
- **MapBlock system** — 16×16×16 voxel blocks
- **Mesh generation** — each MapBlock generates a mesh with all visible block faces
- **Foliage = special block types** — grass, flowers, etc. are 1-voxel blocks with plantlike mesh (2 crossed quads)
- **Mesh optimization** — only render visible faces, ignore interior blocks
- **Client-side mesh caching** — generated meshes are cached, only regenerated when blocks change
- **Drawtype system** — different visual styles per block type (plantlike, firelike, mesh, etc.)
- **No instancing** — foliage is just block faces in the chunk mesh
- **View range** — configurable, typically 50-100 blocks
- **Key insight:** Simple geometry per foliage element (2 triangles for cross-plants) baked into the chunk mesh is incredibly efficient. No separate draw calls per plant.

**Takeaway for Godot:** Both engines bake foliage INTO the chunk mesh rather than instancing it separately. For Godot, the closest equivalent is baking a group of foliage instances into a single merged mesh per chunk. However, MultiMesh is more flexible for animation (e.g., wind sway via shaders) and is the Godot-idiomatic approach.

---

## 9. Reasonable Foliage Density Per 40×40 Chunk

**Native platform targets:**

| Foliage Type | Density | Count per 40×40 chunk | Tri count |
|---|---|---|---|
| Grass blades | 1-3 per m² | 1,600-4,800 | 6,400-19,200 |
| Grass clumps | 0.5-1 per m² | 800-1,600 | 9,600-19,200 |
| Small flowers | 0.1-0.3 per m² | 160-480 | 640-1,920 |
| Bushes | 0.02-0.05 per m² | 32-80 | 1,600-4,000 |
| Trees | 0.005-0.02 per m² | 8-32 | 800-3,200 |

**Web platform targets (reduce ~50%):**

| Foliage Type | Count per 40×40 chunk | Notes |
|---|---|---|
| Grass cards/clumps | 800-2,000 | Use clumps, not individual blades |
| Flowers | 100-200 | Combine with grass in same MultiMesh |
| Bushes | 20-40 | Separate MultiMesh, LOD to billboard |
| Trees | 5-15 | Full mesh near, billboard far |

**Practical recommendation for web:**
- **Grass:** ~1,500 instances per chunk, using 4-tri cross-quad cards with wind sway shader
- **Bushes:** ~30 instances per chunk, 50-100 tri mesh each
- **Trees:** ~10 instances per chunk, LOD to billboard at distance
- **Total visible chunks:** ~9 (3×3 grid around player) = ~13,500 grass + 270 bushes + 90 trees
- **Total draw calls:** ~27 (3 MultiMeshInstance3D × 9 chunks) — very manageable

**Per-instance memory budget:**
- Transform3D: 12 floats × 4 bytes = 48 bytes
- Color: 4 floats × 4 bytes = 16 bytes (8 bytes on web — packed to 16-bit)
- Custom data: 4 floats × 4 bytes = 16 bytes (8 bytes on web)
- Total per instance: ~80 bytes native, ~64 bytes web
- 1,500 grass instances: ~96 KB per chunk — negligible

---

## 10. Data-Driven Entity Spawning (Towns/Buildings/Monsters) Per-Chunk

**Architecture:**

```
ChunkManager
├── VisibleChunk[(x,z)]
│   ├── FoliageLayer (MultiMeshInstance3D × N per foliage type)
│   ├── PropLayer
│   │   ├── StaticMeshInstance3D[] — buildings, rocks, structures
│   │   └── PackedScene instances loaded on demand
│   └── EntityLayer
│       ├── MonsterSpawner — spawns/registers monsters from chunk data
│       └── NPCSpawner — spawns NPCs from chunk data
```

**For towns/buildings (static, no animation needed):**
1. Store building data per chunk: `{type: "house", position: Vector3, rotation: float, variant: int}`
2. On chunk load: instance the building PackedScene at the specified transform
3. Pool building instances — hide/unhide rather than free/allocate
4. For distant buildings: use imposter billboards with Visibility Ranges
5. Can also use MultiMesh for repeated building elements (walls, roofs) if same mesh

**For monsters/NPCs (dynamic, need AI/physics):**
1. Store spawn data per chunk: `{type: "goblin", position: Vector3, level: int}`
2. On chunk load: spawn monsters from PackedScene, add to scene tree
3. On chunk unload: either despawn (simple) or persist state + despawn
4. Use `process_mode = PROCESS_MODE_DISABLED` for off-screen monsters to save CPU
5. Limit active monsters per chunk to avoid CPU bottleneck (e.g., max 10 per chunk)

**Efficient chunk loading pattern:**
```gdscript
func load_chunk(chunk_coord: Vector2i):
    var chunk_data = ChunkData.load_from_file(chunk_coord)
    
    # 1. Foliage — populate MultiMesh (fast, GPU-bound)
    foliage_renderer.populate(chunk_data.foliage)
    
    # 2. Static props — instance PackedScenes (moderate cost)
    for prop in chunk_data.props:
        var instance = prop_pool.acquire(prop.type)
        instance.global_transform = prop.transform
        chunk_container.add_child(instance)
    
    # 3. Dynamic entities — spawn with AI (expensive, stagger)
    for entity in chunk_data.entities:
        var mob = mob_pool.acquire(entity.type)
        mob.global_position = entity.position
        mob.process_mode = Node.PROCESS_MODE_DISABLED  # enable when visible
        entity_container.add_child(mob)

func unload_chunk(chunk_coord: Vector2i):
    # 1. Hide foliage (instant)
    foliage_renderer.hide_chunk(chunk_coord)
    
    # 2. Return props to pool
    for prop in active_props[chunk_coord]:
        prop_pool.release(prop)
    
    # 3. Persist + release mobs
    for mob in active_mobs[chunk_coord]:
        persist_mob_state(mob)
        mob_pool.release(mob)
```

**Memory pooling for entities:**
- Pre-allocate common entity types (goblin, villager, etc.)
- Use `visible = false` + `process_mode = DISABLED` when pooled
- Reuse rather than `instance()` / `queue_free()` per chunk transition
- For monsters: maintain a WanderBehavior that makes them stay near their chunk

---

## Recommended Overall Architecture

```
┌─────────────────────────────────────────────────┐
│                  WorldManager                     │
├─────────────────────────────────────────────────┤
│                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ ChunkLoader │  │ FoliageRendr │  │ EntityMgr│ │
│  │ (threaded)  │  │ (MultiMesh)  │  │ (Pool)   │ │
│  └──────┬──────┘  └──────┬───────┘  └────┬─────┘ │
│         │                │               │        │
│  ┌──────▼──────────────▼───────────────▼─────┐    │
│  │              Chunk (data)                  │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │ foliage: {grass:[], bush:[], tree:[]}│  │    │
│  │  │ props: [{type, xform, variant}, ...] │  │    │
│  │  │ entities: [{type, pos, state}, ...]  │  │    │
│  │  │ heightmap: float[,]                  │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  └───────────────────────────────────────────┘    │
│                                                   │
│  Rendering Layer (per visible chunk):             │
│  ┌─────────────────────────────────────────────┐ │
│  │ [LOD0] MultiMesh grass (near)              │ │
│  │ [LOD0] MultiMesh bushes (near)             │ │
│  │ [LOD0] MeshInstance3D trees (near)         │ │
│  │ [LOD1] MultiMesh grass clusters (mid)      │ │
│  │ [LOD1] MultiMesh bush billboards (mid)     │ │
│  │ [LOD1] MultiMesh tree billboards (mid)    │ │
│  │ [LOD2] Fade out (far) via dither           │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## Key Godot API Reference

| API | Use Case |
|---|---|
| `MultiMesh.new()` | Create instanced mesh data |
| `mm.instance_count = N` | Allocate instances |
| `mm.set_instance_transform(i, t)` | Set per-instance transform |
| `mm.set_instance_color(i, c)` | Set per-instance color variation |
| `mm.set_instance_custom_data(i, c)` | Set per-instance custom data (wind phase, etc.) |
| `mm.visible_instance_count` | Show N of M instances (culling trick) |
| `mm.custom_aabb` | Set AABB for frustum culling |
| `mm.buffer` | PackedFloat32Array — bulk set all data |
| `RenderingServer.multimesh_set_buffer()` | Low-level bulk buffer set (GDExtension) |
| `GeometryInstance3D.visibility_range_*` | HLOD / distance-based LOD switching |
| `BaseMaterial3D.distance_fade` | Dither fade for grass fade-out |
| `MeshInstance3D.lod_bias` | Per-object LOD aggressiveness |
| `RenderingServer.instance_*` | Low-level server API for maximum perf |

---

## Shader Tricks for Foliage MultiMesh

**Wind sway via INSTANCE_CUSTOM:**
```glsl
shader_type spatial;
render_mode cull_disabled; // double-sided for grass cards

uniform float wind_strength = 0.3;
uniform float wind_speed = 1.0;

void vertex() {
    // INSTANCE_CUSTOM.x = random phase offset
    // INSTANCE_CUSTOM.y = wind responsiveness (0-1)
    float wind = sin(TIME * wind_speed + (VERTEX.y * 2.0) + INSTANCE_CUSTOM.x * 6.28) 
                 * wind_strength * INSTANCE_CUSTOM.y;
    VERTEX.x += wind;
    
    // Billboard mode for grass cards (optional)
    // MODEL_MATRIX[0] = vec4(normalize(cam_right), 0.0); // etc.
}
```

**Distance-based vertex collapse (LOD in shader):**
```glsl
void vertex() {
    float dist = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
    // Collapse top vertices for distant grass
    if (VERTEX.y > 0.5) {
        VERTEX.xz *= max(0.01, 1.0 - smoothstep(40.0, 80.0, dist));
    }
    // Discard entirely beyond fade range
    if (dist > 100.0) {
        VERTEX.xyz = vec3(0.0); // Collapse to degenerate triangle
    }
}
```

---

## Summary of Concrete Numbers

| Metric | Native | Web (WebGL2) |
|---|---|---|
| Max grass instances (4-tri cards) | 50,000-100,000 | 10,000-15,000 |
| Max tree instances (200-tri) | 5,000-10,000 | 1,000-2,000 |
| Max MultiMesh instances total | 1,000,000+ (simple mesh) | 30,000-50,000 (simple mesh) |
| Max draw calls (target) | 100-300 | 30-100 |
| Per-chunk grass (40×40) | 1,600-4,800 | 800-2,000 |
| Per-chunk trees (40×40) | 8-32 | 5-15 |
| Visible chunks (3×3 grid) | 9 | 9 |
| Memory per grass instance | ~80 bytes | ~64 bytes |
| MultiMesh buffer upload | O(N) | O(N) (slower on WASM) |
| Recommended foliage types per chunk | 3-5 | 2-3 |
