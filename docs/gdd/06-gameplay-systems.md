# Gameplay Systems

## Goals

- Souls-like real-time combat
- Classless XP-spend skill progression
- Morrowind/Oblivion-inspired attribute leveling
- Full-loot death system
- Transmatalogy — hard magic system
- Weight-based inventory, Morrowind-style equipment
- Full UO crafting with material progression
- Linear + radiant procedural + handcrafted quests
- 11 guilds and factions
- Gold economy + player trading
- Mounts via taming
- **Character portability** — characters travel between worlds carrying stats/equipment
- **World creation/editing** — procedural generation + manual editor for custom worlds

---

## World & Character Separation

### Design
Worlds and characters are independent data sets (Valheim-style).

**World data** includes: terrain, biomes, resource nodes, monster spawns, dungeon entrances, towns, buildings, NPC placements, event zones.

**Character data** includes: stats, skills, XP, inventory, equipment, faction reputation, quest progress, spellbook, mount data.

### Flow
1. Player selects or creates a character.
2. Player selects a world (procedurally generated, edited, or imported).
3. Character enters the world with all stats and equipment.
4. Player plays, earns XP, gathers loot, completes quests.
5. Player leaves the world → character data is saved independently.
6. Player can join a different world with the same character.

### Mod Compatibility
- Every item/skill/spell has a `mod_source` field.
- Modded character entering a non-modded world: foreign items moved to quarantine (visible, unusable). Return to modded world → restored.
- Non-modded character entering a modded world: can pick up and use modded content normally.
- Core stats and vanilla content work everywhere.

## Combat

### Style
- Real-time action, Souls-like
- High attack power, low defense
- Stamina-managed: attacking, blocking, rolling, sprinting
- Directional dodge/roll with i-frames
- Parry system: timed block for counter-attack
- No auto-facing
- Full combat repertoire always available

### Attack Phases (Souls-like)
1. **Telegraph/Wind-up** (≥340ms)
2. **Active** (hitbox live)
3. **Recovery** (≥170ms vulnerability)
4. **Combo/Return**

### Damage System
- Physical (slashing, piercing, blunt)
- Magical (by Transmatalogy school)
- Critical hits (backstab, parry riposte)
- Status effects (poison, burn, freeze, stun)

---

## Death System (Full Loot)

### On Death
1. Player dies → becomes **ghost** (incorporeal, passes through walls)
2. All unblessed items remain on **corpse**
3. Ghost **cannot communicate** with living
4. Ghost can: move freely, see friends, teleport to hub
5. Resurrection: hub shrine, player healer, NPC healer
6. Return to corpse to recover items
7. **Corpse decay:** items persist for limited time, then decay permanently
8. **Ghost dies again:** previous corpse and items lost
9. Others can loot corpses

### Murder System
- Murder counts + criminal flags (gray/red)
- Otherwise: full freedom
- No safe zones (except possibly hubs)

### Hardcore Mode (Optional)
- Per-character opt-in at creation
- Death is permanent
- Cannot be toggled mid-play

---

## Progression

### Core Concept: Classless XP-Spend
- All activities grant **general XP**
- Spend XP to raise **specific skills**
- No classes, no forced repetition

### Skills
- 50+ skills across categories (Combat, Magic, Crafting, Gathering, Stealth/Social, Knowledge)
- **Individual skill cap:** 100 (increasable via power scrolls)
- **No overall skill cap**
- Player spends earned XP to raise chosen skills

### Leveling (Morrowind/Oblivion-Inspired, Improved)
- Accumulate skill gains → level up → allocate 3 attributes
- Attribute bonus: +1 to +5 based on governing skill gains since last level
- **No major/minor distinction** — all skills count equally, no min-maxing trap

### Stats
| Stat | Governs |
|------|---------|
| STR | Carry weight, melee damage, HP |
| INT | Mana pool, magic effectiveness |
| DEX | Stamina pool, speed, accuracy |

### Character Creation
- Customize: face, hair, skin tone
- Distribute starting skill points (TBD: fixed template or point-buy)
- No class selection
- Hardcore mode toggle (permanent)

---

## Transmatalogy (Hard Magic System)

### Lore
Transmatalogy is the study of materials and their exchange with will for effects. Raw components contain the "ability to become anything." Casting releases that potential into one short-lived effect, fueled by the caster's will (mana). It is an everyday science — common folk use it for small tasks (lighting fires, prestidigitation). Only adepts wield it for combat. Unlicensed use is heavily regulated by government institutions.

### Mechanics
- **Single skill:** Magery
- **Casting cost:** Both reagents AND mana
- **Spell acquisition:** Scrolls + spellbook (spellbook can be lost on death!)
- **Skill training:** NPC trainers for money (very expensive)
- **Reagent types:** Sulfurous Ash, Bloodmoss, Mandrake Root, Nightshade, Garlic, Grave Dust, etc.
- **Spell circles:** TBD (UO had 8 circles of 8 spells)

### Regulation
- Mages Guild controls licensed Transmatalogy training
- Unlicensed casting is criminal → investigated by government enforcers
- Druids faction exists outside regulation → viewed with suspicion
- Enforcement in gameplay: reputation loss, criminal flag, possible imprisonment/bounty (TBD)

### Enchanting
- Rare skill — reputable practitioners hard to find
- Enchanted items are valuable and tradeable
- Requires Inscription skill, reagents, mana

---

## Crafting System (Full UO)

