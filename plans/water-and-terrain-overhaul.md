# Water & Terrain Overhaul Plan (v2 — Refined)

## What Went Wrong With v1

The previous attempt at implementing this plan failed in these ways:

1. **Land shape was DESTROYED** — The old plan replaced the elevation formula wholesale. The nice smooth mountains and plains were lost because the new pipeline restructured everything instead of being additive.
2. **Per-chunk coloring was wrong** — Assigning a single color per chunk based on biome/height made areas above water turn blue and sandy areas where they shouldn't be. Chunks are 40×40 units — far too coarse for terrain coloring.
3. **CPU per-vertex depth dropped FPS from ~700 to ~100** — Iterating 4096 vertices, calling heightmap lookup + `surface_update_region()` every frame is a NON-STARTER.
4. **Island suppression was overcomplicated** — Morphological opening / post-process passes are unnecessary when the noise itself can be tuned to never create small features.

## Core Design Principles (NEW)

1. **ADDITIVE, not destructive** — The existing mountain/plains/detail pipeline produces excellent terrain. The continental mask must be applied AFTER that pipeline as a multiplier/lerp, not replace it.
2. **Per-vertex, not per-chunk** — Terrain color must vary per-vertex based on local height and slope. Each vertex already has height and normal — use them.
3. **No CPU per-vertex work per frame** — The water depth approach must be GPU-friendly. Use a rolling heightmap texture sampled in the vertex shader (WebGL2 supports vertex texture fetch), NOT CPU vertex array updates.
4. **Low frequency = no small islands** — Simply lowering continental noise frequency to 0.2 makes features continent-scale. No post-process island suppression needed.
5. **KISS** — Minimal parameter additions. Clean code. No erosion filter, no morphological operations, no basin detection for v1.

---

## Part 1: Continent + Ocean (Heightmap Generator)

### Current State (Preserved As-Is)

The existing pipeline at `heightmap_generator.gd:70-109`:

```
continental = fbm(nx,ny,nz,nw, octaves=2, freq=1.5)
mountain_mask = fbm(nx+100,..., octaves=2, freq=2.0) → smoothstep(0.35,0.65, raw*0.5+0.5)
mountains_raw = ridged_fbm(nx,ny,nz,nw, octaves=5, freq=4.0)
plains = fbm(nx,ny,nz,nw, octaves=3, freq=3.0)
detail = fbm(nx+200,..., octaves=2, freq=30.0)

base_terrain = plains * 0.15 + 0.2 + 0.035 * continental
mountain_noise = max(0, 0.35 + ridged*0.5)
mountain_uplift = pow(mountain_noise, 1.5)
blend = pow(mountain_mask, 1.5)
elevation = lerp(base_terrain, mountain_uplift, blend) + detail*0.03
elevation = clamp(elevation, 0, 1)
final_height = elevation * 80  → range [0, 80]
```

This produces nice smooth mountains and plains. **Do not change any of these layers.** The only change is:
1. Remove the weak `continental * 0.035` bias from `base_terrain`
2. Add a continental MASK step at the END that lerps between ocean floor and the computed land elevation

### New Pipeline (Minimal Diff)

```gdscript
# Step 1: Domain warping for organic continent shapes
var warp_x = fbm(nx,ny,nz,nw, octaves=2, freq=0.6, persistence=0.5, lacunarity=2.0)
var warp_z = fbm(nx+50, ny+50, nz+50, nw+50, octaves=2, freq=0.6, persistence=0.5, lacunarity=2.0)
var wnx = nx + warp_x * 0.3
var wny = ny + warp_x * 0.3
var wnz = nz + warp_z * 0.3
var wnw = nw + warp_z * 0.3

# Step 2: Continental mask from VERY LOW FREQ noise on warped coords
var continental_raw = fbm(wnx, wny, wnz, wnw, octaves=2, freq=0.2, persistence=0.5, lacunarity=2.0)
var continental_01 = continental_raw * 0.5 + 0.5          # remap [-1,1] → [0,1]
var land_mask = smoothstep(0.52, 0.68, continental_01)     # ~30% land, sharp coastlines

# Step 3: Generate land terrain EXACTLY as before (minus the old bias)
var mountain_mask = fbm(nx+mo, ny+mo, nz+mo, nw+mo, ...) → smoothstep
var mountains_raw = ridged_fbm(nx, ny, nz, nw, ...)
var plains = fbm(nx, ny, nz, nw, ...)
var base_terrain = plains * 0.15 + 0.2   # ← NO + continental*0.035 term
var mountain_noise = maxf(0.0, MOUNTAIN_BASE + mountains_raw * 0.5)
var mountain_uplift = pow(mountain_noise, power_exponent)
var blend = pow(mountain_mask, BLEND_POWER)
var land_elevation = lerp(base_terrain, mountain_uplift, blend)
land_elevation += detail * detail_weight

# Step 4: Apply continental mask — THE ONLY NEW OPERATION
var ocean_floor = 0.0          # ocean sits at height_range_min (Y=0)
var elevation = lerp(ocean_floor, land_elevation, land_mask)
elevation = clampf(elevation, 0.0, 1.0)
heightmap[i] = elevation * height_range + height_range_min
```

