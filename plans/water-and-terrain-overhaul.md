# Water & Terrain Overhaul Plan

## Problem Statement

Two issues with the current water system:

1. **No deep water bodies** — All water appears ankle-deep because the terrain beneath the single water plane has minimal variation in its underwater elevation. The ocean floor is too close to `water_level` (Y=15).

2. **Water warbles under/over land** — The Gerstner waves in the vertex shader displace Y both up and down from `water_level`. When waves dip below nearby terrain height, water clips under land. When waves peak, they visually overlap land that's barely above water level.

---

## Part 1: Continent + Ocean + Lakes Generation

### Current State

- Single `continental` FBM noise layer at freq=1.5 with 2 octaves blended at weight 0.035 — too weak to create strong land/ocean distinction
- No distance-to-center shaping — terrain is uniform across the torus
- The height range is 0–80, water level at 15 — but the `base_terrain` formula (`plains * 0.15 + 0.2 + continental * 0.035`) biases everything toward 0.2–0.35 range, meaning most terrain ends up near the water level
- No lake generation mechanism

### Proposed: Multi-Stage Elevation Pipeline

Restructure `HeightmapGenerator` into a clear pipeline of noise layers, each with a distinct purpose:

#### Stage 1: Continental Shape (Land vs Ocean)

**Goal**: Create one large continent surrounded by deep ocean, with meaningful coastline.

**Technique**: Use a **domain-warped FBM** (Inigo Quilez style: `fbm(p + fbm(p))`) at very low frequency to produce organic continent shapes. Then apply a **radial shaping function** to bias the center of the world toward land and the edges toward ocean.

```
continent_raw = fbm(p + fbm(p), octaves=4, freq=0.8)
continent = reshape(continent_raw, land_bias)
```

**Radial shaping** (adapted for torus — see Torus Notes below):
- Calculate a "distance from continent center" concept using a second low-freq noise as a gradient field
- Apply `smoothstep` to push values above 0.5 → land, below 0.5 → ocean
- The continental noise should produce values where ~40% of the map is ocean, ~60% is land

**Key parameter**: `ocean_floor` — a minimum elevation for ocean terrain. Currently underwater terrain is too close to water_level. Set ocean floor to `water_level - 20` (e.g., Y=-5 if water is Y=15). This creates genuinely deep ocean.

**Torus adaptation**: Since we wrap on a torus, we can't use simple Euclidean distance from center. Instead:
- Use the 4D noise coordinates directly — pick a "pole" in 4D space and define distance from that pole
- OR: use a separate low-frequency noise to define the continental "blob" shape, letting noise naturally create landmass shapes that wrap seamlessly on the torus (the current torus mapping already ensures seamless wrapping)
- The simplest approach: make the continental noise strong enough (higher weight, lower frequency) that it naturally creates large landmass regions and large ocean regions. Add a threshold/bias to push the distribution toward a single continent.

**Island suppression**: To avoid tiny 1-2 chunk islands:
- After generating the raw continental elevation, apply a **minimum land area filter**: any land region smaller than ~8x8 chunks gets eroded down to ocean
- Practical approach: use morphological opening — erode the land mask by 3-4 chunks, then dilate back. Small islands disappear, large landmasses persist.
- Alternative (simpler): add a **smoothing pass** that blends each elevation with its neighbors. Small islands get averaged into the surrounding ocean. Large landmasses are unaffected. This can be done as a post-process on the heightmap, or by using `continental_octaves=4` with very low frequency to prevent small features.

#### Stage 2: Mountain Ranges

Keep existing mountain mask + ridged FBM approach, but:
- Apply mountains **only where Stage 1 produced land** (continent mask > 0.5)
- Scale mountain height relative to the continent mask so mountains fade at coastlines
- This ensures no underwater mountains and creates natural coastal plains

#### Stage 3: Plains & Hills

Keep existing plains noise, applied on top of continental shape with:
- Plains elevation biased upward on land, downward in ocean
- `base_elevation = lerp(ocean_floor, plains_base, continent_mask)`

#### Stage 4: Erosion Filter (Optional Enhancement)

The **runevision pseudo-erosion filter** produces gorgeous branching gullies and ridges from any height function, evaluates per-point (no simulation), and is GPU/chunk-friendly. This would replace or augment the existing `detail` layer.

- Input: the height + gradient from Stages 1-3
- Output: eroded height with natural-looking gullies, ridges, and valleys
- Parameters: `erosion_strength`, `erosion_scale`, `erosion_octaves` (3-5), `detail` (controls gully prevalence)
- This is a future enhancement; the initial overhaul should get continental shape + depth right first

