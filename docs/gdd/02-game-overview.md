# Game Overview

## High-Level Vision

**Working Title:** Veins of Kaelor

**World Name:** Kaelor

A pseudo-3D action RPG sandbox built in Godot. Players explore Kaelor — a vast procedurally generated world threatened by an endless monster menace from the Underloom, the immeasurable subterranean realm beneath the surface. Most people know only the Veins — the twisting caverns, mines, and passages that are the Underloom's outermost reaches. Fight with Souls-like precision. Use Transmatalogy — the science of exchanging natural potential and personal will. Shape your character freely through classless skills. Lose everything on death. Join guilds and factions in a world of cooperative kingdoms, political intrigue, and shadow wars. Full-loot P2P multiplayer where characters are portable between solo and group play. RPG Maker–style billboard sprites in a 3D world. Web-first.

## Core Architecture: Worlds and Characters Are Separate

Inspired by Valheim. **Worlds are data. Characters are data. They are independent.**

- A **world** is a finite, pre-generated map: terrain, biomes, resource nodes, monster spawns, dungeon entrances, towns, cities — all generated upfront and saved as a shareable data file.
- A **character** is a portable data set: stats, skills, inventory, equipment, faction standing — carried between worlds.
- Players generate or edit worlds (seed-based or manual), then invite friends. Everyone brings their own character.
- Solo play works the same: pick a character, pick a world, play.
- World editor lets players sculpt terrain, place nodes, define spawns, position buildings, and share worlds.
- Modding support: modded characters can visit non-modded worlds (foreign items quarantined); non-modded characters can visit modded worlds (pick up modded content).

1. **Souls-like Combat** — High attack, low defense, stamina management, rolls, parries, telegraphing. Punishing but fair.
2. **The Monster Menace** — An endless tide of monsters from the Underloom drives all civilization. No final solution — only endure, live, and thrive.
3. **Transmatalogy (Hard Magic)** — Magic is science: exchange of material potential + willpower. Everyday convenience for common folk, regulated power for adepts.
4. **Classless Progression** — All activities earn XP, spent freely on skills. Level up through accumulated gains, allocate attributes. No classes, no traps.
5. **Full-Loot P2P Multiplayer** — True WebRTC P2P mesh, 8 players, character portability, full loot everywhere, ghost/corpse/decay.
6. **Political Sandbox** — Guilds, factions, intrigue. Cooperative kingdoms with a shared enemy but competing ideologies.
7. **Web-First** — Runs in the browser. Baseline requirement.

## The Monster Menace (Central Theme)

Beneath the kingdoms of Kaelor lies the Underloom — an immeasurable subterranean realm from which the endless monster menace emerges. Most people know only the upper reaches: the twisting caverns, abandoned mines, and ancient passages collectively called the Veins. Few have ventured deeper, and fewer still have returned.

The civilized races developed Transmatalogy to protect the surface through enchantments requiring constant upkeep of resources and will. There is no known "fix" — only endure, live, and thrive. This existential threat forces cooperative kingdoms but doesn't eliminate intrigue: shadow wars, false flags, political maneuvering, and the occasional war still erupt over resources, ideology, and power.

Farmers know the Veins. Soldiers defend against incursions from the Veins. Scholars debate the nature of the Underloom. Delvers discover that the Veins are only the outermost capillaries of something far older.

## Factions & Guilds
| Type | Name | Description |
|------|------|-------------|
| Guild | Fighters Guild | Combat training, monster hunting contracts |
| Guild | Mages Guild | Licensed Transmatalogy, regulated magic |
| Guild | Mercantile Guild | Trade, commerce, thievery |
| Guild | Hunters Guild | Monster hunting, tracking, wilderness |
| Guild | Crafters Guild | Crafting professions, quality standards |
| Guild | Gatherer Guild | Mining, lumber, foraging |
| Faction | Nobles | Royalty, landed aristocracy |
| Faction | Business / Land Owners | Merchant class, property, trade |
| Faction | Peasants | Common folk, laborers |
| Faction | Outlaws / Nomads | Unaffiliated, criminals, wanderers |
| Faction | Druids | Unlicensed mages, freedom advocates, secrecy |

## Target Experience

- **Genre:** Action RPG / Sandbox
- **Perspective:** First-person / third-person, swappable
- **Player Count:** P2P, target 8 players
- **Tone:** Fantasy, grounded magic, cooperative but politically complex
- **Session Length:** Multi-hour
- **Platform:** Web export (browser) + native builds
- **Min Specs:** Win 10 64-bit, 8 GB RAM, 4-core 2.0 GHz, DX11/WebGL2 GPU, 1080p, Chrome 56+

## Elevator Pitch

> The Underloom never stops. Monsters endlessly claw their way to the surface through the Veins. Civilization endures through Transmatalogy — the science of material and will — but only barely. Explore Kaelor. Fight with precision in Souls-like combat. Join guilds, navigate faction politics, and carve your own path through a classless system where every action matters. Lose everything on death — if you dare. Play with friends in a true P2P world where power fantasies are legal and the only certainty is the tide below.

## Key Features

- [ ] Procedural terrain — toroidal wrapping, biomes, verticality (`03-world-generation.md`)
- [ ] Procedural instanced dungeons — graph-based generation (`03-world-generation.md`)
- [ ] First-person / third-person camera swap (`05-entities-characters.md`)
- [ ] Billboard sprites — 15-layer sprite stacking (`05-entities-characters.md`)
- [ ] Souls-like combat (`06-gameplay-systems.md`)
- [ ] Classless XP-spend skills + Morrowind/Oblivion leveling (`06-gameplay-systems.md`)
- [ ] Full-loot death — ghost/corpse/decay (`06-gameplay-systems.md`)
- [ ] Transmatalogy — reagents + mana, regulated magic (`06-gameplay-systems.md`)
- [ ] Weight-based inventory, Morrowind-style slots (`06-gameplay-systems.md`)
- [ ] Full UO crafting — material progression, randomized stats (`06-gameplay-systems.md`)
- [ ] Linear + radiant procedural + handcrafted quests (`06-gameplay-systems.md`)
- [ ] 11 guilds/factions (`06-gameplay-systems.md`)
- [ ] P2P multiplayer — WebRTC mesh, 8 players, character portability (`10-technical-architecture.md`)
- [ ] World editor — terrain sculpt, node placement, spawn zones, building placement (`03-world-generation.md`)
- [ ] Character/world separation — portable characters, shareable world files (`10-technical-architecture.md`)
- [ ] Day/night cycle + weather (`03-world-generation.md`)
- [ ] Mounts via taming skill (`05-entities-characters.md`)
- [ ] Gold economy + player trading (`06-gameplay-systems.md`)
- [ ] Instanced player housing (stretch goal) (`04-building-system.md`)
- [ ] Modding support — data-driven JSON architecture (`10-technical-architecture.md`)

## Out of Scope (Current)

- Player building / survival mechanics
- NPC schedules
- Voice acting
- MMO-scale multiplayer
- Mobile platforms
- Cross-platform play

---

*See also:* `01-design-questionnaire.md` | `03-world-generation.md` | `08-art-direction.md`
