# Technical Architecture

## Godot Version
- **Engine:** Godot 4.x (latest stable, 4.3+)
- **Renderer:** Compatibility (GLES3) — required for web export
- **Language:** GDScript only (C# not available for web export)
- **Target:** Web export (browser) — primary constraint

## Minimum Specs

| Component | Minimum |
|-----------|---------|
| OS | Windows 10 64-bit |
| RAM | 8 GB |
| CPU | 4 cores, ≥2.0 GHz (modern x86_64) |
| GPU | DX11+ / WebGL 2.0 compatible |
| Display | 1920×1080 |
| Browser | Chrome 56+, Firefox 51+, Safari 15+, Edge 79+ |
| Network | Broadband 20+ Mbit/s (multiplayer) |
| Build size | <500 MB initial |
| Load time | <20 seconds to title |
| Target FPS | 60 (40 minimum) |

## Architecture Principles
- **DRY** — Don't Repeat Yourself
- **Clean Code** — Readable, maintainable, well-structured
- **KISS** — Keep It Simple, Stupid
- **Data-First** — JSON-driven data for items, enemies, skills, quests, recipes, loot tables. Code reads data, not the other way around.

## Core Architecture: Worlds and Characters Are Separate Data

### Design Philosophy
Inspired by Valheim. **Worlds are data. Characters are data. They are independent.**

- A world is a finite, pre-generated map with terrain, cliffs, resource nodes, monster spawns, dungeon entrances, towns, cities, and all static/dynamic world content.
- A character is a portable data set: stats, skills, inventory, equipment, faction standing, quest progress.
- Characters can travel between worlds carrying their equipment and stats.
- A player generates or edits a world, then invites friends. Everyone brings their own character.
- Solo play works the same way: pick a character, pick a world, play.

### World Data
- Worlds are generated **upfront** (not streamed/chunked at runtime for base terrain).
- Since the world is finite, the entire terrain mesh, biome data, node positions, spawn points, building placements, and dungeon entrance locations can be generated once and saved as data.
- At runtime, the game loads world data and renders it. Chunks/LOD still apply for rendering performance, but the *data* is already fully generated.
- World data includes:
  - Heightmap / terrain mesh
  - Biome assignments per region
  - Resource node positions (ore, trees, reagent plants)
  - Monster spawn zones and patrol routes
  - Dungeon entrance locations and linked dungeon instance data
  - Town/city building placements
  - NPC placements and dialogue assignments
  - World event trigger zones
  - Player housing plots (stretch goal)

### Character Data
- Characters are saved as independent data files.
- Character data includes:
  - Stats (STR/INT/DEX)
  - Skills and XP
  - Inventory and equipment (item IDs + randomized stats)
  - Faction reputation
  - Quest progress (completed, active, failed)
  - Spellbook (known spells)
  - Mount/tamed creature data
  - Death state (ghost/corpse location if dead)
- Characters persist across worlds. Join a friend's world with your character, leave, join another.

### World Editor / Map Editor
- Players/hosts can generate worlds procedurally (seed-based) or edit them manually.
- Editor features:
  - Terrain sculpting (raise/lower terrain, paint biomes)
  - Place/remove resource nodes
  - Place/remove monster spawn zones
  - Place buildings, NPCs, dungeon entrances
  - Define town/city boundaries
  - Set world event trigger zones
  - Test-play within the editor
- Editor data is saved as the world's JSON/data files.
- Generated worlds can be shared (export/import world data files).

### Modding and Cross-World Compatibility
- Mods add new data: items, enemies, spells, recipes, dungeon graphs, sprite sheets, etc.
- **Modded character on non-modded world:**
  - Modded items the character carries are stripped or replaced with defaults when entering a non-modded world.
  - Modded skills/spells are hidden but not lost — they reappear when returning to a modded world.
  - Core stats (STR/INT/DEX) and vanilla content work everywhere.
- **Non-modded character on modded world:**
  - Character works normally. Can interact with modded content if the world host has the mod.
  - Modded items can be picked up and used.
- **Implementation:** Every item/skill/spell has a `mod_source` field. If the current world doesn't have that mod loaded, the item is flagged as foreign. Foreign items are moved to a "quarantine" inventory section — visible but unusable until returning to a compatible world.

## Web Export Constraints
- No C# support
- Threading: `WorkerThreadPool` (web-compatible)
- Audio: Web Audio API (latency considerations)
- Networking: WebSocket and WebRTC only (no raw UDP/TCP)
- File system: `user://` for saves
- Memory: ~2 GB practical limit for WebGL builds
- Test early and often on web target

## Multiplayer Architecture

### Approach: True P2P via WebRTC Mesh
- **Godot class:** `WebRTCMultiplayerPeer`
- **Topology:** Full mesh — each peer connects to every other peer
- **Host:** One peer acts as host (server ID 1), others connect as clients
- **Target player count:** 8 (practical limit for full mesh)
- **Character portability:** Characters stored separately from world state. Play solo → join friend's session with same character.

### World Hosting
- The host's machine runs the world simulation.
- World data is loaded from the host's save file.
- If the host disconnects, the session ends (players can migrate to a new host by saving world state and reconnecting — TBD).
- World edits made during play (buildings placed, nodes harvested, etc.) are saved to the host's world data.

### Signaling Server
- Lightweight WebSocket server for initial peer discovery
- Exchanges: ICE candidates, session descriptions (SDP offers/answers)
- Does NOT relay game data — only connection metadata
- Bandwidth negligible (~KB per connection setup)
- Can host on any VPS (~$5/month) or use existing open-source solutions:
  - Godot's reference: `godot-demo-projects/networking/webrtc_signaling`
  - SakulFlee/Godot-WebRTC-Match-Maker
- Self-hosted recommended for control and cost

### NAT Traversal (ICE Framework)
- **STUN** (free): Google's public STUN servers (`stun:stun.l.google.com:19302`). Works for ~75-80% of connections.
- **TURN** (expensive fallback): Relays traffic for ~20-25% of connections (corporate firewalls, symmetric NAT, mobile carriers, CGNAT).
- **Recommendation:** Start with STUN only. Add TURN later if connection failure reports come in.
- **ICE process:** Host candidates → STUN server-reflexive → TURN relay (last resort). Godot handles this automatically via `WebRTCMultiplayerPeer`.

### Replication
- `SceneMultiplayer` + `MultiplayerSynchronizer` for state replication
- `MultiplayerSpawner` for networked entity instantiation
- Host authoritative for world state (terrain, NPCs, loot, world events)
- Each peer authoritative for their own player character
- Server relay enabled for peer-to-peer messaging

### Disconnected Players
- Character despawns immediately
- Character data saved — available next login
- If disconnected during combat → character dies (becomes ghost/corpse)
- World state is preserved on the host

### Anti-Cheat
- None beyond murder counts. Full player freedom.
- Host validates critical actions (loot distribution, quest completion)

## Project Structure

```
res://
├── scenes/
│   ├── world/
│   │   ├── world_root.tscn          (world scene — loads world data)
│   │   ├── terrain_chunk.tscn       (rendering unit, not data unit)
│   │   ├── dungeon_instance.tscn
│   │   ├── weather_controller.tscn
│   │   └── world_event_controller.tscn
│   ├── editor/
│   │   ├── world_editor.tscn        (map editor scene)
│   │   └── editor_ui.tscn
│   ├── buildings/
│   │   ├── pieces/ (wall, floor, roof, door, stairs)
│   │   └── building_interior.tscn
│   ├── entities/
│   │   ├── player.tscn
│   │   ├── enemy_base.tscn
│   │   ├── npc_base.tscn
│   │   ├── ghost.tscn
│   │   ├── mount.tscn
│   │   └── billboard_sprite.gd
│   ├── ui/
│   │   ├── hud.tscn
│   │   ├── inventory_menu.tscn
│   │   ├── character_menu.tscn
│   │   ├── level_up_screen.tscn
│   │   ├── spellbook_menu.tscn
│   │   ├── crafting_menu.tscn
│   │   ├── quest_log.tscn
│   │   ├── faction_menu.tscn
│   │   ├── dialogue_box.tscn
│   │   ├── map.tscn
│   │   ├── trading_window.tscn
│   │   ├── character_select.tscn
│   │   ├── world_select.tscn
│   │   └── pause_menu.tscn
│   └── main.tscn
├── scripts/
│   ├── world/
│   │   ├── world_gen.gd              (procedural generation)
│   │   ├── world_data.gd             (world data structure)
│   │   ├── world_loader.gd           (loads world data at runtime)
│   │   ├── world_editor.gd           (map editor logic)
│   │   ├── chunk_manager.gd          (rendering chunks, not data chunks)
│   │   ├── biome_controller.gd
│   │   ├── interior_culling.gd
│   │   ├── dungeon_generator.gd
│   │   ├── day_night_cycle.gd
│   │   ├── weather_controller.gd
│   │   └── world_event_controller.gd
│   ├── character/
│   │   ├── character_data.gd         (character data structure)
│   │   ├── character_loader.gd       (loads character data)
│   │   ├── character_validator.gd    (validates character for world compatibility)
│   │   └── mod_compatibility.gd      (handles modded items on non-modded worlds)
│   ├── entities/
│   │   ├── entity_base.gd
│   │   ├── player_controller.gd
│   │   ├── camera_controller.gd
│   │   ├── enemy_ai.gd
│   │   ├── health_component.gd
│   │   ├── stats_component.gd
│   │   ├── skill_component.gd
│   │   ├── equipment_component.gd
│   │   ├── animation_controller.gd
│   │   ├── sprite_stacking.gd
│   │   ├── billboard.gd
│   │   ├── ghost_controller.gd
│   │   └── taming_component.gd
│   ├── combat/
│   │   ├── damage_system.gd
│   │   ├── hitbox_manager.gd
│   │   ├── attack_phase.gd
│   │   └── death_system.gd
│   ├── systems/
│   │   ├── inventory.gd
│   │   ├── equipment.gd
│   │   ├── crafting.gd
│   │   ├── quest_manager.gd
│   │   ├── quest_generator.gd
│   │   ├── faction_manager.gd
│   │   ├── murder_system.gd
│   │   ├── save_system.gd
│   │   ├── audio_manager.gd
│   │   ├── multiplayer_manager.gd
│   │   ├── magic_system.gd
│   │   ├── economy_manager.gd
│   │   └── world_event_manager.gd
│   └── ui/
│       └── ui_manager.gd
├── assets/
│   ├── sprites/
│   │   ├── characters/
│   │   │   ├── base/
│   │   │   ├── equipment/ (15 layers × N items)
│   │   │   ├── faces/
│   │   │   └── hair/
│   │   ├── enemies/
│   │   ├── mounts/
│   │   ├── items/
│   │   └── effects/
│   ├── textures/
│   │   ├── terrain/
│   │   ├── buildings/
│   │   └── ui/
│   ├── audio/
│   │   ├── music/
│   │   └── sfx/
│   └── fonts/
└── data/
    ├── items.json
    ├── enemies.json
    ├── skills.json
    ├── spells.json
    ├── recipes.json
    ├── quests/
    │   ├── linear/
    │   └── radiant_components/
    ├── loot_tables.json
    ├── factions.json
    ├── dungeon_graphs.json
    ├── world_events.json
    └── mounts.json
```

## Key Systems

### World Generator
- Seed-based procedural generation of the entire finite world upfront.
- Generates: heightmap, biomes, resource nodes, spawn zones, dungeon entrances, building placements, NPC positions.
- Output: world data file (JSON or Godot resource).
- Can be re-generated or edited via the world editor.

### World Loader
- At runtime, loads world data file and constructs the scene.
- Creates terrain mesh, places entities, initializes spawn zones.
- Chunks are a **rendering** concept (LOD, culling), not a data concept — all world data is loaded upfront.

### World Editor
- In-game editor for creating and modifying worlds.
- Tools: terrain sculpt, biome paint, node placement, building placement, spawn zone definition, NPC placement, dungeon entrance linking.
- Save/load world data files.
- Export/import for sharing worlds.

### Character Data System
- Characters saved as independent data files.
- Portable between worlds.
- Validation on world entry: checks mod compatibility, strips foreign items to quarantine.
- Character select screen: choose existing or create new.

### Mod Compatibility System
- Every game data item has a `mod_source` field ("vanilla" or mod identifier).
- On world entry, `character_validator.gd` checks each item/skill/spell against the world's loaded mods.
- Foreign items → moved to quarantine inventory (visible but unusable).
- Foreign skills/spells → hidden but preserved.
- On return to a compatible world, everything is restored.

### Dungeon Generator
- Graph-based procedural generation.
- Room templates + connectivity graphs.
- Keys/locks, boss rooms, spawn rooms.
- <1 second generation target.
- Instanced per group/player.

### Multiplayer Manager
- `WebRTCMultiplayerPeer` P2P mesh.
- Signaling server connection (self-hosted WebSocket).
- STUN for NAT traversal.
- Character data synchronization.
- World state authority (host).
- Disconnection handling (despawn + save).

### Sprite Stacking System
- 15-layer compositing for character appearance.
- Each equipment slot = one sprite layer.
- All layers animated in sync.
- **Web performance concern:** optimize via texture atlasing.

### Combat System
- Frame-data driven hitboxes.
- Stamina management.
- Dodge/roll i-frames, parry timing.
- Damage calculation via stats + equipment.

### Death System
- Ghost state (incorporeal, no communication).
- Corpse with item persistence + decay timer.
- Resurrection flow (hub, player healer, NPC healer).
- Murder/criminal flag tracking.

### Skill & Progression System
- XP earning from all activities.
- XP spending on skills (player-initiated).
- Level-up on accumulated skill gains.
- Attribute allocation (+1 to +5, no major/minor trap).

### Transmatalogy (Magic) System
- Reagent + mana cost.
- Spellbook (can be lost on death).
- Scroll-based spell acquisition.
- Trainer-based skill advancement.
- Enchanting via Inscription skill.
- Regulation enforcement (reputation, criminal flags).

### Crafting System
- JSON-driven recipes.
- Material-based quality tiers.
- Randomized stats modified by crafter skill.
- Tool durability.
- Multiple crafting skills.

### Quest System
- Linear quests (handcrafted, JSON-driven).
- Radiant quests (procedural from narrative components).
- Guild contracts (repeatable).
- World events (monster eruptions, Underloom incursions).

### Faction System
- 6 guilds (join multiple).
- 5 factions (join one + outlaws).
- Reputation tracking.
- Benefits/penalties per standing.

### Economy System
- Gold currency.
- Player-to-player trading (trade window).
- NPC merchant buy/sell.
- Loot recirculation via full-loot death.

### Mount System
- Taming skill determines tameable creatures.
- Mounts = combat companions (no separate pet system).
- Mounts can be killed and looted.
- Carry weight bonus while mounted.

### Day/Night Cycle
- Visual: sun/moon, sky color, lighting.
- Gameplay: TBD (enemy spawns, NPC availability, magic effectiveness).

### Weather System
- Atmospheric: rain, snow, fog, clear, overcast.
- Per-biome patterns.
- Particle effects + audio.

### World Event System
- Monster surface eruptions.
- Underloom incursion events.
- Faction conflict events.
- Triggered by time, player actions, or random.

### Save System
- **World saves:** terrain state, harvested nodes, placed buildings, NPC states, world event timers. Stored on host.
- **Character saves:** stats, skills, inventory, equipment, faction standing, quest progress, corpse state. Stored per-player.
- JSON format in `user://`.
- Character data separate from world data (portability).

### Modding Support
- Data-first architecture.
- JSON configs for all game data.
- Community modders can add: items, enemies, quests, dungeons, recipes, sprites.
- Mod manifest file lists all added content with `mod_source` identifiers.
- Clean code architecture for extensibility.

## Performance Targets

- **FPS:** 60 target, 40 minimum
- **Load time:** <20 seconds to title, <10 seconds to world
- **Build size:** <500 MB initial
- **Memory:** <2 GB (WebGL practical limit)
- **Network:** <150ms latency for combat
- **Entities:** 50+ simultaneous (web constraint)
- **Dungeon gen:** <1 second per instance
- **World gen:** <30 seconds for full world upfront

## Dependencies
- `FastNoiseLite` (GDScript port)
- Godot built-in `WebRTCMultiplayerPeer`
- Self-hosted WebSocket signaling server
- Google public STUN servers (free)
- No external multiplayer libraries

## Open Questions
- Sprite stacking implementation (multiple Sprite3D vs. shader compositing)?
- TURN server needed at launch or add later?
- Dungeon instance persistence rules?
- Level-up: automatic or player-initiated?
- Monster menace world event design?
- Host migration: can world state transfer if host disconnects?
- World editor: full in-game editor or external tool?
- World file size: how large is a fully generated world's data?

---

*See also:* `02-game-overview.md` | `03-world-generation.md`
