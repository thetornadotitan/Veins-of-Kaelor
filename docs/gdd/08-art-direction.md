# Art Direction

## Visual Style

**"Pixel Sprites in a Polygon World"**

- 2D RPG Maker–style sprites for all characters and entities
- Simple 3D geometry for terrain, buildings, and props
- 2D tiled textures applied to 3D surfaces (no complex UV work)
- Bright, readable color palette with high contrast between biomes
- Works in both first-person (immersive) and third-person (showcase sprites)
- **4-way directional pseudo-3D characters** (reduced from 8-way for solo-dev scope)
- 15-layer sprite stacking for equipment visualization (long-term goal)

## Sprite Guidelines

### Characters
- Sprite size: TBD (experiment with 64×64 or 128×128 per frame)
- **4-directional, head-on perspective** (forward, left, right, away) - compatible with first/third-person swap
- Animation states: idle, walk, run, melee attack, ranged attack, spell cast, hurt, death, block, dodge/roll
- **Equipment variations via data-driven sprite system** (replaces 15-layer sprite stacking for Phase 2)
- Shadow: separate sprite below character (ellipse)
- Customizable: face, hair, skin tone at character creation

### 4-Way Directional System (Phase 2)
To simulate 3D characters with 2D sprites, each body part uses 4 directional frames based on viewer's camera angle:

| Direction | Description |
|-----------|-------------|
| **Forward** | Character faces the camera |
| **Left**    | Character's left side to the camera |
| **Right**   | Character's right side to the camera |
| **Away**    | Character's back to the camera |

**Implementation:** Single Sprite3D per body part. Client calculates relative angle from camera to character, determines direction, looks up equipped style, and updates:
- `texture.region` (from atlas)
- `offset` (world-space positioning)
- `position.y` (vertical adjustment)
- `render_priority` (draw order for arm layering)

### Data-Driven Equipment Architecture
Instead of quadratic data growth, we use a three-layer separation:

#### 1. Parts Definition (per sheet, shared by all styles)
Pixel-level relationships between body pieces - defined once, never duplicated per style:
```json
"parts": {
  "Chest":  { "px_offset": [0, 0],  "px_width": 16, "px_height": 12 },
  "L_Arm":  { "px_offset": [-7, 0], "px_width": 8,  "px_height": 12 },
  "R_Arm":  { "px_offset": [15, 0], "px_width": 8,  "px_height": 12 }
}
```

#### 2. World Positioning (per sheet, shared by all styles)
World-space offsets per direction - defined once:
```json
"world": {
  "forward": { "sprite_offset": [0, 0], "y": 0 },
  "left":    { "sprite_offset": [0, 0], "y": 0 },
  "right":   { "sprite_offset": [0, 0], "y": 0 },
  "away":    { "sprite_offset": [0, 0], "y": 0 }
}
```

#### 3. Styles (per sheet, minimal data)
Only anchor regions needed - one [x, y, w, h] per style per direction:
```json
"styles": {
  "style_01": {
    "forward": [8, 0, 16, 12],
    "left":    [8, 0, 16, 12],
    "right":   [8, 0, 16, 12],
    "away":    [8, 0, 16, 12]
  }
}
```

**Adding a new style:** Requires only 4 numbers (one anchor per direction), not N×4×M where N=parts, M=directions.

### Equipment Slot Grouping
For Phase 2, certain body parts are locked together to simplify data architecture:
- **Chest slot:** Controls Chest, L_Arm, R_Arm (all change together when equipping clothing)
- **Legs slot:** Controls L_Leg, R_Leg
- **Hands slot:** Controls L_Hand, R_Hand  
- **Head slot:** Controls Head

This means equipping "blue_shirt" updates chest + both arms simultaneously from a single style reference.

### Sprite Sheet Layouts
Each sprite sheet contains all directional frames for its parts arranged in an artist-defined layout (not necessarily a uniform grid). The JSON database explicitly defines:
- Texture path
- Parts (px_offset, px_width, px_height per part)
- World positioning (sprite_offset, y per direction)
- Styles (anchor [x,y,w,h] per style per direction)

Artists define regions directly in JSON without conforming to a grid, enabling irregular layouts like chests that include arms.

### Enemies
- Same sprite guidelines as characters (4-way directional, data-driven equipment)
- Bosses may be larger (scaled up 1.5×–2×)
- Visual telegraph for attacks (wind-up flash, glow, stance change)
- Death animation with loot drop visual

### Ghost Sprites
- Desaturated / blue-tinted version of character sprite
- Semi-transparent
- Equipment visible (tinted) or ghostly outlines only (TBD)
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
- AI-generated art pipeline feasibility? (Consistency across 4 directions × N styles is the challenge)
- Ghost visual treatment finalized?
- Exact Rect2i values for Left/Right/Away directions per chest/legs/hands/faces sheets (Pending asset creation)

---
*See also:* `05-entities-characters.md` | `04-building-system.md`