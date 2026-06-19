# Phase 1: Player Movement & P2P Multiplayer Connectivity

## Goal

Get a player character moving in a 3D environment and two players connected via P2P over localhost. This is the foundational vertical slice — everything else builds on top of this.

## Core Tenets

- **DRY** — No duplicated logic. Shared code lives in one place.
- **Clean Code** — Readable, well-named, small functions, clear responsibility.
- **KISS** — Simplest thing that works. No premature abstraction.
- **Data-First** — Configuration and game data in resources/JSON, not hardcoded.

---

## Step 1: Project Setup & Folder Structure

### 1.1 Scaffold the Godot project folder structure

```
res://
├── scenes/
│   ├── main/
│   │   └── main.tscn              # Entry point — boots into character/world select
│   ├── world/
│   │   └── world.tscn             # World scene — terrain, entities, game logic
│   ├── entities/
│   │   ├── player.tscn            # Player scene
│   │   └── npc_base.tscn          # Base NPC (for testing multiplayer)
│   └── ui/
│       ├── hud.tscn               # Minimal HUD (debug info)
│       └── main_menu.tscn         # Character select + connection UI
├── scripts/
│   ├── player/
│   │   ├── player_controller.gd   # Movement + input
│   │   └── camera_controller.gd   # FP/TP camera
│   ├── multiplayer/
│   │   ├── multiplayer_manager.gd # P2P connection lifecycle
│   │   └── network_spawner.gd     # Spawns players on remote peers
│   ├── world/
│   │   └── world_manager.gd       # World state, entity management
│   └── ui/
│       └── main_menu.gd           # Menu logic
├── assets/
│   ├── sprites/                    # Placeholder sprites
│   ├── textures/                   # Placeholder textures
│   └── audio/                      # Placeholder audio
└── data/
    └── (empty — for future JSON data files)
```

### 1.2 Verify Godot version and export templates

- Confirm Godot 4.3+ is installed.
- Install web export template (for later web testing).
- Test that the project opens and runs without errors.

**Deliverable:** Clean project structure, empty scenes created, project runs.

---

## Step 2: Basic Player Movement

### 2.1 Player scene (`player.tscn`)

```
Player (CharacterBody3D)
├── CollisionShape3D          # Capsule collision
├── Camera3D                  # Attached camera (for now — will split later)
└── MeshInstance3D            # Placeholder capsule mesh (visible to others)
```

### 2.2 Player controller (`player_controller.gd`)

```gdscript
class_name PlayerController
extends CharacterBody3D

## Movement speeds — data-driven, exported for tuning.
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_multiplier: float = 2.0

## Node references — assigned in _ready(), not hardcoded paths.
@onready var _camera: Camera3D = $Camera3D

func _physics_process(delta: float) -> void:
    _apply_gravity(delta)
    _handle_jump()
    _handle_movement()
    move_and_slide()

func _apply_gravity(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= ProjectSettings.get_setting(
            "physics/3d/default_gravity"
        ) * gravity_multiplier * delta

func _handle_jump() -> void:
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

func _handle_movement() -> void:
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
    if direction:
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed
    else:
        velocity.x = move_toward(velocity.x, 0, speed)
        velocity.z = move_toward(velocity.z, 0, speed)
```

### 2.3 Input map (`project.godot`)

Add input actions:
- `move_forward` → W
- `move_back` → S
- `move_left` → A
- `move_right` → D
- `sprint` → Shift
- `jump` → Space

### 2.4 Test: Single player movement

- Create a flat `World3D` scene with a `StaticBody3D` floor.
- Instance the player.
- Verify: WASD movement, sprint, jump, gravity all work.

**Deliverable:** Player can move and jump on a flat surface in first-person view.

---

## Step 3: Basic 3D Terrain

### 3.1 Simple test terrain

