# Design Questionnaire

## Answered Questions (Rounds 1–3)

### Vision & Scope

**1. Core fantasy:** Fighting, exploration, and open-world storytelling quests. Not focused on building/survival. Crafting is desired but not the core loop.

**2. Mood:** Fantasy with a hard magic system — magic has grounded, consistent rules. Transmatalogy: the study of materials and their exchange with will for effects. Magic is science, not mystery.

**3. Multiplayer:** P2P, small groups. Not MMO-scale.

**4. Session length:** Multi-hour sessions.

**5. Scope for first playable:** Undefined.

### World & Terrain

**6. World size:** Finite but large (~UO Britannia scale: ~5120×4096 units).

**7. Biome variety:** Multiple biomes with smooth blending.

**8. Terrain features:** Standard fantasy terrain. No underwater, no floating islands.

**9. Terrain deformability:** No digging/terraforming.

**10. Verticality:** Full 3D verticality.

### Buildings & Placement

**11. Camera:** First-person / third-person, swappable at any time.

**12–17. Building system:** Backburnered.

### Characters & Entities

**18. Player character:** Classless. XP-spend skill system. Sprite stacking for equipment. Customizable face and hair.

**19. NPC types:** All — merchants, quest-givers, enemies, wildlife, bosses.

**20. Enemy behavior:** Aggro chase within patrol/spawn radius.

**21. Companions:** Later goal.

**22. Animation:** 8-directional, head-on perspective.

**23. Sprite resolution:** Undecided — needs experimentation.

### Combat & Gameplay

**24. Combat style:** Real-time action, Souls-like.

**25. RPG mechanics:** UO skill-based (classless). Morrowind/Oblivion-inspired attribute leveling.

**26. Loot system:** Loot tables with randomization.

**27. Quest structure:** Linear main + radiant procedural + handcrafted side quests.

**28. Progression gates:** Full open world. Stat/skill-based gating only.

**29. Death penalty:** Full loot. Ghost → resurrect → recover corpse. Others can loot. Corpse decays.

### Inventory & Items

**30. Inventory system:** Weight-based.

**31. Equipment slots:** Morrowind-style.

**32. Crafting depth:** Full UO system.

**33. Consumables:** Yes — potions, food, throwables, reagents.

### Story & Worldbuilding

**34. Story:** Yes — linear main + radiant procedural + handcrafted side.

**35. Lore delivery:** Item/quest descriptions, concise NPC dialogue, books/journals.

**36. World persistence:** Yes — save state. No NPC schedules.

### Technical & Scope

**37. Target platform:** Web export (browser). Also native builds.

**38. Performance priority:** Smooth framerate and good netcode.

**39. Godot version:** Latest (4.x).

**40. Third-party tools:** FOSS only. AI generation considered.

### Magic System

**N1. Hard magic rules:** Transmatalogy — the study of materials and their exchange with will for effects. Magic is an expenditure of nature (reagents — raw components contain potential to become anything) and an expense of will (mana). Magic is everyday, understood, scientific. Common folk use it for small tasks. Only adepts use it for combat. Heavily regulated by government.

**N2. Magery skill:** Single skill.

**N3. Spell acquisition:** Scrolls + spellbook (can be lost!). Trainers raise skills for money (expensive).

**N4. Enchanting:** Yes, rare to find reputable practitioners.

**N5. Casting cost:** Both reagents AND mana.

### Multiplayer / P2P

**N6. P2P architecture:** True P2P via WebRTC mesh. Characters portable between solo and group.

**N7. Player count target:** 8 (WebRTC mesh practical limit. Diablo 2: 8, Dark Souls: 4-6, Minecraft small groups: 4-10).

**N8. PvP rules:** Full loot PvP everywhere.

**N9. Ghost communication:** Ghosts cannot communicate. Can move, see friends. Teleport to hub for res, be ressed by player, or find NPC healer.

**N10. Murder system:** Murder counts + criminal flags (gray/red). Otherwise full freedom.

### Progression

**N11. Skill cap:** No overall cap. Each skill caps at 100 (increasable later via power scrolls).

**N12. Stat growth:** Morrowind/Oblivion-inspired. Skill gains → level up → allocate 3 attributes freely (+1 to +5 based on governing skill gains). No major/minor trap.

**N13. Skill gain:** XP-Spend model.

**N14. Power creep:** No prevention. Power fantasies are legal. Games should be fun.

### World

**N15. World wrapping:** Toroidal (UO style, east↔west, north↔south).

**N16. Dungeons:** Instanced, procedural, graph-based generation.

**N17. Day/night cycle:** Yes, both visual and gameplay impact.

**N18. Weather system:** Yes, atmospheric only.

### Crafting

**N19. Crafting depth:** Full UO system.

**N20. Resource distribution:** Both procedural and fixed.

**N21. Crafting progression:** Material-based tiers. Stats randomized, modified by skill. Feeds into enchanting.

### Story

**N22. Main quest theme:** (See Q25 below)

**N23. Procedural quest complexity:** Unknown — needs skeleton + playtesting.

