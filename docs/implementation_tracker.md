# Implementation Tracker — Veins of Kaelor

> **Purpose:** Living document that tracks what has been built vs. what the GDD specifies. It is meant to be read by a model (or human) with **zero prior context** so they can immediately understand the project's current state, what remains, and how to update this tracker.
> 
> **Last Updated:** 2026-06-22

---

## 1. Project Overview

**Game:** Veins of Kaelor  
**Engine:** Godot 4.6 (Compatibility renderer for web export)  
**Genre:** Pseudo-3D action RPG sandbox  
**Platform:** Web-first (browser), desktop secondary  
**Architecture:** True WebRTC P2P mesh (8-player target), world/character data separation (Valheim-style)  

### GDD Document Map (for cross-reference)

| File | Topic | Status |
|------|-------|--------|
| `00-gdd-index.md` | Master index + resolved/open questions | Reference |
| `01-design-questionnaire.md` | 74 answered design questions | Reference |
| `02-game-overview.md` | Vision, pillars, factions, target experience | Reference |
| `03-world-generation.md` | Procedural terrain, biomes, dungeons, day/night, weather | **In Progress** (terrain gen + torus wrapping done; biomes, water, foliage deferred) |
| `04-building-system.md` | Buildings, interiors, culling | **Backburnered** |
| `05-entities-characters.md` | Billboard sprites, 15-layer stacking, camera, AI, mounts | **Partial** (4-way directional sprite stacking done; animation, NPC, AI, mounts not started) |
| `06-gameplay-systems.md` | Combat, Transmatalogy, crafting, quests, factions, economy, death | **Not Started** |
| `07-ui-ux.md` | HUD, menus, controls, ghost state UI | **Partial** (main menu + basic HUD only) |
| `08-art-direction.md` | Visual style, sprite stacking, textures | **Partial** (4-way sprite system implemented; art assets placeholder) |
| `09-audio.md` | Music, SFX, ambient | **Not Started** |
| `10-technical-architecture.md` | Godot structure, WebRTC, web export, key systems | **Partial** (multiplayer scaffold + world data architecture done) |
| `11-appendix.md` | Glossary, inspirations, tools | Reference |
| `12-multiplayer-sync-fix.md` | Documentation of the player.tscn replication fix | **Done** |

---

## 2. What Exists Right Now (Completed Features)

### 2.1 Networking Layer (WebRTC P2P)
- [x] **Self-hosted WebSocket signaling server** (`scripts/multiplayer/signaling_server.gd`)
  - Listens on configurable port (default 9080)
  - Assigns unique peer IDs
  - Relays JOIN / OFFER / ANSWER / CANDIDATE messages
