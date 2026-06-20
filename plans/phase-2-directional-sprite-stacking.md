# Phase 2: Directional Sprite Stacking & Equipment Lookups

## Goal

Extend the existing `player.tscn` Sprite3D stack into a **4-way directional pseudo-3D character** that displays the correct sprite frame based on the **local viewer's camera angle**. Add a **data‑driven equipment system** so that equipping a style (e.g. a shirt) can update all linked body parts (chest + arms) from a single sheet reference.

## Core Tenets

- **DRY** — One source of truth for sprite layouts, one script drives all directional updates.
- **Clean Code** — Small, testable helpers (angle → direction, style → region). No magic numbers in logic.
- **KISS** — Single Sprite3D per body part. Swap `region` and `texture` locally. No duplicate node trees.
- **Data‑First** — All sprite offsets, sizes, and style mappings live in a JSON/Resource file, not in code.

---

## How Directional Views Work

The Sprite3D stack currently uses `billboard = 2` (Billboard). The camera always sees the flat front of every sprite. To simulate a 3D character, each body part needs **4 directional frames**:

| Direction | Description |
|-----------|-------------|
| **Forward** | Character faces the camera |
| **Left**    | Character's left side to the camera |
| **Right**   | Character's right side to the camera |
| **Away**    | Character's back to the camera |

> **Note:** Plan originally mentioned 8 directions. Reduced to 4 to keep asset load manageable for a solo dev.

---

## Options Considered for Per‑Viewer Directional Sprites

Since the visible direction depends on **where the local camera is relative to the character**, each viewer may see a different frame.

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| **A** | Duplicate every body part ×4 (one node set per direction), toggle `visible` per viewer | Simple to reason about | Node bloat, painful sync, not DRY |
| **B** | Runtime AtlasTexture swap per viewer on one node per part | Fewer nodes | Requires unique AtlasTexture per viewer, heavy on memory |
| **C** | **Single Sprite3D per part. Every local client calculates the relative angle, looks up the current equipped style, and writes the correct `AtlasTexture.region`** | Minimal nodes, fully local, no network overhead for visuals, DRY | Requires one script to manage all parts |

**✅ Decision: Option C.**

Each client runs the same `DirectionalSpriteStack` script. It calculates the relative yaw angle from the **local active camera** to the character, picks a direction, looks up that player's equipped style, and updates each body part Sprite3D's `texture.region`.

**Why this is safe for multiplayer:** only `position`, `rotation`, and `equipped_styles` need to be replicated by `MultiplayerSynchronizer`. The actual visual frame is derived locally from that replicated state.

---

## Per‑Direction Visual Offsets & Position

Sprite sheets for different directions may have slightly different pivots, or a part may need to sit higher/lower/left/right depending on whether the character is facing forward, left, right, or away. For example, a side‑view arm sprite might need to drop by a pixel or two compared to the front‑view arm sprite.

Because the `Sprite3D` nodes are **purely visual children** of the `CharacterBody3D`, it is safe to adjust their `offset` and `position` (or specific axes like `position.y`) independently on every client. Each viewer sees their own local version of these transforms.

### What to sync vs. what to derive locally

| Property | Synced? | Source | Reason |
|----------|---------|--------|--------|
| `CharacterBody3D.position` | **Yes** | Network (owner) | Physics / gameplay position |
| `CharacterBody3D.rotation` | **Yes** | Network (owner) | World orientation |
| `Sprite3D.texture.region` | **No** | Local client | Derived from `equipped_styles` + camera angle |
| `Sprite3D.offset` | **No** | Local client | Derived from `equipped_styles` + camera angle |
| `Sprite3D.position` (per‑axis) | **No** | Local client | Visual‑only micro‑adjustments per direction |
| `Sprite3D.render_priority` | **No** | Local client | Derived from camera angle |

> **Rule:** Only the physics body (`CharacterBody3D`) needs network sync. Everything under it (visuals, offsets, render order) is a client‑side visual derivation.

---

## Data Architecture

### JSON / Resource Schema

Create `res://data/sprite_database.json` (or a `.tres` / custom Resource).

Regions are separated into three layers, each with a single responsibility:

- **`parts`** — pixel relationships between body pieces (offsets, sizes). **Defined once per sheet**, identical for all styles.
- **`world`** — world-space positioning per direction. **Defined once per sheet**, identical for all styles.
- **`styles`** — only the anchor region for each direction. **One `[x, y, w, h]` per style per direction** — the smallest possible data point.

Adding a new style means adding **4 numbers** (one anchor region per direction). Parts and world offsets never grow.

