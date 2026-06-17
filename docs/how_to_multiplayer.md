# How to Multiplayer – Godot 4.6 Walkthrough

> **Purpose** – This guide is written for developers who have never touched Godot's multiplayer API before. It explains every concept you need to make a functional P2P or client-server game, shows the **exact** syntax for the `@rpc` annotation, and lists the most common pitfalls with fixes.

---

## 1. Overview of Godot 4.6 Networking

| Component | What it does | Where to find it |
|----------|--------------|------------------|
| **Signaling server** | Simple WebSocket server that exchanges ICE candidates and SDP offers/answers. | `scripts/multiplayer/signaling_server.gd` (runs on localhost by default on port 9080). |
| **WebRTCMultiplayerPeer** | High-level multiplayer wrapper that turns the WebRTC data channels into a `MultiplayerAPI`. | `WebRTCMultiplayerPeer` class – <https://docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html> |
| **Peer IDs** | Each connected client receives a unique integer ID from the signaling server (host = 1, first client = 2, …). | `multiplayer.get_unique_id()` – works after the connection is established. |
| **Authority** | The node that owns the simulation of an object (usually the host for that object). | Set via `node.set_multiplayer_authority(peer_id)`. |

The architecture used in this project is a **full-mesh P2P**: every peer runs its own `WebRTCMultiplayerPeer` and directly exchanges ICE candidates with every other peer after the initial signaling step.

---

## 2. Setting Up the Signaling Server (already in the repo)

```gdscript
# scripts/multiplayer/signaling_server.gd – minimal WebSocket signaling server
class_name SignalingServer
extends Node
# … (implementation omitted – see the file for details) …
```

Run it head-less with:

```
godot --headless -- --server --port 9080
```

The `MultiplayerManager` will automatically start an instance when you press **Host** or **Join** in the UI.

---

## 3. Spawning Players & Assigning Authority

`WorldManager.gd` (attached to `scenes/world/world.tscn`) is responsible for creating a `Player` scene for each connected peer.

```gdscript
func _spawn_player(peer_id: int) -> void:
    if _players.get_node_or_null(_player_name(peer_id)):
        return
    var player: Node3D = player_scene.instantiate()
    player.name = _player_name(peer_id)
    # <─ IMPORTANT – give the node the correct authority
    player.set_multiplayer_authority(peer_id)
    _players.add_child(player)
    print("[WorldManager] Spawned player %d" % peer_id)
```

- **Never** forget `set_multiplayer_authority(peer_id)`. Without it, the node will never receive `is_multiplayer_authority() == true` on the owning client, so it will not send its state.
- The host (ID 1) spawns itself immediately in `_ready()`. Clients wait for the `peer_connected` signal.

---

## 4. The `@rpc` Annotation – The New Way to Declare Remote Calls

Godot 4 replaced the old `remote`, `master`, `puppet` keywords with a **single** `@rpc` decorator. The decorator takes **string literals** (quoted) for each option; the order does **not** matter.

### 4.1 Syntax

```gdscript
@rpc("any_peer", "unreliable")
func my_rpc(arg1: int, arg2: String) -> void:
    # code runs on the remote peer that called it
    pass
```

| Parameter | Meaning | Typical values |
|-----------|---------|----------------|
| `"any_peer"` | Any connected client may invoke the RPC. | `"any_peer"` |
| `"authority"` | Only the node's authority can call the function. Default behaviour. | `"authority"` |
| `"call_local"` | Execute the function **locally** on the caller **and** remotely. Useful for effects that the caller should also see (e.g., a gun flash). | `"call_local"` |
| `"reliable"` | Guarantees delivery and ordering (default if omitted). | `"reliable"` |
| `"unreliable"` | No delivery guarantee – best for high-frequency state (position, rotation). | `"unreliable"` |
| `"unreliable_ordered"` | Unreliable but preserves order of packets on the same channel. | `"unreliable_ordered"` |
| **Channel number** | Integer (0-31) specifying a separate transport channel. | `1`, `2`, … |

> **Important:** In Godot 4.6 the parameters must be **quoted strings**. Using the bare identifier (`any_peer`) triggers the parser error you saw earlier.

### 4.2 Call Variants

- `rpc("method_name", args…)` – uses the annotation-defined mode (reliable/unreliable).
- `rpc_id(peer_id, "method_name", args…)` – explicitly target a single peer.
- `rpc_config("method_name", args…, "reliable")` – overrides the mode for a single call (rarely needed).