- [x] **MultiplayerManager autoload** (`scripts/multiplayer/multiplayer_manager.gd`)
  - Host path: starts signaling server, creates `WebRTCMultiplayerPeer` mesh
  - Client path: connects to signaling server, joins mesh
  - ICE candidate buffering/flushing until remote description is set
  - WebRTC connection state guards (won't call `create_offer` if not in `STATE_NEW`)
  - Connection lifecycle signals: `connection_succeeded`, `connection_failed`, `peer_connected`, `peer_disconnected`
- [x] **Host/Client spawn flow**
  - Host (ID 1) spawns its player immediately
  - Clients spawn after receiving their ID from the signaling server
  - `WorldManager` listens to `peer_connected`/`peer_disconnected` to spawn/despawn player instances
- [x] **Player authority assignment**
  - Each spawned player node gets `set_multiplayer_authority(peer_id)`
  - Local physics + camera only run if `is_multiplayer_authority()` is true
- [x] **Player sync via `@rpc`**
  - `@rpc("any_peer", "unreliable") func sync_transform(...)` replicates position + rotation.y
  - Non-auth peers apply the sync; authority peer ignores incoming sync to avoid overwriting local input
  - Positions unwrapped via `TorusUtils.wrap_vector3_near()` for toroidal awareness
- [x] **Reliable initial sync RPC** (`@rpc("authority", "reliable") func initial_sync(...)`)
  - Sent once after spawn to avoid unreliable-packet loss at startup
- [x] **Equipment sync via RPC** (`equip_item`, `sync_equipment`)
  - Authority equips → RPC → all clients update `equipped_styles`
- [x] **`player.tscn` cleanup**
  - Removed corrupted inline `MultiplayerSynchronizerReplicationConfig`
  - Clean scene with Sprite3D stack + VisualController

### 2.2 Player Controller
- [x] **Basic movement** (`scripts/player/player_controller.gd`)
  - WASD driven by `Input.get_vector(...)`
  - Sprint toggle (Shift)
  - Jump (Space) with ground check
  - Gravity application
  - Camera-relative movement (reads yaw from `CameraPivot`)
  - Mesh rotation faces movement direction
  - Toroidal coordinate wrapping (`_wrap_world_coordinates()`)
  - `player_wrapped` signal for remote-player re-unwrapping
  - Added to `"ghostable"` group for ghost entity system
- [x] **Camera controller** (`scripts/player/camera_controller.gd`)
  - `Camera3D` child of a pivot `Node3D`
  - Mouse look with sensitivity, clamped pitch
  - Only processes on authority peer
  - Mouse captured on startup

### 2.3 Directional Sprite Stacking System
- [x] **4-way directional sprites** (`scripts/player/directional_sprite_stack.gd`)
  - `Direction` enum: FORWARD, LEFT, RIGHT, AWAY
  - Calculates relative yaw from camera to character, picks direction
  - Character's own rotation.y factored into relative angle
  - `_apply_visuals()` sets `AtlasTexture.region` + `offset` + `position.y` per part per direction
  - `_update_render_order()` uses `render_priority` for arm layering (LEFT/RIGHT views)
- [x] **Sprite database** (`data/sprite_database.json`)
  - Per-direction `parts` (pixel offsets/sizes), per-direction `world` (sprite_offset, y), per-style `styles` (anchor `[x, y]`)
  - 4 sheets: `human_chest` (Chest, L_Arm, R_Arm), `human_legs` (L_Leg, R_Leg), `human_hands` (L_Hand, R_Hand), `human_faces` (Head)
  - Multiple styles per sheet (naked, shirt1, shirt2, shirt3, etc.)
  - Data architecture: parts + world + styles are separated; adding a new style = 4 numbers
- [x] **SpriteDatabaseLoader autoload** (`scripts/data/sprite_database_loader.gd`)
  - Loads `sprite_database.json` at startup, builds `SheetData` objects
  - Exposes `get_sheet(sheet_id)` for runtime queries
- [x] **Resource classes** (`scripts/data/sheet_data.gd`, `part_def.gd`, `world_def.gd`, `style_def.gd`)
  - `PartDef`: `px_offset: Vector2i`, `px_width: int`, `px_height: int`
  - `WorldDef`: `sprite_offset: Vector2`, `y: float`
  - `SheetData`: `texture: Texture2D`, `parts: Dictionary`, `world: Dictionary`, `styles: Dictionary`
- [x] **Equipment system** (`equip_item()` on `DirectionalSpriteStack`)
  - Style validation against loaded sheet
  - F2 debug key randomizes equipment slots
- [x] **Player scene** (`scenes/entities/player.tscn`)
  - 8 Sprite3D nodes with unique names: Head, Chest, L_Leg, R_Leg, L_Arm, R_Arm, L_Hand, R_Hand
  - `VisualController` node with `DirectionalSpriteStack` script
  - Billboard mode on all sprites

### 2.4 World Generation System
- [x] **4D simplex noise GDExtension** (`addons/simplex_noise_4d/`)
  - C++ implementation: `src/simplex_noise_4d.cpp` / `.hpp` + `register_types.cpp`
  - SCons build system (`SConstruct`)
  - Windows debug/release DLLs built
  - `.gdextension` manifest with auto-detection
  - Web (`.side.wasm`) target planned but not yet built (requires custom export templates)
- [x] **GDScript fallback 4D noise** (`scripts/noise/simplex_noise_4d.gd`)
  - Pure GDScript implementation of 4D simplex noise
  - Same permutation table, gradients, math as C++ version
  - Auto-selected if GDExtension unavailable
- [x] **HeightmapGenerator** (`scripts/world/heightmap_generator.gd`)
  - 4D toroidal coordinate mapping: `(wx, wz) → (R·cos(2πx/L), R·sin(2πx/L), R·cos(2πz/L), R·sin(2πz/L))`
  - Auto-detects GDExtension vs GDScript backend
  - FBM with configurable octaves, frequency, persistence, lacunarity
  - Single-FBM pass (multi-layer noise planned but not yet implemented)
- [x] **World data architecture** (`scripts/world/world_data.gd`, `chunk_data.gd`, `region_data.gd`, `world_meta.gd`)
  - `ChunkData`: `PackedFloat32Array` heightmap (41×41), biome ID, bilinear interpolation
  - `RegionData`: 8×8 chunks per region (64 per file), packed as `.res` binary
  - `WorldData`: loads `world_meta.res`, caches regions, provides chunk access with toroidal wrapping
  - 256 region files for 128×128 chunk world
- [x] **World generator orchestrator** (`scripts/world/world_generator.gd`)
  - Generates all 16,384 chunks upfront
  - Progress reporting via signal
  - Saves region `.res` files + `world_meta.res` + `.json`
- [x] **World gen config** (`data/world_gen_config.json`, `scripts/data/world_config.gd`, `noise_params.gd`)
  - JSON-driven parameters: height_scale, octaves, persistence, lacunarity, water_level, etc.
  - Currently single-FBM config (height_scale=4, octaves=4, persistence=0.5, lacunarity=2.0)
- [x] **Generated world data** (`data/worlds/kaelor_alpha/`)
  - `world_meta.res` + `world_meta.json` — world metadata
  - 256 region `.res` files (first ~7×16=112 generated as of last check)

### 2.5 Terrain Rendering + LOD
- [x] **TerrainMeshBuilder** (`scripts/world/terrain_mesh_builder.gd`)
  - 3-level LOD: spacing = `1 << lod` (LOD0=1, LOD1=2, LOD2=4)
  - LOD distances: `[80, 240, INF]`
  - `SurfaceTool`-based mesh generation with vertex colors (biome coloring)
  - `get_lod_for_distance()` utility
- [x] **TerrainChunk** (`scripts/world/terrain_chunk.gd`)
  - Scene node: `MeshInstance3D` + `StaticBody3D` + `CollisionShape3D`
  - `setup()`: builds mesh, collision, positions chunk
  - `update_lod()`: rebuilds mesh at new LOD level
  - `set_world_position()`: positions chunk with toroidal nearest-copy offset
- [x] **CollisionGenerator** (`scripts/world/collision_generator.gd`)
  - `ConcavePolygonShape3D` from heightmap at LOD0 resolution
  - Built at runtime from data on all platforms (no pre-baked `.mesh`)
- [x] **NavMeshGenerator** (`scripts/world/navmesh_generator.gd`)
  - Runtime-baked `NavigationMesh` from heightmap data on all platforms
  - No platform-specific pre-baking
- [x] **ChunkManager** (`scripts/world/chunk_manager.gd`)
  - `LOAD_RADIUS=3` (~120m visible radius), `UNLOAD_DISTANCE=5`
  - Loads/unloads chunks around player with toroidal wrapping
  - LOD determination per chunk based on distance
  - `_refresh_chunk_positions()` repositions all chunks to nearest copy after wrap
  - `rewrap_remote_players()` re-unwraps remote players when local player wraps
  - `get_terrain_height()` with `fposmod()` for correct negative/wrapped coords

### 2.6 Toroidal Wrapping System
- [x] **TorusUtils** (`scripts/world/torus_utils.gd`)
  - `wrap_near()`: wrap a value to nearest copy relative to a reference
  - `wrap_vector3_near()`: 3D position wrapping with WorldData bounds
  - `toroidal_delta()`: shortest distance on a torus
  - `toroidal_distance_sq()` / `toroidal_distance()`: squared and absolute toroidal distance
  - `is_near_boundary()`: check if entity is within margin of world edge
  - `canonical_position()`: normalize position to `[0, world_size)`
  - `get_wrapped_offsets()`: compute all ghost positions for an entity near a seam
- [x] **Ghost entity system** (`scripts/world/ghost_manager.gd`)
  - `SEAM_MARGIN=160.0` units
  - Tracks `"ghostable"` group entities
  - Spawns/despawns ghost copies for entities near world boundaries
  - Supports corner ghosts (X+Z wrapped simultaneously)
  - `disable_authority_collision()` / `enable_authority_collision()` for projectile ghost mode
  - Auto-starts when `ChunkManager` and `WorldData` become available
- [x] **GhostPlayer** (`scripts/world/ghost_player.gd`)
  - Visual-only ghost (no physics) for minimap seam visibility
  - `sync_from_source()` mirrors source player visual state
- [x] **ProjectileGhost** (`scripts/world/projectile_ghost.gd`)
  - Physics-enabled ghost for projectile collision across seam
  - Collision forwarding to authority projectile
- [x] **Player toroidal wrapping** (in `player_controller.gd`)
  - `_wrap_world_coordinates()`: clamps to `[0, world_size)` each frame
  - `player_wrapped` signal → `WorldManager` → `ChunkManager.rewrap_remote_players()`
  - `sync_transform` uses `TorusUtils.wrap_vector3_near()` for remote position unwrapping
  - `initial_sync` reliable RPC for spawn-time position
  - `get_canonical_position()` + `create_ghost()` for ghost system integration

### 2.7 World Editor Plugin
- [x] **World Generation Editor Tool** (`addons/world_generation/`, `scenes/world/world_editor.tscn`)
  - `WorldGenPlugin` editor plugin for parameter configuration + regenerate
  - `world_editor_ui.gd` for generation UI

### 2.8 UI (Minimal)
- [x] **Main menu** (`scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd`)
  - Host button → starts signaling server + hosts mesh
  - Join button → connects to signaling server + joins mesh
  - Disconnect button
  - Status display (Disconnected / Connected / Connection Failed)
  - Peer count display
  - My ID display
  - Auto-switches to `scenes/world/world.tscn` on successful connection
- [x] **In-world HUD** (`scripts/ui/hud.gd`)
  - FPS counter
  - Peer count / My ID (only when connected)

### 2.9 World Scene
- [x] **World root** (`scenes/world/world.tscn`)
  - Contains `WorldManager` script
  - Contains `ChunkManager` with `TerrainRoot`
  - Contains `Players` node (Node3D) for spawned player instances
  - Contains `GhostManager` node

---

## 3. What Is NOT Done (The Gap)

### 3.1 World Generation — Remaining Work (`03-world-generation.md`)
- [ ] **Multi-layer noise terrain** (Phase 2 Plan T5)
  - Current: single FBM → uniform rolling hills
  - Planned: 5-layer composition (continental + mountain mask + ridged mountains + plains + detail)
  - Power redistribution (`pow(elevation, 2.5)`) for flat valleys + sharp peaks
  - Frequency calibration for 4D torus: continental~2.5, mountain~10, plains~8, detail~200
  - See `plans/plan-map-phase2.md` T5 for full spec
- [ ] **LOD border ring** (Phase 2 Plan T4)
  - Force chunk border vertices to always render at LOD0 density
  - Eliminates T-junction cracks by construction
  - Skirt as safety net for sub-pixel precision issues
  - See `plans/plan-map-phase2.md` T4 for full spec
- [ ] **Extended view distance** (Phase 2 Plan T2)
  - Increase LOD_DISTANCES from `[80, 240, INF]` to `[80, 200, 400, 700, INF]` (5 tiers)
  - Increase LOAD_RADIUS from 3 to 5-6
  - Profile on web; target ~110K tris total
  - See `plans/plan-map-phase2.md` T2 for full spec
- [ ] **Water plane** (Phase 2 Plan T6)
  - `MeshInstance3D` with `PlaneMesh` at Y=water_level
  - Custom `ShaderMaterial` with depth-based terrain masking, Gerstner/sine waves, foam
  - Swimming state in player controller (buoyancy, drag, `MOTION_MODE_FLOATING`)
  - `Area3D` or Y-position check for water detection
  - See `plans/plan-map-phase2.md` T6 + `plans/last_research_save.md` for shader research
- [ ] **MultiMesh foliage** (Phase 2 Plan T3)
  - Per-chunk MultiMeshInstance3D for grass, bushes, trees
  - Data-driven foliage positions from `RegionData`
  - LOD for foliage (full mesh → cluster → billboard → dither fade)
  - Instance budgets: ~1500 grass, ~30 bushes, ~10 trees per chunk (web)
  - See `plans/research-multimesh-foliage.md` + `plans/plan-map-phase2.md` T3
- [ ] Biome system (temperature + moisture noise → Plains, Forest, Mountains, Swamp, Desert, Tundra)
- [ ] Resource node placement (ore, trees, reagent plants, fishing spots)
- [ ] Monster spawn zones with patrol routes
- [ ] Dungeon entrance placement
- [ ] Town / city generation
- [ ] Day / night cycle (visual + gameplay impact)
- [ ] Weather system (rain, snow, fog, overcast)
- [ ] World event trigger zones (monster eruptions, Underloom incursions)
- [ ] World editor: terrain sculpt, node placement, spawn zones, building placement, test-play
- [ ] World data save / load / export / import (JSON) — partial: `.res` binary working, JSON export exists for meta only

### 3.2 Building System (`04-building-system.md`)
- [ ] Building piece library (walls, floors, ceilings, roofs, doors, stairs, props)
- [ ] Interior culling / seamless interior transition
- [ ] Texture atlas for building materials
- [ ] Procedural building placement

### 3.3 Entities & Characters — Remaining Work (`05-entities-characters.md`)
- [ ] Animation states (idle, walk, run, attack, cast, hurt, death, block, dodge) — sprites currently static
- [ ] 8-directional upgrade (currently 4-way)
- [ ] First-person / third-person camera swap (toggle key `V`)
- [ ] Character data structure (stats, skills, inventory, equipment, faction rep, quest progress, spellbook, mount data)
- [ ] Character creation screen (face, hair, skin, hardcore toggle)
- [ ] NPC base (patrol, dialogue, shops, quests, healers, trainers)
- [ ] Enemy AI (aggro, patrol, telegraphed attacks, loot tables)
- [ ] Boss variants
- [ ] Ghost state (death) — incorporeal, no communication, corpse decay
- [ ] Mounts & taming system
- [ ] Entity component system:
  - [ ] `HealthComponent`
  - [ ] `StatsComponent` (STR/INT/DEX)
  - [ ] `SkillComponent`
  - [ ] `EquipmentComponent` (15 layers)
  - [ ] `AggroComponent`
  - [ ] `GhostComponent`
  - [ ] `TamingComponent`
  - [ ] `FactionComponent`
  - [ ] `LootComponent`
  - [ ] `DialogueComponent`

### 3.4 Gameplay Systems (`06-gameplay-systems.md`)
- [ ] **Souls-like combat**
  - [ ] Attack phases (telegraph/wind-up ≥340ms, active hitbox, recovery ≥170ms)
  - [ ] Stamina management (attack, block, roll, sprint)
  - [ ] Dodge/roll with i-frames
  - [ ] Parry system (timed block → counter-attack)
  - [ ] Damage types (physical: slash/pierce/blunt; magical by school)
  - [ ] Critical hits (backstab, riposte)
  - [ ] Status effects (poison, burn, freeze, stun)
- [ ] **Death system (full loot)**
  - [ ] Ghost state on death
  - [ ] Corpse creation with all unblessed items
  - [ ] Corpse decay timer
  - [ ] Resurrection (hub shrine, player healer, NPC healer)
  - [ ] Murder counts + criminal flags (gray/red)
  - [ ] Hardcore mode (permadeath)
- [ ] **Progression**
  - [ ] Classless XP-spend skills (50+ skills, cap 100 each, no overall cap)
  - [ ] Morrowind/Oblivion-style leveling (accumulate skill gains → level up → allocate 3 attributes, bonus +1 to +5)
  - [ ] Character creation (point-buy or template — TBD)
- [ ] **Transmatalogy (Hard Magic)**
  - [ ] Magery skill
  - [ ] Reagent + mana casting cost
  - [ ] Scroll-based spell acquisition
  - [ ] Spellbook (can be lost on death)
  - [ ] Enchanting (via Inscription skill)
  - [ ] Magic regulation enforcement (reputation loss, criminal flags)
- [ ] **Crafting (Full UO)**
  - [ ] Crafting skills: Blacksmithing, Tailoring, Alchemy, Tinkering, Carpentry, Inscription, Cooking
  - [ ] Recipe-based system
  - [ ] Material progression (iron → steel → magical)
  - [ ] Randomized stats on crafted items
  - [ ] Tool durability
  - [ ] Resource gathering (mining, lumberjacking, skinning, harvesting)
- [ ] **Inventory & Equipment**
  - [ ] Weight-based inventory (max carry = f(STR))
  - [ ] Morrowind-style equipment slots (Head, Neck, Torso, L/R Pauldron, L/R Arm, L/R Hand, L/R Leg, Pants, Feet, Weapon, Shield)
  - [ ] Blessed items (persist through death for gold/reagents)
- [ ] **Quests**
  - [ ] Linear main quests (Monster Menace narrative)
  - [ ] Radiant procedural quests
  - [ ] Handcrafted side quests
  - [ ] Guild contracts (repeatable)
  - [ ] World events (eruptions, incursions, faction conflicts)
- [ ] **Factions**
  - [ ] 6 Guilds (Fighters, Mages, Mercantile, Hunters, Crafters, Gatherers) — join multiple
  - [ ] 5 Factions (Nobles, Business, Peasants, Outlaws/Nomads, Druids) — join one
  - [ ] Reputation tracking
  - [ ] Benefits/penalties per standing
- [ ] **Economy**
  - [ ] Gold currency
  - [ ] Player-to-player trading (trade window)
  - [ ] NPC merchants
- [ ] **Mounts & Taming**
  - [ ] Taming skill
  - [ ] Mounts as combat companions
  - [ ] Mount carry weight bonus
  - [ ] Mount feeding/upkeep

### 3.5 UI/UX — Remaining Work (`07-ui-ux.md`)
- [ ] In-game HUD
  - [ ] Health bar
  - [ ] Stamina bar
  - [ ] Mana bar
  - [ ] Minimap (toroidal rendering via ghost system)
  - [ ] Quick slot bar (4-8 slots)
  - [ ] Damage numbers (floating)
  - [ ] Status effect icons
  - [ ] Interaction prompts
  - [ ] Murder/criminal flag indicator
  - [ ] Ghost HUD
  - [ ] Desaturated visual filter
  - [ ] Corpse decay timer
  - [ ] Directional indicator to corpse
  - [ ] Resurrection source indicator
- [ ] Menus
  - [ ] Inventory (weight display, paper doll, drag-and-drop, tooltips, sorting)
  - [ ] Character / Skills (stats, XP spending, skill gains, preview)
  - [ ] Level-up screen (attribute allocation, bonus multipliers)
  - [ ] Magic / Spellbook (known spells, reagent/mana costs, quick-cast)
  - [ ] Map (fog of war, markers, zoom)
  - [ ] Crafting (recipe list, materials, preview, progress)
  - [ ] Quest Log (active/completed, objectives, map markers)
  - [ ] Factions (reputation, benefits, join/leave)
  - [ ] Dialogue box (text box, portrait, choices, typewriter effect)
- [ ] Controls
  - [ ] Complete keyboard + mouse mapping (see GDD `07-ui-ux.md`)
  - [ ] Controller support (lower priority)

### 3.6 Art Direction — Remaining Work (`08-art-direction.md`)
- [ ] Sprite animation frames (walk, attack, cast, etc. per direction)
- [ ] Additional equipment styles beyond placeholder set
- [ ] 15-layer full equipment stack (currently 4 sheets × 8 parts)
- [ ] Sprite resolution experiments (64×64 vs 128×128)
- [ ] Building textures (stone, wood, plaster, metal, thatch, tile)
- [ ] Terrain textures (grass, dirt, sand, snow, stone, water)
- [ ] Color palette per biome
- [ ] Day/night visual treatment
- [ ] Weather particle effects
- [ ] Ghost sprite treatment (desaturated, semi-transparent)
- [ ] Item/prop sprites

### 3.7 Audio (`09-audio.md`)
- [ ] Music system (biome, time of day, dungeon, combat)
- [ ] SFX (combat hits, spells, UI, footsteps, ambient)
- [ ] Ambient audio (biome-specific, weather)
- [ ] Web Audio API compatibility (latency considerations)

### 3.8 Technical Architecture — Remaining Work (`10-technical-architecture.md`)
- [ ] **Multi-layer noise** (see Section 3.1 above — high priority)
- [ ] **LOD seam elimination** (border LOD0 ring — see Section 3.1 above)
- [ ] **Extended view distance** (see Section 3.1 above)
- [ ] **Water rendering + swimming** (see Section 3.1 above)
- [ ] **MultiMesh foliage / entity spawning** (see Section 3.1 above)
- [ ] **Character data system**
  - [ ] `CharacterData` class/structure
  - [ ] `CharacterLoader` (save/load)
  - [ ] `CharacterValidator` (mod compatibility on world entry)
  - [ ] Character select screen (choose existing or create new)
  - [ ] Character/world separation (Valheim-style)
- [ ] **Mod compatibility**
  - [ ] `mod_source` field on all items/skills/spells
  - [ ] Quarantine inventory for foreign items
  - [ ] Hidden-but-preserved foreign skills/spells
- [ ] **Dungeon generator**
  - [ ] Graph-based generation (rooms + corridors)
  - [ ] Room template library
  - [ ] Keys/locks, boss rooms, spawn rooms
  - [ ] <1 second generation target
  - [ ] Instancing per group
- [ ] **Save system**
  - [ ] World saves (terrain state, harvested nodes, placed buildings, NPC states, event timers)
  - [ ] Character saves (stats, skills, inventory, equipment, faction, quest progress, corpse state)
  - [ ] JSON format in `user://`
- [ ] **Chunk/LOD manager enhancements**
  - [ ] Spatial geomorphing for interior vertices (store z_fine + z_coarse in `ARRAY_CUSTOM0`)
  - [ ] Pre-build all LOD meshes at chunk load, swap via reference (avoid runtime rebuild)
- [ ] **World event manager**
  - [ ] Monster eruptions
  - [ ] Underloom incursions
  - [ ] Faction conflicts
  - [ ] Time/action/random triggers
- [ ] **GDExtension web build** (`simplex_noise_4d.side.wasm`)
  - Requires custom export templates with `dlink_enabled=yes`
  - Emscripten 3.x required (v4 has open bug)
  - Currently only Windows DLLs built
- [ ] **Performance targets**
  - [ ] 60 FPS target (40 minimum) — currently unmeasured
  - [ ] Load time <20s to title, <10s to world
  - [ ] Build size <500 MB
  - [ ] Memory <2 GB (WebGL practical limit)
  - [ ] Network latency <150ms for combat
  - [ ] 50+ simultaneous entities (web constraint)

### 3.9 Data Files (JSON-driven architecture)
- [x] `data/world_gen_config.json` — generation parameters
- [x] `data/sprite_database.json` — sprite atlas metadata
- [x] `data/worlds/kaelor_alpha/world_meta.json` — generated world metadata
- [ ] `data/items.json`
- [ ] `data/enemies.json`
- [ ] `data/skills.json`
- [ ] `data/spells.json`
- [ ] `data/recipes.json`
- [ ] `data/loot_tables.json`
- [ ] `data/factions.json`
- [ ] `data/dungeon_graphs.json`
- [ ] `data/world_events.json`
- [ ] `data/mounts.json`
- [ ] `data/quests/linear/`
- [ ] `data/quests/radiant_components/`

---

## 4. Where We Left Off (Most Recent Work)

### Session: 2026-06-17
1. **Fixed `player.tscn` corruption** caused by inline `MultiplayerSynchronizerReplicationConfig` (see `12-multiplayer-sync-fix.md`).
2. **Implemented runtime replication config** in `player_controller.gd` — creates `MultiplayerSynchronizer` + `SceneReplicationConfig` in `_ready()`.
3. **Wrote comprehensive multiplayer documentation** (`docs/how_to_multiplayer.md`).
4. **Verified host/client spawn & sync** — two peers can connect, spawn players, and see each other move.

### Session: 2026-06-19 (Phase 2)
1. **Implemented 4-way directional sprite stacking** — `DirectionalSpriteStack` script with FORWARD/LEFT/RIGHT/AWAY.
2. **Built `sprite_database.json`** with per-direction parts, world offsets, and style anchors for all 4 human body sheets.
3. **Created `SpriteDatabaseLoader` autoload** — loads JSON, builds `SheetData` / `PartDef` / `WorldDef` objects.
4. **Added equipment sync via RPC** — `equip_item` + `sync_equipment` propagate style changes to all clients.
5. **F2 debug key** cycles random equipment styles for testing.

### Session: 2026-06-20 (Phase 3)
1. **Built 4D simplex noise GDExtension** — C++ implementation compiles for Windows (debug + release).
2. **Implemented GDScript fallback** — `SimplexNoise4D` class with identical algorithm.
3. **Created world data architecture** — `ChunkData`, `RegionData`, `WorldData`, `WorldMeta` with region-based `.res` storage.
4. **Implemented heightmap generation** — 4D toroidal mapping, auto-detect GDExtension vs GDScript.
5. **Built terrain rendering pipeline** — `TerrainMeshBuilder` (3 LOD levels), `TerrainChunk`, `CollisionGenerator`, `NavMeshGenerator`.
6. **Created `ChunkManager`** — spatial streaming with LOAD_RADIUS=3, toroidal wrapping, LOD update loop.
7. **Generated world data** — 256 region files for `kaelor_alpha` world (128×128 chunks, 5120×5120 units).
8. **Built world editor plugin** — `WorldGenPlugin` with parameter UI.

### Session: 2026-06-21 (Torus Wrapping Supplemental)
1. **Implemented `TorusUtils`** — static utility for toroidal coordinate math (wrap_near, toroidal_distance, is_near_boundary, canonical_position, get_wrapped_offsets).
2. **Fixed `sync_transform`** — remote player positions now unwrapped via `TorusUtils.wrap_vector3_near()`.
3. **Added reliable `initial_sync` RPC** — prevent lost-unreliable-packet spawn desync.
4. **Fixed `get_terrain_height`** — uses `fposmod()` instead of broken subtraction for negative/wrapped coords.
5. **Implemented `rewrap_remote_players`** — when local player wraps, all remote players re-unwrapped.
6. **Implemented `GhostManager`** — spawns visual-only `GhostPlayer` near world boundaries for minimap seam visibility.
7. **Implemented `ProjectileGhost`** — physics-enabled ghost for future projectile collision across seam.
8. **Player joins `"ghostable"` group** with `get_canonical_position()` + `create_ghost()`.

### Session: 2026-06-22 (Research + Planning)
1. **Compiled comprehensive map research** (`plans/plan-map-phase2.md`) — 6 tasks (T1-T6) with detailed specs:
   - T1: World size & view distance Q&A
   - T2: LOD view distance increase (5 tiers, LOAD_RADIUS 5-6)
   - T3: MultiMesh foliage/town/entity feasibility (web budgets confirmed)
   - T4: Border-LOD0 seam elimination (20-40% vertex overhead, zero crack artifacts)
   - T5: Multi-layer noise (5-layer composition for mountains/plains/valleys)
   - T6: Water plane (depth-based shader, swimming, Gerstner waves)
2. **Documented task dependency graph** — T5→T4→T2→T6→T3; T5 and T4 parallel.
3. **Current blocker / next step:** Multi-layer noise (T5) is the highest-priority implementation target — it affects terrain quality for all downstream work. Border-LOD0 ring (T4) can be done in parallel.

---

## 5. Architectural Considerations

### 5.1 Authority & Replication
- **Host authority** for world state (terrain, NPCs, loot, world events).
- **Peer authority** for their own player character (already implemented in `WorldManager`).
- All new networked entities MUST call `set_multiplayer_authority(peer_id)` immediately after instantiation.
- Use `is_multiplayer_authority()` to gate physics, input, and state-sending logic.
- State sync should use `@rpc("any_peer", "unreliable")` for high-frequency data (transform) and `@rpc("authority", "reliable")` for gameplay-critical commands (damage, item pickup).
- **Toroidal sync rule:** All positions transmitted in canonical `[0, world_size)` space; receivers unwrap to their local frame via `TorusUtils.wrap_vector3_near()`.

### 5.2 Component-Based Design
The GDD explicitly calls for an entity component system. Recommended pattern per entity:

```
Node3D (entity root)
├── BillboardSprite / DirectionalSpriteStack
├── CollisionShape3D
├── HealthComponent
├── StatsComponent
├── EquipmentComponent
├── SkillComponent
├── AnimationController
└── (etc.)
```

- Keep components `Node`-based so they can be added/removed in the editor.
- Use `@export` references for cross-component communication (e.g., `AnimationController` references `EquipmentComponent` to know which sprites to stack).

### 5.3 Data-First Architecture
- All game data (items, enemies, skills, spells, recipes, quests, factions) should live in `res://data/` as JSON.
- Godot scripts should **read** these JSON files at startup and build in-memory dictionaries/static resources.
- This enables modding: a mod is just a JSON patch or additional JSON file with a `mod_source` field.
- Never hard-code item stats, enemy stats, or quest text in GDScript.
- **Sprite data is already data-driven** via `sprite_database.json` → `SpriteDatabaseLoader` → `SheetData`.

### 5.4 World / Character Separation
- `CharacterData` and `WorldData` must be completely independent.
- `CharacterData` is portable: saved to `user://characters/`, loaded before world selection.
- `WorldData` is host-bound: saved to `user://worlds/`, loaded when hosting.
- On join: client sends `CharacterData` to host; host validates it (mod compatibility) and spawns the player.
- On leave/ disconnect: host saves world state; client saves character state.

### 5.5 Web Export Constraints
- **No C#** — GDScript only.
- **Threading:** Use `WorkerThreadPool` (web-compatible). Avoid `Thread`.
- **Audio:** Web Audio API has latency — test early.
- **Networking:** WebSocket + WebRTC only (no raw UDP/TCP).
- **Filesystem:** `user://` for saves. `res://` for pre-baked data (memory-mapped from `.pck`).
- **Memory:** ~2 GB practical limit for WebGL.
- **Renderer:** Compatibility (GLES3).
- **Draw calls:** Target <300 for web (<100 ideal). Use `MultiMesh` for all repeated geometry.
- **No auto-instancing** on Compatibility renderer — must explicitly use `MultiMesh`.
- **Triangles:** 200K-300K/frame conservative for web (720p, simple materials).
- **LOD + HLOD:** Critical for web. Use `Visibility Ranges` for HLOD, mesh LOD for distant geometry.
- **Avoid `Scaling3D < 1.0`** — confirmed bug causing 6x FPS loss on web.
- **Pre-warm shaders** at load time to avoid runtime compilation hitches.

### 5.6 Multiplayer Gotchas
- `rpc_unreliable()` does **not** exist in Godot 4. Use `rpc("method", ...)` with `@rpc("any_peer", "unreliable")`.
- `@rpc` arguments must be **quoted strings** (e.g., `@rpc("any_peer", "unreliable")`). Bare identifiers cause parser errors.
- `MultiplayerSynchronizer` must have a valid `SceneReplicationConfig` or it will spam `_send_sync` warnings.
- Ensure `set_multiplayer_authority()` is called **before** adding the node to the tree if using `MultiplayerSynchronizer`.
- **Toroidal sync:** Always unwrap remote player positions to nearest copy relative to local player. Never use raw canonical positions directly in the scene tree.

### 5.7 Toroidal World Constraints
- All authority positions MUST stay in `[0, world_size)`. Never let positions accumulate.
- Canonical `[0, world_size)` is the only frame for network communication.
- Godot physics uses Euclidean distance — cannot detect collisions across the seam. Use ghost entities with real physics bodies at wrapped positions.
- Only entities near the seam (within `SEAM_MARGIN` = 160 units) need ghosts. Typically 0-3 entities.
- Ghosts are always mirrors of the authority entity. They never have their own state.
- `GhostManager` is the single source of truth for "which entities need ghosts right now."
- Float32 precision at 5120 units is ~0.5 units — adequate. Positions never accumulate beyond `[0, 5120)`.

### 5.8 Unified Build Path (No Platform Split)
- **All platforms build meshes from heightmap at runtime.** No pre-baked `.mesh` or `.navmesh` files.
- Heightmap data is the portable source of truth. Meshes, collision, NavMesh are all derived.
- Web and desktop use identical code paths. Only the noise backend differs at generation time (auto-detected).
- This eliminates platform-specific branches and ensures web parity by design.

---

## 6. Priority Roadmap (Suggested Order)

> This is a suggested sequence, not a mandate. Adjust based on design needs.

### Phase 1: Core World + Player Presence (MVP) — DONE
1. ~~Procedural terrain generation (heightmap + mesh)~~
2. ~~Basic biome coloring (vertex color or simple texture)~~
3. ~~Player spawn point in the world~~
4. ~~Third-person camera swap (first-person can wait)~~
5. ~~Basic player visual (placeholder mesh or sprite)~~

### Phase 2: Terrain Quality + Visual Fidelity — NEXT
1. **Multi-layer noise (T5)** — replace single FBM with 5-layer composition for mountains, valleys, plains
2. **Border-LOD0 ring (T4)** — eliminate seam artifacts at chunk boundaries
3. **Extended view distance (T2)** — 5 LOD tiers, LOAD_RADIUS 5-6
4. **Water plane (T6)** — depth-based shader, swimming, wave displacement
5. **MultiMesh foliage (T3)** — grass, bushes, trees per chunk with LOD

### Phase 3: Combat & Death Loop
1. `HealthComponent` + basic damage
2. Melee attack (no stamina yet — just hitbox + damage)
3. Death → ghost state
4. Corpse creation + item decay timer
5. Resurrection flow (hub shrine)

### Phase 4: Progression & Data
1. `StatsComponent` (STR/INT/DEX) + derived values
2. `SkillComponent` + XP earning/spending
3. Level-up screen + attribute allocation
4. Character data save/load (JSON in `user://`)
5. Character select screen

### Phase 5: Inventory & Equipment
1. Weight-based inventory system
2. Morrowind-style equipment slots
3. 15-layer sprite stacking (or placeholder visual)
4. Item data JSON

### Phase 6: Content Systems
1. Crafting (recipes + stations)
2. Transmatalogy (spells + reagents)
3. NPCs (dialogue + shops)
4. Quests (linear + radiant)
5. Factions (reputation + benefits)

### Phase 7: World Content
1. Dungeon generator + instancing
2. Monster AI + spawning
3. World events (eruptions, incursions)
4. Day/night + weather

### Phase 8: Polish & Scale
1. Art pass (sprites, textures, effects)
2. Audio pass (music, SFX, ambience)
3. Full UI polish (menus, animations, feedback)
4. Performance optimization (LOD, culling, draw calls)
5. Web export testing + optimization

---

## 7. How to Update This File

When you finish a feature, add, or change anything meaningful, update this tracker **in the same commit/PR** so it stays current. A stale tracker is worse than no tracker.

### Adding a Completed Feature
1. Find the relevant section under **3. What Is NOT Done**.
2. Move the checkbox item to **2. What Exists Right Now** (or create a new subsection if it doesn't fit).
3. Add a brief description of what was implemented, including file paths (see existing examples for format).
4. Update the **Last Updated** date at the top of this document.

### Updating "Where We Left Off"
1. Append a new entry to **4. Where We Left Off** with the date and a bullet list of what was done.
2. If there is a new blocker, note it explicitly.
3. Update the **Last Updated** date.

### Adding New Architectural Considerations
1. If you discover a new constraint, gotcha, or best practice during implementation, add it to **5. Architectural Considerations**.
2. Use the same format (heading + bullet list + code example if applicable).

### Reminding Future Agents
At the top of every new task, **point the agent to this file first**. Say:  
> "Read `docs/implementation_tracker.md` for current project state."

This ensures every new context starts from the latest reality, not from the GDD alone.

---

## 8. File Inventory (Current)

### Scenes (`.tscn`)
| File | Purpose | Status |
|------|---------|--------|
| `scenes/main/main.tscn` | Entry point — boots into main menu | Active |
| `scenes/world/world.tscn` | World root — `WorldManager`, `ChunkManager`, `GhostManager`, `Players` | Active |
| `scenes/world/world_editor.tscn` | World generation editor tool | Active |
| `scenes/world/terrain_chunk.tscn` | LOD-capable terrain chunk (MeshInstance3D + StaticBody3D) | Active |
| `scenes/entities/player.tscn` | Player: CharacterBody3D + 8 Sprite3D stack + VisualController | Active |
| `scenes/ui/main_menu.tscn` | Host/Join/Disconnect UI | Active |

### Scripts (`.gd`)
| File | Purpose | Status |
|------|---------|--------|
| `scripts/multiplayer/signaling_server.gd` | WebSocket signaling server | Active |
| `scripts/multiplayer/multiplayer_manager.gd` | WebRTC P2P mesh management | Active |
| `scripts/world/world_manager.gd` | Spawns/despawns players, assigns authority, rewraps on wrap | Active |
| `scripts/world/chunk_manager.gd` | Spatial streaming, LOD, toroidal chunk positioning | Active |
| `scripts/world/terrain_chunk.gd` | LOD-capable terrain chunk node (mesh + collision) | Active |
| `scripts/world/terrain_mesh_builder.gd` | ArrayMesh generation with LOD levels | Active |
| `scripts/world/collision_generator.gd` | ConcavePolygonShape3D from heightmap | Active |
| `scripts/world/navmesh_generator.gd` | Runtime NavigationMesh baking | Active |
| `scripts/world/heightmap_generator.gd` | 4D simplex noise + toroidal mapping + auto-detect backend | Active |
| `scripts/world/world_generator.gd` | Orchestrates full world generation, saves region files | Active |
| `scripts/world/world_data.gd` | WorldData resource — region caching, chunk access | Active |
| `scripts/world/chunk_data.gd` | ChunkData — heightmap, biome, bilinear interpolation | Active |
| `scripts/world/region_data.gd` | RegionData — 8×8 packed chunk data resource | Active |
| `scripts/world/world_meta.gd` | WorldMeta — world metadata resource | Active |
| `scripts/world/torus_utils.gd` | Toroidal coordinate math utilities | Active |
| `scripts/world/ghost_manager.gd` | Ghost entity spawning/despawning near seams | Active |
| `scripts/world/ghost_player.gd` | Visual-only ghost for minimap seam visibility | Active |
| `scripts/world/projectile_ghost.gd` | Physics-enabled ghost for projectile seam collision | Active |
| `scripts/world/world_editor_ui.gd` | World generation editor UI | Active |
| `scripts/player/player_controller.gd` | Movement, jump, gravity, toroidal wrap, sync, ghostable | Active |
| `scripts/player/camera_controller.gd` | Mouse look, pitch clamp | Active |
| `scripts/player/directional_sprite_stack.gd` | 4-way directional sprite + equipment visual system | Active |
| `scripts/data/world_config.gd` | WorldGenConfig — JSON-serializable generation parameters | Active |
| `scripts/data/noise_params.gd` | NoiseParams — noise parameter container | Active |
| `scripts/data/sprite_database_loader.gd` | SpriteDatabaseLoader autoload — JSON → SheetData | Active |
| `scripts/data/sheet_data.gd` | SheetData resource — texture + parts + world + styles | Active |
| `scripts/data/part_def.gd` | PartDef resource — px_offset, px_width, px_height | Active |
| `scripts/data/world_def.gd` | WorldDef resource — sprite_offset, y | Active |
| `scripts/data/style_def.gd` | StyleDef resource — style definition | Active |
| `scripts/noise/simplex_noise_4d.gd` | GDScript fallback 4D simplex noise | Active |
| `scripts/ui/main_menu.gd` | Host/Join/Disconnect UI logic | Active |
| `scripts/ui/hud.gd` | FPS, peer count, my ID | Active |

### GDExtension / Addons
| File | Purpose | Status |
|------|---------|--------|
| `addons/simplex_noise_4d/` | 4D simplex noise C++ GDExtension (Windows DLLs built) | Active |
| `addons/world_generation/` | World generation editor plugin | Active |
| `webrtc/` | WebRTC native library (multi-platform DLLs) | Active |

### Data Files
| File | Purpose | Status |
|------|---------|--------|
| `data/world_gen_config.json` | Generation parameters (seed, octaves, persistence, etc.) | Active |
| `data/sprite_database.json` | Sprite atlas metadata (parts, world, styles per sheet) | Active |
| `data/worlds/kaelor_alpha/world_meta.res` + `.json` | Generated world metadata | Active |
| `data/worlds/kaelor_alpha/regions/*.res` | 256 region files (8×8 chunks each) | Active |

### Sprite Assets
| File | Purpose | Status |
|------|---------|--------|
| `assets/sprites/human/chest.png` | Chest + arm sprite atlas | Placeholder |
| `assets/sprites/human/legs.png` | Leg sprite atlas | Placeholder |
| `assets/sprites/human/hands.png` | Hand sprite atlas | Placeholder |
| `assets/sprites/human/faces.png` | Face/head sprite atlas | Placeholder |

### Documentation
| File | Purpose |
|------|---------|
| `docs/how_to_multiplayer.md` | WebRTC, `@rpc`, authority, common pitfalls |
| `docs/implementation_tracker.md` | This file |
| `docs/gdd/*.md` | Game Design Document (specification) |

### Plans
| File | Purpose | Status |
|------|---------|--------|
| `plans/done/phase-1-movement-and-p2p.md` | Phase 1 plan (completed) | Done |
| `plans/done/phase-2-directional-sprite-stacking.md` | Phase 2 plan (completed) | Done |
| `plans/done/phase-3-world-generation.md` | Phase 3 plan (completed) | Done |
| `plans/done/supplemental-torus-wrapping.md` | Torus wrapping supplemental plan (completed) | Done |
| `plans/plan-map-phase2.md` | Phase 2 map quality tasks (T1-T6, upcoming) | **Active / Next** |
| `plans/research-multimesh-foliage.md` | MultiMesh foliage research | Reference |
| `plans/last_research_save.md` | Web perf research, LOD stitching, water rendering, noise research | Reference |

---

*End of Implementation Tracker*