```json
{
  "human_chest": {
    "texture_path": "res://assets/sprites/human/chest.png",
    "parts": {
      "Chest":  { "px_offset": [0, 0],  "px_width": 16, "px_height": 12 },
      "L_Arm": { "px_offset": [-7, 0], "px_width": 8,  "px_height": 12 },
      "R_Arm": { "px_offset": [15, 0], "px_width": 8,  "px_height": 12 }
    },
    "world": {
      "forward": { "sprite_offset": [0, 0],   "y": 0 },
      "left":    { "sprite_offset": [?, ?],   "y": ? },
      "right":   { "sprite_offset": [?, ?],   "y": ? },
      "away":    { "sprite_offset": [?, ?],   "y": ? }
    },
    "styles": {
      "style_01": {
        "forward": [8, 0, 16, 12],
        "left":    [?, ?, ?, ?],
        "right":   [?, ?, ?, ?],
        "away":    [?, ?, ?, ?]
      },
      "style_02": {
        "forward": [?, ?, ?, ?],
        "left":    [?, ?, ?, ?],
        "right":   [?, ?, ?, ?],
        "away":    [?, ?, ?, ?]
      }
    }
  },
  "human_legs": {
    "texture_path": "res://assets/sprites/human/legs.png",
    "parts": { "L_Leg": { ... }, "R_Leg": { ... } },
    "world": { ... },
    "styles": { "style_01": { ... } }
  },
  "human_hands": {
    "texture_path": "res://assets/sprites/human/hands.png",
    "parts": { "L_Hand": { ... }, "R_Hand": { ... } },
    "world": { ... },
    "styles": { "style_01": { ... } }
  },
  "human_faces": {
    "texture_path": "res://assets/sprites/human/faces.png",
    "parts": { "Head": { ... } },
    "world": { ... },
    "styles": { "style_01": { ... } }
  }
}
```

**Size comparison for `human_chest` (8 sheet-level parts, 10 styles, 4 directions):**

| Old (quadratic) | New (separated) |
|---|---|
| 10 × 4 × 8 = 320 part entries | 8 part defs + 4 world defs + 40 anchor arrays = **52 entries** |

Adding a 10th style: **+4 numbers**, not +32.

### Why JSON over hard‑coded Resources?

- Artists can tweak coordinates without touching GDScript.
- Can be hot‑reloaded during development.
- Keeps all per‑part, per‑direction, per‑style offsets in one place.

### Godot Resource Wrappers (Optional but Recommended)

```gdscript
# part_def.gd — fixed px layout for one body piece (defined ONCE per sheet)
class_name PartDef
extends Resource

@export var px_offset: Vector2i  # offset from the direction‑anchor (pixels)
@export var px_width: int        # width of this piece in the atlas
@export var px_height: int       # height of this piece in the atlas

# world_def.gd — world‑space positioning per direction (defined ONCE per sheet)
class_name WorldDef
extends Resource

@export var sprite_offset: Vector2  # applied to Sprite3D.offset
@export var y: float                # added to Sprite3D.position.y

# sheet_data.gd — the root wrapper for one sprite sheet (.png)
class_name SheetData
extends Resource

@export var texture: Texture2D
@export var parts: Dictionary     # StringName -> PartDef
@export var world: Dictionary     # String -> WorldDef  (key: "forward","left","right","away")
@export var styles: Dictionary    # String -> Dictionary[String, Rect2i]  (style_name -> {direction: anchor})
```

A parser script `SpriteDatabaseLoader.gd` will read `sprite_database.json` at startup, build `SheetData` objects, and expose:

- **`get_sheet(sheet_id: String) -> SheetData`** — returns the full sheet wrapper.

At runtime, calling code (not the loader) computes the final values by combining the three sources:

1. **Anchor region** = `sheet.styles[style_name][direction]`  →  `Rect2i`
2. **Part pixel region** = `anchor.position + sheet.parts[part_name].px_offset`  with size from `sheet.parts[part_name].px_width/px_height`
3. **World positioning** = `sheet.world[direction].sprite_offset` and `.y`

No `computed_region` dictionary is returned — the `DirectionalSpriteStack` does the simple arithmetic directly. 

---

## Direction → Sprite Mapping

```
     Away (Back)
        ↑
Right ←   → Left
        ↓
     Forward (Front)
```

In `_process` (client‑side only):

```gdscript
func _update_direction(camera: Camera3D, target: Node3D) -> Direction:
    var to_target: Vector3 = (target.global_position - camera.global_position).normalized()
    var angle: float = atan2(to_target.x, to_target.z)  # Y‑axis rotation
    var yaw: float = wrapf(angle, 0, TAU)
    if yaw < PI/4 or yaw >= 7*PI/4:
        return Direction.FORWARD
    elif yaw < 3*PI/4:
        return Direction.LEFT
    elif yaw < 5*PI/4:
        return Direction.AWAY
    else:
        return Direction.RIGHT
```