### Why This Preserves Land Quality

- Mountains use the **same `nx,ny,nz,nw` coordinates** — no change to mountain shape
- Plains use the **same coordinates** — no change to rolling hills
- The mask is applied as `lerp(0, land_elevation, mask)` — on land (mask≈1), `elevation = land_elevation` exactly
- The only difference ON LAND is removing the tiny `+0.035*continental` bias, which was negligible anyway
- Mountains are NOT multiplied by the mask — they're inside `land_elevation` which gets masked as a whole. Where mask=1, the full mountain is there. Where mask=0, it's ocean floor. The transition zone (0<mask<1) smoothly fades mountains into ocean — creating natural coastal plains

### Continental Frequency Math

On a torus with R=1.0, each angular cycle spans `2πR ≈ 6.28` 4D units. Features per cycle = `freq × 2πR`:

| Freq | Features per cycle | What you get |
|------|-------------------|-------------|
| 1.5 (current) | ~9.4 | Many small islands/blobs |
| 0.2 (proposed) | ~1.3 | 1-2 continent-scale landmasses |
| 0.15 | ~0.9 | Essentially one supercontinent |

**`continental_freq = 0.2`** is the sweet spot: 1-2 large landmasses with deep ocean between them.

### Smoothstep Edge Controls

`smoothstep(edge0, edge1, continental_01)`:
- **Center** = `(edge0 + edge1) / 2` — controls land fraction. Center=0.60 → ~30% land (one continent surrounded by lots of ocean)
- **Width** = `edge1 - edge0` — controls coastline sharpness. Width=0.16 → moderate transition (~650 world units)

Parameters: **`edge0 = 0.52`, `edge1 = 0.68`** (30% land, moderate coastline). Tune later:
- More land: lower both (e.g., 0.45/0.55 → ~50% land)
- Sharper coast: shrink width (e.g., 0.58/0.62 → very sharp)
- Fewer marginal islands: raise edge0 slightly (0.55/0.69)

### Why No Post-Process Island Suppression Is Needed

At `freq=0.2` on an R=1.0 torus, the **smallest possible noise feature** spans ~1/0.2 of the 4D period ≈ 1/6th of the world circumference ≈ **850 world units**. A 1-chunk island (40 units) cannot exist — the noise simply cannot oscillate fast enough to create isolated land in 40 units. The smoothstep threshold further kills marginal bumps. **Zero post-processing required.**

### Torus Seam Safety

The domain warp uses `fbm(nx,...)` (torus-mapped coordinates) to compute the warp offset. Since `wx=0` and `wx=world_size` map to the same `(nx,ny)`, they get the **same warp offset** and thus the **same final continental value**. Seamlessness is guaranteed.

### Domain Warping Details

- **`warp_freq = 0.6`** (higher than `continental_freq=0.2`) — this creates coastline-level detail without creating new separate landmasses
- **`warp_strength = 0.3`** — mild warping. The continent shifts around organically but doesn't fragment. Values >0.5 risk creating detached islands where the warp folds the domain
- **Two independent warp FBM calls** (one for X, one for Z) with a +50 offset on all 4D coords for the second call — this prevents the warp from being symmetric

### New NoiseParams Fields

```gdscript
@export_group("Continental", "continental_")
@export var continental_freq: float = 0.2         # changed from 1.5
@export var continental_octaves: int = 2           # unchanged
@export var continental_edge0: float = 0.52         # NEW: smoothstep low edge
@export var continental_edge1: float = 0.68         # NEW: smoothstep high edge
@export var continental_warp_strength: float = 0.3  # NEW: domain warp intensity
@export var continental_warp_freq: float = 0.6      # NEW: domain warp frequency
# REMOVED: continental_weight (no longer used — mask replaces bias)
```

