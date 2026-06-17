# Implementation Tracker — Veins of Kaelor

> **Purpose:** Living document that tracks what has been built vs. what the GDD specifies. It is meant to be read by a model (or human) with **zero prior context** so they can immediately understand the project's current state, what remains, and how to update this tracker.
> 
> **Last Updated:** 2026-06-17

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
| `03-world-generation.md` | Procedural terrain, biomes, dungeons, day/night, weather | **Not Started** |
| `04-building-system.md` | Buildings, interiors, culling | **Backburnered** |
| `05-entities-characters.md` | Billboard sprites, 15-layer stacking, camera, AI, mounts | **Not Started** (scaffolding only) |
| `06-gameplay-systems.md` | Combat, Transmatalogy, crafting, quests, factions, economy, death | **Not Started** |
| `07-ui-ux.md` | HUD, menus, controls, ghost state UI | **Partial** (main menu + basic HUD only) |
| `08-art-direction.md` | Visual style, sprite stacking, textures | **Not Started** |
| `09-audio.md` | Music, SFX, ambient | **Not Started** |
| `10-technical-architecture.md` | Godot structure, WebRTC, web export, key systems | **Partial** (multiplayer scaffold done) |
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
- [x] **`player.tscn` cleanup**
  - Removed corrupted inline `MultiplayerSynchronizerReplicationConfig` that was breaking TSCN parsing
  - Clean scene with essential nodes only

### 2.2 Player Controller
- [x] **Basic movement** (`scripts/player/player_controller.gd`)
  - WASD driven by `Input.get_vector(...)`
  - Sprint toggle (Shift)
  - Jump (Space) with ground check
  - Gravity application
  - Camera-relative movement (reads yaw from `CameraPivot`)
  - Mesh rotation faces movement direction
- [x] **Camera controller** (`scripts/player/camera_controller.gd`)
  - `Camera3D` child of a pivot `Node3D`
  - Mouse look with sensitivity, clamped pitch
  - Only processes on authority peer
  - Mouse captured on startup

### 2.3 UI (Minimal)
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

### 2.4 World Scene
- [x] **World root** (`scenes/world/world.tscn`)
  - Contains `WorldManager` script
  - Contains a `Players` node (Node3D) for spawned player instances
  - Stub environment (no terrain yet)

---

## 3. What Is NOT Done (The Gap)

### 3.1 World Generation (`03-world-generation.md`)
- [ ] Procedural terrain (heightmap via `FastNoiseLite` / `ArrayMesh`)
- [ ] Biome system (temperature + moisture noise → Plains, Forest, Mountains, Swamp, Desert, Tundra)
- [ ] Toroidal world wrapping (east↔west, north↔south)
- [ ] Resource node placement (ore, trees, reagent plants, fishing spots)
- [ ] Monster spawn zones with patrol routes
- [ ] Dungeon entrance placement
- [ ] Town / city generation
- [ ] Day / night cycle (visual + gameplay impact)
- [ ] Weather system (rain, snow, fog, overcast)
- [ ] World event trigger zones (monster eruptions, Underloom incursions)
- [ ] World editor (terrain sculpt, node placement, spawn zones, building placement, test-play)
- [ ] World data save / load / export / import (JSON)
- [ ] Chunk/LOD rendering (rendering only — data is upfront)

### 3.2 Building System (`04-building-system.md`)
- [ ] Building piece library (walls, floors, ceilings, roofs, doors, stairs, props)
- [ ] Interior culling / seamless interior transition
- [ ] Texture atlas for building materials
- [ ] Procedural building placement

### 3.3 Entities & Characters (`05-entities-characters.md`)
- [ ] Billboard sprite system (`Sprite3D` or custom `BillboardMesh`)
- [ ] 15-layer sprite stacking for equipment visualization
- [ ] 8-directional RPG Maker-style sprite sheets
- [ ] Animation states (idle, walk, run, attack, cast, hurt, death, block, dodge)
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
  - [ ] 6 Guilds (Fighters, Mages, Mercantile, Hunters, Crafters Mercantile, Hunters, Crafters, Gatherers) — join multiple
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

### 3.5 UI/UX (`07-ui-ux.md`)
- [ ] In-game HUD
  - [ ] Health bar
  - [ ] Stamina bar
  - [ ] Mana bar
  - [ ] Minimap
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

### 3.6 Art Direction (`08-art-direction.md`)
- [ ] Sprite sheets (characters, enemies, mounts)
- [ ] 15-layer equipment sprites (per item × 8 directions × animation frames)
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
- [ ] **World data system**
  - [ ] `WorldData` class/structure
  - [ ] `WorldLoader` (reads data, constructs scene)
  - [ ] `WorldGenerator` (seed-based procedural generation)
  - [ ] `WorldEditor` (in-game terrain sculpt, node placement, spawn zones, building placement)
  - [ ] JSON serialization for world data (save/load/export/import)
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
- [ ] **Chunk/LOD manager**
  - [ ] Rendering chunks (frustum culling, LOD)
  - [ ] Not data chunks — all world data loads upfront
- [ ] **World event manager**
  - [ ] Monster eruptions
  - [ ] Underloom incursions
  - [ ] Faction conflicts
  - [ ] Time/action/random triggers