> **Important:** The character's own `rotation.y` must be considered if the character model rotates in world space. The final angle should be `(camera_yaw - character_yaw)` relative to the character's local forward.

---

## Equipment / Equip System

### What happens when you "equip" an item?

1. The server (host) or authority changes the player's `equipped_styles` dictionary.
2. `MultiplayerSynchronizer` replicates that dictionary to all clients.
3. Every client sees the updated `equipped_styles` and recalculates sprite regions on the next frame.

### Equipped Styles Dictionary

```gdscript
@export var equipped_styles: Dictionary = {
    "chest": "default_shirt",
    "legs":  "default_pants",
    "hands": "default_gloves",
    "head":  "face_01"
}
```

### Example Flow: "Equip Blue Shirt"

1. Player clicks UI → emits `equip_item("human_chest", "blue_shirt")` RPC to server.
2. Server sets `equipped_styles["chest"] = "blue_shirt"`.
3. `MultiplayerSynchronizer` replicates the change.
4. All connected clients see `equipped_styles` change.
5. `DirectionalSpriteStack._process` on each client does:
   - Get `equipped_styles["chest"]` → `"blue_shirt"`
   - Resolve sheet ID via `SHEET_MAP["chest"]` → `"human_chest"`
   - Query `SpriteDatabase.get("human_chest").styles["blue_shirt"]`
   - For each affected part (`Chest`, `L_Arm`, `R_Arm`), get the correct region info for the current `Direction`.
   - Apply `texture.region`, `offset`, and vertical `position_y` as described below.

### DRY Principle Achievement

- **One texture per sheet loaded once** (cached in `PartData.texture`).
- **One update loop** calculates direction and applies regions for all visible players.
- **One JSON file** defines every style for every sheet. No per‑style code.

---

## Draw Order (Render Priority)

When a character faces left or right, the arm on the far side (behind the body) should render *before* the body, and the near arm *after*. Instead of changing `position.z` (which would alter the 3D transform and could break billboard alignment), use the `Sprite3D.render_priority` property.

```gdscript
enum RenderLayer { BACK = -1, BODY = 0, FRONT = 1 }

# In DirectionalSpriteStack:
func _update_render_order(direction: Direction) -> void:
    match direction:
        Direction.LEFT:
            _l_arm.render_priority = RenderLayer.BACK
            _chest.render_priority = RenderLayer.BODY
            _r_arm.render_priority = RenderLayer.FRONT
        Direction.RIGHT:
            _r_arm.render_priority = RenderLayer.BACK
            _chest.render_priority = RenderLayer.BODY
            _l_arm.render_priority = RenderLayer.FRONT
        _:
            # Forward / Away — reset all to BODY (0)
            _head.render_priority   = RenderLayer.BODY
            _chest.render_priority  = RenderLayer.BODY
            _l_arm.render_priority  = RenderLayer.BODY
            _r_arm.render_priority  = RenderLayer.BODY
            _l_leg.render_priority  = RenderLayer.BODY
            _r_leg.render_priority  = RenderLayer.BODY
            _l_hand.render_priority = RenderLayer.BODY
            _r_hand.render_priority = RenderLayer.BODY
```

This keeps the `Transform3D` untouched while solving z‑fighting and overdraw ordering.

---

## Networking Changes

### What to Replicate

| Property | Type | Authority | Notes |
|----------|------|-----------|-------|
| `position` | `Vector3` | Owner | Already done, keep it |
| `rotation` | `Vector3` | Owner | Already done, keep it |
| `equipped_styles` | `Dictionary` | Owner | New: must be in `MultiplayerSynchronizer` |

### What NOT to Replicate

- `AtlasTexture.region`
- `Sprite3D.texture`
- Any visual‑only state

These are derived purely from `equipped_styles` + local camera angle.

---

## Implementation Steps

### Step 1: Define the Sprite Database File

- Create `res://data/sprite_database.json`.
- For each sheet, define `parts` (once), `world` (once), and `styles` (anchor regions only — 4 arrays per style).
- Populate the known forward anchors for at least `style_01`. Use placeholder `?` for unknown direction anchors until art is ready.

### Step 2: Build `SpriteDatabaseLoader` (Autoload)

- Loads `sprite_database.json` at startup, builds `SheetData` objects.
- Exposes `get_sheet(sheet_id: String) -> SheetData`.

