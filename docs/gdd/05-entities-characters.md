# Entities & Characters

## Goals

- Render characters and creatures as 2D billboard sprites in 3D space
- RPG Maker–style animation sets with 8-directional head-on perspective
- 15-layer sprite stacking for equipment/armor/weapon/magic visualization
- Souls-like AI for enemies (telegraphed attacks, patrol/aggro behavior)
- First-person / third-person camera swap (Elder Scrolls style)
- Ghost state (death) with distinct visual treatment
- Mounts as tamed combat companions
- **Character portability:** Characters are independent data that travel between worlds

## Character Data (Portable)
Characters are saved as independent data files separate from world state. A character's data includes:
- Stats (STR/INT/DEX), skills, XP
- Inventory and equipment (item IDs + randomized stats)
- Faction reputation, quest progress, spellbook
- Mount/tamed creature data, death state
- Face/hair/skin customization choices

Characters persist across worlds — join a friend's world with your character, leave, join another. If the destination world doesn't have a required mod, foreign items are quarantined (visible but unusable) until returning to a compatible world.

## Core Concepts

### Camera System
- **First-person:** Camera at eye level, mouse look. Character body not visible (or only hands/weapon).
- **Third-person:** Camera behind and above character, showing full billboard sprite.
- **Swap method:** Toggle key (default: `V`) or scroll wheel zoom.
- **Transition:** Fast lerp or instant.

### Billboard System
- `Sprite3D` or custom `BillboardMesh` always faces camera
- In third-person: billboard faces camera (full sprite visible)
- In first-person: character sprite hidden (only weapon/hand visible)
- Z-positioning for height offset
- Shadow: separate sprite below character (ellipse)

### Sprite Stacking (15 Layers)
Each character is composited from multiple sprite layers drawn in order:

| Layer | Content |
|-------|---------|
| 1 | Shadow (ground ellipse) |
| 2 | Base body |
| 3 | Underwear / base clothing |
| 4 | Pants / leg armor |
| 5 | Shirt / torso armor |
| 6 | Left pauldron |
| 7 | Right pauldron |
| 8 | Left arm armor |
| 9 | Right arm armor |
| 10 | Shoes / boots |
| 11 | Hat / helmet |
| 12 | Jacket / robe (outer) |
| 13 | Weapon (held) |
| 14 | Shield / off-hand |
| 15 | Magic effects (auras, enchantments) |

- Each equipment slot has its own sprite sheet matching base animation frames
- Sprite resolution: TBD (experiment with 64×64 or 128×128 per frame)
- Implementation TBD: multiple Sprite3D nodes vs. shader-based compositing

### Sprite Sources
- RPG Maker–style sprite sheets
- 8-directional, head-on perspective
- Animation states: idle, walk, run, melee attack, ranged attack, spell cast, hurt, death, block/parry, dodge/roll

### Animation
- State machine per entity type
- Frame-based animation with configurable framerate
- Attack animations trigger hitbox frames (event-based, Souls-like frame data)
- Equipment animation frames match base sprite frame count and timing

### Player Character
- WASD movement + mouse aim
- Classless — no character class selection
- Stats: STR (carry weight, melee damage, HP), INT (mana, magic effectiveness), DEX (stamina, speed, accuracy)
- Skill-based progression (see `06-gameplay-systems.md`)
- Equipment changes reflected on sprite via sprite stacking
- Customizable face and hair at character creation
- Ghost state on death (see `06-gameplay-systems.md`)
- Hardcore mode toggle at character creation (permanent permadeath)

### NPCs
- Patrol behavior within spawn zone
- Dialogue interaction (concise, no exposition dumps)
- Shop functionality (merchants)
- Quest-giver functionality
- Healer functionality (can resurrect ghosts — rare and valuable)
- Trainer functionality (skill training for money — very expensive)
- Government enforcers (police unlicensed Transmatalogy use — TBD)

### Enemies
- Spawn zones with patrol paths
- Aggro system: detect player within radius, chase within patrol bounds
- Telegraphed attacks (wind-up → active hitbox → recovery, Souls-like)
- Loot drops on death (loot tables with randomization)
- Boss variants (larger, more complex patterns)
- **Thematic:** All enemies are creatures from the Underloom — demons, monsters, aberrations. The Veins are the accessible tunnels; the Underloom is the vast unknown beneath.

### Mounts
- Tamed creatures that serve as combat companions
- Taming skill determines what can be tamed (higher skill = more dangerous mounts)
- Mounts fight alongside the player (no separate pet system)
- Mounts can be killed and looted by others
- Carry weight bonus while mounted
- Mounts require feeding/upkeep (TBD)
- Rendered as billboard sprites (same system as characters)

### Companions (Later Goal)
- Player-recruited NPC allies (separate from mounts)
- Follow and fight alongside player
- Simple command system (follow, stay, attack target)

## Entity Component Breakdown

### Required Components
- `BillboardSprite` — Rendering with 15-layer sprite stacking
- `CollisionShape3D` — Hitbox/hurtbox
- `NavigationAgent3D` — Pathfinding
- `HealthComponent` — HP tracking
- `StateMachine` — Animation + behavior
- `StatsComponent` — STR/INT/DEX and derived values

### Optional Components
- `LootComponent` — Drop table
- `DialogueComponent` — Interaction
- `EquipmentComponent` — Sprite stacking data (15 layers)
- `SkillComponent` — Skill levels and XP
- `AggroComponent` — Enemy detection/aggro
- `GhostComponent` — Death state management
- `TamingComponent` — Mount taming data
- `FactionComponent` — Faction reputation tracking
- `MountComponent` — Mount-specific data (carry bonus, upkeep)

## Open Questions
- Final sprite resolution? (Experiment needed)
- Sprite stacking implementation: multiple Sprite3D nodes vs. shader compositing?
- First-person: show character body or just weapon/hands?
- How many enemy types at launch?
- Boss design complexity?
- Mount upkeep mechanics?

---

*See also:* `02-game-overview.md` | `06-gameplay-systems.md` | `08-art-direction.md`
