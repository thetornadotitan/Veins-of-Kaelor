# River Generation (Follow-Up Plan)

**Depends on**: `plans/water-and-terrain-overhaul.md` (lakes, ocean, depth system must exist first)

## Status: DEFERRED

This is a research placeholder. Implementation begins after the water/terrain overhaul is complete.

---

## Research Notes

### Source Placement
- River sources should emerge from mountain peaks and high-elevation basins
- Use **blue noise sampling** on high-elevation terrain to pick source points with good spatial distribution
- Source count: parameterized (e.g., 15-30 rivers per world)

### Path Generation: Gradient Descent
- From each source, trace steepest downhill path across the heightmap
- This is purely local: at each step, sample neighboring heights, pick the lowest neighbor
- Paths terminate when they reach: (a) ocean water level, (b) a lake, or (c) a dead-end basin (becomes a lake)
- Step size: half a heightmap cell (~0.5 world units) for smooth curves

### Drainage Area & Width
- For each river cell, compute upstream drainage area (how many source cells flow into it)
- River width is proportional to `sqrt(drainage_area)`
- Minimum width: 1 unit. Maximum: ~6 units for major rivers near the coast.

### River Merging
- When two gradient descent paths converge, they merge into one wider river
- Track which rivers merge to avoid duplicate paths

### Lake Connection
- Rivers that terminate at a lake basin fill that basin (it becomes a lake with an inflow river)
- Lakes at their rim height with an outflow river to the ocean form complete hydrological networks
- Not all lakes need outflow — some are endorheic (closed basins)

### Rendering
- River mesh: thin `ArrayMesh` strip following the gradient descent path
- Place at terrain height (rivers are ON the terrain, not above it like ocean/lake planes)
- Shader: animated UV scroll for flow effect, color varies by width/depth
- Rivers should NOT use a water plane — they're geometry on the terrain surface
- Could also be rendered via decals on the terrain mesh

### Data Storage
- River paths stored as arrays of Vector3 points in world data
- Generated during world generation pipeline (after heightmap + lake detection)

### Performance
- River meshes are static once generated — no per-frame updates
- Load/unload with chunks (river segments per chunk)
- Total river geometry should be modest: ~15 rivers × ~200m average length × ~2-6 width = small triangle count

---

## Open Questions
- River rapids / waterfalls at elevation changes?
- River interaction with player (wading, swimming, fishing)?
- Seasonal river variation (wider in spring)?
- Bridge building across rivers?
- How rivers interact with torus wrapping (rivers near world edge flowing to other side)