#### Stage 5: Detail Noise

Keep existing detail FBM as-is (small surface roughness).

### Lake Generation

**Goal**: Inland water bodies at varying elevations, some above sea level.

#### Approach: Basin Detection + Water Fill

1. **After the full heightmap is generated**, scan for natural basins (depressions surrounded by higher terrain):
   - For each chunk, trace downward gradient. Points that converge to a local minimum that's above sea level are potential lake basins.
   - Simpler: use a **flood fill from the ocean** — any land that the ocean can't reach (landlocked depressions) is a potential lake site.

2. **Lake water level**: For each detected basin, set the lake's water level to the height of the basin's lowest rim point (the "sill"). The lake fills from its floor up to the sill.

3. **Data representation**: Store lakes as a list of `(center_x, center_z, water_level_y, radius)` tuples in the world data. At runtime, each lake is a local water plane at its specific elevation.

4. **Minimum lake size**: Filter out basins smaller than a configurable threshold (e.g., < 3 chunk radius) to avoid puddle-sized lakes.

5. **Lake count control**: Parameterize how many lakes to allow (e.g., 3-8 per world). Select the largest/most prominent basins.

#### Rationale for Post-Heightmap Basin Detection

- Lakes depend on the terrain shape — they can't be generated before the terrain exists
- Basin detection is a well-understood operation on heightmaps
- Keeping it as a post-process means the core noise pipeline stays clean
- This is how real hydrology works: water fills depressions in existing terrain

Start with the basin detection approach. It produces more realistic results and works with whatever terrain shape the noise generates.

### Heightmap Value Ranges (Proposed)

```
Ocean floor:      Y = water_level - 25 to water_level - 15  (deep ocean)
Shallow ocean:     Y = water_level - 5 to water_level        (coastal shelf)
Beach/coast:       Y = water_level to water_level + 3
Plains:            Y = water_level + 3 to water_level + 25
Mountains:         Y = water_level + 25 to water_level + 65
Mountain peaks:    Y = water_level + 50 to water_level + 65
```

With `water_level = 15`:
- Ocean floor: Y = -10 to 0
- Shallow ocean: Y = 10 to 15
- Beach: Y = 15 to 18
- Plains: Y = 18 to 40
- Mountains: Y = 40 to 80

This gives **25 units of ocean depth** (very deep water) and **65 units of land height**. The current system only has ~15 units of depth (0 to water_level) making everything feel shallow.

---

## Part 2: Water Shader Overhaul

### Current Issues

1. **Gerstner waves displace Y negatively** — `gerstner()` returns `a * sin(f)` for Y, which goes below water_level. This causes water to clip under land.
2. **Wave amplitude is uniform** — Same Gerstner strength at 1 unit depth and 25 units depth. Shallow water has aggressive waves.
3. **Depth sensing is screen-space only** — The shader uses `depth_texture` (screen-space depth buffer) to compute `water_thickness`, which is the distance from the water surface to the terrain behind it. This works for color/foam but doesn't help with wave amplitude because the vertex shader runs before the fragment shader.

### Proposed: Depth-From-Heightmap Approach

The core insight: **the heightmap data already exists**. We don't need to rely solely on screen-space depth. We can sample the terrain height at any position and compute `water_depth = water_level - terrain_height`.

#### Shader Uniforms (New/Changed)

```glsl
// Existing (kept)
uniform vec4 shallow_color : source_color = vec4(0.2, 0.5, 0.7, 0.6);
uniform vec4 deep_color : source_color = vec4(0.05, 0.15, 0.3, 0.9);
uniform float water_level = 15.0;
uniform float max_depth = 25.0;
uniform float foam_threshold = 2.0;
uniform float edge_fade = 2.0;

// New
uniform float min_wave_depth = 2.0;   // below this depth, no waves
uniform float max_wave_depth = 20.0;  // at this depth, full wave strength
uniform float shallow_wave_scale = 0.05;  // tiny ripple strength in shallow water
uniform float deep_wave_scale = 1.0;     // full wave strength in deep water

// Wave uniforms (existing, but strengths become multipliers)
// wave_a/b/c_strength, freq, dir, speed — unchanged
```

#### Vertex Shader: Depth-Modulated Waves

The key change: **clamp vertex Y so water never goes below terrain**.

Two approaches (use both):