### Crafting Skills
| Skill | Output |
|-------|--------|
| Blacksmithing | Weapons, metal armor, tools |
| Tailoring | Cloth/leather armor, hats, boots |
| Alchemy | Potions (heal, buff, cure, poison), dyes |
| Tinkering | Tools, traps, gadgets |
| Carpentry | Furniture, bows, shields, containers |
| Inscription | Spell scrolls, enchanted items, books |
| Cooking | Food (buffs, sustenance) |

### Mechanics
- Tools required (hammer, sewing kit, mortar & pestle) — tools wear out
- Resource gathering: mining, lumberjacking, skinning, harvesting
- Recipe-based: basic items immediately, advanced items need learned recipes
- **Material progression:** iron → steel → magical materials
- **Randomized stats** on crafted items, modified by crafter's skill
- Feeds into enchanting system

### Resource Distribution
- Both procedural nodes and fixed locations
- Respawn timers (TBD)
- The Monster Menace drives resource demand (enchantment upkeep requires constant materials)

---

## The Monster Menace & the Underloom

### Lore
Beneath the kingdoms of Kaelor lies the Underloom — an immeasurable subterranean realm from which the endless monster menace emerges. Most people know only the upper reaches: the twisting caverns, abandoned mines, and ancient passages collectively called the Veins. Few have ventured deeper, and fewer still have returned.

The civilized races developed Transmatalogy to hold the surface through enchantments requiring constant upkeep. There is no known "fix" — only endure, live, and thrive.

### Gameplay Manifestation
- **Surface eruptions:** Random monster spawn events at Vein eruption points (world events)
- **Dungeon portals:** Openings to the Underloom that can be entered for instanced dungeon content
- **Enchantment decay:** World enchantments degrade over time, requiring resource investment (TBD — territory control?)
- **Monster scaling:** The deeper into the Veins/Underloom, the worse it gets
- **Resource pressure:** Constant need for reagents and materials drives the economy

---

## Factions & Guilds

### Guilds (Join Multiple)
| Guild | Focus | Benefits |
|-------|-------|----------|
| Fighters Guild | Combat, monster hunting | Combat training, hunting contracts |
| Mages Guild | Licensed Transmatalogy | Spell training, regulated casting |
| Mercantile Guild | Trade, commerce, theft | Trade discounts, stealth skills |
| Hunters Guild | Monster hunting, tracking | Tracking, wilderness survival |
| Crafters Guild | Crafting standards | Recipe access, quality bonuses |
| Gatherer Guild | Resource gathering | Gathering efficiency, node locations |

### Factions (Join One + Outlaws/Nomads)
| Faction | Ideology | Benefits |
|---------|----------|----------|
| Nobles | Aristocratic power, tradition | Political access, land rights |
| Business / Land Owners | Commerce, property | Trade advantages, shop access |
| Peasants | Common folk, labor rights | Community support, crafting discounts |
| Outlaws / Nomads | Freedom, survival | Stealth, black market access |
| Druids | Magical freedom, secrecy | Unlicensed magic training, hidden areas |

- Faction reputation affects NPC interactions, quest availability, shop prices
- Faction conflicts create emergent PvP dynamics
- Druids are viewed with suspicion by authorities but offer unique benefits

---

## Quests

### Types
1. **Linear Main Quests** — The Monster Menace narrative, Transmatalogy lore, faction storylines
2. **Radiant Procedural Quests** — Generated from narrative components (hooks, twists, acts) assigned to NPCs/locations
3. **Handcrafted Side Quests** — Unique, memorable, location/character-specific
4. **Guild Contracts** — Repeatable bounty/contract system per guild
5. **World Events** — Monster eruptions, Underloom incursions, faction conflicts

### Quest Delivery
- NPC dialogue (concise)
- Item/quest descriptions
- Books and journals
- Environmental storytelling

---

## Economy

### Currency: Gold
- Earned from: monster loot, quest rewards, trading, guild contracts
- Spent on: equipment, reagents, training, housing, trading

### Player Trading
- Direct player-to-player trade
- Trade window with confirmation
- No auction house (stretch goal: player shop in housing)

### Economy Drivers
- Monster menace creates constant demand for equipment, reagents, enchantments
- Crafting professions produce tradeable goods
- Guild contracts provide steady income
- Full-loot death means items constantly recirculate

---

## Mounts & Taming

### Taming Skill
- Skill determines what creatures can be tamed
- Higher skill = more powerful/dangerous mounts
- Taming process: weaken creature → use taming ability → success/failure based on skill

### Mounts as Combat Companions
- No separate pet system — tamed creatures ARE combat companions
- Mounts fight alongside the player
- Mounts can be killed (and looted by others)
- Carry weight bonus while mounted
- Mounts require feeding/upkeep (TBD)

---

## Inventory

### System
- Weight-based (max carry = f(STR))
- Over-encumbered = cannot move
- Stackable consumables

### Equipment Slots (Morrowind-Style)
Head, Neck, Torso, L/R Pauldron, L/R Arm, L/R Hand (rings), L/R Leg, Pants, Feet, Weapon, Shield/Off-hand

### Blessed Items
- Can be blessed (by players or NPCs) to persist on death
- Blessing costs gold/reagents

---

## Open Questions
- Boss design (Q31)
- Transmatalogy enforcement mechanics in gameplay
- Magic regulation + PvP interaction
- Dungeon instance persistence rules
- Spell circle count
- Max dungeon party size
- Character creation: fixed template or point-buy?
- Level-up: automatic or player-initiated?
- Monster menace world event design

---

*See also:* `05-entities-characters.md` | `07-ui-ux.md` | `08-art-direction.md`
