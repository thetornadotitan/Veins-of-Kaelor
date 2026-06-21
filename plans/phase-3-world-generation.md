# Phase 3: World Generation — Plan

*Plan version: 3.0 | Created: 2026-06-20 | Updated: 2026-06-20 | Phase: 3*

---

## Table of Contents

1. [Overview](#1-overview)
2. [Research Findings](#2-research-findings)
3. [Core Architecture](#3-core-architecture)
4. [Step 0: World Data Structures](#step-0-world-data-structures)
5. [Step 1: Chunk Data System](#step-1-chunk-data-system)
6. [Step 2: Heightmap Generation](#step-2-heightmap-generation)
7. [Step 3: Mesh Generation + LOD](#step-3-mesh-generation--lod)
8. [Step 4: Collision + Navigation Mesh](#step-4-collision--navigation-mesh)
9. [Step 5: Chunk Manager (Runtime Loading)](#step-5-chunk-manager-runtime-loading)
10. [Step 6: Toroidal Wrapping](#step-6-toroidal-wrapping)
11. [Step 7: World Generation Editor Tool](#step-7-world-generation-editor-tool)
12. [Future Extensibility](#future-extensibility)
13. [Reference: Industry Best Practices](#reference-industry-best-practices)
14. [Reference: Key Algorithms](#reference-key-algorithms)

---

## 1. Overview

### Scope

**In Scope (Phase 3 — Deliverable):**
- Upfront world generation (full world generated at once, saved as chunk data)
- Heightmap-based terrain mesh generation via 4D simplex noise (pre-computed)
- 3-level LOD system for terrain mesh rendering
- Chunk collision (static body per chunk)
- Basic `NavigationMesh` generation per chunk
- Editor tool: generation parameter configuration + regenerate
- Toroidal (seamless wrap) world — east↔west and north↔south
- Player coordinate wrapping so the world feels infinite

**Deferred (Future Phases):**
- Biome blending
- Monster spawn zones, patrol routes, NPC placement
- Resource nodes, reagent nodes, foliage
- Buildings, dungeon entrances
- Instance entrances
- Full world editor (terrain sculpt, node placement)
- Dynamic chunk persistence (player modifications)

### World Parameters

| Parameter | Value |
|-----------|-------|
| Chunk size | 40×40 world units |
| World chunks | 128×128 = 16,384 chunks total |
| Total world size | 5120×5120 world units |
| Height range | 0–40 units (configurable) |
| LOD levels | 3 (full, 50%, 12.5% vertex density) |
| LOD distances | LOD0: <80u, LOD1: <240u, LOD2: anything |
| Target generation | <30 seconds for full world (GDExtension), <20 min (GDScript fallback) |
| Chunk data format | Binary `.res` (primary), JSON (editor/export) |

The chunk size of 40×40 is chosen because:
- `5120 / 40 = 128` — clean power-of-two-aligned division
- 16,384 chunks is manageable for upfront generation
- 40×40 gives ~25×25 vertices at 1-vertex-per-unit — reasonable mesh density
- Each chunk's data file will be small; full world ~50–200 MB of JSON

### Data-First / DRY / KISS Principles

- **Noise parameters** are JSON-serializable config objects. The generator reads config, not code.
- **All noise values are pre-computed at generation time** — runtime uses O(1) lookup from saved heightmap data, never evaluates noise.
- **Chunk data is pure data** — no Godot scene objects. Generated once, loaded as data at runtime.
- **No code duplication** — heightmap, biome, and spawn logic all share the same seeded noise pipeline.
- **Chunk data and render chunk are separate** — data chunk = resource/file; render chunk = `Node3D` scene tree. Data is the source of truth.
- **Portable source of truth is heightmap data** — meshes, collision, NavMesh are all derived from heightmaps. Heightmap data survives engine version changes; baked engine objects may not.
- **Unified build path** — desktop and web use the same runtime path: load heightmap data, build mesh/collision/navmesh at runtime. No pre-baked engine-specific objects (.mesh, .navmesh). This eliminates platform-specific branching and ensures web parity by design.

---

## 2. Research Findings

*Updated in v3.0 — added GDExtension web research, compute shader assessment, unified build decision.*

### 2.1 Pre-Baked Resource Formats

**`ResourceSaver` + `.res` binary files:**
- `ResourceSaver.save(resource, path)` serializes any Godot `Resource` subclass to binary `.res` or text `.tres`
- Binary `.res` is compact and loads via `ResourceLoader` with caching — `load()` returns the cached instance on subsequent calls
- `.res` files are **version-locked to the Godot major+minor version** (e.g., 4.7). Opening a project in 4.8 may invalidate all `.res` files, requiring regeneration
- Custom `Resource` subclasses (like `ChunkData`) serialize all `@export` and public vars automatically
- Loading a `.res` is significantly faster than parsing JSON + constructing objects manually

**`.mesh` binary files:**
- `ArrayMesh` can be saved as `.mesh` via `ResourceSaver`
- **`.mesh` files CANNOT be included in web (HTML5) exports** — Godot's web export does not support importing `.mesh` resource files from `res://` at runtime
- **v3.0 decision: Do not pre-bake `.mesh` files for any platform.** All builds build meshes from heightmap data at runtime. This eliminates platform-specific code paths and ensures web parity by design.

**`.navmesh` files:**
- `NavigationMesh` is a `Resource` and can be saved via `ResourceSaver`
- **v3.0 decision: Do not pre-bake `.navmesh` files either.** NavMesh is always baked at runtime from heightmap data, on all platforms. This unifies the codebase and avoids version-lock risk. Runtime baking of ~49 NavMeshes takes ~1-2 seconds — an acceptable one-time cost.

**Implication:** The only pre-baked data that ships is heightmap data in `RegionData` `.res` files. Everything else (meshes, collision, NavMesh) is derived at runtime. Heightmap data is the single source of truth.

### 2.2 File I/O on Web (HTML5 Export)

**Critical constraint:** Web exports use IndexedDB for `user://` persistence. Each file operation has significant overhead:
- Opening/closing a file has a per-operation cost (~1-5ms on fast browsers, worse on slow devices)
- 16,384 individual JSON chunk files would require 16,384 separate file reads to load the full world — **unacceptable**
- Even loading just the 49 nearby chunks (7×7 grid) means 49 separate file I/O operations

**Solutions:**
1. **Pack chunk data into larger archives.** Instead of 16,384 individual files, store chunks in region files (e.g., 64 chunks per file = 256 region files). This reduces file count by 64×.
2. **Use binary `.res` resources** for chunk data at runtime. `ResourceLoader` caches loaded resources in memory — subsequent `load()` calls for the same path return the cached instance without I/O.
3. **For web, prefer `res://` paths for pre-baked data** (shipped with the build) over `user://` (IndexedDB). `res://` files are memory-mapped from the .pck bundle and load much faster.
4. **Only 7×7 = 49 chunks are loaded at any time.** Even on web, loading 49 files (or 2-4 region files) is manageable.

**Architecture decision:** Use region-based chunk storage. Each region file contains an 8×8 grid of chunks (64 chunks per region, 16×16 = 256 region files total). This balances file count vs. file size and works well on web.

### 2.3 Toroidal Seamless Noise — 4D Simplex Solution

**The problem:** Standard `FastNoiseLite` uses Perlin/Simplex noise which is **NOT periodic**. World-space coordinate sampling ensures **adjacent** chunk edges match (chunk at rx=0 and rx=1 share the same world-space coordinates at their boundary). However, **toroidal** edges (rx=127 ↔ rx=0) do NOT match — the height at world_x=0 is drawn from completely different noise coordinates than world_x=5120.

**Why 4D noise solves this:** True toroidal seamless noise maps 2D world coordinates onto a 4D torus:

```
wx = R * cos(2π * x / WORLD_SIZE)
wy = R * sin(2π * x / WORLD_SIZE)
wz = R * cos(2π * z / WORLD_SIZE)
ww = R * sin(2π * z / WORLD_SIZE)
height = simplex_noise_4d(wx, wy, wz, ww)
```

This mapping is inherently periodic — when x wraps from WORLD_SIZE back to 0, cos/sin produce the same 4D coordinates. No boundary blending needed, no distortion bands.

**v3.0: GDExtension C++ as primary, GDScript as fallback**

The 4D simplex noise algorithm will be implemented as a **GDExtension in C++**, with a **GDScript fallback** for environments where the GDExtension is unavailable. The GDExtension compiles to:
- **Native:** `.dll` (Windows), `.so` (Linux), `.dylib` (macOS) — for editor and desktop exports
- **Web:** `.side.wasm` (WebAssembly side module) — for web exports

**GDExtension web feasibility (research summary):**
- GDExtension supports `platform=web` via SCons + Emscripten, producing a `.side.wasm` side module
- A pure-math noise library (no filesystem, no threading, no exceptions) is an ideal GDExtension candidate for web — it avoids all known web GDExtension limitations
- **Caveat:** Web exports require custom export templates built with `dlink_enabled=yes` (official templates lack dynamic linking support). This is a one-time setup cost.
- **Emscripten version:** Emscripten v4 has an open bug with GDExtension (`sharedModules is undefined`); use Emscripten 3.x (e.g., 3.1.62) until fixed
- **Status:** Experimental but functional for simple cases. Pure-math extensions (like ours) avoid the known pain points (no threads, no filesystem, no exceptions needed)

**If GDExtension web proves too fragile, the GDScript fallback is always available.** The fallback is slower but functionally identical — same algorithm, same results. Web players would accept a longer one-time generation in exchange for guaranteed compatibility.

**Why not compute shaders?** Godot's GL Compatibility renderer (used by this project) does not support compute shaders — `RenderingDevice` is unavailable. Web (WebGL2) also lacks compute shader support. Compute shaders require Forward+ or Mobile renderer and are incompatible with web exports. This option is ruled out entirely.

**Why not use `FastNoiseLite` at all?**

Since we're pre-computing and saving all noise values anyway, there's no need to use Godot's native `FastNoiseLite` at generation time. A custom 4D simplex noise implementation gives us:
1. True toroidal seamless wrapping (no distortion bands)
2. No dependency on `FastNoiseLite`'s thread-safety or API limitations
3. Full control over the noise algorithm (seeds, gradients, permutation table)
4. Portability — the same noise code works everywhere, including web

**Reference implementation:** The 4D simplex noise will be ported from the C++ `SimplexNoise.cpp` reference (Stefan Gustavson / Ken Perlin). The GDExtension IS the C++ implementation; the GDScript fallback is a port of the same algorithm.

### 2.4 Memory Constraints on Web

- WebAssembly builds typically have a ~2GB memory limit (browser-dependent)
- 128×128 world × 41×41 heightmap × 4 bytes/float = ~110 MB for heightmap data alone — **well within limits**
- Only 49 chunks (7×7 × 41×41 × 4 bytes) = ~330 KB of heightmap data loaded at any time — **negligible**
- LOD meshes: 49 chunks × ~3,200 triangles (LOD0) ≈ 156K triangles in memory — **fine**
- Collision shapes: `ConcavePolygonShape3D` per chunk, ~3,200 faces each × 49 chunks — **fine**
- NavMesh: typically smaller than the visual mesh, 49 instances — **fine**
- **Conclusion:** Memory is not a bottleneck. Only 49 of 16,384 chunks are loaded at runtime.

### 2.5 `ResourceLoader` Cache Behavior

- `load()` caches resources in memory by path — subsequent `load(same_path)` returns the cached `Resource` instance
- `ResourceLoader.load_cached(path)` can be used to check if a resource is already cached
- **Important:** If the same chunk is loaded/unloaded/reloaded, `load()` returns the cached instance without re-reading from disk — this is a major performance win
- **Caveat:** Modifying a cached `Resource` instance affects all references to it. Chunk data resources should be treated as immutable after loading.
- To force re-read: `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)`

### 2.6 Summary of Architecture Decisions

| v1.0/2.0 Assumption | v3.0 Decision | Impact |
|---|---|---|
| 16,384 individual JSON files | Per-file I/O overhead is extreme on web | Switch to region-based `.res` files (256 region files instead of 16K JSON) |
| World-space coords = toroidal seamless | `FastNoiseLite` is not periodic; east≠west edge | Implement 4D simplex noise with toroidal mapping; pre-compute and save all values |
| Pre-bake `.mesh` files for runtime | `.mesh` can't ship in web; unneeded complexity | **All platforms build meshes from heightmap at runtime.** No platform split. |
| Pre-bake NavMesh for desktop, runtime-bake for web | Platform split adds complexity + version-lock risk | **All platforms bake NavMesh at runtime from heightmap.** No platform split. |
| Pure-GDScript noise generation | ~10-20 min for full world; too slow for good UX | **GDExtension C++ as primary** (~seconds); GDScript fallback (~10-20 min) |
| JSON chunk data format | Binary `.res` is faster to load, `ResourceLoader` caches | Use `ChunkData` resource saved as `.res`; keep JSON as editor/export fallback |
| `WorkerThreadPool` for generation | Custom noise avoids thread-safety issues | Single-threaded generation with progress reporting (GDExtension is fast enough) |
| NavMesh: desktop pre-bake, web runtime | Platform-specific code paths | **Unified: always runtime-bake from heightmap.** ~1-2s for 49 chunks. |
| Runtime noise evaluation for terrain | Pre-computed heightmaps give O(1) lookup | All noise values saved at generation time; runtime never evaluates noise |

### 2.7 GDExtension Build Architecture

The 4D simplex noise GDExtension uses `godot-cpp` and SCons. Build targets:

| Platform | Output | Command |
|----------|--------|---------|
| Windows (editor) | `simplex_noise_4d.dll` | `scons platform=windows target=editor` |
| Windows (release) | `simplex_noise_4d.dll` | `scons platform=windows target=template_release` |
| Web (WASM) | `simplex_noise_4d.side.wasm` | `scons platform=web target=template_release` |

**Web export requires custom export templates** built with `dlink_enabled=yes`. This is a one-time setup:
```
scons platform=web dlink_enabled=yes target=template_release
scons platform=web dlink_enabled=yes target=template_debug
```

**`.gdextension` manifest** (at `res://addons/simplex_noise_4d/simplex_noise_4d.gdextension`):
```ini
[configuration]
entry_symbol = gdext_init
compatibility_minimum = 4.2

[libraries]
windows.debug.x86_64 = "res://addons/simplex_noise_4d/bin/windows/debug/simplex_noise_4d.dll"
windows.release.x86_64 = "res://addons/simplex_noise_4d/bin/windows/release/simplex_noise_4d.dll"
web.release.wasm32 = "res://addons/simplex_noise_4d/bin/web/release/simplex_noise_4d.side.wasm"
```

**GDScript auto-detection:** The `HeightmapGenerator` attempts to load the GDExtension class first; falls back to GDScript if unavailable:
```gdscript
var _noise: RefCounted

func _init(seed: int) -> void:
    if ClassDB.class_exists("SimplexNoise4DNative"):
        _noise = ClassDB.instantiate("SimplexNoise4DNative")
        _noise.set_seed(seed)
    else:
        _noise = SimplexNoise4D.new(seed)
```

---

## 3. Core Architecture

### Single Unified Runtime Path

```
GENERATION (Editor / Build Time — one-time)
    Config → [GDExtension C++ / GDScript fallback] → 4D simplex noise + toroidal mapping
    → Per-chunk heightmap data → Pack into RegionData → Save 256 region .res files
    → Save world_meta.res + .json

RUNTIME (All platforms — desktop and web are identical)
    Region .res files → ResourceLoader (cached) → Chunk Manager
    → Build LOD mesh from heightmap (TerrainMeshBuilder)
    → Build collision from heightmap (CollisionGenerator)
    → Bake NavMesh from heightmap (NavMeshGenerator)
    → Player exploration + toroidal wrapping
```

**No platform-specific branches.** Desktop and web follow the exact same code path. The only difference is the noise evaluation backend (GDExtension vs GDScript) at generation time — and even that is auto-detected.

### Directory Structure

```
res://
├── addons/
│   └── simplex_noise_4d/
│       ├── simplex_noise_4d.gdextension        # GDExtension manifest
│       ├── src/
│       │   ├── simplex_noise_4d.cpp            # C++ 4D simplex noise (GDExtension)
│       │   ├── simplex_noise_4d.hpp
│       │   └── register_types.cpp              # GDExtension binding registration
│       ├── bin/
│       │   ├── windows/
│       │   │   ├── debug/simplex_noise_4d.dll
│       │   │   └── release/simplex_noise_4d.dll
│       │   └── web/
│       │       └── release/simplex_noise_4d.side.wasm
│       └── SConstruct                          # SCons build script
├── data/
│   └── worlds/
│       └── {world_name}/
│           ├── world_meta.res               # WorldMeta resource (seed, dimensions, params)
│           ├── world_meta.json              # Human-readable copy of metadata
│           └── regions/
│               ├── region_00_00.res          # 8×8 chunks (64 per region)
│               ├── region_00_01.res
│               └── ... (256 region files for 128×128 world)
├── scripts/
│   ├── world/
│   │   ├── world_data.gd                   # WorldData resource (metadata)
│   │   ├── chunk_data.gd                   # ChunkData resource (heightmap, etc.)
│   │   ├── region_data.gd                  # RegionData resource (8×8 chunk grid)
│   │   ├── world_generator.gd              # Generation orchestrator
│   │   ├── heightmap_generator.gd          # 4D simplex noise + toroidal mapping (auto-detects GDExtension)
│   │   ├── terrain_mesh_builder.gd         # ArrayMesh + LOD levels (runtime, all platforms)
│   │   ├── chunk_manager.gd                # Manages which chunks are loaded/rendered
│   │   ├── collision_generator.gd          # ConcavePolygonShape3D from heightmap
│   │   ├── navmesh_generator.gd            # NavigationMesh from heightmap (runtime, all platforms)
│   │   └── world_editor_ui.gd              # Generation config UI
│   └── data/
│       ├── world_config.gd                 # JSON-serializable generation parameters
│       └── noise_params.gd                 # Noise parameter container (shared by generator)
├── scripts/
│   └── noise/
│       └── simplex_noise_4d.gd             # GDScript fallback 4D simplex noise (used if GDExtension unavailable)
├── scenes/
│   ├── world/
│   │   ├── world_root.tscn                 # World scene root
│   │   ├── terrain_chunk.tscn              # LOD-capable terrain chunk scene
│   │   └── world_editor.tscn               # Editor tool scene
│   └── main.tscn
└── assets/
    └── textures/
        └── terrain/                        # Tiled biome textures
```

### Key Design Decisions

1. **Data chunk ≠ render chunk.** A `ChunkData` is a `Resource` containing raw heightmap values and biome assignments, packed into `RegionData` archives. A `TerrainChunk` scene is a `Node3D` that reads `ChunkData` and constructs `MeshInstance3D` at runtime with appropriate LOD.

2. **All chunks generated upfront.** At generation time, loop over all 16,384 chunks and generate heightmap data. Pack into 256 region files (8×8 chunks each). This matches the GDD's "entire world generated upfront as data" requirement.

3. **Runtime chunk loading always builds from heightmap data.** Meshes, collision, and NavMesh are always derived from heightmap data at runtime on all platforms. There is no desktop/web split. The chunk data (heights, biomes) is the only thing stored in `.res` files. At runtime, the chunk manager loads region data, extracts chunk heightmaps, and builds LOD meshes + collision + NavMesh from the heightmap. This works identically on desktop and web.

4. **Toroidal wrapping via 4D simplex noise.** Standard 2D noise is not periodic — height at world_x=0 has no relationship to world_x=5120. A 4D simplex noise implementation maps world (x,z) coordinates onto a 4D torus: `(R·cos(2πx/L), R·sin(2πx/L), R·cos(2πz/L), R·sin(2πz/L))`. This is inherently periodic — no distortion bands, no boundary blending hacks. Since all noise values are pre-computed and saved, the slower GDScript noise evaluation only affects generation time (a one-time cost).

5. **Region-based storage for web performance.** Instead of 16,384 individual JSON files, store chunks in 256 region files (`RegionData` resources, 8×8 chunks per region). This reduces file count by 64× and makes web I/O manageable. `ResourceLoader` caching further reduces redundant loads.

6. **Heightmap data is the portable source of truth; all noise values pre-computed.** Binary `.res` resources are fast to load but version-locked to Godot's major+minor. Heightmap data in `ChunkData` resources is engine-stable. Meshes, collision, and NavMesh are never stored as pre-baked files — always derived at runtime from heightmap data. Since noise evaluation happens only at generation time and all values are saved, runtime never needs to evaluate noise — pure O(1) lookup from pre-computed data.

7. **Editor tool is generation-focused.** The editor is a Godot scene with parameter sliders. Press "Generate" to run the full generator. It does NOT do manual terrain sculpting — that's a future phase.

8. **GDExtension C++ for noise — GDScript fallback.** The primary noise implementation is a C++ GDExtension that compiles to both native (`.dll`) and web (`.side.wasm`). If the GDExtension is unavailable (e.g., custom web templates not built, Emscripten version mismatch), the system auto-falls back to the GDScript implementation. Both produce identical results — same permutation table algorithm, same gradient set, same math.

---

## Step 0: World Data Structures

### World Metadata (`data/worlds/{name}/world_meta.res` + `.json`)

The primary format is a `WorldMeta` resource saved as binary `.res` for fast loading. A human-readable JSON copy is also exported for portability.

```json
{
    "name": "kaelor_alpha",
    "seed": 12345678,
    "created": "2026-06-20T00:00:00Z",
    "version": "3.0",
    "chunk_size": 40,
    "chunk_count_x": 128,
    "chunk_count_z": 128,
    "region_size": 8,
    "height_range": { "min": 0, "max": 40 },
    "torus_radius": 1.0,
    "generation_backend": "gdextension",
    "generation_params": {
        "height_scale": 0.02,
        "octaves": 4,
        "persistence": 0.5,
        "lacunarity": 2.0,
        "biome_temperature_scale": 0.005,
        "biome_moisture_scale": 0.008,
        "water_level": 8.0
    }
}
```

### Region Data (`data/worlds/{name}/regions/region_{rrx}_{rrz}.res`)

Each region file contains an 8×8 grid of chunks (64 chunks). With 128×128 chunks and 8×8 per region: 16×16 = 256 region files.

```gdscript
class_name RegionData
extends Resource

const REGION_SIZE: int = 8

@export var region_rx: int
@export var region_rz: int
@export var chunk_heightmaps: Array[PackedFloat32Array]  # 64 packed heightmaps
@export var chunk_biomes: PackedInt32Array                # 64 biome IDs
@export var chunk_count_x: int = 128
@export var chunk_count_z: int = 128

func get_chunk_heightmap(local_rx: int, local_rz: int) -> PackedFloat32Array:
    var index: int = local_rz * REGION_SIZE + local_rx
    return chunk_heightmaps[index]
```

**Why region files?** Research showed that 16,384 individual file I/O operations are prohibitive on web (IndexedDB). Region files reduce the count to 256 — and the chunk manager only needs to load 2-4 regions at a time (49 chunks span ~2 regions in each axis). With `ResourceLoader` caching, previously loaded regions are free.

### Chunk Data (in-memory, extracted from RegionData)

```gdscript
class_name ChunkData
extends Resource

const CHUNK_SIZE: int = 40
const GRID_RESOLUTION: int = 41

var chunk_rx: int
var chunk_rz: int
var heightmap: PackedFloat32Array  # GRID_RESOLUTION * GRID_RESOLUTION floats
var biome: int = 0

static func from_region(region: RegionData, local_rx: int, local_rz: int) -> ChunkData:
    var cd := ChunkData.new()
    cd.heightmap = region.get_chunk_heightmap(local_rx, local_rz)
    var biome_index: int = local_rz * RegionData.REGION_SIZE + local_rx
    cd.biome = region.chunk_biomes[biome_index]
    cd.chunk_rx = region.region_rx * RegionData.REGION_SIZE + local_rx
    cd.chunk_rz = region.region_rz * RegionData.REGION_SIZE + local_rz
    return cd

func get_height_at(local_x: float, local_z: float) -> float:
    # Bilinear interpolation within this chunk's 41×41 heightmap
    # Used by collision and NavMesh generation

func get_vertex(lx: int, lz: int) -> Vector3:
    # Returns world-space position of heightmap vertex (lx, lz)
    var h: float = heightmap[lz * GRID_RESOLUTION + lx]
    return Vector3(chunk_rx * CHUNK_SIZE + lx, h, chunk_rz * CHUNK_SIZE + lz)
```

**Why `PackedFloat32Array` instead of `Array[float]`?** `PackedFloat32Array` is contiguous memory, serializes compactly in `.res` files, and avoids per-element overhead of `Array[float]`. A single chunk's 41×41 = 1,681 floats = ~6.6 KB as `PackedFloat32Array` vs ~27 KB as `Array[float]` (due to Variant boxing). Full world: ~110 MB vs ~440 MB.

### Generation Config (`data/world_gen_config.json` — editor defaults)

```json
{
    "height_scale": 0.02,
    "octaves": 4,
    "persistence": 0.5,
    "lacunarity": 2.0,
    "seed": 0,
    "generate_new_seed": true,
    "biome_enabled": false,
    "water_level": 8.0,
    "height_range_min": 0.0,
    "height_range_max": 40.0,
    "torus_radius": 1.0,
    "region_size": 8,
    "output_world_name": "kaelor_alpha"
}
```

---

## Step 1: Chunk Data System

### Files

- `scripts/data/noise_params.gd` — `class_name NoiseParams`, `@export` fields, JSON-serializable
- `scripts/world/world_data.gd` — `class_name WorldData`, loads `world_meta.res`, provides chunk access via regions
- `scripts/world/chunk_data.gd` — `class_name ChunkData`, holds `heightmap: PackedFloat32Array`, bilinear interpolation
- `scripts/world/region_data.gd` — `class_name RegionData`, `Resource` subclass with 8×8 packed chunk data

### ChunkData Class

```gdscript
class_name ChunkData
extends Resource

const CHUNK_SIZE: int = 40
const GRID_RESOLUTION: int = 41  # CHUNK_SIZE + 1 (inclusive edges for seamlessness)

var chunk_rx: int
var chunk_rz: int
var heightmap: PackedFloat32Array  # GRID_RESOLUTION * GRID_RESOLUTION floats
var biome: int = 0

static func from_region(region: RegionData, local_rx: int, local_rz: int) -> ChunkData:
    # Extract chunk data from a loaded region

func get_height_at(local_x: float, local_z: float) -> float:
    # Bilinear interpolation within this chunk's heightmap
    # Used by collision and NavMesh generation

func get_vertex(lx: int, lz: int) -> Vector3:
    # Returns world-space position of heightmap vertex (lx, lz)
```

### RegionData Class

```gdscript
class_name RegionData
extends Resource

const REGION_SIZE: int = 8  # 8×8 chunks per region

@export var region_rx: int
@export var region_rz: int
@export var chunk_heightmaps: Array[PackedFloat32Array]  # 64 packed heightmaps
@export var chunk_biomes: PackedInt32Array                # 64 biome IDs

func get_chunk_heightmap(local_rx: int, local_rz: int) -> PackedFloat32Array:
    return chunk_heightmaps[local_rz * REGION_SIZE + local_rx]

func set_chunk_heightmap(local_rx: int, local_rz: int, data: PackedFloat32Array) -> void:
    chunk_heightmaps[local_rz * REGION_SIZE + local_rx] = data

static func create_empty(rx: int, rz: int) -> RegionData:
    var rd := RegionData.new()
    rd.region_rx = rx
    rd.region_rz = rz
    rd.chunk_heightmaps.resize(REGION_SIZE * REGION_SIZE)
    rd.chunk_biomes = PackedInt32Array()
    rd.chunk_biomes.resize(REGION_SIZE * REGION_SIZE)
    return rd
```

### WorldData Class

```gdscript
class_name WorldData
extends Resource

var world_name: String
var seed: int
var chunk_count_x: int = 128
var chunk_count_z: int = 128
var chunk_size: int = 40
var region_size: int = 8
var torus_radius: float = 1.0
var generation_params: NoiseParams

var _cached_regions: Dictionary = {}  # (rrx, rrz) -> RegionData

static func load(world_name: String) -> WorldData:
    # Load world_meta.res + instantiate WorldData

func get_chunk_data(rx: int, rz: int) -> ChunkData:
    # 1. Wrap coords toroidally: rx = posmod(rx, chunk_count_x)
    # 2. Determine region: rrx = rx / region_size, rrz = rz / region_size
    # 3. Load region if not cached (ResourceLoader + cache)
    # 4. Extract ChunkData from region

func get_region_path(rrx: int, rrz: int) -> String:
    return "res://data/worlds/%s/regions/region_%02d_%02d.res" % [world_name, rrx, rrz]

func _load_region(rrx: int, rrz: int) -> RegionData:
    var key := Vector2i(rrx, rrz)
    if _cached_regions.has(key):
        return _cached_regions[key]
    var path := get_region_path(rrx, rrz)
    var region: RegionData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
    _cached_regions[key] = region
    return region

func unload_distant_regions(keep_regions: Array[Vector2i]) -> void:
    # Free cached regions not in keep list to manage memory
    for key in _cached_regions.keys():
        if key not in keep_regions:
            _cached_regions.erase(key)
```

**Key insight:** With only 7×7 chunks loaded, the player spans at most 2×2 = 4 regions at a time. Region caching ensures each is loaded once and reused.

## Step 2: Heightmap Generation

### Algorithm Overview

For each of the 16,384 chunks, generate a `GRID_RESOLUTION × GRID_RESOLUTION` heightmap using 4D simplex noise with toroidal coordinate mapping. All noise values are pre-computed and saved — runtime never evaluates noise.

The noise backend is auto-detected: **GDExtension C++ (primary)** or **GDScript (fallback)**.

**Two types of seamlessness:**
- **Adjacent chunk seams:** Solved automatically — all chunks use world-space coordinates, and shared edges produce the same sample values.
- **Toroidal (wrap-around) seams:** Solved via 4D toroidal mapping — world (x,z) coordinates are mapped onto a 4D torus before noise evaluation. The trigonometric mapping is inherently periodic.

### 4D Toroidal Noise Mapping

The 2D world coordinates (x, z) are mapped to 4D torus coordinates before sampling simplex noise:

```
wx = R * cos(2π * x / WORLD_SIZE_X)
wy = R * sin(2π * x / WORLD_SIZE_X)
wz = R * cos(2π * z / WORLD_SIZE_Z)
ww = R * sin(2π * z / WORLD_SIZE_Z)
height = simplex_noise_4d(seed, wx, wy, wz, ww)
```

This mapping guarantees:
- When x=0 and x=WORLD_SIZE_X, `cos(0) = cos(2π)` and `sin(0) = sin(2π)` — the 4D coordinates are identical
- Adjacent chunks share the same 4D coordinates at their boundary
- No visible seam or distortion at any boundary, including the toroidal wrap

The `R` (torus radius) parameter controls how "tightly" the world wraps on the torus surface. Smaller R values make the noise pattern repeat more visibly; R=1.0 (default) gives a good balance. This is configurable in `WorldGenConfig`.

### GDExtension C++ 4D Simplex Noise (Primary)

The C++ implementation is the authoritative version. It compiles to both native and WebAssembly targets.

```cpp
// addons/simplex_noise_4d/src/simplex_noise_4d.hpp
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {
class SimplexNoise4DNative : public RefCounted {
    GDCLASS(SimplexNoise4DNative, RefCounted)

private:
    uint8_t perm[512];
    float _noise_4d(float x, float y, float z, float w) const;
    float _grad4d(int hash, float x, float y, float z, float w) const;
    static int _fastfloor(float x);

public:
    void set_seed(int64_t seed);
    float get_noise_4d(float x, float y, float z, float w) const;
    float get_noise_4d_fbm(float x, float y, float z, float w,
                            int octaves, float frequency,
                            float persistence, float lacunarity) const;

protected:
    static void _bind_methods();
};
}
```

```cpp
// addons/simplex_noise_4d/src/simplex_noise_4d.cpp
// Full C++ implementation of 4D simplex noise
// - Seeded permutation via Fisher-Yates shuffle (identical to GDScript version)
// - 4D skewing: F4 = (sqrt(5)-1)/4, G4 = (5-sqrt(5))/20
// - 5-corner simplex in 4D
// - 32 gradient directions: permutations of (±1, ±1, 0, 0) / sqrt(2)
// - Exposed to GDScript via _bind_methods()
// - No exceptions, no filesystem, no threading — pure math, web-safe
```

**Build system:**
```python
# addons/simplex_noise_4d/SConstruct
# Standard godot-cpp SCons build
# Targets: platform=windows (debug/release), platform=web (release only)
```

### GDScript Fallback 4D Simplex Noise

When the GDExtension is unavailable (no `.dll`/`.side.wasm`), the system falls back to this pure-GDScript implementation. It produces identical results — same permutation table, same gradients, same math.

```gdscript
# scripts/noise/simplex_noise_4d.gd
class_name SimplexNoise4D
extends RefCounted

var _perm: PackedByteArray  # 512-byte lookup (256 perm + 256 perm for wrapping)

func _init(seed: int = 0) -> void:
    _perm = _generate_permutation(seed)

func _generate_permutation(seed_val: int) -> PackedByteArray:
    var p := PackedByteArray()
    p.resize(256)
    for i in range(256):
        p[i] = i
    # Fisher-Yates shuffle with seeded RNG
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_val
    for i in range(255, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp := p[i]
        p[i] = p[j]
        p[j] = tmp
    # Double the table for wrapping (avoids modulus in inner loop)
    var perm := PackedByteArray()
    perm.resize(512)
    for i in range(256):
        perm[i] = p[i]
        perm[256 + i] = p[i]
    return perm

func noise_4d(x: float, y: float, z: float, w: float) -> float:
    # 4D simplex noise implementation
    # Skewing factors: F4 = (sqrt(5) - 1) / 4 ≈ 0.309016994
    #                  G4 = (5 - sqrt(5)) / 20 ≈ 0.138196601
    const F4: float = 0.309016994374947
    const G4: float = 0.138196601125780
    
    # Skew input space
    var s: float = (x + y + z + w) * F4
    var i: int = _fastfloor(x + s)
    var j: int = _fastfloor(y + s)
    var k: int = _fastfloor(z + s)
    var l: int = _fastfloor(w + s)
    var t: float = (i + j + k + l) * G4
    
    # Unskew back to (x,y,z,w) space
    var X0: float = i - t
    var Y0: float = j - t
    var Z0: float = k - t
    var W0: float = l - t
    var x0: float = x - X0
    var y0: float = y - Y0
    var z0: float = z - Z0
    var w0: float = w - W0
    
    # Determine simplex ordering (5 corners for 4D)
    # ... rank ordering by x0>=y0>=z0>=w0 etc.
    # ... compute 5 corner contributions via grad4d and attenuation
    # ... sum and scale to [-1, 1]
    
    return result  # scaled to [-1, 1]

func noise_4d_fbm(x: float, y: float, z: float, w: float, octaves: int, frequency: float, persistence: float, lacunarity: float) -> float:
    var output: float = 0.0
    var denom: float = 0.0
    var amp: float = 1.0
    var freq: float = frequency
    
    for _i in range(octaves):
        output += amp * noise_4d(x * freq, y * freq, z * freq, w * freq)
        denom += amp
        freq *= lacunarity
        amp *= persistence
    
    return output / denom

static func _fastfloor(x: float) -> int:
    var i: int = int(x)
    return i - 1 if x < i else i

func _grad4d(hash_val: int, x: float, y: float, z: float, w: float) -> float:
    # 32 gradient directions for 4D simplex noise
    # ... implementation following Ken Perlin's 2001 reference
    pass
```

**4D gradient directions:** Both the C++ and GDScript versions use 32 gradient vectors from the set of all permutations of (±1, ±1, 0, 0) / sqrt(2). This matches the standard 4D simplex noise definition.

### HeightmapGenerator (auto-detects backend)

```gdscript
# heightmap_generator.gd
class_name HeightmapGenerator

const WORLD_SIZE: float = 5120.0

static func create_noise(seed: int) -> RefCounted:
    if ClassDB.class_exists("SimplexNoise4DNative"):
        var noise = ClassDB.instantiate("SimplexNoise4DNative")
        noise.set_seed(seed)
        return noise
    return SimplexNoise4D.new(seed)

static func generate_chunk_heightmap(
    chunk_rx: int, chunk_rz: int,
    noise: RefCounted,
    params: NoiseParams,
    torus_radius: float = 1.0
) -> PackedFloat32Array:
    var heightmap := PackedFloat32Array()
    heightmap.resize(ChunkData.GRID_RESOLUTION * ChunkData.GRID_RESOLUTION)
    
    var base_x: float = chunk_rx * ChunkData.CHUNK_SIZE
    var base_z: float = chunk_rz * ChunkData.CHUNK_SIZE
    
    var use_native: bool = noise.has_method("get_noise_4d_fbm")
    
    for lz in range(ChunkData.GRID_RESOLUTION):
        for lx in range(ChunkData.GRID_RESOLUTION):
            var wx: float = base_x + lx
            var wz: float = base_z + lz
            
            # Map to 4D torus coordinates
            var nx: float = torus_radius * cos(2.0 * PI * wx / WORLD_SIZE)
            var ny: float = torus_radius * sin(2.0 * PI * wx / WORLD_SIZE)
            var nz: float = torus_radius * cos(2.0 * PI * wz / WORLD_SIZE)
            var nw: float = torus_radius * sin(2.0 * PI * wz / WORLD_SIZE)
            
            var height: float
            if use_native:
                height = noise.get_noise_4d_fbm(
                    nx, ny, nz, nw,
                    params.octaves,
                    params.height_scale,
                    params.persistence,
                    params.lacunarity
                )
            else:
                height = noise.noise_4d_fbm(
                    nx, ny, nz, nw,
                    params.octaves,
                    params.height_scale,
                    params.persistence,
                    params.lacunarity
                )
            
            heightmap[lz * ChunkData.GRID_RESOLUTION + lx] = height * params.height_range_max
    
    return heightmap
```

**Key advantage over boundary blending:** No distortion bands at world edges. The noise is inherently periodic. The terrain at rx=127 seamlessly transitions to rx=0 with zero artifacts.

### Performance Estimates

| Backend | Total Samples | Per-Sample Time | 4-Octave Total | Notes |
|---------|---------------|-----------------|----------------|-------|
| GDExtension C++ (native) | 27.5M | ~0.05-0.2μs | ~1-6 seconds | Primary; optimal |
| GDExtension C++ (WASM) | 27.5M | ~0.1-0.5μs | ~3-14 seconds | Web; SIMD enabled in Godot 4.5+ |
| GDScript fallback | 27.5M | ~5-20μs | ~10-40 minutes | Fallback; acceptable for one-time offline use |

**GDExtension C++ is ~50-200× faster than GDScript.** The primary path brings world generation from "wait 10-40 minutes" to "wait a few seconds." Even the WASM build is fast enough for a comfortable user experience.

**Mitigation strategies if generation is too slow (GDScript fallback):**
1. **Reduce octave count:** 2-3 octaves gives acceptable terrain quality for a 5120×5120 world
2. **Use coarser frequency:** Higher base frequency means fewer effective noise samples per unit
3. **Show progress bar:** User can see progress and estimates — waiting 10-20 minutes for a one-time world creation is acceptable in the genre

**Why this is acceptable:** This is a one-time offline operation. The generated heightmap data persists forever. Players generate their world once and explore it for hundreds of hours. The quality of seamless toroidal wrapping justifies the wait.

### World Generator Orchestrator

```gdscript
# world_generator.gd
class_name WorldGenerator

signal progress_changed(ratio: float)
signal generation_complete(world_name: String)

func generate_world(config: WorldGenConfig) -> void:
    var noise := HeightmapGenerator.create_noise(config.seed)
    var backend_name := "GDExtension" if noise.has_method("get_noise_4d_fbm") else "GDScript"
    print("World generation using: %s backend" % backend_name)
    
    var params := NoiseParams.new()
    params.height_scale = config.height_scale
    params.octaves = config.octaves
    params.persistence = config.persistence
    params.lacunarity = config.lacunarity
    params.height_range_max = config.height_range_max
    
    var total_chunks := config.chunk_count_x * config.chunk_count_z
    var chunks_done := 0
    
    var region_count_x := config.chunk_count_x / RegionData.REGION_SIZE
    var region_count_z := config.chunk_count_z / RegionData.REGION_SIZE
    
    for rrx in range(region_count_x):
        for rrz in range(region_count_z):
            var region := RegionData.create_empty(rrx, rrz)
            
            for local_rx in range(RegionData.REGION_SIZE):
                for local_rz in range(RegionData.REGION_SIZE):
                    var chunk_rx := rrx * RegionData.REGION_SIZE + local_rx
                    var chunk_rz := rrz * RegionData.REGION_SIZE + local_rz
                    
                    var heightmap := HeightmapGenerator.generate_chunk_heightmap(
                        chunk_rx, chunk_rz, noise, params, config.torus_radius
                    )
                    
                    region.set_chunk_heightmap(local_rx, local_rz, heightmap)
                    region.chunk_biomes[local_rz * RegionData.REGION_SIZE + local_rx] = 0
                    
                    chunks_done += 1
            
            var region_path := "res://data/worlds/%s/regions/region_%02d_%02d.res" % [config.world_name, rrx, rrz]
            ResourceSaver.save(region, region_path)
            
            progress_changed.emit(float(chunks_done) / float(total_chunks))
    
    _save_world_meta(config, backend_name)
    _export_meta_json(config, backend_name)
    
    generation_complete.emit(config.world_name)
```

**Single-threaded:** Both GDExtension and GDScript noise evaluation are pure computation with no Godot scene access needed. The noise object is `RefCounted` — no thread-safety concerns since generation is single-threaded. With GDExtension C++ performance (1-6 seconds for full world), threading is unnecessary.

---

## Step 3: Mesh Generation + LOD

### TerrainMeshBuilder

Meshes are built **at runtime from heightmap data on all platforms**. There is no desktop/web split. There are no pre-baked `.mesh` files. This is required because:
1. Pre-baked `.mesh` files cannot be included in web builds
2. Heightmap data is the portable source of truth; meshes are derived and disposable
3. Only 49 meshes (7×7 chunks) need construction at any time — performance is acceptable
4. A unified code path is simpler, more maintainable, and guaranteed to work the same everywhere

Each chunk produces 3 LOD levels of `ArrayMesh`. LOD is distance-based from the player's camera position.

#### LOD Specifications

| Level | Vertex Spacing | Vertices per Chunk | Triangle Count | Use When |
|-------|---------------|-------------------|----------------|----------|
| LOD0 | 1.0 unit | 41×41 = 1,681 | ~3,200 | < 80 units from camera |
| LOD1 | 2.0 units | 21×21 = 441 | ~800 | < 240 units from camera |
| LOD2 | 4.0 units | 11×11 = 121 | ~200 | > 240 units from camera |

The vertex spacing doubles at each LOD level — this is standard grid decimation.

#### ArrayMesh Construction

```gdscript
# terrain_mesh_builder.gd
class_name TerrainMeshBuilder

static func build_chunk_mesh(chunk_data: ChunkData, lod: int) -> ArrayMesh:
    var spacing: int = int(pow(2, lod))
    var resolution: int = ChunkData.GRID_RESOLUTION
    var lod_res: int = (resolution - 1) / spacing + 1

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for lz in range(0, resolution - 1, spacing):
        for lx in range(0, resolution - 1, spacing):
            var wx0 := chunk_data.chunk_rx * ChunkData.CHUNK_SIZE + lx
            var wz0 := chunk_data.chunk_rz * ChunkData.CHUNK_SIZE + lz
            var wx1 := wx0 + spacing
            var wz1 := wz0 + spacing

            var h00: float = chunk_data.heightmap[lz * resolution + lx]
            var h10: float = chunk_data.heightmap[lz * resolution + lx + spacing]
            var h01: float = chunk_data.heightmap[(lz + spacing) * resolution + lx]
            var h11: float = chunk_data.heightmap[(lz + spacing) * resolution + lx + spacing]

            var v00 := Vector3(wx0, h00, wz0)
            var v10 := Vector3(wx1, h10, wz0)
            var v01 := Vector3(wx0, h01, wz1)
            var v11 := Vector3(wx1, h11, wz1)

            var uv00 := Vector2(float(lx) / float(resolution - 1), float(lz) / float(resolution - 1))
            var uv10 := Vector2(float(lx + spacing) / float(resolution - 1), float(lz) / float(resolution - 1))
            var uv01 := Vector2(float(lx) / float(resolution - 1), float(lz + spacing) / float(resolution - 1))
            var uv11 := Vector2(float(lx + spacing) / float(resolution - 1), float(lz + spacing) / float(resolution - 1))

            var color := _get_biome_color(chunk_data.biome)

            st.set_uv(uv00); st.set_color(color); st.add_vertex(v00)
            st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
            st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)
            st.set_uv(uv10); st.set_color(color); st.add_vertex(v10)
            st.set_uv(uv11); st.set_color(color); st.add_vertex(v11)
            st.set_uv(uv01); st.set_color(color); st.add_vertex(v01)

    st.generate_normals()
    return st.commit()
```

**Performance:** Building 1 LOD0 mesh (1,681 vertices) takes ~0.5ms. Building all 3 LOD levels for one chunk takes ~1ms. For 49 loaded chunks, ~49ms total on chunk load. Spread over multiple frames during loading, this is imperceptible.

### Biome Coloring

For Phase 3, use **vertex coloring** — no texture atlas. Each vertex gets a `Color` based on its biome. The `SurfaceTool.set_color()` call applies this. In future phases, vertex colors can blend at biome borders.

Initial biomes (simplified):
- Plains (0): `#4A7C3F` (green)
- Mountain (1): `#8B7355` (brown)
- Water (2): `#2E5A8C` (blue, at or below water_level)

---

## Step 4: Collision + Navigation Mesh

### CollisionGenerator

Each chunk needs a `StaticBody3D` with a collision mesh generated from the heightmap. Built at runtime from heightmap data on all platforms.

**Approach:** Generate a collision mesh using the LOD0 heightmap grid. Uses `ConcavePolygonShape3D` for static terrain.

```gdscript
# collision_generator.gd
class_name CollisionGenerator

static func build_collision_shape(chunk_data: ChunkData) -> ConcavePolygonShape3D:
    var resolution: int = ChunkData.GRID_RESOLUTION
    var faces := PackedVector3Array()
    
    for lz in range(resolution - 1):
        for lx in range(resolution - 1):
            var v00 := chunk_data.get_vertex(lx, lz)
            var v10 := chunk_data.get_vertex(lx + 1, lz)
            var v01 := chunk_data.get_vertex(lx, lz + 1)
            var v11 := chunk_data.get_vertex(lx + 1, lz + 1)
            
            faces.append(v00); faces.append(v10); faces.append(v01)
            faces.append(v10); faces.append(v11); faces.append(v01)
    
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(faces)
    return shape
```

**Critical:** For the `StaticBody3D` to work with the character controller, the collision mesh must match the visual mesh closely. Use the same heightmap data.

### NavMeshGenerator

NavMesh is **always baked at runtime from heightmap data, on all platforms.** There is no desktop/web split, no pre-baked `.res` NavMesh files. This decision unifies the codebase and eliminates:
- Engine version-lock risk on pre-baked `.res` NavMesh files
- Platform-specific code paths that diverge and accumulate tech debt
- Web-specific fallback logic

Runtime baking is cheap (~1-2 seconds for 49 chunks) and happens once during initial chunk load. This is an acceptable trade-off.

```gdscript
# navmesh_generator.gd
class_name NavMeshGenerator

static func build_navmesh(chunk_data: ChunkData) -> NavigationMesh:
    var navmesh := NavigationMesh.new()
    
    # Build source geometry from heightmap
    var source_mesh := _build_walkable_mesh(chunk_data)
    
    var geometry := NavigationMeshSourceGeometryData3D.new()
    NavigationServer3D.parse_source_geometry_parameters(navmesh, geometry, source_mesh)
    
    navmesh.agent_radius = 0.5
    navmesh.agent_height = 1.6
    navmesh.agent_max_climb = 0.5
    navmesh.agent_max_slope = 50.0
    
    NavigationServer3D.bake_from_source_geometry_data(navmesh, geometry)
    return navmesh
```

**Performance:** Baking 49 NavMeshes at runtime takes ~1-2 seconds on modern devices. This is a one-time cost during initial chunk load, amortized over the player's session.

---

## Step 5: Chunk Manager (Runtime Loading)

### ChunkManager

At runtime, only chunks near the player are loaded into the scene tree. This is the classic spatial streaming system. Chunks are loaded from region files via `WorldData.get_chunk_data()`, which handles region caching internally.

```gdscript
# chunk_manager.gd
class_name ChunkManager
extends Node3D

const LOAD_RADIUS: int = 3  # Load chunks within 3-chunk radius of player
const UNLOAD_DISTANCE: int = 5  # Unload chunks beyond 5-chunk radius

var _world_data: WorldData
var _loaded_chunks: Dictionary = {}  # Vector2i → TerrainChunk instance
var _player_chunk: Vector2i = Vector2i(-1, -1)

@onready var _terrain_root: Node3D = %TerrainRoot

func _ready() -> void:
    _world_data = WorldData.load("kaelor_alpha")

func _process(_delta: float) -> void:
    var player_pos := _get_player_world_position()
    var player_chunk: Vector2i = _world_to_chunk(player_pos)

    if player_chunk != _player_chunk:
        _player_chunk = player_chunk
        _update_loaded_chunks()

func _update_loaded_chunks() -> void:
    var to_load: Array[Vector2i] = []
    for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
        for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
            var chunk_pos := Vector2i(
                posmod(_player_chunk.x + dx, _world_data.chunk_count_x),
                posmod(_player_chunk.y + dz, _world_data.chunk_count_z)
            )
            if not _loaded_chunks.has(chunk_pos):
                to_load.append(chunk_pos)

    var to_unload: Array[Vector2i] = []
    for chunk_pos in _loaded_chunks.keys():
        var dist := _chunk_distance_wrapped(chunk_pos, _player_chunk)
        if dist > UNLOAD_DISTANCE:
            to_unload.append(chunk_pos)

    for chunk_pos in to_load:
        _load_chunk(chunk_pos)

    for chunk_pos in to_unload:
        _unload_chunk(chunk_pos)

    # Prune unused regions from cache
    var needed_regions := _get_needed_regions()
    _world_data.unload_distant_regions(needed_regions)

func _load_chunk(chunk_pos: Vector2i) -> void:
    var chunk_data: ChunkData = _world_data.get_chunk_data(chunk_pos.x, chunk_pos.y)
    var lod: int = _determine_lod(chunk_pos)
    
    var chunk_scene := TerrainChunkScene.instantiate()
    chunk_scene.setup(chunk_data, lod)
    _terrain_root.add_child(chunk_scene)
    _loaded_chunks[chunk_pos] = chunk_scene

func _unload_chunk(chunk_pos: Vector2i) -> void:
    var chunk_node: Node3D = _loaded_chunks[chunk_pos]
    chunk_node.queue_free()
    _loaded_chunks.erase(chunk_pos)

func _chunk_distance_wrapped(a: Vector2i, b: Vector2i) -> int:
    # Toroidal distance — shortest path around the world
    var dx := absi(a.x - b.x)
    var dz := absi(a.y - b.y)
    dx = mini(dx, _world_data.chunk_count_x - dx)
    dz = mini(dz, _world_data.chunk_count_z - dz)
    return maxi(dx, dz)
```

### TerrainChunk Node

```gdscript
# terrain_chunk.gd (attached to each chunk instance)
class_name TerrainChunk
extends Node3D

var _chunk_data: ChunkData
var _current_lod: int = -1
var _mesh_instance: MeshInstance3D
var _static_body: StaticBody3D
var _nav_region: NavigationRegion3D

func setup(chunk_data: ChunkData, lod: int) -> void:
    _chunk_data = chunk_data
    _current_lod = lod
    
    # Build visual mesh from heightmap (all platforms)
    var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(chunk_data, lod)
    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.mesh = mesh
    add_child(_mesh_instance)
    
    # Build collision from heightmap (all platforms)
    var shape: ConcavePolygonShape3D = CollisionGenerator.build_collision_shape(chunk_data)
    _static_body = StaticBody3D.new()
    var col_shape := CollisionShape3D.new()
    col_shape.shape = shape
    _static_body.add_child(col_shape)
    add_child(_static_body)
    
    # Bake NavMesh from heightmap at runtime (all platforms)
    var navmesh: NavigationMesh = NavMeshGenerator.build_navmesh(chunk_data)
    _nav_region = NavigationRegion3D.new()
    _nav_region.navigation_mesh = navmesh
    add_child(_nav_region)

func update_lod(new_lod: int) -> void:
    if new_lod == _current_lod:
        return
    _current_lod = new_lod
    var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(_chunk_data, new_lod)
    _mesh_instance.mesh = mesh
```

### LOD Selection

```gdscript
func _determine_lod(chunk_pos: Vector2i) -> int:
    var player_world_pos := _get_player_world_position()
    var chunk_center := Vector3(
        chunk_pos.x * ChunkData.CHUNK_SIZE + ChunkData.CHUNK_SIZE / 2.0,
        0.0,
        chunk_pos.y * ChunkData.CHUNK_SIZE + ChunkData.CHUNK_SIZE / 2.0
    )
    
    # Toroidal distance for LOD
    var diff := chunk_center - player_world_pos
    var world_size := _world_data.chunk_count_x * ChunkData.CHUNK_SIZE
    if absf(diff.x) > world_size * 0.5:
        diff.x -= signf(diff.x) * world_size
    if absf(diff.z) > world_size * 0.5:
        diff.z -= signf(diff.z) * world_size
    var dist := diff.length()
    
    if dist < 80.0:
        return 0
    elif dist < 240.0:
        return 1
    else:
        return 2
```

**Key difference from v1.0:** LOD distances now account for toroidal wrapping. A chunk near the east edge uses the shortest distance to the player even if the player is near the west edge.

---

## Step 6: Toroidal Wrapping

### Player Coordinate Wrapping

The player's `CharacterBody3D` should be able to move freely without hitting a wall. The key is that world coordinates always wrap for chunk lookups, but the player's visual position must also wrap.

```gdscript
# In player_controller.gd or a WorldRoot level script:
const WORLD_SIZE_X: float = 5120.0
const WORLD_SIZE_Z: float = 5120.0

func _physics_process(_delta: float) -> void:
    # ... existing movement code ...
    
    var pos := global_position

    if pos.x < 0:
        pos.x += WORLD_SIZE_X
    elif pos.x >= WORLD_SIZE_X:
        pos.x -= WORLD_SIZE_X

    if pos.z < 0:
        pos.z += WORLD_SIZE_Z
    elif pos.z >= WORLD_SIZE_Z:
        pos.z -= WORLD_SIZE_Z

    global_position = pos
```

### Chunk Coordinate Wrapping

```gdscript
func _wrap_chunk_coords(chunk_pos: Vector2i) -> Vector2i:
    var cx: int = posmod(chunk_pos.x, 128)  # 128 chunks on X
    var cz: int = posmod(chunk_pos.y, 128)  # 128 chunks on Z
    return Vector2i(cx, cz)
```

**Critical:** `posmod` (Python-style modulo that handles negatives correctly) must be used — not GDScript's `%` operator which is remainder, not modulo. GDScript's `posmod()` function handles this correctly.

### Toroidal Wrapping and Noise Seams

**v1.0 incorrectly stated** that world-space coordinate sampling automatically creates seamless toroidal edges. This is wrong — `FastNoiseLite` is not periodic. The noise value at world_x=0 has no relationship to the noise value at world_x=5120.

**v3.0 solution:** The HeightmapGenerator uses 4D simplex noise with toroidal coordinate mapping (see Step 2). World (x,z) coordinates are mapped onto a 4D torus via `cos(2πx/L)` and `sin(2πx/L)` before noise evaluation. This is inherently periodic — there are no seams, no distortion bands, and no blend zones needed.

- **Interior chunk seams** (e.g., rx=5 ↔ rx=6): Perfectly seamless — both chunks sample the same 4D coordinates at their shared edge.
- **Toroidal boundary seams** (e.g., rx=127 ↔ rx=0): Perfectly seamless — the 4D torus mapping wraps around naturally when x goes from WORLD_SIZE to 0.

### Visual Seamlessness

With the chunk loading system, at any position near an edge, the player sees chunks from both sides of the world. Because the heightmap generation uses 4D toroidal mapping, the seam is seamless — the terrain tiles smoothly.

**Near the east edge (x ≈ 5120):**
- Loaded chunks include the actual east chunks (rx ≈ 127)
- Plus the wrapped west chunks (rx = 0) placed at world coordinates offset by WORLD_SIZE
- Heights align because 4D toroidal mapping ensured rx=127's east edge matches rx=0's west edge

**Crossing the boundary:**
- Player moves from x=5119 to x=5120 → x wraps to x=0
- Same chunk (rx=0) now appears at both x=0 and x=5120
- No pop — the heightmap is consistent

### Camera and Third-Person Considerations

When the camera is near a world boundary and looking across it, the renderer needs to see chunks on both sides. The `ChunkManager` already handles this because it loads based on world-space position — if the player's camera is at x=5110 looking east, chunks at rx=127 (x ≈ 5040–5120) AND rx=0 (x ≈ 0–40) are both loaded.

**Camera offset at boundaries:** The camera may need to render chunks at offset positions (e.g., rx=0 chunk rendered at both x=0 and x=5120). The `TerrainChunk` position is set by the `ChunkManager` based on which "copy" of the chunk is being displayed. This is handled by rendering wrapped chunks at offset world positions.

```
Player at x=5110, looking east:
  - rx=127 chunk: rendered at world position x = 5040
  - rx=0 chunk (wrapped): rendered at world position x = 5120  (offset by WORLD_SIZE)
  
When player crosses to x=0:
  - rx=0 chunk: now rendered at world position x = 0
  - rx=127 chunk (wrapped): rendered at world position x = -80  (offset by -WORLD_SIZE)
```

---

## Step 7: World Generation Editor Tool

### Editor Scene

`scenes/editor/world_editor.tscn` — a `Control` panel with:

- **Seed input** — integer, with "Randomize" button
- **Generation parameters** — sliders for `height_scale`, `octaves`, `persistence`, `lacunarity`, `height_range_max`, `water_level`
- **Output world name** — string input
- **Generate button** — runs the full generator
- **Progress bar** — shows chunk generation progress
- **Backend indicator** — shows "GDExtension (fast)" or "GDScript (slow)" so user knows what to expect
- **Open world** — button to load the generated world and jump into test play

### Editor Script

```gdscript
# world_editor_ui.gd
extends Control

@onready var _seed_input: SpinBox
@onready var _height_scale_slider: HSlider
@onready var _octaves_slider: SpinBox
@onready var _generate_btn: Button
@onready var _progress_bar: ProgressBar
@onready var _log_label: Label

func _ready() -> void:
    var has_native := ClassDB.class_exists("SimplexNoise4DNative")
    _backend_label.text = "GDExtension C++ (fast)" if has_native else "GDScript fallback (~10-20 min)"

func _on_generate_pressed() -> void:
    var config := _build_config_from_ui()
    var generator := WorldGenerator.new()
    generator.progress_changed.connect(_on_progress)

    _generate_btn.disabled = true
    _log_label.text = "Generating world..."

    # Run in thread to avoid freezing editor
    generator.generate_world(config)

func _on_progress(ratio: float) -> void:
    _progress_bar.value = ratio * 100.0
    if ratio >= 1.0:
        _log_label.text = "Generation complete!"
        _generate_btn.disabled = false

func _build_config_from_ui() -> WorldGenConfig:
    return WorldGenConfig.new({
        "seed": _seed_input.value,
        "height_scale": _height_scale_slider.value,
        "octaves": _octaves_slider.value,
        "world_name": _world_name_input.text,
        "chunk_count_x": 128,
        "chunk_count_z": 128,
        "chunk_size": 40,
    })
```

### Data-Driven Config

All editor parameters feed into a `WorldGenConfig` resource that is JSON-serializable. This means:
- Configs can be saved/loaded
- Worlds can be regenerated from the same seed+params
- Config files are portable and shareable

---

## Future Extensibility

The architecture intentionally leaves hooks for future systems:

### Hook Point 1: Per-Chunk Entity Lists

Each `ChunkData` JSON already has a flexible structure. Extend it:

```json
{
    "chunk_rx": 5,
    "chunk_rz": 12,
    "heightmap": [...],
    "biome": "forest",
    "entities": [
        { "type": "spawn_zone", "template": "goblin_patrol", "position": { "x": 12.5, "y": 0.0, "z": 8.3 } },
        { "type": "resource_node", "template": "iron_ore", "position": {...} },
        { "type": "dungeon_entrance", "template": "veins_entrance", "position": {...} }
    ]
}
```

The `ChunkLoader` would iterate `chunk_data.entities` and spawn the appropriate scene for each.

### Hook Point 2: Dynamic Chunk State

`ChunkData` can have a `state` section for persistence:

```json
{
    "chunk_rx": 5,
    "chunk_rz": 12,
    "state": {
        "modified": false,
        "harvested_nodes": [],
        "placed_structures": [],
        "active_entities": []
    }
}
```

On save, only the `state` section is written (delta from generation). On load, merge `state` back in.

### Hook Point 3: Multiplayer Sync of Chunk State

When player A harvests a resource node:
1. RPC call to host: `harvest_node(chunk_rx, chunk_rz, node_id)`
2. Host updates `ChunkData.state.harvested_nodes[node_id] = true`
3. Host saves the chunk delta
4. Host broadcasts `chunk_state_changed(chunk_rx, chunk_rz, state_delta)` to all peers
5. All clients update their local `ChunkData` and reflect the change (node disappears)

This is efficient because the full chunk data is never transmitted — only deltas.

### Hook Point 4: Chunk Unloading with Persistent State

When a chunk is unloaded (player moves away):
- Its `ChunkData.state` is already in memory (if modified)
- A background save writes it to the JSON delta file
- The chunk node is freed, but the data object persists in a `Dictionary[Vector2i, ChunkData]`

When reloaded, merge state back in.

### Hook Point 5: Navigation Mesh for AI

NPCs/enemies near chunk boundaries need their NavMesh to be continuous across chunks. The solution:
- NavMesh is baked per chunk at runtime from heightmap data
- At runtime, adjacent chunks' NavMeshes are stitched at chunk boundaries via `NavigationRegion3D.bake_from_source_geometry_data` with edge vertices forced to match
- Or: use a single unified NavMesh for the entire loaded region (merge chunks before baking)

For AI at the edge of loaded chunks: Keep a buffer of loaded chunks extending 1 chunk beyond what's rendered. AI only operates within the loaded region.

---

## Reference: Industry Best Practices

### How the Pros Do It

**Valheim** (Iron Gate Studio):
- World is generated upfront from seed at world creation
- Chunks are 32×32 world units
- Heightmap generated per-chunk from shared noise function
- Terrain mesh built with 3 LOD levels
- Collision mesh is the visual mesh (slightly simplified)
- NavMesh baked per-chunk, stitched at runtime via NavigationRegion3D
- Chunks are serialized as binary `.chunk` files

**No Man's Sky** (Hello Games):
- Entire universe is seed-based procedural — 18 quintillion planets from a single algorithm
- For any given planet, chunks are generated on-demand from the seed
- LOD uses geometry clipmaps (seamless tile-based LOD)
- No pre-baked data — everything is deterministic from seed

**The Elder Scrolls: Arena / Daggerfall** (Bethesda):
- Toroidal world wrapping (the original inspiration for this GDD's design)
- World divided into cells (chunks)
- Each cell has a heightmap + objects (buildings, NPCs, etc.)
- City/world objects defined in separate data files

**Minecraft** (Mojang):
- Chunks are 16×256×16 (x, y, z)
- Heightmap generated per-chunk using layered Perlin noise
- LOD not used — chunks are fully loaded within render distance
- For web/performance: render-distance-based chunk streaming

### Key Lessons for Solo Dev + AI Budget

1. **Upfront generation + runtime streaming is the sweet spot.** Valheim does it. It means generation is slow (acceptable for a world editor) but runtime is fast. With GDExtension C++ noise, even generation is fast (~seconds).

2. **Pre-bake data, not engine objects.** Heightmap data is the portable source of truth. Collision meshes, NavMeshes, LOD meshes are all derived at runtime from heightmap data. No pre-baked `.mesh` or `.navmesh` files — unified code path for all platforms.

3. **Toroidal wrapping requires 4D noise with torus mapping.** Standard 2D noise (`FastNoiseLite`) is NOT periodic — cannot create seamless toroidal edges. A 4D simplex noise implementation with toroidal coordinate mapping gives inherently periodic, distortion-free results. Since all values are pre-computed and saved, the slower GDScript evaluation only affects one-time generation.

4. **Use Godot's navigation server properly.** `NavigationMesh` baking happens at runtime from heightmap data on all platforms. No platform-specific pre-baking. Bake time is ~1-2s for 49 chunks — acceptable.

5. **Chunk data is pure data, stored efficiently.** `PackedFloat32Array` in `RegionData` resource archives. No 16K individual JSON files. Region-based storage reduces file count and works on web.

6. **Data-driven parameters for everything.** Noise params, generation config, biome rules — all JSON. No magic numbers in code.

7. **Multiplayer persistence is chunk-based.** Each chunk has mutable state. Only transmit chunk state deltas, not full chunks.

8. **Web export shapes every architecture decision.** File I/O overhead, memory limits, `.mesh` file incompatibility, and IndexedDB latency all constrain the design. The unified build path (all runtime) makes web a first-class target, not an afterthought.

9. **GDExtension C++ makes one-time generation fast.** A pure-math noise GDExtension compiles to both native and WebAssembly, reducing generation from ~10-40 minutes (GDScript) to ~1-14 seconds. The GDScript fallback ensures the system still works even without the GDExtension.

---

## Reference: Key Algorithms

### Seamless Heightmap Generation with 4D Toroidal Mapping

```
function generate_chunk_heightmap(chunk_rx, chunk_rz, noise, params, torus_radius):
    base_world_x = chunk_rx * CHUNK_SIZE
    base_world_z = chunk_rz * CHUNK_SIZE
    resolution = CHUNK_SIZE + 1
    WORLD_SIZE = 5120.0

    heightmap = new PackedFloat32Array[resolution * resolution]

    for local_z in 0..resolution-1:
        for local_x in 0..resolution-1:
            world_x = base_world_x + local_x
            world_z = base_world_z + local_z
            
            # Map to 4D torus coordinates (inherently periodic)
            nx = torus_radius * cos(2π * world_x / WORLD_SIZE)
            ny = torus_radius * sin(2π * world_x / WORLD_SIZE)
            nz = torus_radius * cos(2π * world_z / WORLD_SIZE)
            nw = torus_radius * sin(2π * world_z / WORLD_SIZE)
            
            height = noise.noise_4d_fbm(nx, ny, nz, nw, params)
            heightmap[local_z * resolution + local_x] = height * height_max

    return heightmap
```

### Why This Produces Seamless Toroidal Wrapping

```
# At world_x = 0:
nx = R * cos(0) = R * 1.0
ny = R * sin(0) = R * 0.0

# At world_x = WORLD_SIZE (5120):
nx = R * cos(2π * 5120 / 5120) = R * cos(2π) = R * 1.0
ny = R * sin(2π * 5120 / 5120) = R * sin(2π) = R * 0.0

# Same 4D coordinates → same noise value → seamless wrap
```

### Adjacent Chunk Seam (Automatic, No Extra Work)

```
# Chunks at rx=5 and rx=6 share world-space coordinates at their boundary:
# chunk_5 vertex at local_x=40 → world_x = 5*40 + 40 = 240
# chunk_6 vertex at local_x=0  → world_x = 6*40 + 0  = 240
# Same world-space input → same noise output → seamless
```

### Bilinear Height Interpolation

```
function get_bilinear_height(chunk_heightmap, local_x, local_z):
    # For collision/NavMesh generation from chunk data
    x0 = floor(local_x), x1 = ceil(local_x)
    z0 = floor(local_z), z1 = ceil(local_z)
    fx = local_x - x0, fz = local_z - z0

    h00 = chunk_heightmap[z0 * RES + x0]
    h10 = chunk_heightmap[z0 * RES + x1]
    h01 = chunk_heightmap[z1 * RES + x0]
    h11 = chunk_heightmap[z1 * RES + x1]

    h0 = h00 * (1-fx) + h10 * fx
    h1 = h01 * (1-fx) + h11 * fx
    return h0 * (1-fz) + h1 * fz
```

### LOD Distance Calculation (with toroidal wrapping)

```
function get_lod_for_chunk(chunk_center_world_pos, camera_world_pos, world_size):
    diff = chunk_center_world_pos - camera_world_pos
    
    # Toroidal shortest path
    if abs(diff.x) > world_size / 2:
        diff.x -= sign(diff.x) * world_size
    if abs(diff.z) > world_size / 2:
        diff.z -= sign(diff.z) * world_size
    
    dist = diff.length()

    if dist < 80: return LOD_0  # 41×41 vertices
    elif dist < 240: return LOD_1  # 21×21 vertices
    else: return LOD_2  # 11×11 vertices
```

### Toroidal Chunk Coordinate Wrapping

```
function wrap_chunk_coord(coord, chunk_count):
    # Must use posmod, not %, because % in GDScript is remainder not modulo
    return posmod(coord, chunk_count)  # chunk_count = 128 for this project
```

### Chunk Loading Decision (Streaming)

```
function should_chunk_be_loaded(chunk_pos, player_chunk, load_radius):
    dx = abs(chunk_pos.x - player_chunk.x)
    dz = abs(chunk_pos.z - player_chunk.z)
    # Handle wrap-around distance
    dx = min(dx, 128 - dx)
    dz = min(dz, 128 - dz)
    return dx <= load_radius and dz <= load_radius
```

### GDExtension Backend Auto-Detection

```
function create_noise(seed):
    if ClassDB.class_exists("SimplexNoise4DNative"):
        noise = ClassDB.instantiate("SimplexNoise4DNative")
        noise.set_seed(seed)
        return noise  # GDExtension C++ path
    else:
        return SimplexNoise4D.new(seed)  # GDScript fallback
```

---

## Implementation Checklist

### GDExtension (New in v3.0)
- [ ] `addons/simplex_noise_4d/SConstruct` — SCons build script for native + web targets
- [ ] `addons/simplex_noise_4d/src/simplex_noise_4d.hpp` — C++ header
- [ ] `addons/simplex_noise_4d/src/simplex_noise_4d.cpp` — C++ 4D simplex noise implementation
- [ ] `addons/simplex_noise_4d/src/register_types.cpp` — GDExtension binding registration
- [ ] `addons/simplex_noise_4d/simplex_noise_4d.gdextension` — GDExtension manifest
- [ ] Build: Windows `.dll` (debug + release)
- [ ] Build: Web `.side.wasm` (release)
- [ ] Test: Windows native GDExtension loads and produces correct noise values
- [ ] Test: Web WASM GDExtension loads (requires custom export templates with `dlink_enabled=yes`)
- [ ] Test: GDScript fallback produces identical output to C++ version (same seed → same heightmap)

### Data Layer
- [ ] `scripts/data/noise_params.gd` — JSON-serializable noise parameters
- [ ] `scripts/world/world_data.gd` — WorldData, loads world_meta.res, region caching, chunk access
- [ ] `scripts/world/chunk_data.gd` — ChunkData, PackedFloat32Array heightmap, bilinear interpolation
- [ ] `scripts/world/region_data.gd` — RegionData, 8×8 chunk archive resource

### Generation
- [ ] `scripts/noise/simplex_noise_4d.gd` — GDScript fallback 4D simplex noise (1D/2D/3D/4D + fBm)
- [ ] `scripts/world/world_generator.gd` — Orchestrates single-threaded generation, saves region .res files
- [ ] `scripts/world/heightmap_generator.gd` — 4D simplex noise + toroidal mapping, auto-detects backend
- [ ] `scripts/data/world_config.gd` — WorldGenConfig, generation parameters from editor

### Runtime (All Platforms — Unified)
- [ ] `scripts/world/terrain_mesh_builder.gd` — Builds ArrayMesh from heightmap data, 3 LOD levels
- [ ] `scripts/world/collision_generator.gd` — Builds ConcavePolygonShape3D from heightmap
- [ ] `scripts/world/navmesh_generator.gd` — Bakes NavigationMesh from heightmap at runtime (all platforms)
- [ ] `scripts/world/chunk_manager.gd` — Runtime chunk streaming with toroidal distance, region cache pruning
- [ ] `scripts/world/terrain_chunk.gd` — LOD-capable terrain chunk node, builds mesh/collision/nav at setup

### Scenes
- [ ] `scenes/world/terrain_chunk.tscn` — Scene template for loaded chunks
- [ ] `scenes/world/world_editor.tscn` — Editor tool scene (generation UI with backend indicator)
- [ ] Update `scenes/world/world.tscn` — Replace flat ground with ChunkManager + TerrainRoot

### Generated Data
- [ ] `data/worlds/{name}/world_meta.res` — Generated metadata (binary)
- [ ] `data/worlds/{name}/world_meta.json` — Human-readable metadata copy
- [ ] `data/worlds/{name}/regions/region_{rrx}_{rrz}.res` — 256 region files (binary)

### Integration
- [ ] Update `scripts/player/player_controller.gd` — Add world coordinate wrapping
- [ ] Update `scripts/world/world_manager.gd` — Integrate with ChunkManager for terrain

---

*Plan version: 3.0 | Created: 2026-06-20 | Updated: 2026-06-20 | Phase: 3*
*See also: docs/gdd/03-world-generation.md | docs/gdd/02-game-overview.md | docs/gdd/10-technical-architecture.md*
*Key changes from v2.0: Unified build path (no desktop/web split), GDExtension C++ 4D simplex noise as primary, GDScript fallback, compute shaders ruled out, NavMesh always runtime-baked, no pre-baked .mesh/.navmesh files*