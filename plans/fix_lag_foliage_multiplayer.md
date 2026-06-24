# Fix Plan: Lag Spikes, Foliage Rendering, Multiplayer RPC Race

## Issue A: Chunk Loading Lag Spikes

### Root Cause
The foliage queue only moved foliage generation out of `_load_chunk`. The **terrain** pipeline is still entirely synchronous:

1. **`_update_loaded_chunks()`** (`chunk_manager.gd:104-105`) loads ALL new chunks in a single frame loop — when crossing a chunk boundary, 10-50+ chunks can load at once.
2. **Each `_load_chunk()`** does 3 heavy synchronous operations:
   - `WorldData.get_chunk_data()` → `_load_region()` → `ResourceLoader.load()` (synchronous disk I/O, ~hundreds KB per region .res file)
   - `TerrainChunk.setup()` → `TerrainMeshBuilder.build_chunk_mesh()` (SurfaceTool: ~1,600 quads + normal gen + commit)
   - `TerrainChunk.setup()` → `CollisionGenerator.build_collision_shape()` (9,600 vertices, ConcavePolygonShape3D)
3. **Duplicate collision work**: `NavMeshGenerator.build_navmesh()` builds collision shape **again** (line 16 of navmesh_generator.gd).
4. **NavMesh baking**: `NavigationMeshGenerator.bake_from_source_geometry_data()` is extremely CPU-heavy, and multiple bake calls can queue up across frames.

### Fix Plan

#### A1: Chunk load budget — process N chunks per frame
In `chunk_manager.gd`, replace the synchronous `for chunk_pos in to_load: _load_chunk(...)` loop with a queue:

```gdscript
var _chunk_load_queue: Array[Vector2i] = []
const CHUNKS_PER_FRAME: int = 2

func _process(delta):
    if not _initialized: return
    _process_chunk_queue()
    _update_chunks()  # only detects chunk changes, queues new loads

func _update_loaded_chunks():
    # ... existing logic to compute to_load / to_unload ...
    for chunk_pos in to_unload:
        _unload_chunk(chunk_pos)
    _chunk_load_queue.append_array(to_load)  # queue instead of immediate
    # ... rest of refresh/lod logic ...

func _process_chunk_queue():
    for i in range(mini(CHUNKS_PER_FRAME, _chunk_load_queue.size())):
        _load_chunk(_chunk_load_queue.pop_front())
```

Key: unload still happens immediately (no cost), but loads are spread across frames. Keep `_update_lods()` and `_refresh_chunk_positions()` running every frame since they're cheap.

#### A2: Async region loading
In `world_data.gd`, replace `ResourceLoader.load()` with `ResourceLoader.load_threaded()`:

```gdscript
func _load_region(rrx, rrz):
    if _cached_regions.has(key): return _cached_regions[key]
    var path = get_region_path(rrx, rrz)
    if not ResourceLoader.exists(path): return null
    ResourceLoader.load_threaded_request(path)
    # ... need to handle the async pattern
```

This is complex because `get_chunk_data()` is synchronous. Two approaches:
- **Simple**: Preload regions when player enters a new area (call `ResourceLoader.load_threaded_request` proactively), then poll for completion.
- **Better**: Add `WorldData.preload_regions_around(chunk_x, chunk_z, radius)` that starts threaded loads for likely-needed regions. The synchronous `_load_region` will hit the cache since threaded loads complete in background.

**Recommended: Simple approach** — add a preload step in `_update_loaded_chunks()` before queuing chunk loads:

```gdscript
func _preload_needed_regions(to_load):
    var needed = _compute_needed_regions(to_load)
    for key in needed:
        if not _world_data.has_cached_region(key):
            _world_data.request_threaded_load(key)

func _process_chunk_queue():
    for i in range(mini(CHUNKS_PER_FRAME, _chunk_load_queue.size())):
        var chunk_pos = _chunk_load_queue.pop_front()
        if _world_data.is_region_ready_for(chunk_pos):
            _load_chunk(chunk_pos)
        else:
            _chunk_load_queue.push_front(chunk_pos)  # re-queue, try next frame
            break
```

Add to `WorldData`:
- `has_cached_region(key) -> bool`
- `request_threaded_load(key) -> void`
- `is_region_ready_for(chunk_rx, chunk_rz) -> bool`

#### A3: Eliminate duplicate collision shape for navmesh
In `navmesh_generator.gd`, reuse the chunk's existing StaticBody3D/collision instead of creating a new one:

```gdscript
func build_navmesh(chunk_data, chunk_node):
    var navmesh := NavigationMesh.new()
    # ... navmesh params ...
    var source_geometry := NavigationMeshSourceGeometryData3D.new()
    # Use the chunk's existing _static_body instead of creating a new collision
    var static_body = chunk_node.get_node("StaticBody3D")
    NavigationMeshGenerator.parse_source_geometry_data(navmesh, source_geometry, static_body)
    await chunk_node.get_tree().process_frame
    NavigationMeshGenerator.bake_from_source_geometry_data(navmesh, source_geometry)
    return navmesh
```