**Approach A: Heightmap texture lookup in vertex shader**

Pass the terrain heightmap as a uniform texture (`uniform sampler2D terrain_heightmap`). Sample it at the vertex's world XZ position to get terrain height. Compute depth = `water_level - terrain_height`. Scale wave amplitude by depth.

This requires `hint_filter_nearest` and `repeat_disable` on the heightmap texture, and the heightmap must cover the visible area around the player.

**Drawback**: Vertex texture fetch is unreliable on WebGL2 (Compatibility renderer). Not guaranteed to work on all platforms.

**Approach B: Depth from vertex position (chosen primary approach)**

Since `WaterPlane` is a `PlaneMesh` that follows the player, we can compute approximate depth **per-vertex on the CPU side** and pass it as vertex color or a custom attribute.

In `water_plane.gd`:
1. Each frame (or on a timer), sample `WorldData.get_height_at(world_x, world_z)` for each vertex of the water mesh
2. Compute `depth = max(0, water_level - terrain_height)` for each vertex
3. Store depth as vertex color R channel (or a custom attribute)

In the shader:
- Read the depth from vertex color
- Scale Gerstner wave amplitude: `strength = lerp(shallow_wave_scale, deep_wave_scale, smoothstep(min_wave_depth, max_wave_depth, depth))`
- Clamp vertex Y: `VERTEX.y = max(VERTEX.y, water_level - depth + 0.1)` — ensures wave troughs never go below terrain

**This is the recommended approach for Compatibility renderer / WebGL2 compatibility.**

#### Vertex Shader (Pseudocode)

```glsl
void vertex() {
    float depth = COLOR.r;  // set by CPU, 0 = at/below terrain, 25 = deep ocean
    
    // Depth-based wave scaling
    float wave_scale = mix(shallow_wave_scale, deep_wave_scale, 
                           smoothstep(min_wave_depth, max_wave_depth, depth));
    
    vec3 p = VERTEX;
    p += gerstner(p.xz, wave_a_dir, wave_a_strength * wave_scale, 12.0, wave_a_speed);
    p += gerstner(p.xz, wave_b_dir, wave_b_strength * wave_scale, 8.0, wave_b_speed);
    p += gerstner(p.xz, wave_c_dir, wave_c_strength * wave_scale, 5.0, wave_c_speed);
    
    // Critical: water never goes below terrain
    // terrain_y = water_level - depth, water surface must be >= terrain_y
    float terrain_y = water_level - depth;
    p.y = max(p.y, terrain_y + 0.05);
    
    VERTEX = p;
}
```

#### Fragment Shader Enhancements

The existing fragment shader already does depth-based color and foam via screen-space depth. Keep that — it's correct for visual coloring at the pixel level. Add:

1. **Depth-based transparency**: Shallow water should be more transparent (lower alpha). Deep water should be opaque.
   ```glsl
   float vertex_depth = COLOR.r;
   float depth_alpha = smoothstep(0.0, max_depth * 0.3, vertex_depth);
   // Blend with existing screen-space depth alpha
   ALPHA *= depth_alpha;
   ```

2. **Depth-based color tinting**: Use vertex depth to bias toward shallow_color or deep_color independently of screen-space thickness. This handles the case where the camera is far away and screen-space depth is unreliable.
   ```glsl
   float vertex_depth_factor = smoothstep(0.0, max_depth, vertex_depth);
   vec4 vertex_color = mix(shallow_color, deep_color, vertex_depth_factor);
   ALBEDO = mix(ALBEDO, vertex_color.rgb, 0.5);  // blend with screen-space color
   ```

3. **Specular intensity by depth**: Deep water should have sharper specular (more reflective). Shallow water should have diffuse, muted reflections.
   ```glsl
   ROUGHNESS = mix(0.4, 0.05, smoothstep(min_wave_depth, max_wave_depth, vertex_depth));
   ```

4. **Foam improvement**: Current foam uses `1 - smoothstep(foam_threshold * 0.5, foam_threshold, water_thickness)`. This only catches breaks at the shoreline. Add wave-crest foam for deep water:
   ```glsl
   float crest_foam = smoothstep(0.6, 0.9, (VERTEX.y - water_level) / (wave_a_strength * deep_wave_scale + 0.001));
   // Only in moderate-to-deep water
   crest_foam *= smoothstep(min_wave_depth, max_wave_depth * 0.5, vertex_depth);
   ALBEDO = mix(ALBEDO, vec3(0.95, 0.98, 1.0), crest_foam * 0.3);
   ```

