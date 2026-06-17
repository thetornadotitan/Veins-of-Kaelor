# GDD Index — Veins of Kaelor

## Project Overview
A pseudo-3D action RPG sandbox built in Godot. Procedurally generated 3D terrain with toroidal wrapping, 3D buildings with 2D tileable textures, and billboard 2D character/entity sprites (RPG Maker style, 15-layer sprite stacking). Souls-like combat, classless XP-spend skill progression, Morrowind/Oblivion-inspired attribute leveling, full-loot P2P death system, Transmatalogy (hard magic: reagents + mana), procedural instanced dungeons, 11 guilds/factions, gold economy, web export target.

## Document Structure

| File | Title | Description |
|------|-------|-------------|
| `00-gdd-index.md` | GDD Index | This file. Navigate and context guide. |
| `01-design-questionnaire.md` | Design Questionnaire | 74 answered questions + ~11 remaining open |
| `02-game-overview.md` | Game Overview | Vision, pillars, factions, target experience |
| `03-world-generation.md` | World & Terrain | Procedural mesh, biomes, toroidal wrapping, dungeons, day/night, weather |
| `04-building-system.md` | Building System | Backburnered. Dev/procedural placement, interior culling |
| `05-entities-characters.md` | Entities & Characters | Billboard sprites, 15-layer stacking, FP/TP camera, ghost state, mounts |
| `06-gameplay-systems.md` | Gameplay Systems | Souls-like combat, Transmatalogy, crafting, quests, factions, economy, death |
| `07-ui-ux.md` | UI/UX | HUD, menus, controls, ghost state UI |
| `08-art-direction.md` | Art Direction | Visual style, sprite stacking layers, textures |
| `09-audio.md` | Audio | Music, SFX, ambient systems |
| `10-technical-architecture.md` | Technical Architecture | Godot structure, WebRTC P2P, web export, key systems |
| `11-appendix.md` | Appendix | Glossary, inspirations, tools, revision history |

## Key Design Decisions (Resolved)

| Decision | Choice | Doc |
|----------|--------|-----|
| Combat | Real-time, Souls-like | `06` |
| Progression | XP-spend skills, no overall cap, 100 per skill | `06` |
| Leveling | Morrowind/Oblivion-inspired, freely allocated, no major/minor trap | `06` |
| Death | Full loot, ghost/corpse, decay, no ghost communication | `06` |
| Camera | First/third person, swappable | `05` |
| Multiplayer | True P2P, WebRTC mesh, 8 players, character portability | `10` |
| Platform | Web export (browser) — baseline requirement | `10` |
| World size | Finite, ~UO Britannia scale, toroidal wrapping | `03` |
| Dungeons | Instanced, procedural, graph-based generation | `03` |
| Building | Backburnered (dev/procedural only) | `04` |
| Magic | Transmatalogy: reagents + mana, regulated, everyday science | `06` |
| Quests | Linear + radiant procedural + handcrafted side + guild contracts + world events | `06` |
| Inventory | Weight-based, Morrowind-style slots | `06` |
| Crafting | Full UO system, material progression, randomized stats | `06` |
| Sprites | Billboard, 8-directional, 15-layer sprite stacking | `05` |
| Day/Night | Yes, gameplay impact + visual | `03` |
| Weather | Yes, atmospheric only | `03` |
| Factions | 6 guilds + 5 factions (11 total) | `06` |
| Murder system | Murder counts + criminal flags, otherwise full freedom | `06` |
| Mounts | Yes, via taming skill (combat companions, not pets) | `06` |
| Economy | Gold currency + player trading | `06` |
| Hardcore mode | Optional per-character permadeath | `06` |
| Housing | Instanced player housing (stretch goal) | `04` |
| Modding | Data-first JSON architecture, DRY/Clean/KISS principles | `10` |
| Min specs | Win10, 8GB RAM, 4-core 2.0GHz, DX11/WebGL2, Chrome 56+ | `10` |
| Signaling | Self-hosted WebSocket server | `10` |
| NAT traversal | STUN (Google public) at launch, TURN added later if needed | `10` |
| Disconnect | Despawn + save; if in combat → death | `10` |
| World gen | Entire world generated upfront as data, not streamed | `03` |
| World editor | In-game terrain sculpt, node placement, spawn zones | `03` |
| Char/world separation | Independent data — characters portable between worlds | `10` |
| Mod compatibility | `mod_source` field, quarantine foreign items | `10` |
| Architecture | DRY, Clean Code, KISS, Data-First | `10` |

## Remaining Open Questions (~9)

| # | Question | Priority |
|---|----------|----------|
| ~~Q26b~~ | **World name: Kaelor** (resolved) | Done |
| — | **Underground: Underloom** (scholarly) / **the Veins** (common) (resolved) | Done |
| Q31 | Boss design complexity target | Medium |
| — | Transmatalogy enforcement mechanics | Medium |
| — | Magic regulation + PvP interaction | Medium |
| — | Dungeon instance persistence | Medium |
| — | Spell circle count | Medium |
| — | Max dungeon party size | Low |
| — | Character creation: fixed template or point-buy? | Medium |
| — | Level-up: automatic or player-initiated? | Low |
| — | Monster menace world event design | High |

## Intended Audience
- Solo developer (current)
- Future collaborators
- LLM agents working on implementation (each doc is self-contained for context)

---

*Last updated: 2026-06-16*