- [ ] **Performance targets**
  - [ ] 60 FPS target (40 minimum) — currently unmeasured
  - [ ] Load time <20s to title, <10s to world
  - [ ] Build size <500 MB
  - [ ] Memory <2 GB (WebGL practical limit)
  - [ ] Network latency <150ms for combat
  - [ ] 50+ simultaneous entities (web constraint)

### 3.9 Data Files (JSON-driven architecture)
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
3. **Wrote comprehensive multiplayer documentation** (`docs/how_to_multiplayer.md`) covering WebRTC, `@rpc` syntax, authority, and common pitfalls.
4. **Verified host/client spawn & sync** — two peers can connect, spawn players, and see each other move.
5. **Current blocker / next natural step:** None technical — the core multiplayer scaffold is solid. The next logical work is **gameplay systems** (combat, health, death) or **world generation** (terrain, biomes).

---

## 5. Architectural Considerations

### 5.1 Authority & Replication
- **Host authority** for world state (terrain, NPCs, loot, world events).
- **Peer authority** for their own player character (already implemented in `WorldManager`).
- All new networked entities MUST call `set_multiplayer_authority(peer_id)` immediately after instantiation.
- Use `is_multiplayer_authority()` to gate physics, input, and state-sending logic.
- State sync should use `@rpc("any_peer", "unreliable")` for high-frequency data (transform) and `@rpc("authority", "reliable")` for gameplay-critical commands (damage, item pickup).

### 5.2 Component-Based Design
The GDD explicitly calls for an entity component system. Recommended pattern per entity:

```
Node3D (entity root)
├── BillboardSprite (or Sprite3D)
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
- **Filesystem:** `user://` for saves.
- **Memory:** ~2 GB practical limit for WebGL.
- **Renderer:** Compatibility (GLES3).

### 5.6 Multiplayer Gotchas
- `rpc_unreliable()` does **not** exist in Godot 4. Use `rpc("method", ...)` with `@rpc("any_peer", "unreliable")`.
- `@rpc` arguments must be **quoted strings** (e.g., `@rpc("any_peer", "unreliable")`). Bare identifiers cause parser errors.
- `MultiplayerSynchronizer` must have a valid `SceneReplicationConfig` or it will spam `_send_sync` warnings.
- Ensure `set_multiplayer_authority()` is called **before** adding the node to the tree if using `MultiplayerSynchronizer`.

---

## 6. Priority Roadmap (Suggested Order)

> This is a suggested sequence, not a mandate. Adjust based on design needs.

### Phase 1: Core World + Player Presence (MVP)
1. Procedural terrain generation (heightmap + mesh)
2. Basic biome coloring (vertex color or simple texture)
3. Player spawn point in the world
4. Third-person camera swap (first-person can wait)
5. Basic player visual (placeholder mesh or sprite)

### Phase 2: Combat & Death Loop
1. `HealthComponent` + basic damage
2. Melee attack (no stamina yet — just hitbox + damage)
3. Death → ghost state
4. Corpse creation + item decay timer
5. Resurrection flow (hub shrine)

### Phase 3: Progression & Data
1. `StatsComponent` (STR/INT/DEX) + derived values
2. `SkillComponent` + XP earning/spending
3. Level-up screen + attribute allocation
4. Character data save/load (JSON in `user://`)
5. Character select screen

### Phase 4: Inventory & Equipment
1. Weight-based inventory system
2. Morrowind-style equipment slots
3. 15-layer sprite stacking (or placeholder visual)
4. Item data JSON

### Phase 5: Content Systems
1. Crafting (recipes + stations)
2. Transmatalogy (spells + reagents)
3. NPCs (dialogue + shops)
4. Quests (linear + radiant)
5. Factions (reputation + benefits)

### Phase 6: World Content
1. Dungeon generator + instancing
2. Monster AI + spawning
3. World events (eruptions, incursions)
4. Day/night + weather

### Phase 7: Polish & Scale
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
| `scenes/world/world.tscn` | World root, holds `WorldManager` | Active |
| `scenes/entities/player.tscn` | Player character body + mesh + camera pivot | Active |
| `scenes/ui/main_menu.tscn` | Host/Join menu | Active |
| `scenes/main/main.tscn` | Main autoload / entry point (implied) | Active |

### Scripts (`.gd`)
| File | Purpose | Status |
|------|---------|--------|
| `scripts/multiplayer/signaling_server.gd` | WebSocket signaling server | Active |
| `scripts/multiplayer/multiplayer_manager.gd` | WebRTC P2P mesh management | Active |
| `scripts/world/world_manager.gd` | Spawns/despawns players, assigns authority | Active |
| `scripts/player/player_controller.gd` | Movement, jump, gravity, sync | Active |
| `scripts/player/camera_controller.gd` | Mouse look, pitch clamp | Active |
| `scripts/ui/main_menu.gd` | Host/Join/Disconnect UI logic | Active |
| `scripts/ui/hud.gd` | FPS, peer count, my ID | Active |

### Documentation
| File | Purpose |
|------|---------|
| `docs/how_to_multiplayer.md` | WebRTC, `@rpc`, authority, common pitfalls |
| `docs/implementation_tracker.md` | This file |
| `docs/gdd/*.md` | Game Design Document (specification) |

---

*End of Implementation Tracker*