5. **Subsurface scattering approximation**: Deep water should have a subtle green/blue glow from below. Simple approximation:
   ```glsl
   vec3 sss_color = vec3(0.0, 0.3, 0.2);
   float sss = (1.0 - depth_factor) * 0.1 * max(0.0, dot(NORMAL, normalize(LIGHT_DIRECTION)));
   ALBEDO += sss_color * sss;
   ```

### Water Never Below Land — Complete Solution

Two mechanisms ensure water never renders below terrain:

1. **Vertex Y clamp** (above) — prevents Gerstner wave troughs from going below terrain height
2. **Fragment discard** (already exists in current shader, line 66-68) — `if (depth_diff < 0.0) { discard; }` removes fragments where terrain is above the water surface

Together these handle: (a) the water mesh itself doesn't dip below terrain, and (b) any remaining edge artifacts where water fragments overlap terrain are discarded.

### Shoreline Softening

Currently the water has a hard edge where terrain meets water ( exacerbated by the discard). Improve with:
- Existing `edge_fade` + `smoothstep` handles this in fragment shader — keep it
- Add **vertex-level shoreline damping**: where depth < `edge_fade`, scale wave amplitude down further
- The vertex Y clamp already acts as a natural shore dampener (waves can't go below terrain, so near-shore waves get cut off and appear calmer)

---

## Part 3: WaterPlane Architecture Changes

### Current

Single `PlaneMesh` at `water_level`, follows player, one `ShaderMaterial`.

### Proposed

```
WaterPlane (Node3D)
├── OceanPlane (MeshInstance3D)     — at sea_level (Y=15), large mesh
├── LakePlane1 (MeshInstance3D)     — at lake_1_level (e.g., Y=30)
├── LakePlane2 (MeshInstance3D)     — at lake_2_level (e.g., Y=25)
└── ...
```

#### OceanPlane

- Same as current WaterPlane but with depth vertex data
- Follows player position
- Uses the overhauled depth-sensitive shader
- Only renders where terrain height < sea_level (the discard in fragment shader handles this)

#### LakePlanes

- Each lake gets its own `MeshInstance3D`
- Position: center of lake basin, Y = lake water level
- Size: matched to lake basin extent (smaller than ocean plane)
- Does NOT follow player — only active when player is near
- Same shader as ocean but with `water_level = lake_level` and smaller wave scale (lakes are calmer than ocean)
- Lake mesh is a **circular or polygon PlaneMesh** sized to the lake basin, not a full 600x600 square

#### Lake Visibility Management

- Lakes are loaded/unloaded based on player distance (similar to chunks)
- Only render lakes within ~200m of the player
- Use `RenderingServer` directly for lake meshes (consistent with chunk rendering approach)

### CPU-Side Depth Computation

In `water_plane.gd` (or a new `_update_depth_data` method):

1. Access `WorldData` / `ChunkData` to get terrain heights
2. Iterate over the PlaneMesh vertices (access via `Mesh.surface_get_arrays()`)
3. For each vertex: compute world position from mesh local + WaterPlane global transform
4. Sample terrain height at that world XZ
5. Compute `depth = max(0.0, water_level - terrain_height)`
6. Write depth to vertex color R channel
7. Call `mesh.surface_update_region()` to upload updated vertex data

**Frequency**: Update every N frames (e.g., every 4 frames) or when player moves more than 10 units. Depth doesn't change rapidly.

**Performance**: 64x64 = 4096 vertices, each needs one heightmap lookup via `ChunkData.get_height_at()`. This is a fast bilinear interpolation — should be <1ms total.

---

## Part 4: NoiseParams & WorldConfig Changes

Add to `NoiseParams`:

```gdscript
@export_group("Ocean", "ocean_")
@export var ocean_floor_depth: float = 25.0    # how far below water_level the ocean goes
@export var ocean_min_depth: float = 3.0       # minimum depth for "deep" water
@export var island_suppression: float = 0.7   # morphological erosion for tiny islands

@export_group("Lakes", "lake_")
@export var lake_min_basin_area: float = 900.0  # min area in sq units for a lake
@export var lake_max_count: int = 8
@export var lake_min_elevation_above_sea: float = 5.0  # lakes must be at least this far above sea level

@export_group("Water Shader", "water_shader_")
@export var water_min_wave_depth: float = 2.0
@export var water_max_wave_depth: float = 20.0
@export var water_shallow_wave_scale: float = 0.05
@export var water_deep_wave_scale: float = 1.0
```

---

## Part 5: Heightmap Generator Changes

### New Pipeline Order

```gdscript
# Stage 1: Continental shape
var continent = fbm_with_warp(nx, ny, nz, nw, ...)  # domain-warped for organic shapes
continent = apply_continental_bias(continent)  # push toward land/ocean split
var continent_mask = smoothstep(0.45, 0.55, continent)  # 0=ocean, 1=land

# Stage 2: Ocean floor
var ocean_elevation = water_level - ocean_floor_depth  # e.g., Y=-10

# Stage 3: Base elevation (land or ocean)
var base_elevation = lerp(ocean_elevation, plains_elevation, continent_mask)

# Stage 4: Mountains (land only, scaled by continent_mask)
var mountain_uplift = mountains * pow(continent_mask, 0.5)
var elevation = base_elevation + mountain_uplift

# Stage 5: Detail
elevation += detail * detail_weight
elevation = clamp(elevation, height_range_min, height_range_max)
```

### Key Differences From Current

1. **Continental bias is explicit** — not a subtle weight of 0.035 but a full binary-ish split with smooth transition
2. **Ocean floor is genuinely low** — not just "terrain near 0 that happens to be below water_level"
3. **Mountains respect coastline** — no underwater mountains
4. **Depth exists** — the 25-unit gap between ocean floor and water_level creates deep water

### Island Suppression (Post-Process)

After heightmap generation, apply a smoothing pass that removes small land islands:

1. Threshold: `elevation > water_level` = land
2. For each land cell, count connected land cells in a 5-chunk radius
3. If count < threshold, set elevation to `water_level - 2` (below water)
4. This is computationally cheap (one pass over the heightmap) and only runs during generation

---

## Implementation Order

1. **Heightmap generator overhaul** — continental shape, ocean depth, mountain masking
2. **Water shader vertex depth** — CPU-side depth computation + vertex color pass
3. **Wave depth scaling** — vertex shader amplitude by depth
4. **Water Y clamping** — prevent wave troughs under terrain
5. **Fragment shader enhancements** — depth-based transparency, specular, foam
6. **NoiseParam/WorldConfig additions** — new parameters
7. **Lake basin detection** — post-generation analysis
8. **Lake water planes** — runtime lake rendering
9. **Island suppression** — remove tiny land dots
10. **Erosion filter** (future) — runevision-style pseudo-erosion

---

## Open Questions

- **Torus continent shape**: How to best define "one continent" on a torus? Options:
  - (A) Single continent emerges naturally from low-freq noise with bias toward a large connected landmass
  - (B) Use an offset in 4D noise space to create an asymmetric "pole" that maps to one side of the torus as land
  - (C) Generate on a flat map first, then map to torus (breaks seamless wrapping at one seam)
  
  **Recommendation**: Start with (A). Tune continental noise frequency (lower = fewer, larger landmasses) and octaves (more = wilder coastlines). If one continent is too hard to guarantee, accept 1-3 landmasses and make the primary one very large.

- **Lake depth data at runtime**: How to efficiently pass lake depth to the shader? Options:
  - (A) Separate PlaneMesh per lake with own ShaderMaterial + `water_level` uniform
  - (B) All lakes rendered into a world-space depth texture
  - (C) Bake lake extents into the terrain vertex color or a world mask texture
  
  **Recommendation**: (A) — simplest, few lakes (3-8), no texture management overhead.

- **Height range**: If ocean floor is Y=-10, `height_range_min` must become negative. Current: `0.0 to 80.0`. Proposed: `-10.0 to 80.0`. This changes the total range from 80 to 90 units. Verify this doesn't break anything in mesh builder, collision, or navmesh generation.

- **WebGL2 vertex texture fetch**: We're choosing CPU-side depth computation specifically to avoid this. Verify that `Mesh.surface_update_region()` works in Compatibility renderer for animated vertex colors.

---

## Rivers (Separate Follow-Up Plan)

Rivers are deferred to `plans/river-generation.md`. Key research notes:

- **Blue noise placement** for river sources (from mountain peaks / high elevation)
- **Gradient descent** from source to ocean — follow steepest downhill path on the heightmap
- **Runevision ridge map** could provide natural water drainage paths
- River rendering: mesh strip at terrain level, with flow animation in shader
- Rivers connect lakes to ocean (hydrologically correct)
- River width proportional to upstream drainage area
- Separate plan file to be created when terrain + lakes + ocean are working