Also throttle navmesh baking — only bake for the closest N chunks per frame.

#### A4: NavMesh bake throttling
Add a queue for navmesh baking in `TerrainChunk._ready()`:

```gdscript
# In chunk_manager.gd:
var _navmesh_queue: Array[TerrainChunk] = []
const NAVMESH_PER_FRAME: int = 1

func _process_navmesh_queue():
    if _navmesh_queue.is_empty(): return
    var chunk = _navmesh_queue.pop_front()
    if is_instance_valid(chunk) and chunk.is_inside_tree():
        chunk.bake_navmesh_now()
```

---

## Issue B: Foliage Rendering — Sprite-based Billboards

### Root Cause
Current foliage uses procedural `ArrayMesh` (solid colored pyramids/diamonds/cards). These have no textures, no configurable sprite sizes, and don't match the pixel-art aesthetic of the player characters.

### Design
Player uses `pixel_size = 0.05` (1 pixel = 0.05 world units, or 20px = 1 world unit). Foliage should follow the same scale.

**Two rendering options:**

#### Option 1: Y-Billboard Sprite3D per MultiMesh instance (REJECTED)
Sprite3D cannot be used with MultiMesh directly — each Sprite3D is a separate node. Would need 1500+ nodes for grass. Not viable.

#### Option 2: Cross-Plane MultiMesh with AtlasTextures (RECOMMENDED)
Use two intersecting quads (cross planes = "X" pattern when viewed from above) per foliage instance, rendered via MultiMesh with a shared texture atlas. This is the standard approach for grass/bushes in stylized games.

**Implementation:**

1. **Create foliage texture atlas** — a single PNG with regions for grass, bush, tree sprites at configurable pixel sizes:
   - Grass: 16×16 sprite (configurable via `FoliageType.sprite_size`)
   - Bush: 16×16 sprite
   - Tree: 16×32 sprite

2. **Create cross-plane meshes** per type — two quads at 90° rotation around Y:
   ```
   Quad A: vertices (-w,0,0), (w,0,0), (-w,h,0), (w,h,0) with UVs (0,1)...(1,0)
   Quad B: vertices (0,0,-w), (0,0,w), (0,h,-w), (0,h,w) with same UVs
   ```
   Where `w` = width in world units = `sprite_size_x * pixel_size`, `h` = height = `sprite_size_y * pixel_size`.

3. **Update `FoliageRenderer`**:
   - Store `pixel_size: float = 0.05` (configurable, same as player)
   - Per foliage type, define `sprite_size: Vector2i` (e.g., grass = 16×16, tree = 16×32)
   - Per foliage type, define `texture_region: Rect2` (atlas region)
   - `_create_grass_card()` → `_create_cross_plane(sprite_size, texture_region)`
   - Same for bush and tree, but with different dimensions

4. **Update `foliage.gdshader`**:
   - Sample from a texture atlas using UVs: `ALBEDO = texture_albedoLOD0; ALPHA = ALBEDO.a;` or use `ALPHA_SCISSOR` threshold for cutout (more performant than alpha blend)
   - Keep wind vertex shader
   - Keep `vertex_lighting` and `cull_disabled` (both sides of cross planes visible)

5. **Configurable defaults**:
   ```gdscript
   var FOLIAGE_TYPES: Dictionary = {
       "grass": {
           "max_per_chunk": 1500,
           "sprite_size": Vector2i(16, 16),  # pixels
           "pixel_size": 0.05,                # world units per pixel
           "texture_path": "res://assets/sprites/foliage/grass.png",
           # ... mesh cached after first build
       },
       "bush": { "sprite_size": Vector2i(16, 16), ... },
       "tree": { "sprite_size": Vector2i(16, 32), ... },
   }
   ```

6. **Art assets needed**: Create/atlas the sprite textures for grass, bush, tree. These can be simple pixel-art 16×16 and 16×32 PNGs matching the game's existing aesthetic.

---

## Issue C: Multiplayer "Node not found: World/Players/Player_2" RPC Race

### Root Cause
Three interlocking race conditions:

1. **Scene transition gap**: `connection_succeeded` fires while main_menu is still the active scene. The 1-second timer then calls `change_scene_to_file`. If `peer_connected(2)` fires during this gap (or during the scene transition itself), `WorldManager._on_peer_connected` doesn't exist yet — the player node for peer 2 is never spawned on the host.

2. **Same-frame RPC race**: When the WebRTC channel opens, `peer_connected` fires and the host spawns `Player_2` via `_spawn_player(2)`. But the client's `Player_2` starts sending `sync_transform` RPCs immediately in `_physics_process`. These RPCs address the path `World/Players/Player_2` on the host, but the node may not be in the tree yet when the first RPC is processed.