**N24. Factions:** Guilds and factions (see Q28 below). No virtue system.

### Technical

**N25. Web export constraint:** Baseline requirement. Must run in browser.

**N26. Netcode:** Godot WebRTC P2P mesh.

---

## Round 3 Answers

### World Lore & Magic

**Q25. Central conflict / narrative:** The never-ending monster/demon menace from beneath the earth. A never-ending tide of monsters surfaces constantly. The civilized races developed Transmatalogy to protect the surface through enchantments (material + will), but the enchantments require constant upkeep of resources and will. Killing monsters, gathering resources, and delving into the Void (the underground source) are all motivated by survival. There is no known "fix" — only endure, live, and thrive within the constraints. This leads to cooperative kingdoms with a shared enemy, though intrigue, shadow wars, false flags, and occasional wars still occur.

**Q26. World name and lore:** The world has a natural-feeling history: big bang → evolution → slow growth of civilization → development of understanding of magic (from randomness → myth/storytelling → science/Transmatalogy). Governed by kingdoms with kings, advisors, elected representatives, guilds, and factions. Kings have final say, but powerful forces (guilds, factions, ideologies) compete for influence. Tyrants don't live long. **World name:** TBD — needs a unique name that feels natural and grounded, evoking the world's history of chaos-to-civilization. Should feel mythic but earned, not generic fantasy.

**Q27. Government structure:** See Q26. Kingdoms with monarchy + advisory councils + elected reps. Guilds and factions act as powerful lobbying forces. Transmatalogy regulation is a core government function — unlicensed magic use is criminal. Institutions exist to police rogue mages. Government funding comes from taxes on guilds, trade, and resource extraction.

### Factions & Guilds

**Q28. Baseline factions:**
| Type | Name | Description |
|------|------|-------------|
| Guild | Fighters Guild | Combat training, monster hunting contracts |
| Guild | Mages Guild | Licensed Transmatalogy training, regulated magic |
| Guild | Mercantile Guild | Trade, commerce, thieves' guild arm |
| Guild | Hunters Guild | Monster hunting, tracking, wilderness survival |
| Guild | Crafters Guild | Crafting professions, quality standards |
| Guild | Gatherer Guild | Resource gathering, mining, lumber, foraging |
| Faction | Nobles | Royalty, landed aristocracy, political power |
| Faction | Business / Land Owners | Merchant class, property owners, trade guilds |
| Faction | Peasants | Common folk, laborers, workers |
| Faction | Outlaws / Nomads | Unaffiliated, criminals, wanderers, hermits |
| Faction | Druids | Non-imperial mages living outside government regulation. Secrecy-based society. Believers in magical freedom. Many are fine people, but criminal element is drawn to their ideology, creating negative stereotypes they can't shake. |

- Players can join multiple guilds
- Players can only join non-conflicting factions (cannot be both Noble and Peasant, for example)
- Guilds provide skill training, quest access, reputation benefits
- Factions provide political standing, territory access, shop discounts, PvP dynamics

### Systems & Scope

**Q29. Player housing:** Yes — instanced housing as a far stretch goal (EverQuest style). Instanced rooms/players housing. Post-launch feature.

**Q30. Enemy variety:** Extensible system. Make as we go. Needs to support:
- Biome-specific enemies
- Dungeon-specific enemies
- Overworld roaming enemies
- Boss enemies (world bosses + dungeon bosses)
- Monster menace from the Void (thematic consistency)

**Q31. Boss design:** Unknown — needs design work and playtesting.

**Q32. Mounts:** Yes! Taming skill for sure. Mounts are animals/monsters that can be tamed.

**Q33. Pets:** No separate pet system. Taming = combat companions. Carry-only "pets" are just tamed creatures you protect.

**Q34. Economy:** Gold as currency. Player-to-player trading. Economy driven by:
- Monster loot drops
- Resource gathering → crafting → selling
- NPC merchants (buy/sell markup)
- Guild contracts/bounties
- Player shops/housing shops (stretch goal)

**Q35. Minimum specs (reasonable baseline):**
| Component | Minimum |
|-----------|---------|
| OS | Windows 10 64-bit |
| RAM | 8 GB |
| CPU | 4 cores, ≥2.0 GHz (modern x86_64) |
| GPU | DirectX 11+ / WebGL 2.0 compatible |
| Display | 1920×1080 |
| Browser | Chrome 56+, Firefox 51+, Safari 15+, Edge 79+ |
| Network | Broadband (20+ Mbit/s for multiplayer) |
| Build size | Target <500 MB initial load |
| Load time | <20 seconds to title menu |
| Target FPS | 60 FPS (40 FPS minimum acceptable) |

**Q36. Disconnected player:** Despawn. Character is saved and available next login. If in combat when disconnected, character dies (becomes ghost/corpse).

**Q37. Anti-griefing:** Beyond murder counts — no additional anti-griefing. Players can do as they wish. Full freedom.

**Q38. Hardcore mode:** Optional permadeth mode per character. If enabled, death is permanent. Cannot be toggled mid-play.