### Step 3: Create `DirectionalSpriteStack` Script

Attach to a new child node of Player (e.g. `VisualController`):

```gdscript
class_name DirectionalSpriteStack
extends Node3D

@onready var _head: Sprite3D   = %Head
@onready var _chest: Sprite3D  = %Chest
@onready var _l_leg: Sprite3D  = %L_Leg
@onready var _r_leg: Sprite3D  = %R_Leg
@onready var _l_arm: Sprite3D  = %L_Arm
@onready var _r_arm: Sprite3D  = %R_Arm
@onready var _l_hand: Sprite3D = %L_Hand
@onready var _r_hand: Sprite3D = %R_Hand

var _base_y: Dictionary = {}

# Maps style slot keys ("chest", "legs", "hands", "head") to sheet IDs
# ("human_chest", "human_legs", "human_hands", "human_faces").
# Keeping these separate avoids a key-mismatch bug in _apply_visuals.
const SHEET_MAP: Dictionary = {
    "chest": "human_chest",
    "legs": "human_legs",
    "hands": "human_hands",
    "head": "human_faces",
}

# Maps part names (from JSON) to Sprite3D node references.
# GDScript 4 `match` is a statement, not an expression — it cannot
# return a value inline, so we use a dictionary lookup instead.
var _part_nodes: Dictionary = {}

# Replicated from server
@export var equipped_styles: Dictionary = {
    "chest": "default",
    "legs": "default",
    "hands": "default",
    "head": "default"
}

func _ready() -> void:
    _part_nodes = {
        "Head":   _head,
        "Chest":  _chest,
        "L_Leg":  _l_leg,
        "R_Leg":  _r_leg,
        "L_Arm":  _l_arm,
        "R_Arm":  _r_arm,
        "L_Hand": _l_hand,
        "R_Hand": _r_hand,
    }
    _cache_base_y()

func _cache_base_y() -> void:
    for part_name in _part_nodes:
        var node: Sprite3D = _part_nodes[part_name]
        if node:
            _base_y[part_name] = node.position.y

func _process(_delta: float) -> void:
    var camera := get_viewport().get_camera_3d()
    if not camera:
        return
    var dir := _calculate_direction(camera)
    _apply_visuals(dir)
    _update_render_order(dir)

func _calculate_direction(camera: Camera3D) -> Direction:
    ... # yaw math as shown earlier

func _apply_visuals(dir: Direction) -> void:
    for slot in SHEET_MAP:
        var sheet_id: String = SHEET_MAP[slot]
        var sheet: SheetData = SpriteDatabaseLoader.get_sheet(sheet_id)
        var style := equipped_styles.get(slot, "default")
        var anchors: Dictionary = sheet.styles.get(style, {})
        var anchor_region: Rect2i = anchors.get(dir, Rect2i())
        var world: WorldDef = sheet.world.get(dir, WorldDef.new())

        for part_name in sheet.parts:
            var part: PartDef = sheet.parts[part_name]
            var sprite_node: Sprite3D = _part_nodes.get(part_name)
            if not sprite_node:
                continue
            var region_rect := Rect2(
                anchor_region.position + part.px_offset,
                Vector2(part.px_width, part.px_height)
            )
            sprite_node.texture.region = region_rect
            sprite_node.texture = sheet.texture
            sprite_node.offset = world.sprite_offset
            sprite_node.position.y = _base_y.get(part_name, 0.0) + world.y

func _update_render_order(dir: Direction) -> void:
    ... # render_priority adjustments for arm draw order
```

### Step 4: Update `player.tscn`

1. Add an empty `Node3D` child named `VisualController`.
2. Attach the `DirectionalSpriteStack` script.
3. Enable **unique_name_in_owner** on each Sprite3D (Head, Chest, L_Leg, R_Leg, L_Arm, R_Arm, L_Hand, R_Hand) so that `%Name` references resolve correctly.
4. Replace hard‑coded `AtlasTexture` sub‑resources with a simple placeholder `CompressedTexture2D` pointing at the same `.png` sheets. This keeps sprites visible in the editor while the script overwrites `texture` and `region` at runtime.

### Step 5: Add `equipped_styles` to `MultiplayerSynchronizer`

In `player.tscn`, the existing `MultiplayerSynchronizer` must watch:
- `position`, `rotation` (existing)
- `VisualController:equipped_styles` (new)

### Step 6: Hook Up an Equip Test

Temporarily add a debug key (e.g. `F2`) that cycles `equipped_styles["chest"]` through a few placeholder styles. Verify that:
- All clients see the same visual change.
- Directional offsets shift correctly for each direction.

