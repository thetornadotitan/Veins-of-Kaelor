# UI/UX

## Goals

- Clean HUD that doesn't obscure the action
- Intuitive menus for inventory, map, crafting, skills
- Keyboard + mouse (web-first)
- Works in both first-person and third-person views
- Ghost state has distinct UI treatment

## HUD

### In-Game Display
- Health bar (player) — prominent, always visible
- Stamina bar — visible during/after stamina use
- Mana bar — visible during/after magic use
- Minimap (TBD — real-time or discovery-based?)
- Quick slot bar for consumables (4-8 slots)
- Damage numbers on hit (floating above entities)
- Status effect icons (poison, burn, buffs, debuffs)
- Interaction prompt (context-sensitive: "Press E to talk," "Press F to loot")
- Murder/criminal flag indicator (gray/red)

### Ghost HUD (Death State)
- Distinct visual filter (desaturated, ghostly overlay)
- Timer showing corpse decay remaining
- Directional indicator toward corpse
- Resurrection source indicator (hub, healer NPC, player healer)
- Cannot communicate — chat disabled
- Movement indicator (can pass through walls/doors)

### Dialogue
- Text box at bottom of screen (RPG style)
- Portrait on left side
- Concise text — no exposition dumps
- Choice prompts for player response (when applicable)
- Typewriter text effect (TBD)

## Menus

### Inventory
- Weight-based display with carry weight indicator
- Equipment slots on left (paper doll or slot grid)
- Bag inventory on right (grid view)
- Item tooltips on hover (stat comparison)
- Drag-and-drop equipping
- Sorting filters (type, weight, value)

### Character / Skills
- Current stats display (STR/INT/DEX)
- Skill list with current values and XP spending controls
- XP available to spend
- Skill gain progress toward next level-up
- Active effects/debuffs
- Character preview (sprite with current equipment — all 15 layers visible)

### Level-Up Screen
- Triggered when enough skill gains accumulated
- Shows 3 attribute slots to fill
- Each attribute shows bonus multiplier (+1 to +5) based on governing skill gains since last level
- Player freely allocates — no major/minor skill trap
- Confirmation required

### Magic / Spellbook
- List of known spells (acquired via scrolls)
- Spell details: circle, reagent cost, mana cost, description
- Spellbook can be lost on death (warning indicator)
- Casting interface (quick-cast from spellbook or quick slots)

### Map
- Fog of war / explored areas
- Player position marker
- Quest markers (active objectives)
- Building/location markers
- Dungeon entrance markers
- Zoom in/out

### Crafting
- Recipe list on left (filterable by skill)
- Materials required on right
- Craftable items highlighted
- Result preview (stats, quality tier)
- Crafting progress bar
- Tool durability indicator

### Quest Log
- Active quests list
- Objective descriptions
- Map markers for objectives
- Completed quest history

### Factions
- List of known factions
- Current reputation/standing
- Faction benefits/penalties
- Join/leave controls (TBD)

## Controls

### Keyboard + Mouse

#### Movement
| Key | Action |
|-----|--------|
| WASD | Movement |
| Shift | Sprint (costs stamina) |
| Space | Dodge/Roll (costs stamina) |
| Ctrl | Crouch (TBD) |

#### Camera
| Key | Action |
|-----|--------|
| Mouse | Look/aim |
| Scroll wheel | Zoom (FP/TP toggle at extremes) |
| V | Toggle first-person / third-person |

#### Combat
| Key | Action |
|-----|--------|
| Left click | Attack |
| Right click | Block/Parry |
| Middle click | Secondary attack (TBD) |
| 1-8 | Quick slot use |

#### Magic
| Key | Action |
|-----|--------|
| Q | Quick-cast last spell |
| B | Open spellbook |
| R | Cycle quick spells |

#### Interaction
| Key | Action |
|-----|--------|
| E | Interact (talk, loot, open) |
| Tab | Inventory |
| C | Character/Skills |
| M | Map |
| J | Quest Log |
| F1 | Spellbook |
| Escape | Pause menu |

### Ghost Controls
| Key | Action |
|-----|--------|
| WASD | Move (pass through walls) |
| E | Teleport to hub (for resurrection) |
| T | Teleport to corpse (if in range) |

### Controller (TBD — lower priority for web)
- Left stick: Movement
- Right stick: Look/aim
- Face buttons: Interact/dodge
- Triggers: Attack/block
- D-pad: Quick slots

## Open Questions
- How much screen real estate for HUD?
- Minimap: real-time or discovery-based?
- Colorblind/accessibility options?
- Localization support needed?
- Paper doll vs. slot grid for equipment display?
- Level-up: automatic on threshold or player-initiated?

---

*See also:* `06-gameplay-systems.md`
