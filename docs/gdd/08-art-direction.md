# Art Direction

## Visual Style

**"Pixel Sprites in a Polygon World"**

- 2D RPG Maker–style sprites for all characters and entities
- Simple 3D geometry for terrain, buildings, and props
- 2D tiled textures applied to 3D surfaces (no complex UV work)
- Bright, readable color palette with high contrast between biomes
- Works in both first-person (immersive) and third-person (showcase sprites)
- 15-layer sprite stacking for equipment visualization

## Sprite Guidelines

### Characters
- Sprite size: TBD (experiment with 64×64 or 128×128 per frame)
- 8-directional, head-on perspective (compatible with FP/TP swap)
- Animation states: idle, walk, run, melee attack, ranged attack, spell cast, hurt, death, block, dodge/roll
- Equipment variations via **15-layer sprite stacking**
- Shadow: separate sprite below character (ellipse)
- Customizable: face, hair, skin tone at character creation

### Sprite Stacking Layers (Bottom to Top)
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

- Each equipment slot has its own sprite sheet matching the base animation frames
- All layers must align pixel-perfectly across all 8 directions and all animation frames
- **Production concern:** N equipment items × 15 layers × 8 directions × M frames = large art burden. AI generation may help but consistency is critical.

### Enemies
- Same sprite guidelines as characters
- Bosses may be larger (scaled up 1.5×–2×)
- Visual telegraph for attacks (wind-up flash, glow, stance change)
- Death animation with loot drop visual

### Ghost Sprites
- Desaturated / blue-tinted version of character sprite
- Semi-transparent
- No equipment visible (or ghostly outlines only)
- Distinct visual filter to clearly communicate death state

### Props and Items
- Small sprite sheets (32×32 or 64×64)
- Inventory icons (32×32)
- Consistent perspective across all assets
- Items rendered as sprites in world, 3D models in inventory (TBD)

## Building Textures

### Style
- Seamable/tileable textures
- Resolution: 32×32 or 64×64 tiles
- Flat color + simple detail (no normal maps initially)
- One texture per material: stone, wood, plaster, metal, thatch, tile

### Texture List
| Material | Use |
|----------|-----|
| Stone | Foundations, walls |
| Wood | Floors, rustic walls, furniture |
| Plaster | Interior walls |
| Metal | Reinforcement, hardware, decorative |
| Thatch | Roofs |
| Tile | Decorative floors/walls |

## Terrain Textures

- Vertex coloring for biome blending (preferred for smooth transitions)
- Or tiled terrain textures per biome (simpler but harder blending)
- Simple, readable, high contrast between zones
- Minimum set: grass, dirt, sand, snow, stone, water

## Color Palette

| Biome | Primary | Secondary | Accent |
|-------|---------|-----------|--------|
| Plains | Green | Brown | Gold |
| Forest | Dark green | Brown | Red |
| Mountains | Grey | White | Cyan |
| Swamp | Olive | Teal | Yellow |
| Desert | Tan | Orange | Red |
| Tundra | White | Light blue | Purple |

## Day/Night Visual Treatment
- Day: bright, saturated, warm lighting
- Night: dark, desaturated, cool blue/moonlight
- Dawn/dusk: warm orange/purple transition
- Interior lighting: torch/firelight warmth

## Weather Visual Treatment
- Rain: particle overlay, wet surface reflections, puddle effects
- Snow: particle overlay, white accumulation on surfaces
- Fog: reduced visibility, atmospheric haze
- Overcast: diffused lighting, no sharp shadows

## Inspiration
- **RPG Maker series** — Sprite aesthetic, top-down RPG mechanics
- **Ultima Online** — World design, skill system, death mechanics, crafting
- **Dark Souls** — Combat feel, telegraphing, punishment/reward loop
- **Elder Scrolls (Morrowind/Oblivion/Skyrim)** — First/third person swap, open world, equipment slots
- **Doom / Heretic / DUSK** — Boomer shooter aesthetic, fast combat
- **Tactics Ogre / FFT** — Top-down tactical presentation
- **Hyper Light Drifter** — Top-down action with pixel art

## Open Questions
- Final sprite resolution? (Needs experimentation — critical for web performance)
- Color palette finalized?
- Normal/specular maps for 3D surfaces or pure diffuse?
- Prop detail level (simple cubes with textures vs. modeled)?
- AI-generated art pipeline feasibility? (Consistency across 15 layers × 8 directions × N frames is the challenge)
- Ghost visual treatment finalized?

---

*See also:* `05-entities-characters.md` | `04-building-system.md`