3. **`initial_sync` only sent for local player**: `_place_player_on_terrain` only runs for the local authority player (line 43-44 of world_manager.gd). The remote player never gets an `initial_sync`, so its first reliable position data is unreliable `sync_transform` packets which may arrive before the node exists.

### Fix Plan

#### C1: Buffer RPCs for unknown nodes
Godot's high-level multiplayer automatically drops RPCs for nodes not in the scene tree (with the error we see). Instead, we need to ensure nodes exist before RPCs arrive. The simplest fix:

**Spawn ALL expected players when WorldManager loads**, by querying the multiplayer peer list:

```gdscript
func _ready():
    _players.add_to_group("players")
    MultiplayerManager.peer_connected.connect(_on_peer_connected)
    MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

    # Spawn players for all already-connected peers (handles race where
    # peer_connected fires before the world scene loads)
    if multiplayer.multiplayer_peer != null:
        for peer_id in multiplayer.get_peers():
            _spawn_player(peer_id)

    # Always spawn self
    if MultiplayerManager.get_my_id() != 0:
        _spawn_player(MultiplayerManager.get_my_id())
```

This eliminates the "missed signal" race by checking the current peer list on startup.

#### C2: Defer RPC sending until remote peer confirms player is spawned
In `player_controller.gd`, don't send `sync_transform` until we know the remote side has the node:

```gdscript
var _rpc_ready: bool = false

func _ready():
    # ... existing code ...
    if is_multiplayer_authority():
        # Wait 2 frames for the node to propagate to all clients
        await get_tree().create_timer(0.1).timeout
        _rpc_ready = true
```

Or simpler: use `rpc_id` to target specific peers only after confirming they can see the node. But this adds complexity.

**Simpler approach**: Put guards in `sync_transform` and `initial_sync` on the receiving side:

```gdscript
@rpc("any_peer", "unreliable")
func sync_transform(pos, yaw):
    # Silently ignore if we don't have authority (node exists but not ours to move)
    if is_multiplayer_authority(): return
    global_transform.origin = pos
    camera_yaw = yaw
```

Wait, the error is on the **sender** — Godot can't find the path on the remote. The RPC is being sent TO `World/Players/Player_2` which doesn't exist on the host yet. But Godot's error is on the receiving side.

**Best fix: Combine C1 with a graceful RPC receive handler.**

#### C3: Add initial_sync for remote players
When the host spawns a remote player (`peer_id != my_id`), it should send that player's initial position:

```gdscript
func _spawn_player(peer_id):
    if _players.get_node_or_null(_player_name(peer_id)):
        return
    var player = player_scene.instantiate()
    player.name = _player_name(peer_id)
    player.set_multiplayer_authority(peer_id)
    _players.add_child(player)
    if peer_id == MultiplayerManager.get_my_id():
        _place_player_on_terrain(player)
    # For remote players: the authority peer will send initial_sync
```

The client (authority over Player_2) needs to send initial_sync after spawning:

```gdscript
# In player_controller.gd _ready(), after being added to tree:
if is_multiplayer_authority() and multiplayer.multiplayer_peer:
    # Small delay to ensure all peers have the node
    await get_tree().create_timer(0.2).timeout
    rpc("initial_sync", global_position, camera_yaw)
```

#### C4: Scene transition — ensure peer_connected persists across scene change
Since `MultiplayerManager` is an autoload, its signals persist. But `WorldManager` connects to them in `_ready()`. If `peer_connected` fires before the world scene loads, the signal is missed.

**Fix**: In `WorldManager._ready()`, check existing connections:

```gdscript
func _ready():
    _players.add_to_group("players")
    MultiplayerManager.peer_connected.connect(_on_peer_connected)
    MultiplayerManager.peer_disconnected.connect(_on_peer_disconnected)

    # Handle peers that connected before this scene loaded
    if multiplayer.multiplayer_peer:
        for existing_peer in multiplayer.get_peers():
            _spawn_player(existing_peer)

    # Spawn self
    var my_id = MultiplayerManager.get_my_id()
    if my_id != 0:
        _spawn_player(my_id)
```

Remove the `_on_connection_succeeded` handler since it's redundant with the above.

---

## Implementation Order

1. **C: Multiplayer race fix** — smallest change, biggest reliability win
   - C1+C4: WorldManager._ready spawns all existing peers
   - C3: Player sends initial_sync after short delay

2. **A: Chunk loading performance** — most impactful for smoothness
   - A1: Chunk load queue (CHUNKS_PER_FRAME=2)
   - A2: Threaded region preloading
   - A3: Eliminate duplicate collision for navmesh
   - A4: NavMesh bake throttling

3. **B: Sprite-based foliage** — visual overhaul
   - Create cross-plane mesh builder
   - Create foliage texture atlas
   - Update foliage.gdshader for texture sampling with alpha cutout
   - Update FoliageRenderer with configurable sprite sizes
   - Update FoliageGenerator to remove per-instance color (now comes from texture)
