# World & Terrain Generation

## Goals

- Generate the entire finite world **upfront** as data (not streamed at runtime)
- Support biome variety with smooth blending
- Deterministic generation via seed system
- Toroidal wrapping at edges (east↔west, north↔south)
- Full verticality: cliffs, elevation changes, multi-level terrain
- Include all world content in generation: resource nodes, monster spawns, dungeon entrances, towns, cities
- Support in-game world editor for manual editing and creation from scratch
- Export/import world data files for sharing
- Day/night cycle (gameplay impact) + weather (atmosphere)
- Instanced procedural dungeons (graph-based generation)
- World events (monster eruptions, Underloom incursions)

## Core Concepts

### Upfront Generation
- The entire world is generated **before runtime** as a data file.
- Since Kaelor is finite (~5120 × 4096 units), all terrain, biomes, nodes, spawns, buildings, and entrance locations fit in a single shareable data file.
- At runtime, the world loader reads the data file and constructs the scene. Rendering uses chunks/LOD for performance, but the *data* is already fully generated.
- World generation target: <30 seconds for full world.
- Generated worlds can be saved, loaded, shared, and edited.

### World Data Contents
A world data file contains:
- Heightmap / terrain mesh
- Biome assignments per region
- Resource node positions (ore veins, trees, reagent plants, fishing spots)
- Monster spawn zones with patrol routes and difficulty tiers
- Dungeon entrance locations (linked to dungeon instance data)
- Town/city building placements and boundaries
- NPC placements with dialogue/quest/faction assignments
- World event trigger zones (eruption points, incursion sites)
- Player housing plots (stretch goal)
- World metadata: name, seed, creation date, edit history

### World Size & Wrapping
- Target: ~5120 × 4096 world units
- **Toroidal wrapping:** East↔west, north↔south (UO Britannia style). Seamless.
- Fully explorable continuous world

### Mesh Generation
- Heightmap-based terrain (MeshInstance3D with ArrayMesh)
- Vertex coloring or tiled textures per biome
- LOD for distant rendering chunks
- Cliff faces as steep heightmap gradients

### Biomes
- Multiple biomes with smooth blending
- Biome determination via multi-octave noise (temperature + moisture)
- Minimum set: Plains, Forest, Mountains, Swamp, Desert, Tundra

### Seed System
- Single seed drives all generation
- Reproducible worlds from seed
- Worlds can be shared by seed value or by data file

### Terrain Features
- Water planes at configurable sea level
- Cliff faces via steep heightmap gradients
- No digging/terraforming in gameplay
- No underwater areas, no floating islands
- Rivers via noise-based placement

### Verticality
- Full 3D vertical axis matters
- Cliffs, plateaus, valleys, elevation-based gameplay

### Rendering Chunks
- Chunks are a **rendering** concept only (frustum culling, LOD), not a data loading concept.
- All world data loads at scene start; chunks determine what's rendered.

### Day/Night Cycle
- Visual: sun/moon, sky color, lighting shifts
- Gameplay impact: TBD (enemy spawns, NPC availability, magic effectiveness)

### Weather System
- Atmospheric only
- Rain, snow, fog, clear, overcast
- Per-biome weather patterns

## The Underloom (Underground Monster Source)

### Lore
Beneath the kingdoms of Kaelor lies the Underloom — an immeasurable subterranean realm from which the endless monster menace emerges. Most people know only the upper reaches: the twisting caverns, abandoned mines, and ancient passages collectively called the Veins.

### Surface Manifestations
- **Monster eruption points:** Fixed locations where creatures surface through the Veins
- **Dungeon portals:** Openings to the Underloom for instanced content
- **World events:** Large-scale incursions
- **Enchantment decay:** World enchantments degrade, requiring resource investment

## World Editor

### Goals
- Let players/hosts create worlds from scratch or edit procedurally generated worlds
- Support the modding community creating custom content

### Editor Features
- **Terrain sculpting:** Raise/lower terrain, paint biomes, carve rivers
- **Node placement:** Resource nodes (ore, trees, reagents)
- **Spawn zones:** Monster types, density, patrol routes, difficulty
- **Building placement:** Pre-built structures, NPC assignments
- **Dungeon entrances:** Link to dungeon instance templates
- **Town/city boundaries:** Define shop NPCs, quest givers, housing plots
- **World event zones:** Eruption points, incursion sites
- **Test play:** Jump into the world directly from the editor
- **Undo/redo:** Full edit history

### Data Export/Import
- Save/load world data files (JSON)
- Share worlds by distributing data files
- Import community-made worlds

## Dungeons (Instanced, Procedural)

### Approach: Graph-Based Generation
- Input: connectivity graph (nodes = rooms, edges = connections) + room template library
- Output: non-overlapping room placement with doors/corridors
- Supports: keys/locks, boss rooms, spawn rooms, treasure rooms
- Algorithm: simulated annealing with chain decomposition
- Generation target: <1 second per dungeon instance

### Dungeon Components
- **Room templates:** Predefined room shapes with door position constraints
- **Connectivity graph:** Room connections (designer-authored or procedural)
- **Corridor rooms:** Narrow templates between connected rooms
- **Special rooms:** Spawn, boss, treasure — unique templates

### Instancing
- Each dungeon entrance links to a dungeon instance
- Instances generated on first entry, then persisted
- Persistence: TBD (reset on all-leave or timer?)

### Thematic
- All dungeons are Underloom-connected — underground, alien, demonic
- Deeper into the Veins/Underloom = harder = better rewards
- Boss rooms contain powerful Underloom creatures

## World Events

### Monster Eruptions
- Periodic surface spawn events at eruption points
- Scale with time since last eruption
- Players respond for rewards (XP, loot, faction reputation)
- If ignored, monsters spread (TBD)

### Underloom Incursions
- Large-scale world events
- Multiple eruption points activate simultaneously
- Faction-wide response encouraged
- Unique rewards and loot tables

### Faction Conflicts
- Territory disputes between factions
- Players participate for reputation gains
- Emergent PvP dynamics

## Open Questions
- Integer or float height precision?
- Max terrain height?
- Day/night gameplay effects?
- Dungeon instance persistence rules?
- How many dungeon graph templates at launch?
- World event frequency and scaling?
- World file size estimates?
- Editor: full in-game editor or external tool?

## Technical Notes
- Godot 4.x `SurfaceTool` / `ArrayMesh` for mesh construction
- `FastNoiseLite` / `NoiseTexture` for heightmap generation
- `MultiMesh3D` for repeated details (grass, rocks, trees)
- Dungeon generation: GDScript graph-based algorithm
- World data serialized as JSON for portability and modding

---

*See also:* `02-game-overview.md` | `04-building-system.md` | `10-technical-architecture.md`