---

## 5. Example – Syncing a Player's Transform Using RPCs

Below is a **complete** `player_controller.gd` ready to copy into your project.

```gdscript
class_name PlayerController
extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_multiplier: float = 2.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D

# ---------------------------------------------------------------------
# 1. Enable physics only on the authority (the peer that owns this node).
# ---------------------------------------------------------------------
func _ready() -> void:
    set_physics_process(is_multiplayer_authority())

# ---------------------------------------------------------------------
# 2. Main loop – movement + broadcast when we are the authority.
# ---------------------------------------------------------------------
func _physics_process(delta: float) -> void:
    _apply_gravity(delta)
    _handle_jump()
    _handle_movement()
    move_and_slide()

    # -----------------------------------------------------------------
    # Only the authority sends its state. The RPC is declared "any_peer"
    # and "unreliable" – perfect for frequent transform updates.
    # -----------------------------------------------------------------
    if is_multiplayer_authority():
        rpc("sync_transform", global_transform.origin, rotation.y)

# ---------------------------------------------------------------------
# 3. Remote function that other peers call to update the visual state.
#    It runs on **every** peer, but early-out on the authority to avoid
#    overwriting local input.
# ---------------------------------------------------------------------
@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, rot_y: float) -> void:
    if not is_multiplayer_authority():
        global_transform.origin = pos
        rotation.y = rot_y

# ---------------------------------------------------------------------
# 4. Helper functions – unchanged from the original implementation.
# ---------------------------------------------------------------------
func _apply_gravity(delta: float) -> void:
    if not is_on_floor():
        var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
        velocity.y -= g * gravity_multiplier * delta

func _handle_jump() -> void:
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

func _handle_movement() -> void:
    var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var camera_yaw: float = 0.0
    var pivot = get_node_or_null("CameraPivot")
    if pivot:
        camera_yaw = pivot.rotation.y
    var forward = Vector3(0, 0, -1).rotated(Vector3.UP, camera_yaw)
    var right   = Vector3(1, 0, 0).rotated(Vector3.UP, camera_yaw)
    var direction = (-forward * input_dir.y + right * input_dir.x).normalized()
    var speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
    if direction.length() > 0.1:
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed
        if _mesh:
            _mesh.rotation.y = atan2(direction.x, direction.z) + camera_yaw
    else:
        velocity.x = move_toward(velocity.x, 0, speed)
        velocity.z = move_toward(velocity.z, 0, speed)
```

### Why This Works

1. **Authority check** – `set_physics_process(is_multiplayer_authority())` ensures only the owning client runs the physics code.
2. **`rpc("sync_transform", …)`** automatically uses the mode defined in the annotation (`unreliable`). No need for the deprecated `rpc_unreliable()`.
3. **`@rpc("any_peer", "unreliable")`** makes the function callable by any client, and the transport is unreliable (fast, low latency).
4. The receiver skips the update when it *is* the authority (`if not is_multiplayer_authority():`) – otherwise the local player would constantly overwrite its own movement.

---

## 6. Optional – Using `MultiplayerSynchronizer` & `SceneReplicationConfig`

If you have many properties to sync (health, ammo, custom state) you can let Godot handle the dirty-checking for you.

### 6.1 Creating the Config in Code (no editor UI needed)

```gdscript
var sync = MultiplayerSynchronizer.new()
add_child(sync)
sync.root_path = NodePath(".")   # sync the node this script is attached to

var cfg = SceneReplicationConfig.new()
# Add any property you want to replicate. The NodePath is relative to the root_path.
cfg.add_property("transform")          # position + rotation + scale
cfg.add_property("health")
cfg.add_property("ammo")
sync.replication_config = cfg
```

### 6.2 How It Works Internally

