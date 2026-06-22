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

| Track               | Use                   |
| ------------------- | --------------------- |
| Main Theme          | Title screen          |
| Overworld           | Default exploration   |
| Biome tracks (×4-6) | Per-biome ambience    |
| Combat (standard)   | Standard fights       |
| Combat (boss)       | Boss encounters       |
| Dungeon             | Interior/exploration  |
| Ghost/Death         | Death state           |
| Crafting            | Crafting menu         |
| Hub/Safe Area       | Resurrection hub      |
| Day variant         | Daytime exploration   |
| Night variant       | Nighttime exploration |
| (TBD)               | (TBD)                 |

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

# Styling Guide / Promtps for Generation:

🎮 GLOBAL STYLE (reuse for everything)

Late-1990s fantasy MMORPG soundtrack. Medieval Renaissance Celtic instrumentation. Wooden flute, recorder, lute, Celtic harp, fiddle, viola, cello, English horn, oboe, dulcimer, frame drum, hand percussion, occasional French horn. Modal harmony (Dorian, Aeolian, Mixolydian), pedal tones, open fifths, simple counterpoint, repeating motifs. Acoustic, natural dynamics, minimal production. Loop-friendly game music structure. No cinematic orchestral swells, no trailer percussion, no synths, no EDM.

🌍 OVERWORLD
BPM: 88
Duration: 2:15–3:00
Key: D Dorian

Wooden flute leads a lightly bouncing wandering melody over harp arpeggios, lute, and soft strings. Gentle rhythmic motion suggesting footsteps on an old road. Short repeating motifs with subtle variation and playful ornamentation. Curious, lightly adventurous, and warm without becoming emotional or dramatic. Designed to loop seamlessly with no strong beginning or ending.

🏡 SMALL VILLAGE
BPM: 92
Duration: 1:45–2:30
Key: G Major (modal folk feel)

Simple folk melody on fiddle and recorder with lute and light percussion. Cozy rhythmic pulse, slightly dance-like but restrained. Friendly, rustic, and intimate. Repeating phrases with small variations. Feels like daily life rather than performance.

🏙️ TOWN
BPM: 96
Duration: 2:00–2:45
Key: C Mixolydian

Lute, harp, fiddle, and pizzicato strings create a gentle bustling rhythm. Light melodic movement with small counter-melodies suggesting market activity. Lively but controlled, structured but not busy. Steady loopable motion with no dramatic peaks.

🏰 CAPITAL CITY
BPM: 84
Duration: 2:30–3:30
Key: F Dorian

Chamber ensemble with strings, oboe, English horn, and harp. Slow dignified melodic phrases with restrained harmony. Noble and ancient, but not grandiose. Slight counterpoint and formal structure without cinematic weight. Loopable with calm continuity.

🌲 FOREST (OVERWORLD VARIANT)
BPM: 86
Duration: 2:15–3:15
Key: A Dorian

Flute and recorder trade short wandering phrases over harp and soft strings. Organic, lightly playful motion with call-and-response motifs. Melodies drift like birds moving through trees. Gentle forward flow, never static.

⛰️ MOUNTAINS
BPM: 72
Duration: 2:30–3:30
Key: E Aeolian

Slow horn calls and flute fragments over low sustained strings and harp drones. Wide open intervals and long pauses between phrases. Spacious, isolated, and grounded. Minimal rhythmic presence.

🏜️ DESERT
BPM: 78
Duration: 2:00–3:00
Key: D Phrygian-ish (or D minor modal)

Sparse lute, flute, and light hand percussion with long drones. Repetitive hypnotic motifs. Dry, ancient, and expansive. Minimal melodic movement with wide intervals.

🌊 COAST
BPM: 90
Duration: 2:15–3:00
Key: G Mixolydian

Flowing harp arpeggios and fiddle with soft flute melody. Rolling rhythmic motion resembling waves. Light, airy, and steady. Subtle cyclical phrasing.

🌙 NIGHT OVERWORLD
BPM: 70
Duration: 2:30–3:30
Key: D Dorian

Sparse flute, soft strings, bells, and low drones. Very light rhythmic presence. Long gaps between phrases. Calm, slightly mysterious but not tense.

⚔️ COMBAT (FIELD)
BPM: 110
Duration: 1:00–1:45
Key: E Dorian

Frame drum pulse with low strings and short horn stabs. Repeating rhythmic motif with restrained intensity. Controlled danger rather than heroism. Loopable without escalation.

🐉 BOSS
BPM: 96
Duration: 1:30–2:30
Key: D Minor (modal)

Slow building tension with strings, horn, choir pads, and timpani used sparingly. Heavy sustained harmony and rhythmic gravity. Powerful but not chaotic. Structured looping intensity.

☠️ DEATH / GHOST
BPM: 48
Duration: 2:30–3:30
Key: A Aeolian

Choir pads, English horn, harp harmonics, and distant bells. Extremely slow harmonic movement with long sustained tones. No percussion. Floating, detached, and loopable without resolution.

🏛️ DUNGEON
BPM: 74
Duration: 2:30–3:30
Key: E Phrygian

Low drones, bass flute, cello, and distant bells. Sparse melodic fragments with heavy space between events. Subtle tension without horror or drama. Ancient, enclosed, and slow-moving.

🪦 RUINS
BPM: 76
Duration: 2:15–3:15
Key: F Dorian

Harp, oboe, strings, and soft choir textures. Fragmented melodic ideas that fade into silence. Sense of lost civilization and fading memory. Gentle emotional weight, no climax.

⛪ TEMPLE
BPM: 66
Duration: 2:30–3:30
Key: C Aeolian

Pipe organ, choir pads, harp, and bells. Slow sacred harmonic movement with minimal rhythm. Reverent, stable, and meditative. Looping without resolution.

⚰️ CAVE
BPM: 60
Duration: 2:00–3:00
Key: D Phrygian

Deep drones, sparse flute echoes, and low strings. Almost no rhythm. Empty spatial sound with isolated musical events. Natural and unstructured.

---

_See also:_ `08-art-direction.md` | `10-technical-architecture.md`