- Create a `MeshInstance3D` with a `PlaneMesh` (50×50 units) as the ground.
- Add a `CollisionShape3D` with a `BoxShape3D` matching the plane.
- Add a `DirectionalLight3D` and `WorldEnvironment` with a basic sky.
- Optionally: add a few `StaticBody3D` boxes as obstacles.

### 3.2 Test: Player on terrain

- Player can walk on the plane, collide with obstacles.
- No falling through the floor.

**Deliverable:** Player moves on a 3D surface with collision.

---

## Step 4: Multiplayer P2P — Signaling Server

### 4.1 Set up a local signaling server

Use Godot's reference WebSocket signaling server:

```
godot-demo-projects/networking/webrtc_signaling/
```

- Clone or copy the signaling server project.
- Run it locally (it's a Godot project itself, or can be run headless).
- Default port: `9080`.

```bash
# From the signaling server project directory:
godot --headless -- --server --port 9080
```

### 4.2 Verify signaling server is running

- Server logs should show it's listening on the configured port.
- Test with a simple WebSocket client if needed.

**Deliverable:** Signaling server running on `ws://127.0.0.1:9080`.

---

## Step 5: Multiplayer Manager

### 5.1 Multiplayer manager scene (`multiplayer_manager.tscn`)

An `Autoload` (singleton) that manages the P2P connection lifecycle.

### 5.2 Multiplayer manager script (`multiplayer_manager.gd`)

```gdscript
class_name MultiplayerManager
extends Node

## Signals for UI and game state.
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()

## Configuration — data-driven.
@export var signaling_url: String = "ws://127.0.0.1:9080"
@export var stun_server: String = "stun:stun.l.google.com:19302"

var _peer: WebRTCMultiplayerPeer = null
var _my_id: int = 0

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Host a new session. Returns host ID (1).
func host_game() -> Error:
    _peer = WebRTCMultiplayerPeer.new()
    var err := _peer.create_server()
    if err != OK:
        connection_failed.emit()
        return err
    multiplayer.multiplayer_peer = _peer
    _my_id = 1
    connection_succeeded.emit()
    return OK

## Join an existing session. Connects to host (ID 1).
func join_game() -> Error:
    _peer = WebRTCMultiplayerPeer.new()
    var err := _peer.create_client(1)
    if err != OK:
        connection_failed.emit()
        return err
    multiplayer.multiplayer_peer = _peer
    _my_id = _peer.get_unique_id()
    connection_succeeded.emit()
    return OK

func _on_peer_connected(peer_id: int) -> void:
    peer_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
    peer_disconnected.emit(peer_id)

func get_my_id() -> int:
    return _my_id

func is_host() -> bool:
    return _my_id == 1
```

### 5.3 Network spawner (`network_spawner.gd`)

A `MultiplayerSpawner` node in the world scene that spawns player scenes for each connected peer.

```gdscript
class_name NetworkSpawner
extends MultiplayerSpawner

@export var player_scene: PackedScene

func _ready() -> void:
    # Only the host spawns NPCs and world entities.
    # Each peer spawns their own player.
    if player_scene:
        add_spawnable_scene(player_scene.resource_path)
```

**Deliverable:** Singleton manages P2P connection. Two Godot instances can connect.

---

## Step 6: Player Spawning & Replication

### 6.1 Player scene with `MultiplayerSynchronizer`

Add a `MultiplayerSynchronizer` node to `player.tscn` that replicates:
- `position` (reliable)
- `rotation` (unreliable — high frequency, low importance)

### 6.2 World manager (`world_manager.gd`)

Manages which entities each peer is responsible for:

```gdscript
class_name WorldManager
extends Node

@export var player_scene: PackedScene

func _ready() -> void:
    MultiplayerManager.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
    # The spawner handles instantiation.
    # Each peer owns their own player instance.
    if multiplayer.is_server():
        print("Peer %d connected" % peer_id)
```

### 6.3 Spawn logic

- When a peer connects, the `MultiplayerSpawner` instantiates the player scene.
- Each peer has authority over their own player instance.
- The `MultiplayerSynchronizer` replicates position/rotation to all peers.

### 6.4 Test: Two players see each other

- Launch two Godot instances (or one instance + one exported build).
- Instance 1: Host.
- Instance 2: Join.
- Both should see a placeholder capsule for the other player.
- Moving in one instance should move the capsule in the other.

**Deliverable:** Two players connected over localhost, see each other's position.

---

## Step 7: Minimal UI

### 7.1 Main menu (`main_menu.tscn` + `main_menu.gd`)

Simple UI with:
- "Host" button → calls `MultiplayerManager.host_game()`
- "Join" button → calls `MultiplayerManager.join_game()`
- Status label — shows "Hosting...", "Connected", "Failed", etc.
- Debug label — shows peer count, my ID.

### 7.2 HUD (`hud.tscn`)

Minimal in-game HUD:
- Peer count
- My player ID
- Connection status
- FPS counter

### 7.3 Test: Full flow

1. Launch instance 1 → click "Host" → status shows "Hosting".
2. Launch instance 2 → click "Join" → status shows "Connected".
3. Both see each other's player capsules.
4. Movement is replicated.

**Deliverable:** Two players can host/join via UI and see each other move.

---

## Step 8: Iteration & Polish

### 8.1 Camera separation

Split the camera out of the player scene:
- `CameraController` as a separate node.
- Player body mesh is visible to others (third-person view).
- Camera follows the local player only.

### 8.2 Basic animation placeholder

- Add a simple `AnimationPlayer` to the player mesh.
- Idle animation (subtle bob) — just to confirm animation replication works.

### 8.3 Disconnect handling

- When a peer disconnects, their player instance is removed.
- UI updates peer count.

### 8.4 Test: Disconnect/reconnect

- Player 2 disconnects → their capsule disappears from Player 1's view.
- Player 2 reconnects → capsule reappears.

**Deliverable:** Clean disconnect/reconnect, camera separated, basic animation.

---

## Testing Checklist

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| T1 | Single player movement | WASD + sprint + jump work |
| T2 | Player on terrain | No falling, collision works |
| T3 | Signaling server runs | Server accepts WebSocket connections |
| T4 | Host creates session | Instance 1 hosts, status updates |
| T5 | Client joins session | Instance 2 joins, both see "Connected" |
| T6 | Player spawning | Both instances see 2 player capsules |
| T7 | Movement replication | Moving in P1 moves P2's capsule |
| T8 | Disconnect handling | P2 disconnects → capsule removed from P1 |
| T9 | Reconnect | P2 reconnects → capsule reappears |
| T10 | UI flow | Host/Join buttons work, status labels update |

---

## What This Does NOT Include (Future Phases)

- World generation / terrain mesh
- Character data persistence
- Combat system
- Inventory / equipment
- Crafting
- Quests
- Magic system
- Day/night cycle
- Weather
- Dungeons
- World editor
- Web export testing
- TURN server
- Character creation
- Sprite stacking
- Audio

---

## File Checklist

| File | Purpose | Status |
|------|---------|--------|
| `scenes/main/main.tscn` | Entry point | TODO |
| `scenes/world/world.tscn` | World scene | TODO |
| `scenes/entities/player.tscn` | Player scene | TODO |
| `scenes/ui/main_menu.tscn` | Connection UI | TODO |
| `scenes/ui/hud.tscn` | In-game HUD | TODO |
| `scripts/player/player_controller.gd` | Movement | TODO |
| `scripts/player/camera_controller.gd` | Camera | TODO |
| `scripts/multiplayer/multiplayer_manager.gd` | P2P lifecycle | TODO |
| `scripts/multiplayer/network_spawner.gd` | Player spawning | TODO |
| `scripts/world/world_manager.gd` | World state | TODO |
| `scripts/ui/main_menu.gd` | Menu logic | TODO |

---

*Plan version: 1.0 | Created: 2026-06-16 | Phase: 1 of ?*
