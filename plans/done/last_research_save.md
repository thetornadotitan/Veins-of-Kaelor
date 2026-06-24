Here is a comprehensive research summary based on official Godot docs, GitHub issues, and known community benchmarks:

Godot 4 Web Export (WebGL2) 3D Performance Research
1. Draw Calls, Triangle Counts, and Mesh Instances — GL Compatibility Renderer / WebGL2
Draw calls are the #1 bottleneck in web builds. The official docs state: "The communication and driver activity involved can be quite costly, especially in OpenGL, OpenGL ES and WebGL." Each OpenGL/WebGL API command requires expensive validation and state changes.

Practical limits (mid-range desktop GPU, Chrome/Firefox):

Metric	Conservative Target	Notes
Draw calls / frame	100–300 (hard limit ~500)	WebGL driver overhead per-draw-call is ~2-5x worse than Vulkan/DX11. Beyond 300 you'll see significant FPS drops on mid-range hardware.
Triangles / frame	200K–500K	Desktop can handle 1M+, but WebGL2 adds CPU-side overhead per batch. 500K is the upper bound for consistent 60fps on mid-range.
Active MeshInstance3D nodes	100–300	Each unique MeshInstance3D = at least 1 draw call. Automatic instancing (batching identical mesh+material) is NOT available in the Compatibility renderer — only Forward+. So 300 unique meshes = 300 draw calls.
Critical insight: The Compatibility renderer (the only renderer available for web) does not support automatic instancing of identical MeshInstance3D nodes. This is explicitly stated in the docs: "This is only implemented in the Forward+ renderer, not Mobile or Compatibility." This means every MeshInstance3D that isn't using MultiMesh is a separate draw call on web.

2. MeshInstance3D Count Before FPS Drop
Scenario	Approx. Limit	FPS
Simple meshes, shared material	~200–400	60fps (mid-range)
Unique materials per mesh	~50–100	60fps (material/state changes are very expensive)
Simple meshes, few shared materials	~300–500	60fps (high-end GPU)
Animated/skinned meshes	~20–50	60fps (skinning is costly on WebGL)
The Godot docs confirm: "If a scene has 20,000 objects with 20,000 different materials, rendering will be slow. If the same scene has 20,000 objects but only uses 100 materials, rendering will be much faster."

3. Practical Triangle Budget for 60fps Web
Profile	Triangles/Frame	Resolution	Shading Complexity
Conservative (any mid-range)	200K–300K	720p	Simple materials
Moderate	300K–500K	720p-1080p	Standard PBR
Aggressive (high-end GPU only)	500K–1M	1080p	Standard PBR
With baked lighting, few textures	Up to 500K	720p	Minimal shaders
Key factor: On web, fill rate is often worse than vertex count because WebGL2 goes through ANGLE (on Windows Chrome) or direct OpenGL paths, adding overhead. The docs' advice: "When targeting mobile devices, consider using the simplest possible shaders." This applies doubly to WebGL2.

Avoid rendering/scaling_3d/scale below 1.0 — confirmed bug #119317: setting Scaling3D < 1.0 in web exports causes massive FPS drops (160fps → 27fps on an RX 9070 XT rendering a single cube).

4. MultiMesh Performance in WebGL2 vs Desktop
MultiMesh is the most important optimization for web builds.

MultiMesh Scenario	Desktop (Forward+)	WebGL2 (Compatibility)
1,000 instances	~5-10 draw calls	~1 draw call per MultiMesh
10,000 instances	~5-10 draw calls	~1 draw call per MultiMesh
100,000 simple instances	Still fast (1 draw call)	Feasible if mesh is simple (few vertices)
1,000,000 instances	Possible on high-end	Not recommended — no per-instance culling; all always rendered
Key differences from desktop:

MultiMesh works the same way in WebGL2 (single draw call for all instances), which is its main advantage
WebGL2 uses OpenGL ES 3.0, which supports instanced drawing (glDrawArraysInstanced / glDrawElementsInstanced) — this is what MultiMesh uses under the hood
Performance gap: MultiMesh on WebGL2 is roughly 30-50% slower than native desktop for the same instance count, due to WebGL API overhead and ANGLE translation layers
On desktop Forward+, automatic instancing handles identical MeshInstance3Ds — not available on web
On web, you must use MultiMesh explicitly for any repeated geometry
Caveat: All instances in a MultiMesh share the same LOD level (closest AABB point to camera is used). No per-instance frustum culling. Split into separate MultiMeshInstance3D nodes for spread-out instances.

5. Main Performance Bottlenecks (Ranked)
For web builds specifically, from most to least impactful:

Draw calls / state changes (#1 bottleneck) — OpenGL/WebGL driver overhead per call is extremely high. Each material change, texture change, or shader change is a full state revalidation in the GL driver. Reduce unique materials aggressively.
Fill rate / fragment shading (#2) — WebGL2 + browser compositing adds overhead. Every transparent pixel is rendered in painter's order. Reduce overdraw, disable unnecessary post-processing, reduce shadow map sizes.
Vertex count (#3) — Less impactful than draw calls on most web hardware, but matters on integrated GPUs and mobile browsers. Avoid vertex-dense meshes in small screen areas (bad for tile-based GPUs on mobile web).
Shader compilation stalls — WebGL2 requires runtime shader compilation. First-time draws of new shader variants cause hitches. Pre-warm shaders by showing all material types briefly at load time.
CPU-side culling overhead — Occlusion culling adds CPU cost. On single-threaded web exports (the default), this competes with your game logic. Consider whether occlusion culling overhead is worth it for your scene complexity.
Texture bandwidth — Use VRAM compression (ETC2 for WebGL2). Uncompressed textures are a major bandwidth bottleneck, especially at 1080p+.
Transparency is disproportionately expensive on web. The docs warn: transparent objects are rendered back-to-front, forcing full shading on every overlapping fragment. Use dithering or alpha-cutout instead of alpha-blend where possible.

6. LOD in Web Builds
Mesh LOD is highly effective on web because it reduces both vertex count AND draw call weight (smaller meshes = less data per call).

Automatic mesh LOD (via meshoptimizer on import) works in the Compatibility renderer and on web. Generated LOD meshes are selected based on screen-space pixel threshold.
HLOD (Visibility Ranges) — More effective than mesh LOD alone because it replaces multiple MeshInstance3Ds with a single merged mesh at distance, reducing draw calls. This is the single most impactful LOD technique for web.
LOD threshold tuning: Rendering > Mesh LOD > LOD Change > Threshold Pixels (default 1px). Increase to 4-8px for more aggressive LOD on web — the visual loss is minimal at the smaller viewport sizes typical in browsers.
Mesh LOD + MultiMesh: All instances share the same LOD level. If instances are spread out, use separate MultiMeshInstance3D nodes per region.
Billboards/impostors: At far distances, replace 3D meshes with Sprite3D billboards via visibility ranges. A single textured quad vs. a 2000-tri tree is an enormous saving.
Practical impact: In scenes with 100+ objects, enabling HLOD can reduce draw calls from 100+ down to 5-10 at distance, improving FPS by 2-4x in web builds.

7. Godot-Recommended Best Practices for Web 3D Games
Compiled from official docs and the Web export guide:

Rendering
Use the Compatibility renderer (only option for web anyway)
Maximize material reuse — same material on as many meshes as possible; use texture atlases
Use MultiMesh for all repeated geometry (grass, trees, rocks, props)
Bake all lighting — use LightmapGI with Static bake mode for most lights; keep only DirectionalLight3D as Dynamic
Disable shadows on as many lights/objects as possible; reduce shadow map sizes
Avoid Scaling3D < 1.0 (confirmed bug causing 6x FPS loss)
Use VRAM-compressed textures (ETC2 for web/mobile)
Use single-threaded export (default since 4.3) for maximum hosting compatibility
Scene Structure
Use HLOD (Visibility Ranges) to merge distant geometry into fewer draw calls
Enable occlusion culling for interior/urban scenes (test cost vs. benefit)
Use VisibleOnScreenEnabler3D to disable off-screen animated meshes
Split large worlds into loadable chunks to limit active object count
Shaders
Use StandardMaterial3D (auto-optimizes shader variants) instead of custom shaders where possible
Disable unnecessary material features: normal maps, rim, clearcoat, subsurface scattering, refraction
Prefer alpha-cut / dithering over alpha-blend transparency
Use vertex-lit shading for particles/distanced objects via Vertex lighting material option
Audio
Default to Sample playback (not Stream) for web — avoids audio glitching on single-threaded exports
Register samples at load time with AudioServer.register_stream_as_sample()
Export
Use PWA export if you need threaded builds without server-side COOP/COEP headers
Compile custom export templates with unused features disabled to reduce .wasm from ~40MB to much less
Enable Brotli/gzip compression on server for .wasm and .pck files (wasm compresses ~75%)
8. Maximum Visible Terrain Size for Web
There is no official Godot number for this. Based on the constraints above:

For a heightmap terrain mesh:

Terrain Detail	Tri Budget	Max Size (world units at 1m/tri)	Notes
Low-poly (8K tris)	8,000	~90x90m (10m triangles)	Flat, stylized terrain only
Moderate (50K tris)	50,000	~224x224m (1m triangles)	Acceptable for most web games
Detailed (200K tris)	200,000	~447x447m (1m triangles)	Uses most of the web triangle budget alone
Very detailed (500K tris)	500,000	~707x707m (1m triangles)	Leaves almost nothing for other objects
Practical recommendation:

Terrain alone: 50K–150K triangles maximum in view at once
At 1m resolution: 224m x 224m visible area = **50K triangles**
At 2m resolution: 320m x 320m visible area = **50K triangles**
Chunk terrain and load/unload based on player position
Use LOD aggressively on terrain (reduce distant chunk resolution)
For visibility ranges of ~200-300m, you can keep terrain + props under the 300K total budget
Consider a low-poly terrain base (50K tris) with detail added via decals and small props only near the camera
The real constraint is draw calls, not triangles. A single terrain mesh of 200K triangles is 1 draw call and renders fast. 200 individual 1000-tri rocks = 200 draw calls and will tank FPS on web.

--------------

Based on extensive research (GPU Gems 2 geometry clipmaps, Geomipmapping, RasterGrid's GPU LOD, and general terrain rendering literature), here's a comprehensive technical reference:

Terrain LOD Stitching Techniques
1. What is LOD Stitching / Seaming?
When adjacent terrain chunks render at different LOD levels, their vertex grids don't align — a chunk at LOD0 may have 65x65 vertices while its neighbor at LOD1 has 33x33. This creates T-junctions where edges meet: the finer mesh has vertices that fall on the middle of a coarse edge, creating visible cracks (gaps where no triangle covers the space between the two meshes).

"Stitching" or "seaming" refers to any technique that eliminates these T-junctions and cracks so the terrain appears as a continuous, watertight surface.

2. How Commercial Engines Handle It
Engine	Approach
Elder Scrolls (Bethesda)	Uses a form of Geomipmapping with crack-fixing filler triangles along chunk borders. The newer Creation Engine uses streaming terrain with pre-built LOD meshes.
Far Cry (Dunia/Ubisoft)	Uses geometry clipmaps (Hoppe 2004 style) with transition regions that smoothly morph between LOD levels in the vertex shader.
Unity Terrain	Uses uniform LOD for the entire terrain (no per-chunk LOD variation) — avoids the seam problem entirely but limits performance. The newer HDRP supports more granular LOD.
Unreal Terrain	Uses a fixed LOD hierarchy where each component reduces by half. Seams are handled by ensuring border vertices remain on the coarser grid boundary. UE5's Nanite eliminates this for static meshes.
The common theme: either avoid LOD mismatch at borders, or fill the cracks with extra geometry, or morph between levels.

3. The "Skirts" / "Crack Fixing" Approach
Concept: For each terrain chunk, extend a vertical "skirt" strip of triangles downward along all four edges. These skirts hang below the terrain surface.

How it works:

Duplicate the border vertices and offset them downward (along -Y) by some amount
The skirt triangles connect the original border edge to the lowered duplicate
If two adjacent chunks have different LODs, the gap between their surfaces is now "covered" by the skirt of the higher-detail chunk — the skirt triangles project downward behind the crack
Since you never see under the terrain from above, the cracks are hidden
Pros: Extremely simple to implement (just duplicate border verts + offset). No index buffer modifications needed at runtime. Works with any LOD scheme.

Cons: Doesn't truly eliminate cracks — just hides them from typical viewing angles. Under-surface views (flying camera looking up at terrain from below) will still show cracks. Adds a small number of extra triangles (typically 2 × border_vertices per chunk). Doesn't handle horizontal cracking well on steep terrain.

Implementation complexity: Very low — can be done in the vertex shader by checking if a vertex is on a border and pushing it down.

4. The "Transitional LOD" / "Morph LOD" Approach
Concept: Instead of switching discretely between LOD levels, smoothly interpolate vertex positions over time from the current LOD to the next LOD.

How it works:

Each vertex stores (or computes) its position at both the current LOD and the next coarser LOD
A blend factor alpha (0→1) ramps up as the viewer approaches the LOD transition distance
Final position = lerp(position_coarse, position_fine, alpha)
When alpha = 0, the vertex is at the coarser position; when alpha = 1, it's at the fine position
The transition happens over a configurable width (e.g., 10% of the LOD region)
For terrain specifically (from GPU Gems 2, Hoppe's Geometry Clipmaps):

In the transition region near the outer boundary of each clipmap level, the vertex shader computes alpha = clamp((distance_from_viewer - alpha_start) / transition_width, 0, 1)
Height is blended: z = z_fine + alpha * (z_coarse - z_fine)
Both geometry AND normal maps are blended in the same transition region
The z_coarse value is pre-packed into the same texture as the fine elevation using integer/fractional packing
Pros: Completely eliminates popping. Seamless visual transition. No extra geometry needed. Runs entirely in the vertex shader.

Cons: Requires two height values per vertex (fine + coarse) — either two texture lookups or packed encoding. The transition region still has the full vertex count of the finer level (no GPU savings there). Doesn't solve the T-junction/crack problem by itself — it only smooths the visual pop. You still need stitching or skirts for geometric continuity.

5. Chunked LOD Approach
Concept (originally by Thatcher Ulrich, 2000): Organize terrain as a quadtree of chunks, where each chunk has a pre-built mesh at its LOD level. The key rule: a chunk's border vertices must always match the grid resolution of any neighbor's border.

How it handles seams:

Each chunk at LOD n has 2^n + 1 vertices per side (power-of-two + 1 to ensure shared corners)
When a chunk is at LOD n and its neighbor is at LOD n-1 (coarser), the finer chunk must degenerate its border triangles to match the coarser neighbor's vertex positions
This is done by pre-building stitch strips — small index buffer patterns that connect a fine edge to a coarse edge
The stitch strip for each of the 4 sides is selected based on the neighbor's LOD level
Common patterns: if neighbor is 1 level coarser, collapse every other border vertex onto its neighbor; if 2 levels coarser, collapse 3 out of 4, etc.
Stitch strip patterns (for a side with k fine vertices meeting k/2 coarse vertices):

Fine:  *-*-*-*-*-*-*-*
Coarse: *---*---*---*
Stitch:  /| /| /| /|    (diagonal triangles filling the gap)
Key constraint: Chunks may differ by at most 1 LOD level across a border. If a chunk switches from LOD0 to LOD2, an intermediate LOD1 ring must be inserted. This limits the crack patterns to a small, pre-computable set.

Pros: Clean geometric solution with no visual artifacts. Well-suited for out-of-core/streaming. Exact vertex matching at borders. Works with quadtree culling.

Cons: CPU must track neighbor LODs and select the right stitch strips per side (up to 4 different strips per chunk). Requires storing multiple index buffer variants or dynamically modifying them. The "max 1 LOD difference" constraint can cause LOD over-draw (forcing chunks to be higher-detail than needed to satisfy the neighbor constraint).

6. Vertex Morph / Geomorph Approach
Concept: A variation of the transition approach that specifically solves the "popping" problem during LOD switches by morphing vertex positions from the old LOD to the new LOD over several frames.

Two variants:

6a. Temporal Geomorph (time-based)
When a chunk transitions from LOD_n to LOD_n+1, start a timer (e.g., 0.5 seconds)
During the transition, alpha goes from 0 to 1
Each vertex position = lerp(LOD_n_position, LOD_n+1_position, alpha)
After the transition completes, the chunk permanently switches to LOD_n+1
Requires: Each chunk must be able to compute vertex positions at both the current AND next LOD level simultaneously.

6b. Spatial Geomorph (distance-based, used in Geometry Clipmaps)
alpha is computed purely from the viewer's distance, not from time
In the transition zone (e.g., outer 10% of each clipmap ring), alpha increases linearly from 0 to 1
No discrete "switch" event — the transition is continuous and implicit
This is what GPU Gems 2 describes: z = z_fine + alpha * (z_coarse - z_fine)
For a practical implementation in a shader:

// In vertex shader
float alpha = clamp((dist_from_viewer - transition_start) / transition_width, 0.0, 1.0);
float z_fine = textureLod(elevation_map, fine_uv, 0.0).r;
float z_coarse = textureLod(elevation_map, coarse_uv, 1.0).r;  // sample at LOD+1
float z = mix(z_fine, z_coarse, alpha);
Pros: Perfectly smooth transitions, no popping at all. The spatial variant requires no state tracking (no "currently transitioning" flag per chunk).

Cons: Extra texture fetch per vertex. Transition regions render at the finer LOD's triangle density (no GPU savings there). Still need separate crack-fixing for T-junctions at borders. Temporal variant requires per-chunk state and is harder to implement.

7. "Border Always LOD0" Approach
Concept: Force all chunk borders (outermost ring of vertices) to always render at the highest detail (LOD0) regardless of the chunk's actual LOD level. Interior vertices can simplify freely.

How it works:

Each terrain chunk stores its border vertices at full LOD0 resolution
The interior uses the simplified mesh for the chunk's assigned LOD level
Since all adjacent chunks share the same border vertex density (LOD0), their edges always match perfectly — no T-junctions possible by construction
This is essentially how Unreal Engine's terrain system works — each component's border ring stays at full res
Implementation:

A chunk at LOD0: full N×N grid (border IS the edge)
A chunk at LOD1: interior at half resolution, but the outermost row/column keeps every vertex
A chunk at LOD2: interior at quarter resolution, outermost row/column still full density
The border ring is a thin strip (typically 1-2 vertices wide) that acts as a "seam" between chunks
Structure per chunk:

+---+---------------+---+
| B |               | B |   B = Border strip (full LOD0 density)
| O |   Interior    | O |   I = Interior (reduced density per LOD)
| R |   (LOD N)     | R |
| D |               | D |
| E |               | E |
+---+---------------+---+
| B |   Interior    | B |
| O |   (LOD N)     | O |
| R +---------------+ R |
| D |               | D |
| E |               | E |
+---+---------------+---+
Pros: Eliminates ALL seam artifacts by construction. No runtime stitching logic needed. No skirts, no crack-filling triangles. Dead-simple to reason about. Adjacent chunks of any LOD always match at borders.

Cons: The border ring adds vertices that can't be simplified — for a chunk of size (N+2) × (N+2) with a 1-vertex border, at LOD2 the interior is (N/2-1)² but the border still costs 4*(N+1) vertices. The overhead is ~20-40% more vertices per chunk compared to free interior simplification. Doesn't eliminate the "pop" when interior LOD changes — you still need geomorphing for that.

8. Performance Cost Comparison
Technique	GPU Cost	CPU Cost	Memory Overhead	Seam Quality
Skirts	~2-5% more triangles	Near zero	Negligible (a few extra verts per chunk)	Hidden, not fixed
Stitch strips	Zero extra	Medium (select stitch pattern per side, track 4 neighbors)	Multiple index buffers per LOD combo	Perfect
Geomorph (spatial)	1 extra tex fetch per vertex	Near zero	Elevation at 2 LODs (packed)	Smooth pop-free but needs separate crack fix
Geomorph (temporal)	1 extra tex fetch per vertex during transition	Per-chunk transition state	Same as spatial	Smooth but needs separate crack fix
Border LOD0 ring	20-40% more vertices per chunk	Low	Slightly larger vertex buffers	Perfect seams
Geometry Clipmaps	Vertex texture lookups (expensive on older HW), transition blend	Low (toroidal updates)	L levels × n² textures	Near-perfect (transition + degenerate tris)
9. Recommended Approach for Godot 4 Web Builds
Use: Border-LOD0 Ring + Skirts + Spatial Geomorphing

Why this combination:
Web builds have constrained GPU bandwidth — you can't rely on vertex texture fetches (WebGL 2 has limited/no vertex texture support in practice). Avoid geometry clipmap-style vertex texture sampling.
Border-LOD0 ring eliminates seams by construction. It's the simplest approach that's provably correct — no edge cases, no neighbor tracking, no index buffer swapping. Perfect for Godot where you control mesh generation in GDScript/C#.
Skirts as a safety net. Even with border rings, floating-point precision on WebGL can cause sub-pixel cracks. Adding a thin skirt (1-2 pixel drop on border edges) costs almost nothing and guarantees no sky-visible-through-terrain artifacts.
Spatial geomorphing for the interior eliminates LOD pop. Since borders are always LOD0, you only need to morph the interior vertices between their current and next-coarser elevation. This can be done by storing both LOD heights in the vertex data (no texture fetch needed).
Practical Godot 4 Implementation Outline:
Mesh layout per chunk:
- Border ring: 1 vertex wide, always at full LOD0 resolution
- Interior: simplified at chunk's current LOD
- Skirt: border vertices duplicated, Y-offset downward
- Vertex data: vec3 position + float z_coarse (for geomorphing)

LOD selection:
- Based on camera distance per chunk (simple in _process)
- Clamp: no chunk can be more than 1 LOD different from neighbor
  (enforced by the border ring — already handled)

Transition:
- Store blend alpha per chunk (0 = fine, 1 = fully coarse)
- In vertex shader: z = mix(z_fine, z_coarse, alpha)
- alpha ramps based on distance, computed in shader from camera pos
- Only applies to interior vertices; border vertices always use z_fine

Index buffer:
- Pre-built per LOD level (you only need 1 per LOD, no neighbor variants)
- Border ring topology is identical across all LODs
Key Godot-specific considerations:
Use ArrayMesh to build terrain procedurally — gives full control over vertex layout
Store z_coarse as a custom vertex attribute (e.g., using Mesh.ARRAY_CUSTOM0)
Vertex shader: access via CUSTOM0.x or a uniform for the blend alpha
WebGL 2 limitation: No textureLod() in vertex shaders on many devices — avoid vertex texture fetches entirely and bake both heights into vertex data
Chunk size: 33x33 (32² quads) works well — border ring is 4×32 = 128 extra vertices, which is ~12% overhead at LOD0 and shrinks relative to interior cost at coarser LODs
Pre-allocate all LOD meshes at load time to avoid runtime mesh regeneration
Performance estimate for web:
A 33×33 chunk at LOD0: 2048 triangles (interior) + ~128 triangles (border ring) + ~128 triangles (skirt) = **2304 triangles per chunk**
At LOD2: 512 triangles (interior) + ~128 (border) + ~128 (skirt) = **768 triangles per chunk** (3× reduction)
A visible area of ~16×16 chunks ≈ 12K-37K triangles — very comfortable for WebGL


---------


Now I have a thorough understanding of both the research and the existing codebase. Here is the comprehensive research document:

Multi-Layer Noise Terrain Generation — Research Summary
Context: Your Current System
Your existing terrain pipeline at heightmap_generator.gd:36-62:

Maps 2D world coordinates (wx, wz) to 4D torus coordinates: nx = R*cos(2π*wx/W), ny = R*sin(2π*wx/W), nz = R*cos(2π*wz/W), nw = R*sin(2π*wz/W)
Calls noise_4d_fbm(nx, ny, nz, nw, octaves, frequency, persistence, lacunarity) — a single FBM pass
Current params: height_scale=4.0, octaves=4, persistence=0.5, lacunarity=2.0, height_range=[0, 40]
Output: (noise * 0.5 + 0.5) remapped to [0, 40]
Problem: One FBM pass with persistence=0.5 produces gentle rolling hills. No mountains, no flat plains, no valleys — just uniform bumpy terrain.

1. Multi-Octave FBM: The Standard Approach
Fractional Brownian Motion (FBM) stacks noise at increasing frequencies (detail) with decreasing amplitudes (influence). Your existing noise_4d_fbm already does this. The key insight from Red Blob Games (Amit Patel):

Standard FBM produces only one type of terrain. To get multiple terrain types, you need to go beyond a single FBM call.

The standard layering approach uses separate noise layers at different scale regimes, not just different octaves:

Layer	Frequency	Purpose	Frequency ratio vs base
Continental	1×	Landmass shapes, ocean vs land	1
Mountain	4–8×	Mountain ranges, large valleys	4–8
Hill	16–32×	Rolling hills, ridges	16–32
Detail	64–128×	Bumps, rocks, fine texture	64–128
Lacunarity=2.0 is the standard (each octave doubles frequency, halves the wavelength). This produces self-similar fractal terrain. Higher lacunarity (2.5–3.0) creates more gap between scales, making features at different scales feel more distinct.

2. Combining Continental → Mountain → Hill Noise
The standard technique is additive blending weighted by a "mountain mask":

continental = fbm(pos, 1-2 octaves, freq=0.002)   // Large land shapes
mountain_mask = fbm(pos_diff_seed, 1-2 octaves, freq=0.004)  // Where mountains appear
mountain = ridge_fbm(pos, 4-6 octaves, freq=0.008)  // Ridged mountain detail
hills = fbm(pos, 4-6 octaves, freq=0.016)           // Gentle hills

// Mountain mask determines where mountains exist (0 = flat, 1 = full mountains)
mountain_factor = smoothstep(0.3, 0.7, mountain_mask)

// Combine: plains where no mountains, mountains where mask says so
elevation = lerp(hills, mountain, mountain_factor)
elevation = elevation + 0.3 * continental  // Continental shape on top
Frequency ratios that work:

Continental:Mountain = 1:4 to 1:8
Mountain:Hill = 1:2 to 1:4
Within each layer, use standard FBM lacunarity of 2.0
No Man's Sky approach (Sean Murray, GDC 2017): They layer ~15-20 different noise functions with different types (standard, ridged, terraced), each weighted by other noise functions that act as region masks. The key is that every parameter can itself be driven by noise.

3. Domain Warping
From Inigo Quilez's seminal article (iquilezles.org/articles/warp):

Domain warping distorts the input coordinates to a noise function using another noise function, creating organic, terrain-like patterns:

// Single warp — fbm( p + fbm(p) )
vec2 q = vec2(fbm(p + vec2(0.0, 0.0)), fbm(p + vec2(5.2, 1.3)))
result = fbm(p + 4.0 * q)

// Double warp — fbm( p + fbm( p + fbm(p) ) )  
vec2 r = vec2(fbm(p + 4.0*q + vec2(1.7, 9.2)), fbm(p + 4.0*q + vec2(8.3, 2.8)))
result = fbm(p + 4.0 * r)
For terrain, domain warping:

Creates meandering valleys and ridges instead of uniform blobs
The warp amplitude (4.0 in the example) controls how much coordinates shift — higher = more distorted/organic
A single warp creates continent-scale deformation; double warp adds fine detail warping
The offset constants (5.2, 1.3, etc.) are arbitrary — they just ensure the two fbm calls sample different parts of the noise space
Adapted for your 4D torus system:

func warped_fbm(noise, nx, ny, nz, nw, octaves, freq, pers, lac, warp_strength):
    # First warp layer
    var qx = noise.noise_4d_fbm(nx, ny, nz, nw, 2, freq * 0.5, 0.5, 2.0)
    var qy = noise.noise_4d_fbm(nx + 5.2, ny + 1.3, nz + 7.1, nw + 3.7, 2, freq * 0.5, 0.5, 2.0)
    
    # Apply warp to coordinates
    var wx = nx + warp_strength * qx
    var wy = ny + warp_strength * qy
    var wz = nz + warp_strength * qx  # Reuse or use separate warp for z/w
    var ww = nw + warp_strength * qy
    
    return noise.noise_4d_fbm(wx, wy, wz, ww, octaves, freq, pers, lac)
Performance note: Domain warping doubles or triples the noise evaluations. For pre-baked worlds this is fine.

4. Flat Plains vs Mountainous Areas
Three proven techniques:

4a. Ridge Noise (sharp mountain ridges)
function ridged_noise(x, y, z, w):
    return 1.0 - abs(noise(x, y, z, w))  // Creates V-shaped valleys, sharp ridges
For multi-octave ridge noise, multiply each octave by the previous so detail only appears on existing ridges:

e0 = ridged_noise(freq1)
e1 = ridged_noise(freq2) * e0  // Detail only where mountain already exists
e2 = ridged_noise(freq3) * (e0 + e1)
result = (e0 + e1 + e2) / weights
This is the "ridged multifractal" approach from Musgrave's original work. It creates realistic-looking mountain spines.

In your 4D system:

func ridged_fbm(noise, nx, ny, nz, nw, octaves, freq, pers, lac):
    var output = 0.0
    var denom = 0.0
    var amp = 1.0
    var f = freq
    var weight = 1.0
    for i in range(octaves):
        var n = 1.0 - abs(noise.noise_4d(nx * f, ny * f, nz * f, nw * f))
        n = n * n  # Square for sharper ridges
        n *= weight
        weight = clamp(n * 2.0, 0.0, 1.0)  # Next octave only where this one has ridges
        output += n * amp
        denom += amp
        f *= lac
        amp *= pers
    return output / denom
4b. Terrace/Step Noise (plateau-like terrain)
terrace(e, steps) = round(e * steps) / steps
This quantizes heights into flat terraces. Using smoothstep instead of round gives rounded terraces:

smooth_terrace(e, steps) = floor(e * steps) / steps + smoothstep(0, 1, fract(e * steps))
4c. Slope-Based Blending (plains + mountains)
The most effective approach for varied terrain:

# Separate noise for "where should mountains be"
var mountain_mask = noise.noise_4d_fbm(nx, ny, nz, nw, 2, 0.003, 0.5, 2.0)
# Remap to [0, 1] with smoothstep to create crisp region boundaries
var mountain_factor = smoothstep(0.35, 0.65, (mountain_mask * 0.5 + 0.5))

# Plains: low-frequency, gentle FBM
var plains = plain_fbm(...)   # Low persistence (0.3), low frequency

# Mountains: ridged multifractal
var mountains = ridged_fbm(...)  # Higher persistence (0.55), ridge noise

# Blend based on mask
var height = lerp(plains, mountains, mountain_factor)
4d. Power-curve redistribution (flatten valleys, sharpen peaks)
From Red Blob Games — raise elevation to a power to push mid-elevations into valleys:

e = pow(e, exponent)
exponent=1: no change
exponent=2–3: pushes mid-range terrain lower, creating flatter lowlands and sharper peaks
exponent=0.5: pulls terrain up, creating more plateaus
5. Thermal & Hydraulic Erosion Simulation
Thermal Erosion
Simulates material crumbling when slope exceeds an angle of repose:

for each cell:
    for each neighbor:
        diff = height[cell] - height[neighbor]
        if diff > threshold:
            transfer = (diff - threshold) * 0.5
            height[cell] -= transfer
            height[neighbor] += transfer
Fast: ~5–20 iterations over the full heightmap, very simple. Produces talus slopes at cliff bases.

Hydraulic Erosion
Simulates water drops flowing downhill, picking up and depositing sediment:

Drop a particle at random position
Follow gradient downhill (with inertia/friction)
Erode where water flows fast (steep slopes, carrying capacity exceeded)
Deposit where water slows (flat areas, carrying capacity not met)
Evaporate water over time
Typical: 50,000–500,000 drop simulations for a 1024×1024 heightmap. Takes seconds to minutes.

Feasibility for Pre-Baked Worlds
For a pre-baked world, both are entirely feasible since generation happens once offline. However:

Standard hydraulic erosion has a major problem with torus worlds: It's a global iterative simulation that requires the entire heightmap in memory. With your world being 128×128 chunks × 40² grid = 5120×5120 vertices, you'd need the full heightmap loaded (~100MB). That's feasible for a pre-bake step.
The erosion filter technique by Rune Skovbo Johansen (runevision, 2026) is a far better fit: It's a point-evaluable pseudo-erosion that produces branching gullies and ridges without simulation. Every point can be computed independently — perfect for chunk-based generation on a torus. This is what you should use.
The Runevision Erosion Filter (Recommended)
This is a noise-based approach that looks like erosion but is evaluable per-point:

Compute terrain gradient (slope direction) at each point
Apply stripe patterns aligned with the gradient (gullies along slope)
Each octave's gullies modify the slope for the next octave, creating natural branching
Fade gullies to zero at peaks/valleys to preserve crisp features
"Stacked fading" ensures smaller gullies don't break up larger ridges
"Normalized gullies" for consistent ridge sharpness
Available implementations: Shadertoy (GLSL), Unity Burst, Godot (forum post), Blender geometry nodes.

For your system: This works directly with 4D noise — replace the base noise with an erosion-filtered version. Since it's point-evaluable, it preserves the torus wrapping automatically.

6. Biome Region Generation from Noise
The Whittaker Biome Model (Red Blob Games approach)
Use two independent noise fields — elevation and moisture — to determine biome:

function biome(elevation, moisture):
    if elevation < water_level: return OCEAN
    if elevation < water_level + 0.02: return BEACH
    
    if elevation > 0.8:
        if moisture < 0.1: return SCORCHED
        if moisture < 0.2: return BARE
        if moisture < 0.5: return TUNDRA
        return SNOW
    
    if elevation > 0.6:
        if moisture < 0.33: return TEMPERATE_DESERT
        if moisture < 0.66: return SHRUBLAND
        return TAIGA
    
    if elevation > 0.3:
        if moisture < 0.16: return TEMPERATE_DESERT
        if moisture < 0.50: return GRASSLAND
        if moisture < 0.83: return TEMPERATE_FOREST
        return TEMPERATE_RAIN_FOREST
    
    # Low elevation
    if moisture < 0.16: return SUBTROPICAL_DESERT
    if moisture < 0.33: return GRASSLAND
    if moisture < 0.66: return TROPICAL_SEASONAL_FOREST
    return TROPICAL_RAIN_FOREST
Critical: Use different seeds (or large coordinate offsets) for elevation vs moisture noise, otherwise they'll be correlated and produce boring stripe-like biome bands.

Terrain-Type Regions (flat plains, rugged mountains, river valleys)
For your 2D RPG, you want spatial regions of different terrain types, not just Whittaker biomes:

# Layer 1: Continental shape (where is land vs water, low vs high)
var continental = noise_fbm_4d(pos, 2 octaves, freq=0.003)

# Layer 2: Mountain mask (where should mountains exist)
var mountain_mask = noise_fbm_4d(pos + offset1, 2 octaves, freq=0.005)
mountain_mask = smoothstep(0.3, 0.7, mountain_mask * 0.5 + 0.5)

# Layer 3: Valley factor (creates river-like low areas)
var valley_mask = noise_fbm_4d(pos + offset2, 1 octave, freq=0.004)
valley_mask = smoothstep(0.4, 0.6, valley_mask * 0.5 + 0.5)  # Binary-ish: valley or not

# Combine:
# High mountain_mask + low valley_mask = rugged mountains
# Low mountain_mask + low valley_mask = flat plains
# Low mountain_mask + high valley_mask = river valley (even flatter)
# High mountain_mask + high valley_mask = mountain pass (medium height)
Adding Temperature/Moisture for Biome Color
Your NoiseParams already has biome_temperature_scale and biome_moisture_scale (0.005, 0.008). These are correct scales — they operate at continental frequency to produce large biome regions. The key formula for elevation-modified temperature:

var temp = temperature_noise - 0.3 * elevation  # Higher = colder
var moist = moisture_noise
7. Proven FBM Parameter Sets for Varied Terrain
Gentle rolling hills (current)
octaves=4, persistence=0.5, lacunarity=2.0, frequency=4.0
Problem: persistence=0.5 means each octave has half the amplitude → smooth, boring
Mountains and valleys (ridged multifractal)
octaves=6-8, persistence=0.5, lacunarity=2.0-2.5, using ridge function
Power redistribution: pow(e, 2.5-3.5) to flatten lowlands, sharpen peaks
This is the single most impactful change you can make
Mixed terrain (plains + mountains, recommended)
Continental: octaves=2, persistence=0.5, lacunarity=2.0, freq=0.003
Mountain mask: octaves=2, persistence=0.5, lacunarity=2.0, freq=0.005
Mountain height: ridged, octaves=6-8, persistence=0.55, lacunarity=2.2, freq=0.01
Plains height: standard, octaves=4, persistence=0.35, lacunarity=2.0, freq=0.008
Detail: standard, octaves=2, persistence=0.3, lacunarity=2.5, added on top of everything
Proven numbers from production games:
Factorio (FFF-390): Uses multi-layer noise with different scales per layer, each combined through addition/multiplication/clamping operations. Very similar to the "mountain mask" approach.
Minecraft: Uses 3-octave simplex for continental, then adds biome-specific height modifiers. Continental scale is ~1/800 of the world.
No Man's Sky: ~15-20 noise layers of different types, all combined with weighting functions.
8. 4D Torus Noise Interaction with Multi-Layer Terrain
Your torus mapping is completely compatible with all the techniques above. Here's why:

How the torus mapping works
nx = R * cos(2π * wx / W)   // X-axis world coord → two 4D coords
ny = R * sin(2π * wx / W)
nz = R * cos(2π * wz / W)   // Z-axis world coord → two 4D coords
nw = R * sin(2π * wz / W)
Walking off the east edge of the world (wx = W+1) gives the same (nx, ny, nz, nw) as wx = 1, because cos(2π * (W+1)/W) = cos(2π/W + 2π) = cos(2π/W). Perfect seamless wrapping.

Key interactions:
All noise calls must go through the torus mapping. Any function that uses world coordinates must convert them to 4D first. This means separate noise layers (mountain mask, moisture, temperature, domain warp) all need their own 4D coordinate conversion — but they can share the same (nx, ny, nz, nw) since the mapping is the same; they just need different noise seeds or large offsets.
Domain warping in 4D is safe. Add the warp offsets to the 4D coordinates before evaluation. The warp must not be so large that it moves the coordinates outside a "reasonable" range on the 4D torus, but since the noise function is periodic along the torus anyway, any warp amount is fine — you'll just sample a different part of the torus.
Ridge noise works unchanged in 4D. The 1.0 - abs(noise) transform applies to the output, not the input.
Power redistribution, terrace noise, slope blending all work on the output values and are completely independent of the 4D mapping.
4D noise has a narrower absolute range than 2D. Per KdotJPG's research, 4D simplex noise maxes out at a lower absolute value than 2D due to more gradient cancellation in higher dimensions. Multiply by sqrt(2) ≈ 1.414 to compensate, or calibrate empirically by sampling many points and finding actual min/max.
Frequency scale consideration: Your current height_scale=4.0 is used as the frequency parameter sent to noise_4d_fbm. The actual spatial frequency depends on torus_radius. With torus_radius=1.0, the 4D torus has circumference 2π ≈ 6.28. A frequency of 4.0 means the noise traverses ~4 full cycles around this circumference, creating features of wavelength ~1.57 in 4D space. In world space, this maps to world_size/4 ≈ 1280 units per feature — those are continental-scale features. For hills at ~80-unit wavelength, you'd need frequency ~50-64.
Correct frequency scaling for your world
With world_size = 5120 (128 chunks × 40 units):

Continental features (~2000 units): freq ≈ 2.5
Mountain ranges (~500 units): freq ≈ 10
Hills (~100 units): freq ≈ 50
Bumps/detail (~25 units): freq ≈ 200
Your current height_scale=4.0 is only producing continental-scale variation. To get mountains and hills, you need the separate layer approach with appropriate frequencies.

Recommended Implementation Plan for Your Codebase
Add ridge noise function to simplex_noise_4d.gd / simplex_noise_4d.cpp (ridged multifractal variant of fbm)
Expand NoiseParams to include separate parameters for continental, mountain, hill layers plus a mountain mask
Rewrite HeightmapGenerator.generate_chunk_heightmap() to use multi-layer composition:
# Pseudocode
var continental = noise_4d_fbm(nx, ny, nz, nw, 2, 0.003, 0.5, 2.0)
var mountain_mask = noise_4d_fbm(nx+100, ny+200, nz+300, nw+400, 2, 0.005, 0.5, 2.0)
mountain_mask = smoothstep(0.3, 0.7, mountain_mask * 0.5 + 0.5)
var mountains = ridged_fbm(nx, ny, nz, nw, 6, 0.01, 0.55, 2.2)
var plains = noise_4d_fbm(nx, ny, nz, nw, 4, 0.008, 0.35, 2.0)
var elevation = lerp(plains, mountains, mountain_mask) + 0.3 * continental
elevation = pow(max(0, elevation), 2.5)  # Flatten valleys, sharpen peaks
Optionally add the erosion filter (runevision approach) as a post-process on the generated heightmap, since it's point-evaluable and works per-chunk
Add biome noise using separate 4D noise calls with different offsets for temperature and moisture, then use the Whittaker lookup table

---------

Here is a comprehensive research document on water rendering in Godot 4 for the GL Compatibility renderer targeting WebGL2:

Godot 4 Water Rendering for GL Compatibility / WebGL2
1. Water as a Fixed-Height Plane
Setup:

Create a MeshInstance3D with a PlaneMesh (oriented to XZ)
Position it at your desired water_level Y coordinate
The plane should be large enough to cover your terrain
Assign a ShaderMaterial with a custom spatial shader
# In script or scene:
var water_plane = MeshInstance3D.new()
water_plane.mesh = PlaneMesh.new()
water_plane.mesh.size = Vector2(200, 200)  # adjust to terrain
water_plane.rotation_degrees.x = -90  # PlaneMesh faces Y-up by default; this isn't needed if using PlaneMesh which is already XZ
water_plane.position.y = water_level
Key render modes for the shader:

shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;
cull_disabled: See both sides of the water from above and below
depth_draw_always: Ensures depth is written even with alpha, critical for depth-based effects
2. Wave/Displacement Approaches Compatible with WebGL2
WebGL2 = OpenGL ES 3.0. Not available: compute shaders, tessellation shaders, geometry shaders.

Available approaches:

A. Gerstner Waves (vertex shader)
The gold standard for water displacement. Sum multiple sine-wave components with different directions, frequencies, and amplitudes. Fully compatible with Compatibility renderer.

vec3 gerstner_wave(vec2 pos, vec2 direction, float steepness, float wavelength, float time) {
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k);
    float f = k * (dot(direction, pos) - c * time);
    float a = steepness / k;
    return vec3(direction.x * a * cos(f), a * sin(f), direction.y * a * cos(f));
}

void vertex() {
    vec3 p = VERTEX;
    p += gerstner_wave(p.xz, vec2(1.0, 0.0), 0.25, 12.0, TIME);
    p += gerstner_wave(p.xz, vec2(0.0, 1.0), 0.15, 8.0, TIME * 1.1);
    p += gerstner_wave(p.xz, vec2(0.7, 0.7), 0.1, 5.0, TIME * 0.9);
    VERTEX = p;
}
B. Noise-based Displacement (vertex shader)
Sample a 3D noise texture (FastNoiseLite resource) with animated offset:

uniform sampler3D noise_tex;
void vertex() {
    vec3 sample_pos = TIME * 0.1 + vec3(VERTEX.x, 0, VERTEX.z) * 0.05;
    VERTEX.y += texture(noise_tex, sample_pos).r;
}
(This is the approach used by the "Simple Water" shader from godotshaders.com)

C. Procedural Hash/FBM Noise
Generate noise mathematically in the shader — no textures needed:

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) { /* value noise interpolation */ }
float fbm(vec2 p) { /* fractal sum of noise octaves */ }

void vertex() {
    float wave = fbm(VERTEX.xz * 0.5 + TIME * 0.3) * 0.5;
    VERTEX.y += wave;
}
Used by the "Lowpoly Water with sspr" shader. Most portable — no texture dependencies.

D. Scrolling Normal Maps (fragment shader only)
Don't displace vertices at all. Instead, scroll two normal maps in different directions at different speeds, blend them, and apply as NORMAL_MAP. Fast, simple, gives the illusion of surface motion without geometry changes. Excellent for flat water.

3. Preventing Water from Showing Under Terrain
This is the critical problem. A flat water plane at Y=water_level will render everywhere including under hills. Several solutions:

Approach A: Depth Buffer / hint_depth_texture (Screen-Space)
The standard approach for Compatibility renderer. Compare the water fragment's depth against the scene depth buffer. If terrain is closer to the camera (above water), reduce alpha or discard.

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
    float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    
    // IMPORTANT: Compatibility renderer uses different NDC convention
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, scene_depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
    #endif
    
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_scene_depth = -view.z;
    
    // Get water's own linear depth
    float water_ndc_z = FRAGCOORD.z;
    vec3 water_ndc = vec3(SCREEN_UV * 2.0 - 1.0, water_ndc_z);
    vec4 water_view = INV_PROJECTION_MATRIX * vec4(water_ndc, 1.0);
    water_view.xyz /= water_view.w;
    float linear_water_depth = -water_view.z;
    
    float depth_diff = linear_scene_depth - linear_water_depth;
    
    // If terrain is closer (above water), fade out water
    if (depth_diff > 0.0) {
        // terrain is above water level here — mask it
        ALPHA = 0.0;
        // or use smoothstep for soft edges
    }
}
Critical Compatibility renderer note: The NDC depth convention differs. From the "Mesh Blend" shader on godotshaders.com:

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
You must use the CURRENT_RENDERER check or your depth reconstruction will be wrong on WebGL2/Compatibility.

Approach B: Alpha Depth Fade (Soft Particles / Proximity Fade)
Fade water alpha based on depth difference. When terrain is close to or above water level, alpha goes to 0:

uniform float fade_distance = 2.0;
void fragment() {
    // ... get linear_scene_depth and linear_water_depth ...
    ALPHA *= clamp(1.0 - smoothstep(
        linear_scene_depth + fade_distance, 
        linear_scene_depth, 
        linear_water_depth
    ), 0.0, 1.0);
}
This is exactly the "soft particle" technique. Godot 4.6+ also has built-in proximity_fade on StandardMaterial3D, but using a custom shader gives you more control.

Approach C: discard Where Terrain is Above
Hard cutoff using discard:

if (linear_depth >= linear_object_depth) {
    discard; // terrain is closer, don't render water here
}
Warning: discard has a performance cost — prevents early-Z and depth prepass optimization. Prefer alpha fade.

4. Water That Respects Terrain Height
Screen-Space Depth Method (Recommended)
Use hint_depth_texture to compare depths. This is the only practical screen-space method that works in Compatibility renderer because:

hint_depth_texture is supported in Compatibility mode
hint_normal_roughness_texture is NOT supported in Compatibility (Forward+ only)
Compute shaders are not available
The depth texture approach automatically handles any terrain shape — hills above water get masked, valleys below water show water. This is what the "Foam Edge Water Shader" and "Simple Water" shaders do.

Alternative: Terrain Heightmap Texture
Pass your terrain's heightmap as a sampler2D uniform. In the fragment shader, look up the terrain height at the current world XZ position:

uniform sampler2D terrain_heightmap;
uniform float terrain_size;
uniform float terrain_height_scale;

void fragment() {
    vec2 terrain_uv = (VERTEX.xz + terrain_size * 0.5) / terrain_size;
    float terrain_h = texture(terrain_heightmap, terrain_uv).r * terrain_height_scale;
    float water_y = water_level; // uniform
    
    if (terrain_h > water_y) {
        discard;
    }
}
Pros: No depth buffer dependency, works in all renderers. Cons: Requires you to pass the heightmap and know its exact mapping. Doesn't handle non-heightmap terrain (CSG, instanced meshes, etc.).

Alternative: Area3D / Collision Masking (GDScript)
Use an Area3D with a collision shape matching the water plane. Only enable water rendering in areas where the Area3D overlaps terrain valleys. This is a game-logic approach, not a rendering one, but can work for simple level layouts.

5. Swimming / Water Collision for CharacterBody3D
Detecting Water Entry
# On your water node (e.g., WaterPlane with Area3D child)
extends Node3D

@export var water_level: float = 0.0

func _ready():
    # Add an Area3D for water detection
    var area = Area3D.new()
    var shape = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = Vector3(200, 10, 200)  # covers terrain
    shape.shape = box
    area.add_child(shape)
    area.position.y = water_level - 5  # center of detection volume
    add_child(area)
    area.body_entered.connect(_on_body_entered_water)
    area.body_exited.connect(_on_body_exited_water)

func _on_body_entered_water(body):
    if body.has_method("enter_water"):
        body.enter_water()

func _on_body_exited_water(body):
    if body.has_method("exit_water"):
        body.exit_water()
Simpler Y-Position Check (No Area3D needed)
# In your character's _physics_process:
var is_in_water = global_position.y < water_level

if is_in_water:
    velocity.y += swim_buoyancy * delta  # upward force
    velocity *= (1.0 - water_drag * delta) # water resistance
    # Reduce gravity or zero it
    # Allow vertical movement (swim up/down)
Full Swimming Controller Pattern
extends CharacterBody3D

var water_level: float = 5.0
var is_swimming: bool = false
var swim_speed: float = 4.0
var swim_gravity: float = -2.0  # reduced gravity underwater
var buoyancy: float = 5.0
var water_drag: float = 3.0

func _physics_process(delta):
    var was_swimming = is_swimming
    is_swimming = global_position.y < water_level
    
    if is_swimming:
        # Apply buoyancy (float up)
        velocity.y += buoyancy * delta
        # Water drag
        velocity *= (1.0 - water_drag * delta)
        # Swim input
        var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
        velocity.x = direction.x * swim_speed
        velocity.z = direction.z * swim_speed
        
        # Vertical swim input
        if Input.is_action_pressed("jump"):
            velocity.y = swim_speed
        elif Input.is_action_pressed("crouch"):
            velocity.y = -swim_speed
    else:
        # Normal gravity and movement
        if not is_on_floor():
            velocity.y -= 9.8 * delta
        # ... normal movement code ...
    
    move_and_slide()
Key points:

Switch motion_mode to MOTION_MODE_FLOATING when swimming (no floor concept)
Or keep MOTION_MODE_GROUNDED and treat water like a floor at water_level
Apply velocity.y += buoyancy * delta to counteract gravity
Apply drag: velocity *= (1.0 - water_drag * delta)
You can change up_direction or modify floor_max_angle when transitioning
Area3D Approach (more precise)
Create an Area3D with a BoxShape3D at water level. Connect body_entered/body_exited signals. This handles cases where terrain creates overhangs or the water surface isn't perfectly flat.

6. Compatibility-Renderer-Safe Water Shader Examples
Best picks from godotshaders.com:
Shader	Techniques	Compatibility Safe?	Notes
Simple Water (dairycultist)	Depth texture, 3D noise texture, vertex displacement	Yes	Minimal, depth-based alpha. Best starting point.
Toon Water (dairycultist)	Depth texture, scrolling texture, simple vertex waves	Yes	Unshaded, stylized. Good for NPR.
Foam Edge Water Shader (Antz)	Depth texture, screen texture, foam, Gerstner waves, normal maps	Mostly (see note)	Comprehensive but heavy. Uses world_vertex_coords, diffuse_burley. Depth reconstruction via camera_mix matrix.
Lowpoly Water with sspr (meny233)	Gerstner waves, depth texture, FBM noise, SSR	Partial	SSR ray-marching is expensive for web. Strip the SSR for WebGL2.
Water with foam and depth (SomebodyGPT)	Depth texture, screen texture, normal maps, foam	No — "Works only on vulkan api" per author	Uses features not available in Compatibility. Avoid.
Mesh Blend / Soft Particles (penguenbit)	Depth fade, alpha blending	Yes (with CURRENT_RENDERER check)	Not a water shader per se — shows the correct depth reconstruction for Compatibility.
Recommended base shader for your use case:
Start with Simple Water or Toon Water and add features incrementally. Both use hint_depth_texture and simple vertex waves — fully Compatibility-safe.

7. Depth-Based Water Color Variation
The core technique from all the shaders above:

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.0, 0.8, 0.8);
uniform vec3 deep_color : source_color = vec3(0.0, 0.1, 0.3);
uniform float max_depth : hint_range(0.1, 50.0) = 10.0;

void fragment() {
    float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
    #endif
    
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float scene_depth = -view.z;
    
    // Water's own depth
    float water_depth_raw = FRAGCOORD.z;
    vec3 water_ndc = vec3(SCREEN_UV * 2.0 - 1.0, water_depth_raw);
    vec4 water_view = INV_PROJECTION_MATRIX * vec4(water_ndc, 1.0);
    water_view.xyz /= water_view.w;
    float water_depth = -water_view.z;
    
    // How deep the water is at this pixel
    float water_thickness = scene_depth - water_depth;
    
    // Normalize and map to color
    float depth_factor = clamp(water_thickness / max_depth, 0.0, 1.0);
    ALBEDO = mix(shallow_color, deep_color, depth_factor);
    
    // Alpha: more opaque when deeper
    ALPHA = mix(0.2, 0.9, depth_factor);
    
    // Foam at shallow edges
    float foam = 1.0 - smoothstep(0.0, 0.5, water_thickness);
}
Key insight: scene_depth - water_depth gives you the actual water thickness in view space. This is your depth metric for color, transparency, and foam.

8. Performance Considerations for Web Builds
What's affordable on WebGL2:
Effect	Cost	Recommendation
Vertex wave displacement (Gerstner/sine)	Low	Yes — GPU-side, very cheap
Procedural FBM noise (3-4 octaves)	Low-Med	Yes — but keep octaves ≤ 4
hint_depth_texture read	Low	Yes — single texture sample
hint_screen_texture read	Med	Yes — forces full-screen copy once, then cached
Scrolling normal maps (2 layers)	Low	Yes — cheapest wave appearance method
Depth-based color/alpha	Low	Yes — just math after the depth sample
Foam at edges	Low	Yes — simple depth comparison
SSR (screen-space reflections)	High	Avoid — ray-marching in fragment shader, 20+ texture samples per pixel
Refraction (screen texture distortion)	Med	Use with caution — adds a screen copy
Specular highlights	Low	Yes — just SPECULAR + ROUGHNESS
discard	Med-High	Avoid — kills early-Z, defeats depth prepass
Tips for web:
Subdivide your water plane sparingly. Vertex waves need enough polygons, but a 64×64 or 128×128 subdivision for a large plane is plenty for wave detail.
Avoid SSR. It's the most expensive common water effect. Use planar reflections or simple specular instead.
Minimize texture samples. Each texture() call in the fragment shader costs bandwidth. 3-4 samples is fine; 20+ is not.
Use mediump precision where possible (mobile/web benefit):
mediump float depth_factor;
Render water after terrain. The depth buffer must contain terrain for depth-masking to work. This happens automatically with opaque pass → transparent pass ordering.
Set render_priority on the water ShaderMaterial to ensure it renders after other transparent objects if needed.
Use depth_prepass_alpha render mode if you need correct depth with alpha — but it costs an extra pass.
Reduce water plane size to only cover areas where water is actually visible. Don't make it 1000×1000 if your terrain is 200×200.
9. Can a Simple Plane + Custom Shader Achieve Good Water in WebGL2?
Yes, absolutely. This is the standard approach and it works well. Here's why:

The depth buffer approach (hint_depth_texture) handles terrain masking automatically
Vertex shader displacement handles waves
Scrolling normal maps handle surface detail
Depth-based alpha handles transparency variation
All of these work in the Compatibility renderer with WebGL2
What you give up vs. Forward+:

No hint_normal_roughness_texture (no screen-space normals for SSR)
No compute shaders (no GPU simulation)
No tessellation (no adaptive LOD on the water mesh)
Limited per-instance uniform indexing (must use switch statements instead of dynamic array indexing)
What you still get:

Depth texture access
Screen texture access (refraction)
Normal maps, PBR lighting
All standard shader math (sin, cos, noise functions)
Multiple render targets work
dFdx/dFdy for flat normals (low-poly style)
Minimal complete water shader for Compatibility:
shader_type spatial;
render_mode cull_disabled, depth_draw_always, blend_mix;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_map1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 shallow_color : source_color = vec4(0.3, 0.7, 0.8, 0.3);
uniform vec4 deep_color : source_color = vec4(0.05, 0.15, 0.3, 0.9);
uniform float max_depth : hint_range(0.1, 50.0) = 10.0;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.5;
uniform float wave_height : hint_range(0.0, 2.0) = 0.3;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;
uniform float edge_fade : hint_range(0.0, 5.0) = 1.0;

void vertex() {
    // Simple sine wave
    VERTEX.y += sin(VERTEX.x * 1.5 + TIME * wave_speed) * wave_height * 0.5;
    VERTEX.y += sin(VERTEX.z * 1.2 + TIME * wave_speed * 0.8) * wave_height * 0.3;
    VERTEX.y += sin((VERTEX.x + VERTEX.z) * 0.8 + TIME * wave_speed * 1.2) * wave_height * 0.2;
}

void fragment() {
    // Depth reconstruction (Compatibility-safe)
    float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
    #endif
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_scene_depth = -view.z;
    
    float water_depth_raw = FRAGCOORD.z;
    vec3 water_ndc = vec3(SCREEN_UV * 2.0 - 1.0, water_depth_raw);
    vec4 water_view = INV_PROJECTION_MATRIX * vec4(water_ndc, 1.0);
    water_view.xyz /= water_view.w;
    float linear_water_depth = -water_view.z;
    
    float water_thickness = linear_scene_depth - linear_water_depth;
    
    // If terrain is above water, fade out
    if (water_thickness < 0.0) {
        ALPHA = 0.0;
    } else {
        float depth_factor = clamp(water_thickness / max_depth, 0.0, 1.0);
        ALBEDO = mix(shallow_color.rgb, deep_color.rgb, depth_factor);
        ALPHA = mix(shallow_color.a, deep_color.a, depth_factor);
        
        // Soft edge fade where water meets terrain
        float edge_alpha = smoothstep(0.0, edge_fade, water_thickness);
        ALPHA *= edge_alpha;
    }
    
    // Scrolling normal maps
    vec2 uv1 = UV * 2.0 + TIME * vec2(0.02, 0.01);
    vec2 uv2 = UV * 2.0 - TIME * vec2(0.015, 0.025);
    vec3 n1 = texture(normal_map1, uv1).rgb;
    vec3 n2 = texture(normal_map2, uv2).rgb;
    NORMAL_MAP = mix(n1, n2, 0.5);
    NORMAL_MAP_DEPTH = normal_scale;
    
    METALLIC = 0.1;
    ROUGHNESS = 0.2;
    SPECULAR = 0.5;
}
Summary of key constraints for your use case:

Web export = Compatibility renderer only (WebGL 2.0 required, no WebGPU yet)
hint_depth_texture works in Compatibility — use it for terrain masking
Must use CURRENT_RENDERER == RENDERER_COMPATIBILITY branch for correct NDC depth reconstruction
Avoid SSR, compute shaders, tessellation, hint_normal_roughness_texture
A plane with vertex waves + depth-based alpha + scrolling normal maps is the sweet spot for quality vs. performance on web

--------------

I now have enough information from the official Godot docs and community sources. Let me compile the comprehensive research document.

Test-Path -LiteralPath "E:\Actual Projects\GoDot\2d-rpg"
#< CLIXML
True
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><Obj S="progress" RefId="0"><TN RefId="0"><T>System.Management.Automation.PSCustomObject</T><T>System.Object</T></TN><MS><I64 N="SourceId">1</I64><PR N="Record"><AV>Preparing modules for first use.</AV><AI>0</AI><Nil /><PI>-1</PI><PC>-1</PC><T>Completed</T><SR>-1</SR><SD> </SD></PR></MS></Obj></Objs>
Research compiled to docs/research-multimesh-foliage.md. Key concrete findings:

WebGL2 limits: Stay under 10k-15k grass instances (4-tri cards) and 1k-2k tree instances per frame on web. Native handles 50k-100k grass easily.

Architecture: One MultiMeshInstance3D per chunk per foliage type. Set custom_aabb to chunk bounds for automatic frustum culling. Pool and reuse nodes across chunk loads/unloads — don't free/reallocate.

Per 40×40 chunk: ~1,500 grass cards, ~30 bushes, ~10 trees for web; double for native.

Culling: No per-instance culling inside a MultiMesh. The per-chunk MultiMesh pattern solves this — each chunk's MultiMesh is culled as a whole by the engine when its AABB leaves the frustum.

LOD: 3-tier — full mesh near → simplified cluster mesh mid → billboard far → dither fade out. Use visibility_range_* for HLOD switching, distance_fade = DISTANCE_FADE_OBJECT_DITHER for cheap fades.

Veloren/Minetest approach: Both bake foliage into chunk meshes (voxel-based, no instancing). For Godot, MultiMesh is the idiomatic equivalent with the added benefit of per-instance shader animation (wind sway).

Entities: Pool PackedScene instances for buildings/monsters. process_mode = DISABLED for off-screen mobs. MultiMesh for static props, real nodes for anything needing AI/physics.