# Audio

## Goals

- Fantasy soundtrack matching the world's tone
- Punchy, Souls-like combat SFX with weight and impact
- Ambient world audio for immersion
- Magic system audio (casting, reagents, enchanting)
- Ghost state audio treatment
- Web export compatible (no heavy audio processing)

## Music

### Style (TBD)
- Fantasy orchestral with dark undertones
- Per-biome ambient tracks
- Combat tracks per encounter type
- Exploration music that doesn't fatigue over long sessions
- Ghost/death state music (somber, ethereal)

### Tracks Needed
| Track | Use |
|-------|-----|
| Main Theme | Title screen |
| Overworld | Default exploration |
| Biome tracks (×4-6) | Per-biome ambience |
| Combat (standard) | Standard fights |
| Combat (boss) | Boss encounters |
| Dungeon | Interior/exploration |
| Ghost/Death | Death state |
| Crafting | Crafting menu |
| Hub/Safe Area | Resurrection hub |
| Day variant | Daytime exploration |
| Night variant | Nighttime exploration |
| (TBD) | (TBD) |

## Sound Effects

### Combat
- Melee swing (whoosh)
- Melee impact (hit + damage variation by material)
- Ranged launch (bow, crossbow, magic projectile)
- Ranged impact
- Enemy hit
- Player hit
- Death/destruction
- Block (shield/parry)
- Dodge/roll
- Critical hit
- Status effect application

### Magic
- Spell cast (per school/type — fire, ice, lightning, healing, etc.)
- Spell impact
- Reagent consumption (bottle break, powder scatter)
- Enchantment (mysterious hum, sparkle)
- Spell failure (fizzle)
- Mana depletion warning

### Ghost State
- Death sound (distinct, impactful)
- Ghost ambient (ethereal whisper, wind)
- Ghost movement (soft footstep, whoosh)
- Resurrection sound (chime, warmth returning)
- Corpse decay warning (timer tick)

### UI
- Menu open/close
- Button click
- Item equip/unequip
- Item pickup
- Level up / skill increase
- Quest complete
- Error/invalid action
- Murder/criminal flag (TBD)

### World
- Footstep (per terrain type: grass, stone, wood, snow, sand)
- Door open/close
- Weather (rain, wind, thunder)
- Ambient creatures
- Water (streams, waterfalls)
- Day/night transition (ambient shift)

### System
- Corpse loot
- Crafting complete
- Crafting fail
- Dungeon enter/exit
- Teleport (hub, dungeon)

## Voice

- No voice acting initially
- Ghost moaning (UO reference — ghosts can't communicate meaningfully)
- Possible retro-style alert beeps for important events

## Audio Implementation
- Godot `AudioStreamPlayer` for music (crossfade between tracks)
- `AudioStreamPlayer3D` for positional world sounds
- Audio bus layout: Master, Music, SFX, Ambient, UI, Voice, Magic
- Web export: Test audio latency early; consider Web Audio API limitations
- Ghost state: apply audio filter (low-pass, reverb) to all game audio

## Open Questions
- Composer/source for music?
- SFX generation (Bfxr, Chiptone, licensed, FOSS?)
- Dynamic music layers or simple track switching?
- Ambient sound density for web performance?
- Magic SFX per school or generic?

---

*See also:* `08-art-direction.md` | `10-technical-architecture.md`
