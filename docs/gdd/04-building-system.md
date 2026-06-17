# Building System

## Status: BACKBURNERED

Player building is **not** a current focus. This document covers buildings as world objects placed by the dev team or procedural systems.

## Goals

- Provide 3D building structures as part of the world
- Keep geometry simple enough for 2D tiled textures
- Support seamless interior access via culling (preferred) or doorway transitions

## Core Concepts

### Building Placement
- Buildings placed by dev team or procedural generation
- No player building system (for now)
- Buildings are persistent world objects (saved with world state)

### Interiors (Priority: Seamless)
- **Preferred:** Interiors rendered in-place with aggressive culling (occlusion culling, portal culling, or manual visibility toggling). Player walks through a door and the interior is already there — just hidden until needed.
- **Fallback:** Doorway activation triggers a scene transition (load interior as separate area). Doorless transitions (walk over threshold) also acceptable.
- **Last resort:** Buildings are exteriors only.

### Building Pieces (For Dev/Procedural Use)
- **Walls** — Flat planes with tiled stone/wood/plaster textures
- **Floors** — Horizontal planes, tileable ground textures
- **Ceilings** — For interior spaces
- **Roofs** — Pitched or flat, simple geometry
- **Doors/Doorframes** — Transition points
- **Stairs/Ramps** — For multi-level structures
- **Furniture/Props** — Tables, chairs, crates (simple geometry + textures)

### Texturing
- Single tiled texture per piece type per material
- Texture atlas for all building materials
- No UV unwrap complexity — planar mapping only
- Optional: vertex coloring for variation

### Materials (TBD)
| Material | Use |
|----------|-----|
| Stone | Foundations, walls |
| Wood | Floors, rustic walls, furniture |
| Plaster | Interior walls |
| Metal | Reinforcement, decorative, hardware |
| Thatch | Roofs |
| Tile | Decorative floors/walls |

## Performance Considerations
- Merge static meshes for placed buildings
- Occlusion culling for interiors
- Limit polygon count per piece
- Visibility toggling for interior rooms

## Open Questions
- How many building templates at launch?
- Procedural placement rules?
- Interior culling approach feasibility in Godot web export?

---

*See also:* `03-world-generation.md` | `05-entities-characters.md` | `06-gameplay-systems.md`