### Height Range

Keep `height_range_min = 0.0`, `height_range_max = 80.0`. Ocean floor at Y=0 (below `water_level=15`) gives 15 units of depth. This is simpler than negative ranges and doesn't break mesh builder, collision, or navmesh.

If deeper ocean is desired later, lower `height_range_min` to -10 and increase `height_range_max - height_range_min` to 90. But Y=0 floor with water_level=15 already feels like proper ocean — the screen-space depth shader will show 15 units of water as deep blue.

---

## Part 2: Per-Vertex Terrain Coloring

### The Problem With Per-Chunk Colors

Each chunk is 40×40 units. A single color per chunk means:
- A chunk with a mountain on one side and plains on the other gets ONE color
- A chunk at the shoreline is either "land green" or "ocean blue" for its entire area
- Result: blocky, wrong colors everywhere, blue patches on dry land

### The Fix: Per-Vertex Height + Slope Coloring

Every vertex already has a height (from the heightmap) and a normal (precomputed for lighting). Use these to determine color per-vertex. **Zero extra computation** — just use the data that's already there.

### Color Bands

| Band | Height above water_level | Color | Description |
|------|-------------------------|-------|-------------|
| Ocean floor | < 0 | `Color(0.14, 0.20, 0.16)` | Dark underwater |
| Beach | 0 to +3 | `Color(0.72, 0.64, 0.44)` | Warm sand |
| Lowland | +3 to +20 | `Color(0.29, 0.49, 0.25)` | Green grass |
| Highland | +20 to +45 | `Color(0.35, 0.42, 0.23)` | Dark olive |
| Rock | +45 to +65 | `Color(0.42, 0.38, 0.34)` | Brown-gray |
| Snow | > +65 | `Color(0.88, 0.88, 0.90)` | Off-white |

Each boundary has a **3-unit smooth blend** (smoothstep over 3 height units). With ~1 unit between vertices, that's ~3 vertices of gradual transition — smooth and natural.

### Slope Override

Steep surfaces → rock color regardless of height band:

```gdscript
var slope_factor = 1.0 - smoothstep(0.55, 0.85, normal_y)
color = color.lerp(cliff_rock, slope_factor * 0.7)
```

`normal.y > 0.85` = flat (<32° slope) → full height-based color. `normal.y < 0.55` = steep (>57° slope) → 70% rock color. Between: smooth blend.

### Implementation in terrain_mesh_builder.gd

Replace the `BIOME_COLORS` lookup with a `_get_terrain_color()` static method. The heights `h00/h10/h01/h11` and normals `n00/n10/n01/n11` are already computed at lines 113-122 for vertex positions. Just call `_get_terrain_color(h00, water_level, n00.y)` instead of appending the flat chunk color.

Pass `water_level` into `build_chunk_mesh_arrays()` as a parameter (available from `ChunkData` or `WorldMeta.generation_params`).

### Performance

1681 vertices/chunk at LOD0. The color function is ~10 comparisons + a few lerps per vertex. Built on a background thread (`ChunkWorker`). **Negligible cost — maybe 1-2% overhead on mesh build.**

### LOD Compatibility

No special handling needed. At lower LOD, fewer vertices mean coarser color transitions, but hardware interpolates vertex colors across triangles so transitions stay smooth. At LOD4 (3×3 vertices, viewed at 700m+), any slight banding is invisible.

---

## Part 3: Water Shader Overhaul

### Current Issues

1. Gerstner waves displace Y below terrain → water clips under land
2. Wave amplitude is uniform regardless of depth
3. `water_level` uniform is declared but unused in shader logic
4. No depth modulation in vertex shader

### Approach: Heightmap Texture in Vertex Shader (NOT CPU per-vertex)

**v1 plan used CPU per-vertex depth computation → FPS 700→100. REJECTED.**

**v2 approach**: Bake terrain heights into a rolling `ImageTexture` that covers the water plane's area. Sample it in the vertex shader to get approximate depth. This is a **vertex texture fetch (VTF)** which IS supported in WebGL2 / OpenGL ES 3.0 (spec guarantees `MAX_VERTEX_TEXTURE_IMAGE_UNITS ≥ 16`).