### Step 7: GDD / Docs Update

Update the following documents to reflect the new decisions:
- **`docs/gdd/05-entities-characters.md`** – add the anchor/offset workflow, the `render_priority` layering system, and the `equipped_styles` dictionary as the visual source of truth.
- **`docs/gdd/08-art-direction.md`** – describe the 4‑way system (down from 8) and the per‑sheet explicit region mapping using anchors.

---

## Testing Checklist

| # | Test | Pass Criteria |
|---|------|---------------|
| T1 | Add `VisualController` to player | Scene opens without errors |
| T2 | Direction calculation | Moving camera around a player shows 4 distinct directional frames |
| T3 | Equip style (single player) | Changing `equipped_styles["chest"]` updates chest + both arms simultaneously |
| T4 | Style data from JSON | Removing `sprite_database.json` causes a clear error; valid JSON loads on startup |
| T5 | Multiplayer sync | Client A equips item; Client B sees the new shirt + arms |
| T6 | Direction per viewer | Two players (A and B) stand apart; A and B each see B facing the correct direction relative to their own camera |
| T7 | Render priority | Left/right views show back arm behind body, front arm in front (no clipping), without changing `transform` |
| T8 | Billboard preserved | Sprites still face the camera (`billboard = 2`) in all directions |
| T9 | Offset per direction | Verify that sprites shift correctly (offset/X/Y) for each direction using the anchor/offset system |

---

## Open Questions — Answered

| # | Question | Answer | Impact |
|---|----------|--------|--------|
| 1 | Do regions follow a uniform grid? | **No.** Each sheet has a different layout. Chest is irregular because it includes arms. Faces are uniform. JSON must define regions explicitly per style, per direction, per part. | Schema is flat (no grid math), just `region` arrays. |
| 2 | Why does chest include arms? | Intentional grouping. Chest + arms belong to a "clothing" slot. Later expansion will add overlay layers (armor, jackets, etc.). Arms are locked to the chest style. | One `human_chest` entry in JSON with `affected_parts: ["Chest", "L_Arm", "R_Arm"]`. |
| 3 | Style names? | Placeholder names for now: `style_01`, `style_02`, etc. | JSON keys are generic; easy to rename later. |
| 4 | Arm link behavior? | Arms are **locked** to their chest style. No mixing long‑sleeve shirt with bare arms, for now. | Simplifies data architecture. Future phase can split if needed. |
| 5 | First‑person or third‑person? | **First‑person now, third‑person planned.** `DirectionalSpriteStack` runs on all instances; local player's sprites are hidden via visibility when in first‑person. No early‑out needed — the system is camera‑relative and works identically for any viewer angle. | Third‑person support is a camera change, not a visual‑system change. |

### Remaining Blockers for Implementation

1. **Exact `Rect2i` values for Left, Right, and Away directions** for each sheet:
   - `chest.png`: chest + L_Arm + R_Arm
   - `legs.png`: L_Leg + R_Leg
   - `hands.png`: L_Hand + R_Hand
   - `faces.png`: Head
2. **Number of styles per sheet:** How many distinct clothing options exist in each sprite sheet? (You mentioned it can be calculated from the grouping — please confirm for chest, legs, hands, faces.)

---

## What This Does NOT Include (Future Phases)

- Animation (idle/walk frame cycling) — sprites are currently static frames.
- 8‑directional upgrade.
- Third‑person camera mode (the visual system already supports it; camera logic is separate).
- Color/tint overlays (dyeing equipment).
- Overhead nameplate / health bar UI.
- Complex layering (capes, backpacks behind body).
- VFX (sparks, auras).

---

## File Checklist

| File | Purpose | Status |
|------|---------|--------|
| `data/sprite_database.json`                         | Central atlas metadata — `parts`, `world`, `styles` per sheet | TODO |
| `scripts/player/directional_sprite_stack.gd`        | Main script: angle calc, region calc from anchor+px_offset, render priority | TODO |
| `scripts/data/sprite_database_loader.gd`            | JSON → `SheetData` objects, Autoload | TODO |
| `scripts/data/part_def.gd`                          | Resource: px_offset, px_width, px_height for one body piece | TODO |
| `scripts/data/world_def.gd`                         | Resource: sprite_offset, y for one direction | TODO |
| `scripts/data/sheet_data.gd`                        | Resource: texture + parts + world + styles for one sprite sheet | TODO |
| `scenes/entities/player.tscn`                       | Add `VisualController` node, update Sprite3D setup | TODO |

---

*Plan version: 1.1 | Created: 2026‑06‑19 | Phase: 2*
