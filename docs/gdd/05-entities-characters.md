# Entities & Characters

## Goals

- Render characters and creatures as 2D billboard sprites in 3D space
- **4-way directional pseudo-3D character sprites** that display the correct frame based on viewer's camera angle
- Data-driven equipment system so equipping a style updates all linked body parts from a single sheet reference
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

### Directional Sprite Stacking (4-Way Pseudo-3D)

Each character uses a **4-directional sprite system** (forward, left, right, away) rather than full 8-way to balance visual fidelity with development scope for solo development:

| Direction | Description |
|-----------|-------------|
| **Forward** | Character faces the camera |
| **Left**    | Character's left side to the camera |
| **Right**   | Character's right side to the camera |
| **Away**    | Character's back to the camera |

**Implementation:** Each body part is a single `Sprite3D` node. The client calculates the relative angle from the local camera to the character, determines the direction, looks up the equipped style, and updates the Sprite3D's `texture.region` and positioning data locally. No network synchronization is needed for visuals - only `position`, `rotation`, and `equipped_styles` are replicated.

### Data-Driven Equipment System

Equipment is managed through a data-first approach:

- **JSON Database:** `sprite_database.json` defines all sprite metadata
- **Three-layer separation per sheet:**
  - `parts`: Pixel relationships between body pieces (offsets, sizes) - defined once per sheet
  - `world`: World-space positioning per direction - defined once per sheet  
  - `styles`: Anchor regions per style per direction - `[x, y, w, h]` arrays
- **Adding a style:** Requires only 4 numbers (one anchor region per direction)
- **Equipment lookup:** `equipped_styles["slot"] = "style_name"` → query database for anchor → apply part offsets → set Sprite3D.region

### Equipment Synchronization

Equipment changes use the existing RPC system:

1. Local player (or server) calls `equip_item(slot, style)` RPC
2. Server updates `equipped_styles` dictionary and replicates via RPC sync
3. All clients receive updated `equipped_styles` and recalculate visuals locally
4. Visual derivation is client-side: `direction` (from camera angle) + `equipped_styles` → final sprite

### Sprite3D Optimization

Following KISS and DRY principles:

- **Single Sprite3D per body part** - no duplication for directions
- **Runtime region calculation** - combines anchor + part offset
- **Local visual derivation** - `offset`, `position.y`, `render_priority`, `texture.region` calculated per-frame
- **Billboard preserved** - `billboard = 2` maintained for camera-facing behavior
- **Draw order via render_priority** - solves z-fighting without breaking billboard alignment

### Sprite Stacking Layers (Bottom to Top)

For Phase 2, we implement a simplified version focusing on core body parts:

| Layer | Content |
|-------|---------|
| 1 | Shadow (ground ellipse - separate system) |
| 2 | Base body |
| 3 | Chest / torso (includes linked arms) |
| 4 | Legs |
| 5 | Hands |
| 6 | Head / face |
| *(Future phases will expand to full 15-layer system)* |

### Character Systems

#### Player Character
- WASD movement + mouse aim
- Classless — no character class selection
- Stats: STR (carry weight, melee damage, HP), INT (mana, magic effectiveness), DEX (stamina, speed, accuracy)
- Skill-based progression (see `06-gameplay-systems.md`)
- **Equipment changes reflected via 4-way directional sprite system**
- Customizable face and hair at character creation
- Ghost state on death (see `06-gameplay-systems.md`)
- Hardcore mode toggle at character creation (permanent permadeath)

#### NPCs
- Patrol behavior within spawn zone
- Dialogue interaction (concise, no exposition dumps)
- Shop functionality (merchants)
- Quest-giver functionality
- Healer functionality (can resurrect ghosts — rare and valuable)
- Trainer functionality (skill training for money — very expensive)
- Government enforcers (police unlicensed Transmatalogy use — TBD)

#### Enemies
- Spawn zones with patrol paths
- Aggro system: detect player within radius, chase within patrol bounds
- Telegraphed attacks (wind-up → active hitbox → recovery, Souls-like)
- Loot drops on death (loot tables with randomization)
- Boss variants (larger, more complex patterns)
- **Thematic:** All enemies are creatures from the Underloom — demons, monsters, aberrations. The Veins are the accessible tunnels; the Underloom is the vast unknown beneath.

#### Mounts
- Tamed creatures that serve as combat companions
- Taming skill determines what can be tamed (higher skill = more dangerous mounts)
- Mounts fight alongside the player (no separate pet system)
- Mounts can be killed and looted by others
- Carry weight bonus while mounted
- Rendered as billboard sprites (same directional system as characters)
- Mounts require feeding/upkeep (TBD)

#### Companions (Later Goal)
- Player-recruited NPC allies (separate from mounts)
- Follow and fight alongside player
- Simple command system (follow, stay, attack target)

## Entity Component Breakdown

### Required Components
- `DirectionalSpriteStack` — 4-way directional sprite system with data-driven equipment
- `CollisionShape3D` — Hitbox/hurtbox
- `NavigationAgent3D` — Pathfinding
- `HealthComponent` — HP tracking
- `StateMachine` — Animation + behavior
- `StatsComponent` — STR/INT/DEX and derived values

### Optional Components
- `LootComponent` — Drop table
- `DialogueComponent` — Interaction
- `EquipmentComponent` — Equipment slot management (integrated with DirectionalSpriteStack)
- `SkillComponent` — Skill levels and XP
- `AggroComponent` — Enemy detection/aggro
- `GhostComponent` — Death state management
- `TamingComponent` — Mount taming data
- `FactionComponent` — Faction reputation tracking
- `MountComponent` — Mount-specific data (carry bonus, upkeep)

## Open Questions
- Final sprite resolution? (Experiment needed)
- How many styles per sprite sheet? (Determined by artist asset preparation)
- Exact Rect2i values for Left/Right/Away directions per sheet (Pending asset creation)
- First-person: show character body or just weapon/hands? (Currently hidden in first-person)
- How many enemy types at launch?
- Boss design complexity?
- Mount upkeep mechanics?

---
*See also:* `02-game-overview.md` | `06-gameplay-systems.md` | `08-art-direction.md`