### Rolling Heightmap Texture

**CPU side** (`water_plane.gd`):

- Create a **64×64 R16F ImageTexture** (~8 KB VRAM) covering the 600×600 water plane area
- 9.4 units per texel — coarse but sufficient for wave amplitude scaling (doesn't need to be pixel-perfect)
- Update when player moves ≥5 units — only write the scrolled strip (not the whole texture)
- Pass `heightmap_offset` and `heightmap_scale` uniforms for UV mapping

```gdscript
const HEIGHTMAP_RES: int = 64
const UPDATE_THRESHOLD: float = 5.0

func _update_heightmap_if_needed(player_pos: Vector3):
    var offset := Vector2(player_pos.x - plane_size * 0.5, player_pos.z - plane_size * 0.5)
    if offset.distance_to(_last_update_pos) < UPDATE_THRESHOLD:
        return
    _last_update_pos = offset
    # Sample terrain heights into _heightmap_image (64×64 grid)
    # Call _heightmap_texture.update(_heightmap_image)
    # Set shader uniforms: heightmap_offset, heightmap_scale
```

**Cost**: 4096 heightmap lookups, but only when player moves 5+ units (~2-5 times/second while moving). Each lookup is a `ChunkData.get_height_at()` bilinear interpolation. Total: ~0.5ms per update, 0ms on idle frames.

**Vertex shader**:

```glsl
uniform sampler2D terrain_heightmap : repeat_disable, filter_linear;
uniform vec2 heightmap_offset = vec2(0.0);
uniform vec2 heightmap_scale = vec2(0.001667);  // 1/600

void vertex() {
    vec3 p = VERTEX;

    // Compute world XZ from vertex position + instance transform
    vec2 world_xz = vec2(INSTANCE_MATRIX[3][0], INSTANCE_MATRIX[3][2]) + VERTEX.xz;

    // Sample terrain height from rolling texture
    vec2 hm_uv = (world_xz - heightmap_offset) * heightmap_scale;
    float terrain_h = textureLod(terrain_heightmap, hm_uv, 0.0).r;
    float depth = max(0.0, water_level - terrain_h);

    // Scale wave amplitude by depth — calm near shore, full in deep water
    float wave_scale = smoothstep(0.0, 5.0, depth);
    p += gerstner(p.xz, wave_a_dir, wave_a_strength * wave_scale, 12.0, wave_a_speed);
    p += gerstner(p.xz, wave_b_dir, wave_b_strength * wave_scale, 8.0, wave_b_speed);
    p += gerstner(p.xz, wave_c_dir, wave_c_strength * wave_scale, 5.0, wave_c_speed);

    // Critical: water never goes below terrain
    p.y = max(p.y, terrain_h + 0.05);

    VERTEX = p;
}
```

**Fragment shader**: Keep existing `depth_texture` (screen-space) for color/foam/alpha — it works correctly for pixel-precise depth coloring. Add vertex depth as a supplemental signal:

```glsl
// In fragment(), after existing depth_factor calculation:
float vertex_depth_factor = smoothstep(0.0, max_depth, depth_from_vertex);

// Blend screen-space and vertex depth for more robust coloring at all camera distances
float combined_depth = mix(depth_factor, vertex_depth_factor, 0.3);

// Depth-based roughness (deep = reflective, shallow = diffuse)
ROUGHNESS = mix(0.4, 0.05, smoothstep(2.0, 20.0, depth_from_vertex));
```

Pass `depth` from vertex to fragment via a varying (not COLOR, since we want to keep vertex colors available for terrain).

### Fallback for Old Mobile GPUs

Some older Mali GPUs have slow VTF. If this becomes an issue:
1. The texture is only 64×64 — even slow VTF handles this in <1ms
2. If truly problematic, reduce to 32×32 and use `filter_linear` for interpolation
3. Worst case: remove the vertex shader texture lookup and rely only on fragment `discard` + wider `edge_fade` for shoreline masking. This gives no wave dampening but prevents visual artifacts via fragment discard

### Water Never Below Land — Complete Solution

1. **Vertex Y clamp** — `p.y = max(p.y, terrain_h + 0.05)` prevents geometric clipping
2. **Fragment discard** — existing `if (depth_diff < 0.0) { discard; }` catches any remaining artifacts
3. Together: no water visible under terrain from any camera angle

---

## Part 4: NoiseParams & WorldConfig Changes

### Changes to NoiseParams

```gdscript
@export_group("Continental", "continental_")
@export var continental_freq: float = 0.2           # was 1.5
@export var continental_octaves: int = 2             # unchanged
@export var continental_edge0: float = 0.52           # NEW: replaces continental_weight
@export var continental_edge1: float = 0.68           # NEW
@export var continental_warp_strength: float = 0.3    # NEW
@export var continental_warp_freq: float = 0.6        # NEW
# REMOVE: continental_weight (no longer a bias — mask replaces it)
```

### Changes to WorldGenConfig

Same fields added, matching NoiseParams:
- `continental_freq` default → 0.2
- `continental_edge0` = 0.52
- `continental_edge1` = 0.68
- `continental_warp_strength` = 0.3
- `continental_warp_freq` = 0.6
- Remove `continental_weight`

### ChunkData Addition

Add `water_level: float` field so the mesh builder can access it for per-vertex coloring:

```gdscript
var water_level: float = 15.0
```

Set in `ChunkData.from_region()` or pass explicitly from `WorldMeta.generation_params.water_level`.

---

## Part 5: Heightmap Generator Changes (Exact Diff)

### Current Code (lines 70-109)

```gdscript
var continental = _fbm(noise, use_native,
    nx, ny, nz, nw,
    params.continental_octaves, params.continental_freq,
    0.5, 2.0)

var mountain_mask = _fbm(noise, use_native,
    nx + mo, ny + mo, nz + mo, nw + mo,
    params.mountain_mask_octaves, params.mountain_mask_freq,
    0.5, 2.0)
mountain_mask = _smoothstep(
    params.mountain_mask_edge0, params.mountain_mask_edge1,
    mountain_mask * 0.5 + 0.5)

var mountains_raw = _ridged_fbm(noise, use_native,
    nx, ny, nz, nw,
    params.mountain_octaves, params.mountain_freq,
    params.mountain_persistence, params.mountain_lacunarity)

var plains = _fbm(noise, use_native,
    nx, ny, nz, nw,
    params.plains_octaves, params.plains_freq,
    params.plains_persistence, 2.0)

var base_terrain = plains * 0.15 + 0.2
base_terrain += params.continental_weight * continental * 0.1

var mountain_noise = maxf(0.0, MOUNTAIN_BASE + mountains_raw * 0.5)
var mountain_uplift = pow(mountain_noise, params.power_exponent)

var blend = pow(mountain_mask, BLEND_POWER)
var elevation = lerp(base_terrain, mountain_uplift, blend)

var detail = _fbm(noise, use_native,
    nx + d_off, ny + d_off, nz + d_off, nw + d_off,
    params.detail_octaves, params.detail_freq,
    params.detail_persistence, params.detail_lacunarity)
elevation += detail * params.detail_weight

elevation = clampf(elevation, 0.0, 1.0)
heightmap[lz * sr + lx] = elevation * height_range + params.height_range_min
```

### New Code

```gdscript
# --- Domain warp for organic continent shapes ---
var warp_x = _fbm(noise, use_native,
    nx, ny, nz, nw,
    2, params.continental_warp_freq, 0.5, 2.0)
var warp_z = _fbm(noise, use_native,
    nx + 50.0, ny + 50.0, nz + 50.0, nw + 50.0,
    2, params.continental_warp_freq, 0.5, 2.0)
var ws: float = params.continental_warp_strength
var wnx = nx + warp_x * ws
var wny = ny + warp_x * ws
var wnz = nz + warp_z * ws
var wnw = nw + warp_z * ws

# --- Continental mask ---
var continental_raw = _fbm(noise, use_native,
    wnx, wny, wnz, wnw,
    params.continental_octaves, params.continental_freq,
    0.5, 2.0)
var continental_01 = continental_raw * 0.5 + 0.5
var land_mask = _smoothstep(params.continental_edge0, params.continental_edge1, continental_01)

# --- Generate land terrain (unchanged except no continental bias) ---
var mountain_mask = _fbm(noise, use_native,
    nx + mo, ny + mo, nz + mo, nw + mo,
    params.mountain_mask_octaves, params.mountain_mask_freq,
    0.5, 2.0)
mountain_mask = _smoothstep(
    params.mountain_mask_edge0, params.mountain_mask_edge1,
    mountain_mask * 0.5 + 0.5)

var mountains_raw = _ridged_fbm(noise, use_native,
    nx, ny, nz, nw,
    params.mountain_octaves, params.mountain_freq,
    params.mountain_persistence, params.mountain_lacunarity)

var plains = _fbm(noise, use_native,
    nx, ny, nz, nw,
    params.plains_octaves, params.plains_freq,
    params.plains_persistence, 2.0)

var base_terrain = plains * 0.15 + 0.2

var mountain_noise = maxf(0.0, MOUNTAIN_BASE + mountains_raw * 0.5)
var mountain_uplift = pow(mountain_noise, params.power_exponent)

var blend = pow(mountain_mask, BLEND_POWER)
var land_elevation = lerp(base_terrain, mountain_uplift, blend)

var detail = _fbm(noise, use_native,
    nx + d_off, ny + d_off, nz + d_off, nw + d_off,
    params.detail_octaves, params.detail_freq,
    params.detail_persistence, params.detail_lacunarity)
land_elevation += detail * params.detail_weight

# --- Apply continental mask ---
var elevation = lerp(0.0, land_elevation, land_mask)

elevation = clampf(elevation, 0.0, 1.0)
heightmap[lz * sr + lx] = elevation * height_range + params.height_range_min
```

**Net diff**: Remove 1 line (`base_terrain += continental_weight * continental * 0.1`), add ~8 lines for warp, ~3 lines for mask, change 1 line (`lerp(base_terrain, ...)` → `lerp(0.0, land_elevation, land_mask)`). The existing mountain/plains/detail generation is 100% structurally identical.

---

## Part 6: Terrain Mesh Builder Changes

### Remove

- `BIOME_COLORS` constant (lines 5-9)
- The `var color: Color = BIOME_COLORS.get(chunk_data.biome, BIOME_COLORS[0])` line

### Add

```gdscript
static func _get_terrain_color(height: float, water_level: float, normal_y: float) -> Color:
    var h: float = height - water_level

    var ocean_floor := Color(0.14, 0.20, 0.16)
    var sand := Color(0.72, 0.64, 0.44)
    var grass := Color(0.29, 0.49, 0.25)
    var highland := Color(0.35, 0.42, 0.23)
    var rock := Color(0.42, 0.38, 0.34)
    var snow := Color(0.88, 0.88, 0.90)
    var cliff_rock := Color(0.40, 0.37, 0.33)

    var c: Color
    if h < -2.0:
        c = ocean_floor
    elif h < 0.0:
        c = ocean_floor.lerp(sand, _smoothstep(-2.0, 0.0, h))
    elif h < 3.0:
        c = sand
    elif h < 6.0:
        c = sand.lerp(grass, _smoothstep(3.0, 6.0, h))
    elif h < 20.0:
        c = grass
    elif h < 23.0:
        c = grass.lerp(highland, _smoothstep(20.0, 23.0, h))
    elif h < 45.0:
        c = highland
    elif h < 48.0:
        c = highland.lerp(rock, _smoothstep(45.0, 48.0, h))
    elif h < 65.0:
        c = rock
    elif h < 68.0:
        c = rock.lerp(snow, _smoothstep(65.0, 68.0, h))
    else:
        c = snow

    var slope_factor: float = 1.0 - _smoothstep(0.55, 0.85, normal_y)
    c = c.lerp(cliff_rock, slope_factor * 0.7)

    return c
```

Already has `_smoothstep` in `HeightmapGenerator` but not in `TerrainMeshBuilder` — add the same static method (3 lines).

### Change in build_chunk_mesh_arrays()

```gdscript
# OLD:
var color: Color = BIOME_COLORS.get(chunk_data.biome, BIOME_COLORS[0])
# ... for each quad:
colors.append(color)  # ×4

# NEW:
var water_level: float = chunk_data.water_level
# ... for each quad:
colors.append(_get_terrain_color(_h(hm, lx, lz, res), water_level, n00.y))
colors.append(_get_terrain_color(_h(hm, nx, lz, res), water_level, n10.y))
colors.append(_get_terrain_color(_h(hm, lx, nz, res), water_level, n01.y))
colors.append(_get_terrain_color(_h(hm, nx, nz, res), water_level, n11.y))
```

The heights and normals are already computed for vertex positions. **Zero new lookups.**

### Skirt Coloring

Skirt top-edge vertices use the same `_get_terrain_color()` as their terrain vertex. Bottom-edge vertices (dropped by `SKIRT_DROP`) use the same color. Change `_build_skirt_arrays` to compute colors per-vertex instead of taking a `color` parameter.

---

## Part 7: WaterPlane Changes

### Rolling Heightmap Texture

Add to `water_plane.gd`:

- `var _heightmap_image: Image` — 64×64, FORMAT_RF (single-channel float)
- `var _heightmap_texture: ImageTexture`
- `var _last_heightmap_update_pos: Vector2 = Vector2.INF`
- `const _HEIGHTMAP_RES: int = 64`
- `const _HEIGHTMAP_UPDATE_DIST: float = 5.0`

On `_ready()`: create the image and texture, set shader uniforms.

In `_process()`: call `_update_heightmap_if_needed()` after updating position. This method:
1. Computes the world-space offset of the 64×64 grid (player_pos - plane_size/2)
2. For each texel: compute world XZ, get terrain height from ChunkManager
3. Write to Image, call `ImageTexture.update()`
4. Set `heightmap_offset` and `heightmap_scale` shader uniforms

**Only runs when the player moves 5+ units** — typically 2-5 times/second while moving, never while standing still.

### New Shader Uniforms

```glsl
uniform sampler2D terrain_heightmap : repeat_disable, filter_linear;
uniform vec2 heightmap_offset = vec2(0.0);
uniform vec2 heightmap_scale = vec2(0.001667);  // 1.0 / plane_size
```

Add a varying to pass depth from vertex to fragment shader:

```glsl
varying float v_depth;

// In vertex():
v_depth = depth;

// In fragment():
float depth_from_vertex = v_depth;
```

---

## Implementation Order

1. **Per-vertex terrain coloring** — Change `TerrainMeshBuilder._get_terrain_color()` + `build_chunk_mesh_arrays()`. No generation changes. Visual improvement is immediate and independent.
2. **Heightmap generator continental mask** — Change `generate_chunk_heightmap()` + `NoiseParams/WorldGenConfig` new parameters. Delete old `continental_weight`. Regenerate world.
3. **World generation** — Regenerate the world with new parameters. Verify continent shape, ocean depth, mountain preservation.
4. **Rolling heightmap texture** — Add to `water_plane.gd`. Create Image, update loop, pass to shader.
5. **Water vertex shader depth** — Add heightmap texture lookup, wave scaling, Y clamping.
6. **Water fragment shader enhancements** — Depth-based roughness, blended depth factor, wave-crest foam.
7. **Lake generation** (future, not v2) — Basin detection + lake water planes. Separate from this plan.

---

## Resolved Open Questions

| Question | v1 Answer | v2 Answer |
|----------|-----------|-----------|
| Torus continent shape | Radial shaping or 4D pole | **Low-freq noise only** — freq=0.2 naturally creates 1-2 landmasses on a torus. No radial/pole needed. |
| Island suppression | Morphological opening post-process | **Not needed** — freq=0.2 cannot create features smaller than ~850 units. No post-processing. |
| Water depth approach | CPU per-vertex (REJECTED — FPS 700→100) | **Rolling heightmap texture** sampled in vertex shader. ~0.5ms per update, ~0ms idle. |
| Terrain coloring | Per-chunk biome color | **Per-vertex height + slope** — zero extra computation, just use heights/normals that already exist. |
| Height range | Negative range (-10 to 80) | **Keep 0–80** — ocean floor at Y=0 with water_level=15 gives 15 units depth. Simpler, nothing breaks. |
| Lake rendering | Per-lake PlaneMesh + ShaderMaterial | **Deferred** — lakes are a follow-up after ocean + coloring work correctly. |
| Height range min < 0 | Needed for deep ocean | **Not needed** — 15 units of depth at Y=0 looks deep with the shader's depth-based coloring. Can extend later if desired. |

---

## Deferred Items (Not In v2)

- **Lake generation** — Basin detection, lake water planes, per-lake ShaderMaterial. Separate plan after ocean works.
- **Erosion filter** — Runevision pseudo-erosion. Nice-to-have, not required for ocean/continent.
- **Per-vertex color noise variation** — Subtle noise-based shifting of band boundaries for more organic edges. Polish pass.
- **Rivers** — Already in `plans/river-generation.md` (deferred).
- **Negative height_range_min** — Can explore later if 15 units of ocean depth feels too shallow.
