# Phase 3: World Generation — Plan

*Plan version: 1.0 | Created: 2026-06-20 | Phase: 3*

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Architecture](#2-core-architecture)
3. [Step 0: World Data Structures](#step-0-world-data-structures)
4. [Step 1: Chunk Data System](#step-1-chunk-data-system)
5. [Step 2: Heightmap Generation](#step-2-heightmap-generation)
6. [Step 3: Mesh Generation + LOD](#step-3-mesh-generation--lod)
7. [Step 4: Collision + Navigation Mesh](#step-4-collision--navigation-mesh)
8. [Step 5: Chunk Manager (Runtime Loading)](#step-5-chunk-manager-runtime-loading)
9. [Step 6: Toroidal Wrapping](#step-6-toroidal-wrapping)
10. [Step 7: World Generation Editor Tool](#step-7-world-generation-editor-tool)
11. [Future Extensibility](#future-extensibility)
12. [Reference: Industry Best Practices](#reference-industry-best-practices)
13. [Reference: Key Algorithms](#reference-key-algorithms)

---

## 1. Overview

### Scope

**In Scope (Phase 3 — Deliverable):**
- Upfront world generation (full world generated at once, saved as chunk data)
- Heightmap-based terrain mesh generation via `FastNoiseLite`
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
| Target generation | <30 seconds for full world |
| Chunk data format | JSON (human-readable, moddable) |

The chunk size of 40×40 is chosen because:
- `5120 / 40 = 128` — clean power-of-two-aligned division
- 16,384 chunks is manageable for upfront generation
- 40×40 gives ~25×25 vertices at 1-vertex-per-unit — reasonable mesh density
- Each chunk's data file will be small; full world ~50–200 MB of JSON

### Data-First / DRY / KISS Principles

- **Noise parameters** are JSON-serializable config objects. The generator reads config, not code.
- **Chunk data is pure data** — no Godot objects. Generated once, loaded as data at runtime.
- **No code duplication** — heightmap, biome, and spawn logic all share the same seeded noise pipeline.
- **Chunk data and render chunk are separate** — data chunk = JSON file; render chunk = `Node3D` scene tree. Data is the source of truth.

---

## 2. Core Architecture

### Two-Phase Approach

```
PHASE 1: GENERATION (Editor / Build Time)
    Seed → Noise Parameters → Per-Chunk Heightmap Data → JSON files

PHASE 2: RUNTIME (Game Load)
    JSON files → Chunk Manager → LOD mesh → Static Body + NavMesh → Player exploration
```

### Directory Structure

```
res://
├── data/
│   └── worlds/
│       └── {world_name}/
│           ├── world_metadata.json          # seed, dimensions, generation params
│           └── chunks/
│               ├── chunk_000_000.json       # row 0, col 0
│               ├── chunk_000_001.json
│               └── ... (16,384 files)
├── scripts/
│   ├── world/
│   │   ├── world_data.gd                   # WorldData resource (metadata)
│   │   ├── chunk_data.gd                   # ChunkData resource (heightmap, etc.)
│   │   ├── world_generator.gd              # Generation orchestrator
│   │   ├── heightmap_generator.gd          # FastNoiseLite heightmap
│   │   ├── terrain_mesh_builder.gd         # ArrayMesh + LOD levels
│   │   ├── chunk_loader.gd                 # Runtime chunk data loader
│   │   ├── chunk_manager.gd                # Manages which chunks are loaded/rendered
│   │   ├── collision_generator.gd          # StaticBody3D mesh from heightmap
│   │   ├── navmesh_generator.gd            # NavigationMesh from heightmap
│   │   └── world_editor_ui.gd              # Generation config UI
│   └── data/
│       ├── world_config.gd                 # JSON-serializable generation parameters
│       └── noise_params.gd                 # FastNoiseLite parameter container
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

1. **Data chunk ≠ render chunk.** A `ChunkData` is a JSON file containing raw heightmap values and biome assignments. A `TerrainChunk` scene is a `Node3D` that reads `ChunkData` and constructs `MeshInstance3D` at runtime with appropriate LOD.

2. **All chunks generated upfront.** At generation time, loop over all 16,384 chunks and generate heightmap data. Save each as JSON. This matches the GDD's "entire world generated upfront as data" requirement.

3. **Runtime chunk loading is purely visual/physics.** The chunk data (heights, biomes) is already computed. At runtime, the chunk manager decides which chunks to render based on player position, builds LOD meshes, and updates `StaticBody3D` + `NavigationMesh`.

4. **Toroidal wrapping via coordinate math.** Player position wraps at world boundaries. Neighboring chunks at edges are always loaded (including the wrapped neighbors) so the seam is invisible.

5. **Editor tool is generation-focused.** The editor is a Godot scene with parameter sliders. Press "Generate" to run the full generator. It does NOT do manual terrain sculpting — that's a future phase.

---

## Step 0: World Data Structures

### World Metadata (`data/worlds/{name}/world_metadata.json`)

```json
{
    "name": "kaelor_alpha",
    "seed": 12345678,
    "created": "2026-06-20T00:00:00Z",
    "version": "1.0",
    "chunk_size": 40,
    "chunk_count_x": 128,
    "chunk_count_z": 128,
    "height_range": { "min": 0, "max": 40 },
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

### Chunk Data (`data/worlds/{name}/chunks/chunk_{rx}_{rz}.json`)

```json
{
    "chunk_rx": 0,
    "chunk_rz": 0,
    "heightmap": {
        "resolution": 41,
        "values": [ /* 1681 floats, row-major, includes edge overlap for seamlessness */ ]
    },
    "biome": "plains",
    "vertices_world_y": [ /* precomputed per-vertex Y for collision/NavMesh */ ]
}
```

**Why precompute `heightmap.values`?** `FastNoiseLite` is deterministic — given the same seed + coordinates, it always returns the same value. But precomputing and storing avoids re-running noise during collision/NavMesh generation, which can be expensive. At 41×41×16,384 = ~5.7M noise samples, this is negligible memory overhead (~23 MB) for significant speed gain.

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
    "lod_distances": [80.0, 240.0],
    "output_world_name": "kaelor_alpha"
}
```

---

## Step 1: Chunk Data System

### Files

- `scripts/data/noise_params.gd` — `class_name NoiseParams`, `@export` fields, JSON-serializable
- `scripts/world/world_data.gd` — `class_name WorldData`, loads `world_metadata.json`
- `scripts/world/chunk_data.gd` — `class_name ChunkData`, loads `chunk_Rx_Rz.json`, holds `heightmap: Array[Float]`

### ChunkData Class

```gdscript
class_name ChunkData
extends Resource

const CHUNK_SIZE: int = 40
const GRID_RESOLUTION: int = 41  # CHUNK_SIZE + 1 (inclusive edges for seamlessness)

var chunk_rx: int
var chunk_rz: int
var heightmap: Array[float]     # GRID_RESOLUTION * GRID_RESOLUTION floats
var biome: String = "plains"

static func from_json(path: String) -> ChunkData:
    # Load and deserialize JSON → ChunkData

static func get_height(world_x: float, world_z: float) -> float:
    # Bilinear interpolation within this chunk's heightmap
    # Used by collision and NavMesh generation

func get_vertex(rx: int, rz: int) -> Vector3:
    # Returns world-space position of heightmap vertex (rx, rz)
```

### World Data Class

```gdscript
class_name WorldData
extends Resource

var world_name: String
var seed: int
var chunk_count_x: int
var chunk_count_z: int
var generation_params: NoiseParams

static func load(world_name: String) -> WorldData:
    # Load world_metadata.json + instantiate WorldData

func get_chunk_path(rx: int, rz: int) -> String:
    # Returns "res://data/worlds/{world_name}/chunks/chunk_{rx}_{rz}.json"
    # Handles wrapping: (rx + chunk_count_x) % chunk_count_x

func load_chunk(rx: int, rz: int) -> ChunkData:
    # Wraps coordinates for toroidal access → get_chunk_path → ChunkData.from_json

func is_valid_chunk(rx: int, rz: int) -> bool:
    # Always true with toroidal — all coordinates valid
```

---

## Step 2: Heightmap Generation

### Algorithm Overview

For each of the 16,384 chunks, generate a `GRID_RESOLUTION × GRID_RESOLUTION` heightmap using `FastNoiseLite` with a deterministic coordinate mapping. The key is ensuring chunks generate consistent values at shared edges (toroidal seamlessness).

### Seamless Toroidal Noise

The critical challenge: chunk edge values must match between adjacent chunks so there are no visible seams.

**Solution:** Use world-space coordinates as noise input, not chunk-local coordinates.

```gdscript
# heightmap_generator.gd
func get_height_at(world_x: float, world_z: float, seed: int, params: NoiseParams) -> float:
    var noise := FastNoiseLite.new()
    noise.seed = seed
    noise.frequency = params.height_scale
    noise.octaves = params.octaves
    noise.persistence = params.persistence
    noise.lacunarity = params.lacunarity

    var height := 0.0
    for i in params.octaves:
        var nx := world_x * pow(2, i) * params.height_scale
        var nz := world_z * pow(2, i) * params.height_scale
        height += noise.get_noise_2d(nx, nz) * pow(params.persistence, i)

    return height * params.height_scale * params.height_range_max
```

**Why this works:** Chunks at (rx=0,rz=0) and (rx=127,rz=0) share the same world_x coordinate range (e.g., [0,40] and [5080,5120]). When wrapping, the noise function's periodic behavior is NOT used — instead, the heightmap values naturally align because `get_height_at` uses world-space coordinates that wrap at world boundaries. As long as two adjacent chunks sample the same world_x/z values at their shared edge, heights match perfectly.

For chunk local storage, we only store `CHUNK_SIZE + 1 = 41` vertices per axis. The `+1` provides the overlap seam for neighbor matching.

### World Generator Orchestrator

```gdscript
# world_generator.gd
func generate_world(config: WorldGenConfig) -> void:
    var total_chunks := config.chunk_count_x * config.chunk_count_z
    var progress := 0.0
    var chunk_paths := []

    for rx in range(config.chunk_count_x):
        for rz in range(config.chunk_count_z):
            # Generate heightmap data for this chunk
            var heightmap := _generate_chunk_heightmap(rx, rz, config)

            # Determine biome (future: use temperature + moisture noise)
            var biome := "plains"

            var chunk_data := ChunkData.new()
            chunk_data.chunk_rx = rx
            chunk_data.chunk_rz = rz
            chunk_data.heightmap = heightmap
            chunk_data.biome = biome

            # Save to JSON
            var path := _get_chunk_path(rx, rz, config.world_name)
            chunk_data.save_to_json(path)
            chunk_paths.append(path)

            progress += 1.0
            _report_progress(progress / total_chunks)

    # Save world metadata
    _save_world_metadata(config)
```

**Important:** Generation is I/O-bound. Use `WorkerThreadPool` for parallel chunk generation (GDScript, web-compatible). Each thread generates one chunk's heightmap independently — no shared state, no race conditions.

```gdscript
func _generate_chunk_heightmap_async(rx: int, rz: int, config: WorldGenConfig) -> Array[float]:
    # Worker thread function — pure computation, no Godot scene access
    pass

# Call via:
WorkerThreadPool.add_task(func(): _generate_chunk_heightmap_async(...))
```

**Generation target:** With 16,384 chunks and each taking ~1ms to generate, total time is ~16 seconds with parallelization. Reasonable for the <30 second target.

---

## Step 3: Mesh Generation + LOD

### TerrainMeshBuilder

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

static func build_chunk_mesh(chunk_data: ChunkData, lod: int, world_data: WorldData) -> ArrayMesh:
    var spacing: float = pow(2.0, lod)
    var resolution: int = 41  # always build from full res, decimate during index gen

    var surface_tool := SurfaceTool.new()
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

    for rz in range(0, resolution, int(spacing)):
        for rx in range(0, resolution, int(spacing)):
            var world_x := chunk_data.chunk_rx * world_data.chunk_size * 40.0 + rx
            var world_z := chunk_data.chunk_rz * world_data.chunk_size * 40.0 + rz
            var height: float = chunk_data.heightmap[rz * resolution + rx]

            var vertex := Vector3(world_x, height, world_z)
            surface_tool.add_vertex(vertex)

            # UV
            surface_tool.set_uv(Vector2(rx, rz) / float(resolution - 1))

            # Color (biome-based)
            surface_tool.set_color(_get_biome_color(chunk_data.biome))

    # Generate indices for triangle strip → triangles
    _add_indices_for_grid(surface_tool, resolution, spacing)

    return surface_tool.commit()
```

**Note:** Build all 3 LOD meshes upfront during generation and store them in the chunk data JSON as `PackedByteArray` (or as separate `.mesh` files). Runtime only does `MeshInstance3D.mesh = lod_mesh[lod_level]` — no mesh building at runtime. This is critical for web performance.

**Better approach:** Store pre-built `ArrayMesh` as Godot `.mesh` binary files in `res://data/worlds/{name}/chunks/meshes/`. Godot's binary mesh format loads instantly. Use `ResourceSaver` during generation.

```gdscript
# During generation:
var mesh := TerrainMeshBuilder.build_chunk_mesh(chunk_data, lod, world_data)
ResourceSaver.save(mesh, chunk_mesh_path)

# At runtime:
var mesh := load(chunk_mesh_path) as ArrayMesh
mesh_instance.mesh = mesh
```

### Biome Coloring

For Phase 3, use **vertex coloring** — no texture atlas. Each vertex gets a `Color` based on its biome. The `SurfaceTool.set_color()` call applies this. In future phases, vertex colors can blend at biome borders.

Initial biomes (simplified):
- Plains: `#4A7C3F` (green)
- Mountain: `#8B7355` (brown)
- Water: `#2E5A8C` (blue, at or below water_level)

---

## Step 4: Collision + Navigation Mesh

### CollisionGenerator

Each chunk needs a `StaticBody3D` with a collision mesh generated from the heightmap.

**Approach:** Generate a simplified collision mesh using the same vertex grid, but with merged faces (one `Mesh` for the whole chunk, not individual triangles).

```gdscript
# collision_generator.gd
static func build_collision_mesh(chunk_data: ChunkData, world_data: WorldData) -> Mesh:
    # Build a simplified mesh (no UVs, no colors needed for collision)
    # Use the full-resolution heightmap (LOD0 geometry)
    # Create triangles from the grid — no indexing needed, just add vertices + indices

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var resolution: int = 41
    for rz in range(resolution - 1):
        for rx in range(resolution - 1):
            # Get 4 corners of the quad
            var h00 := chunk_data.heightmap[(rz + 0) * resolution + (rx + 0)]
            var h10 := chunk_data.heightmap[(rz + 0) * resolution + (rx + 1)]
            var h01 := chunk_data.heightmap[(rz + 1) * resolution + (rx + 0)]
            var h11 := chunk_data.heightmap[(rz + 1) * resolution + (rx + 1)]

            var base_x := chunk_data.chunk_rx * world_data.chunk_size
            var base_z := chunk_data.chunk_rz * world_data.chunk_size

            var v00 := Vector3(base_x + rx + 0, h00, base_z + rz + 0)
            var v10 := Vector3(base_x + rx + 1, h10, base_z + rz + 0)
            var v01 := Vector3(base_x + rx + 0, h01, base_z + rz + 1)
            var v11 := Vector3(base_x + rx + 1, h11, base_z + rz + 1)

            # Two triangles per quad
            st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v01)
            st.add_vertex(v10); st.add_vertex(v11); st.add_vertex(v01)

    return st.commit()
```

**Critical:** For the `StaticBody3D` to work with the character controller, the collision mesh must match the visual mesh closely. Use the same heightmap data.

### NavMeshGenerator

Use Godot's `NavigationMesh` API. The heightmap grid naturally forms a walkable mesh.

```gdscript
# navmesh_generator.gd
static func build_navmesh(chunk_data: ChunkData, world_data: WorldData) -> NavigationMesh:
    var navmesh := NavigationMesh.new()
    var geometry := NavigationMeshSourceGeometryData3D.new()

    # Add the terrain mesh as source geometry
    var collision_mesh: Mesh = CollisionGenerator.build_collision_mesh(chunk_data, world_data)
    navmesh.add_source_geometry(collision_mesh)

    # Configure agent parameters
    navmesh.agent_radius = 0.5
    navmesh.agent_height = 1.6
    navmesh.agent_max_climb = 0.5  # Max step height
    navmesh.agent_max_slope = 50.0  # Degrees

    # Bake
    NavigationServer3D.bake_from_source_geometry_data(navmesh, geometry)
    return navmesh
```

**Web compatibility note:** `NavigationServer3D.bake_from_source_geometry_data()` is server-side only (runs in the navigation server thread). For web, NavMesh baking should happen **at generation time** (offline), not at runtime. Pre-bake and store the `NavigationMesh` as a `.navmesh` binary file.

```gdscript
# At generation time (offline):
var navmesh := NavMeshGenerator.build_navmesh(chunk_data, world_data)
ResourceSaver.save(navmesh, chunk_navmesh_path)

# At runtime:
var navmesh: NavigationMesh = load(chunk_navmesh_path)
nav_region.navigation_mesh = navmesh
```

This approach also avoids runtime CPU cost, which is critical for web builds.

---

## Step 5: Chunk Manager (Runtime Loading)

### ChunkManager

At runtime, only chunks near the player are loaded into the scene tree. This is the classic spatial streaming system.

```gdscript
# chunk_manager.gd
extends Node3D

const LOAD_RADIUS: int = 3  # Load chunks within 3-chunk radius of player
const UNLOAD_DISTANCE: int = 5  # Unload chunks beyond 5-chunk radius

var _world_data: WorldData
var _loaded_chunks: Dictionary = {}  # (rx, rz) → TerrainChunk instance
var _player_chunk: Vector2i = Vector2i(-1, -1)

@onready var _world_root: Node3D = %WorldRoot

func _ready() -> void:
    _world_data = WorldData.load("kaelor_alpha")

func _process(_delta: float) -> void:
    var player_pos := _get_player_world_position()
    var player_chunk: Vector2i = _world_to_chunk(player_pos)

    if player_chunk != _player_chunk:
        _player_chunk = player_chunk
        _update_loaded_chunks()

func _update_loaded_chunks() -> void:
    # Determine which chunks should be loaded
    var to_load: Array[Vector2i] = []
    for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
        for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
            var chunk_pos := Vector2i(_player_chunk.x + dx, _player_chunk.y + dz)
            chunk_pos = _wrap_chunk_coords(chunk_pos)
            if not _loaded_chunks.has(chunk_pos):
                to_load.append(chunk_pos)

    # Unload distant chunks
    var to_unload: Array[Vector2i] = []
    for chunk_pos in _loaded_chunks.keys():
        var dist := _chunk_distance(chunk_pos, _player_chunk)
        if dist > UNLOAD_DISTANCE:
            to_unload.append(chunk_pos)

    # Execute loads
    for chunk_pos in to_load:
        _load_chunk(chunk_pos)

    # Execute unloads
    for chunk_pos in to_unload:
        _unload_chunk(chunk_pos)

func _load_chunk(chunk_pos: Vector2i) -> void:
    var chunk_data: ChunkData = _world_data.load_chunk(chunk_pos.x, chunk_pos.y)

    var chunk_scene: Node3D = _create_chunk_node(chunk_pos, chunk_data)
    _world_root.add_child(chunk_scene)
    _loaded_chunks[chunk_pos] = chunk_scene

func _unload_chunk(chunk_pos: Vector2i) -> void:
    var chunk_node: Node3D = _loaded_chunks[chunk_pos]
    chunk_node.queue_free()
    _loaded_chunks.erase(chunk_pos)
```

### TerrainChunk Node

```gdscript
# terrain_chunk.gd (attached to each chunk instance)
extends Node3D

var _chunk_data: ChunkData
var _mesh_instances: Array[MeshInstance3D] = []
var _static_body: StaticBody3D
var _nav_region: NavigationRegion3D

func setup(chunk_data: ChunkData, world_data: WorldData, lod: int) -> void:
    _chunk_data = chunk_data

    # LOD mesh
    var mesh: ArrayMesh = _load_lod_mesh(chunk_data, lod)
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.position = Vector3(chunk_data.chunk_rx * 40.0, 0.0, chunk_data.chunk_rz * 40.0)
    add_child(mi)
    _mesh_instances.append(mi)

    # Static body
    var collision_mesh: Mesh = _load_collision_mesh(chunk_data)
    var sb := StaticBody3D.new()
    var shape := ConcavePolygonShape3D.new()
    # ... set up collision from collision_mesh ...
    sb.add_child(shape)
    sb.position = mi.position
    add_child(sb)
    _static_body = sb

    # Navigation
    var navmesh: NavigationMesh = _load_navmesh(chunk_data)
    var nav_region := NavigationRegion3D.new()
    nav_region.navigation_mesh = navmesh
    nav_region.position = mi.position
    add_child(nav_region)
    _nav_region = nav_region

func _load_lod_mesh(chunk_data: ChunkData, lod: int) -> ArrayMesh:
    var path := "res://data/worlds/kaelor_alpha/chunks/meshes/chunk_%d_%d_lod%d.mesh" % [chunk_data.chunk_rx, chunk_data.chunk_rz, lod]
    return load(path) as ArrayMesh
```

### LOD Selection

```gdscript
# Inside ChunkManager._create_chunk_node:
func _determine_lod(chunk_pos: Vector2i) -> int:
    var player_world_pos := _get_player_world_position()
    var chunk_center := Vector3(chunk_pos.x * 40.0 + 20.0, 0.0, chunk_pos.y * 40.0 + 20.0)
    var dist := player_world_pos.distance_to(chunk_center)

    if dist < 80.0:
        return 0
    elif dist < 240.0:
        return 1
    else:
        return 2
```

**Future optimization:** Transition between LOD levels smoothly (not pop-in). In Godot 4, this can be done with `LOD3D` or by blending mesh transition. Defer for now.

---

## Step 6: Toroidal Wrapping

### Player Coordinate Wrapping

The player's `CharacterBody3D` should be able to move freely without hitting a wall. The key is that world coordinates always wrap for chunk lookups, but the player's visual position must also wrap.

```gdscript
# In player_controller.gd or a WorldRoot level script:
const WORLD_SIZE_X: float = 5120.0
const WORLD_SIZE_Z: float = 5120.0

func _process(_delta: float) -> void:
    var pos := global_position

    # Wrap X
    if pos.x < 0:
        pos.x += WORLD_SIZE_X
    elif pos.x >= WORLD_SIZE_X:
        pos.x -= WORLD_SIZE_X

    # Wrap Z
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

### Visual Seamlessness

With the chunk loading system, at any position near an edge, the player sees chunks from both sides of the world. Because the heightmap generation uses world-space coordinates, the seam is seamless — the terrain tiles perfectly.

**Near the east edge (x ≈ 5120):**
- Loaded chunks include the actual east chunks (rx ≈ 127)
- Plus the wrapped west chunks (rx = 0) at x+WORLD_SIZE_X
- Both generate heights that align at the boundary because they share the same world-space samples

**Crossing the boundary:**
- Player moves from x=5119 to x=5120 → x wraps to x=0
- Same chunk (rx=0) now appears at both x=0 and x=5120
- No pop — the heightmap is consistent

### Camera and Third-Person Considerations

When the camera is near a world boundary and looking across it, the renderer needs to see chunks on both sides. The `ChunkManager` already handles this because it loads based on world-space position — if the player's camera is at x=5110 looking east, chunks at rx=127 (x ≈ 5040–5120) AND rx=0 (x ≈ 0–40) are both loaded.

---

## Step 7: World Generation Editor Tool

### Editor Scene

`scenes/editor/world_editor.tscn` — a `Control` panel with:

- **Seed input** — integer, with "Randomize" button
- **Generation parameters** — sliders for `height_scale`, `octaves`, `persistence`, `lacunarity`, `height_range_max`, `water_level`
- **Output world name** — string input
- **Generate button** — runs the full generator
- **Progress bar** — shows chunk generation progress
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
- NavMesh is pre-baked per chunk
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

1. **Upfront generation + runtime streaming is the sweet spot.** Valheim does it. It means generation is slow (acceptable for a world editor) but runtime is fast.

2. **Pre-bake everything possible.** Collision meshes, NavMeshes, LOD meshes — all pre-built during generation. Runtime is purely loading and placing nodes.

3. **Toroidal wrapping requires world-space noise sampling** — not chunk-local. This ensures seamlessness.

4. **Use Godot's navigation server properly.** `NavigationMesh` baking should happen at generation time, not runtime. Store as binary `.navmesh` files.

5. **Chunk data is pure JSON data.** No Godot objects serialized. This means worlds are portable, shareable, and editable outside Godot.

6. **Data-driven parameters for everything.** Noise params, generation config, biome rules — all JSON. No magic numbers in code.

7. **Multiplayer persistence is chunk-based.** Each chunk has mutable state. Only transmit chunk state deltas, not full chunks.

---

## Reference: Key Algorithms

### Seamless Heightmap Generation (Pseudocode)

```
function generate_chunk_heightmap(chunk_rx, chunk_rz, world_seed, params):
    base_world_x = chunk_rx * CHUNK_SIZE
    base_world_z = chunk_rz * CHUNK_SIZE
    resolution = CHUNK_SIZE + 1

    heightmap = new Array[resolution * resolution]

    for local_z in 0..resolution-1:
        for local_x in 0..resolution-1:
            world_x = base_world_x + local_x
            world_z = base_world_z + local_z
            height = sample_seamless_noise(world_x, world_z, world_seed, params)
            heightmap[local_z * resolution + local_x] = height

    return heightmap

function sample_seamless_noise(world_x, world_z, seed, params):
    # Uses FastNoiseLite with world-space coordinates
    # Chunks at edges automatically align because they sample the same world coords
    return FastNoiseLite.noise2d(world_x * freq, world_z * freq) * amplitude
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

### LOD Distance Calculation

```
function get_lod_for_chunk(chunk_center_world_pos, camera_world_pos):
    dist = chunk_center_world_pos.distance_to(camera_world_pos)

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

---

## Implementation Checklist

- [ ] `scripts/data/noise_params.gd` — JSON-serializable noise parameters
- [ ] `scripts/world/world_data.gd` — WorldData, loads world_metadata.json
- [ ] `scripts/world/chunk_data.gd` — ChunkData, loads chunk JSONs, heightmap access
- [ ] `scripts/world/world_generator.gd` — Orchestrates parallel generation of all chunks
- [ ] `scripts/world/heightmap_generator.gd` — Seamless heightmap via world-space noise
- [ ] `scripts/world/terrain_mesh_builder.gd` — Builds ArrayMesh + 3 LOD levels
- [ ] `scripts/world/collision_generator.gd` — Builds StaticBody3D collision mesh
- [ ] `scripts/world/navmesh_generator.gd` — Pre-bakes NavigationMesh at generation time
- [ ] `scripts/world/chunk_manager.gd` — Runtime chunk streaming based on player position
- [ ] `scripts/world/world_editor_ui.gd` — Parameter sliders + generate button + progress
- [ ] `scenes/world/terrain_chunk.tscn` — Scene template for loaded chunks
- [ ] `scenes/editor/world_editor.tscn` — Editor tool scene
- [ ] `data/worlds/{name}/world_metadata.json` — Generated metadata
- [ ] `data/worlds/{name}/chunks/chunk_{rx}_{rz}.json` — 16,384 chunk data files
- [ ] Update player controller for world coordinate wrapping
- [ ] Update GDD `03-world-generation.md` with implementation details

---

*Plan version: 1.0 | Created: 2026-06-20 | Phase: 3*
*See also: docs/gdd/03-world-generation.md | docs/gdd/02-game-overview.md | docs/gdd/10-technical-architecture.md*