**Q39. Modding support:** Yes. Architecture principles: DRY, Clean Code, KISS, Data-First. Data-driven design (JSON configs for items, enemies, skills, quests, recipes, loot tables). Community modders should be able to add:
- Custom items (via JSON + sprite sheets)
- Custom enemies (via JSON + sprites + behavior scripts)
- Custom quests (via narrative component JSON)
- Custom dungeon graphs (via graph JSON + room templates)
- Custom crafting recipes (via JSON)

### Technical Deep-Dive

**Q40–41. Signaling server:** We can host a lightweight signaling server. Godot provides a reference WebSocket signaling server (godot-demo-projects/networking/webrtc_signaling). Open-source options exist (SakulFlee/Godot-WebRTC-Match-Maker). A signaling server only exchanges connection metadata (ICE candidates, session descriptions) — it does NOT relay game data. Bandwidth is negligible. Can be hosted on any VPS for ~$5/month.

**Q42. NAT traversal research:**

**Answer:** WebRTC NAT traversal uses ICE (Interactive Connectivity Establishment) which coordinates three mechanisms:

1. **STUN** (free, lightweight): Discovers public IP address. Works for ~75-80% of connections.
2. **TURN** (expensive, bandwidth-heavy): Relays traffic when direct connection fails. Needed for ~20-25% of connections (corporate firewalls, symmetric NAT, mobile carriers, CGNAT).
3. **ICE framework**: Tries all candidates (host → STUN → TURN) and picks the best working path.

**Recommendation for this project:**
- **STUN:** Use Google's public STUN servers (`stun:stun.l.google.com:19302`) — free.
- **TURN:** Initially skip. ~80% of connections will work via STUN/direct alone. If connection failures are reported from players behind strict networks, add a TURN server later (use a relay service like Twilio Network Traversal Service, or self-host coturn on a VPS).
- **Expected outcome:** 4 out of 5 random players will connect directly. The 5th (behind corporate firewall or strict NAT) may fail.
- **Mesh topology consideration:** With 8 peers, that's 28 connections (N(N-1)/2). If 20% fail, ~5-6 connections might need TURN fallback. This is manageable.

**Additional reference:** Godot's built-in ICE candidate gathering handles this automatically via `WebRTCMultiplayerPeer`. You just configure STUN/TURN server URLs in the peer config.

---

## Remaining Open Questions

| # | Question | Priority |
|---|----------|----------|
| ~~Q26b~~ | **World name: Kaelor** (resolved) | Done |
| — | **Underground: Underloom** (scholarly) / **the Veins** (common) (resolved) | Done |
| Q31 | Boss design complexity target | Medium |
| — | Transmatalogy enforcement in gameplay terms? (NPC inspectors? Reputation loss? Criminal justice system?) | Medium |
| — | Magic regulation + PvP interaction? | Medium |
| — | Dungeon instance persistence (reset on all-leave or timer?) | Medium |
| — | Spell circle count (UO's 8×8 or fewer?) | Medium |
| — | Max dungeon party size? | Low |
| — | Character creation: fixed template or point-buy? | Medium |
| — | Level-up: automatic or player-initiated? | Low |
| — | Monster menace world event design? | High |

### World Lore Resolution

**World name:** Kaelor
- Adjective: Kaeloric
- People: Kaeloran
- Derived terms: the Kaeloran Crown, the Kingdoms of Kaelor, the First Age of Kaelor

**Underground:**
- **The Underloom** (scholarly/religious): The immense subterranean realm from which the monster menace emerges. "Few maps survive beyond the Third Stratum of the Underloom." Scholars debate whether it formed naturally or is the foundation of the world.
- **The Veins** (common): The sprawling network of tunnels, caverns, mines, ruins, and passages that are the accessible fraction of the Underloom. "They broke into a Vein." "Don't follow that Vein." Miners and soldiers say "Veins." Professors and texts say "Underloom."

**Lore summary:**
> Beneath the kingdoms of Kaelor lies the Underloom, an immeasurable subterranean realm from which the endless monster menace emerges. Most people know only the upper reaches — the twisting caverns, abandoned mines, and ancient passages collectively called the Veins. Few have ventured deeper, and fewer still have returned.

## World & Character Architecture Resolution

**Decision:** Worlds and characters are separate data (Valheim-style).

- **Worlds** are generated upfront as complete data files: terrain, biomes, resource nodes, monster spawns, dungeon entrances, towns, cities, NPC placements, event zones.
- **Characters** are portable data sets: stats, skills, inventory, equipment, faction standing, quest progress.
- Characters travel between worlds carrying everything. Join a friend's world, leave, join another.
- **World editor** lets players sculpt terrain, place nodes, define spawns, position buildings, and share world files.
- **Mod compatibility:** `mod_source` field on every item/skill/spell. Foreign items quarantined on non-modded worlds. Vanilla content works everywhere.
- **Architecture principles:** DRY, Clean Code, KISS, Data-First. JSON-driven data for all game content.

*Answered: 2026-06-16 (R1–R5) | ~80 questions answered across 5 rounds | ~9 remaining open*
