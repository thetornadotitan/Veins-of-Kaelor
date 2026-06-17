# Appendix

## Glossary

| Term | Definition |
|------|-----------|
| **Billboard** | A 2D sprite that always faces the camera in 3D space |
| **Chunk** | A fixed-size section of the world generated as a unit |
| **Heightmap** | A 2D array of height values used to generate terrain mesh |
| **LOD** | Level of Detail — reduced geometry for distant objects |
| **Tileable** | A texture that repeats seamlessly when tiled across a surface |
| **Souls-like** | Combat genre: high attack, low defense, stamina management, telegraphed attacks, punishing but fair |
| **RPG Maker** | Game engine known for 2D top-down RPGs with sprite-based characters |
| **Sprite Stacking** | Layering 15 2D sprites to composite a final character appearance |
| **Transmatalogy** | The hard magic system: study of materials and their exchange with will for effects. Magic as science. |
| **Reagent** | Physical material consumed when casting — the "expenditure of nature" |
| **Mana** | Personal will/energy consumed when casting — the "expenditure of will" |
| **The Underloom** | The immeasurable subterranean realm beneath Kaelor from which the monster menace emerges (scholarly/religious term) |
| **The Veins** | The accessible network of tunnels, caverns, mines, and passages that are the outermost reaches of the Underloom (common term) |
| **Kaelor** | The world. Adjective: Kaeloric. People: Kaeloran. |
| **Monster Menace** | The central existential threat: endless tide of monsters from the Underloom |
| **Full Loot** | On death, all items drop to corpse and can be looted by others |
| **Ghost** | Player state after death — incorporeal, cannot communicate |
| **Corpse Decay** | Timer after which items on a dead player's corpse are permanently lost |
| **P2P** | Peer-to-peer — players connect in a mesh, no central game server |
| **WebRTC** | Web Real-Time Communication — enables true P2P in the browser |
| **STUN** | Session Traversal Utilities for NAT — helps peers discover public IPs (free) |
| **TURN** | Traversal Using Relays around NAT — relays traffic when direct connection fails (expensive) |
| **ICE** | Interactive Connectivity Establishment — coordinates STUN/TURN for NAT traversal |
| **Signaling Server** | Lightweight WebSocket server for initial peer discovery (not game data relay) |
| **XP-Spend** | Progression model: all activities earn general XP, spent to raise specific skills |
| **Toroidal Wrapping** | World edges wrap (east↔west, north↔south) — seamless finite world |
| **Graph-Based Dungeon** | Procedural generation using connectivity graphs + room templates |
| **Hardcore Mode** | Optional per-character permadeath |
| **GDScript** | Godot's built-in scripting language (required for web export) |
| **Data-First** | Architecture principle: JSON-driven data, code reads data |
| **Character Portability** | Characters are independent data that travel between worlds |
| **World Editor** | In-game tool for creating and editing worlds |
| **Quarantine** | Inventory section for modded items on non-modded worlds (visible, unusable) |
| **Mod Source** | Field on every item/skill/spell identifying its origin ("vanilla" or mod ID) |
| **Upfront Generation** | World data generated entirely before runtime, not streamed |
| **Rendering Chunk** | Visual LOD/culling unit, distinct from data loading |

## Inspirations

### Games
- **Ultima Online** — Skill system, death mechanics, crafting, open world, full loot PvP, classless progression, world size, toroidal wrapping, reagent-based magic, enchanting, murder system
- **Dark Souls series** — Combat feel, telegraphing, stamina, punishment/reward loop
- **Elder Scrolls (Morrowind/Oblivion/Skyrim)** — FP/TP camera swap, open world, equipment slots, weight-based inventory, attribute leveling
- **Diablo 2** — 8-player multiplayer, loot tables, randomized stats
- **EverQuest** — Instanced player housing (stretch goal reference)
- **Valheim** — World/character separation, portable characters, shared worlds
- **Doom / Heretic / DUSK** — Booster shooter aesthetic
- **RPG Maker series** — Sprite aesthetic
- **Hyper Light Drifter** — Top-down pixel art action

### Technical
- Godot 4.x documentation
- Godot `WebRTCMultiplayerPeer` / `SceneMultiplayer` documentation
- Godot WebSocket signaling server demo (godot-demo-projects)
- SakulFlee/Godot-WebRTC-Match-Maker (open-source signaling server)
- Graph-based dungeon generation (pcgworkshop.com, Ondřej Nepožitek)
- WebRTC NAT traversal research (STUN/TURN/ICE)

## Tools

| Tool | Use | License |
|------|-----|---------|
| Godot 4.x | Game engine | MIT |
| GIMP | Texture/sprite editing | GPL |
| Blender | 3D modeling | GPL |
| Aseprite / LibreSprite | Sprite creation | Prop. / GPL |
| Bfxr / Chiptone | SFX generation | FOSS |
| LMMS / FamiTracker | Music composition | GPL |
| Git | Version control | GPL |
| coturn (if needed) | TURN server for NAT traversal | BSD |
| Signaling server | WebSocket peer discovery | Self-hosted |
| JSON editor | Data file editing | Various |

## Revision History

| Date | Change |
|------|--------|
| 2026-06-16 | Initial GDD skeleton created |
| 2026-06-16 | R1: 40 questions answered — Souls-like combat, UO skills/death/crafting, FP/TP camera, P2P, web export, sprite stacking, hard magic, procedural quests. 27 new questions. |
| 2026-06-16 | R2: 17 answers — Magic (reagents + mana, regulated), P2P (WebRTC mesh, 8 players), progression (no overall cap, TES leveling without trap), world (toroidal wrapping, graph-based dungeons, day/night + weather), crafting (full UO, material progression), factions (guilds, no virtue system). 13 new questions. |
| 2026-06-16 | R3: 17 answers — Monster menace lore, Transmatalogy details, government structure, 11 guilds/factions, mounts, gold economy, min specs, hardcore mode, modding architecture, signaling server, NAT traversal. 11 new questions. |
| 2026-06-16 | R4: World name **Kaelor**, underground **Underloom** (scholarly) / **the Veins** (common). Layered naming. Lore summary. |
| 2026-06-16 | R5: World/character separation (Valheim-style). Worlds generated upfront as data. Characters portable between worlds. World editor (terrain sculpt, node placement, spawn zones). Mod compatibility system (quarantine foreign items). Architecture principles: DRY, Clean Code, KISS, Data-First. ~9 remaining open questions. |

---

*See also:* All other GDD documents