- **`SceneReplicationConfig`** stores a list of `NodePath`s.
- On each tick the `MultiplayerSynchronizer` checks those properties, builds a delta packet, and sends it using the mode defined on the RPC that *calls* the synchronizer internally (you don't call it directly).
- When the packet arrives, the synchronizer writes the values back to the target node.

> **Caution** – The synchronizer will **only** work if the node has a valid authority set **before** the synchronizer is added to the scene tree. Otherwise you will see errors like `"_get_prop_target: Node 'transform' not found"` or `_send_sync` warnings.

---

## 7. Common Pitfalls & Quick-Fix Cheat-Sheet

| Symptom | Typical cause | Fix (one-liner) |
|---------|---------------|-----------------|
| `Invalid call. Nonexistent function 'create_answer'` | Manually calling `create_answer()` on a `WebRTCLibPeerConnection`. | **Remove** the call – the answer is generated automatically after `set_remote_description()`. |
| `_send_sync: Condition "!sync \|\| !sync->get_replication_config_ptr()"` | `MultiplayerSynchronizer` exists but has no `replication_config`. | Either **delete** the synchronizer or assign a proper `SceneReplicationConfig` (see §6). |
| `Parser Error: Identifier "any_peer" not declared` | Using the old syntax `@rpc(any_peer, ...)` without quotes. | Use **quoted strings**: `@rpc("any_peer", "unreliable")`. |
| `Function "rpc_unreliable()" not found` | Godot 4 merged `rpc_unreliable` into `rpc()`. | Call `rpc("method", …)` and set the mode in the annotation. |
| `Property '.' not found` when adding a property to `SceneReplicationConfig` | Passing the root node (`"."`) instead of an actual property path. | Use concrete paths like `"transform"`, `"health"`, or `"/root/Player:transform"`. |
| `multiplayer.get_unique_id() == 0` after connection | Peer never received an **ID** from the signaling server. | Ensure the signaling server sends an `ID` message and that `MultiplayerManager` processes it (see `multiplayer_manager.gd`). |
| `ERR_INVALID_DATA` in `MultiplayerSynchronizer::get_state` | The RPC tried to access a property that does not exist on the node. | Verify the property name matches exactly (case-sensitive) and that the node actually has that property. |

### Debugging Tips

- **Print the sender**: Inside any RPC, `multiplayer.get_remote_sender_id()` tells you who called it.
- **Authority logs**: `print("Authority: ", get_multiplayer_authority())` in `_ready()` helps confirm IDs.
- **Network stats**: `MultiplayerAPI.get_packet_peer()` can be used to inspect raw packets if needed.
- **Enable verbose output** in the project settings → `Network > Verbose RPC` for detailed logs.

---

## 8. Performance & Best Practices

| Guidance | Reason |
|----------|--------|
| Use **unreliable** for frequently-updated state (position, rotation). | Lower latency, packet loss is tolerable – the next packet will correct it. |
| Use **reliable** for gameplay-critical commands (damage, item pickup). | Guarantees delivery, prevents desynchronization. |
| Keep RPC payloads **small** – avoid sending whole `Transform` objects; send only the components you need (e.g., `origin` and `rotation.y`). |
| Group unrelated data into **different RPCs** or **different channels** to avoid one slow reliable call blocking many fast unreliable updates. |
| Avoid calling RPCs inside tight loops; let the engine's `process` or `physics_process` drive the rate (≈60 Hz). |

---

## 9. Reference Links (official & community)

- **High-level Multiplayer tutorial** – <https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html>
- **`@rpc` annotation reference** – <https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#rpc-annotation>
- **`MultiplayerSynchronizer` class** – <https://docs.godotengine.org/en/stable/classes/class_multiplayersynchronizer.html>
- **`SceneReplicationConfig` class** – <https://docs.godotengine.org/en/stable/classes/class_scenereplicationconfig.html>
- **WebRTC multiplayer overview** – <https://docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html>
- **Blog post about RPC syntax change (Godot 4.0)** – <https://godotengine.org/article/multiplayer-changes-godot-4-0-report-2/>
- **Godot 4.6 release notes** – <https://godotengine.org/article/godot-4-6-release-notes>
- **Community Q&A about missing `any_peer`** – <https://github.com/godotengine/godot/issues/80717>

---

## 10. TL;DR Checklist for Adding a New Networked Object

1. **Create the scene** (e.g., `enemy.tscn`).
2. **Add the node** to the world with `instance()`.
3. **Call `set_multiplayer_authority(peer_id)`** on the new node.
4. **Write movement / logic code** inside `if is_multiplayer_authority():` blocks.
5. **Expose the state you want to sync** via an `@rpc` function (unreliable for position, reliable for actions).
6. **Optional:** attach a `MultiplayerSynchronizer` and a `SceneReplicationConfig` if you have many properties.
7. **Test** with two instances (host + client) and check the console for any `_send_sync` warnings.

Follow these steps and you'll have a robust, future-proof multiplayer implementation.

---

*Document generated on 2026-06-17 for the 2-player P2P prototype.*
