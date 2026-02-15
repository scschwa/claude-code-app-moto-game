# Desert Pulse: A Rhythm-Reactive Motorcycle Game

## Vision

A music-reactive arcade motorcycle game inspired by long desert road trips and the feeling of a perfect song syncing with the open road. The player rides through stylized, neon-soaked desert landscapes that transform in real time based on whatever music is playing on their PC. When the beat drops, the world intensifies. When the song breathes, the road opens up.

Think *Sayonara Wild Hearts* meets *Audiosurf* meets the feeling of driving through Nevada at sunset with the stereo cranked.

---

## Core Concept

- **Genre:** Arcade driving / rhythm-reactive experience
- **Platform:** PC (Windows)
- **Input:** Controller (primary), keyboard (secondary)
- **Audio Source:** System audio capture (any music the player is already listening to — Spotify, YouTube, local files, anything)
- **Perspective:** Third-person behind-the-bike, slightly low camera angle for drama

---

## Audio Analysis System

The game captures system audio in real time and extracts musical features to drive gameplay. No pre-analysis or beat maps required.

### Extracted Features

| Feature | How It's Used |
|---|---|
| **Tempo / BPM** | Base speed of the world; faster BPM = faster movement |
| **Beat onsets** | Trigger discrete events — coin spawns, obstacle appearances, terrain shifts |
| **Spectral energy (low/mid/high)** | Low = terrain rumble and ground shake; Mid = traffic and obstacles; High = visual sparkle and particle effects |
| **Volume / RMS energy** | Overall intensity level — controls how "busy" the world is |
| **Onset density** | How many hits per second — drives road complexity (curves, lane changes) |
| **Spectral flux** | Sudden changes in the frequency spectrum — triggers dramatic moments (jumps, tunnels, lane splits) |
| **Silence / quiet passages** | World opens up, minimal obstacles, serene desert stretches |

### Implementation Approach

- Use WASAPI loopback capture (Windows) to grab system audio
- Run FFT and onset detection in real time (libraries like FMOD, or a custom DSP pipeline)
- Smooth extracted features over short windows to avoid jitter
- Map features to gameplay parameters through a tunable "reactivity" layer

---

## Gameplay Mechanics

### Riding

- The motorcycle moves forward automatically at a base speed influenced by the music's tempo
- Player controls **lateral movement** (lane switching / steering) and **timing actions** (jumps, ducks, boosts)
- The bike leans into turns with exaggerated, stylish animations
- Controller rumble synced to the beat

### Road & Terrain Dynamics (Music-Reactive)

The road is procedurally generated ahead of the player, shaped by the audio analysis:

| Music State | Road Response |
|---|---|
| **High energy / fast tempo** | Road narrows, more curves, canyon walls close in, traffic increases |
| **Low energy / slow tempo** | Road widens, straightens out, open desert vistas, minimal traffic |
| **Bass drops** | Terrain shifts — road cracks and splits, ground rumbles, dust storms roll in |
| **High-frequency bursts** | Shimmering visual effects, coin cascades, neon trails intensify |
| **Build-ups (rising energy)** | Road gradually elevates uphill, tension increases, sky darkens |
| **Drops after build-ups** | Massive downhill plunge, speed boost, explosion of color and particles |
| **Quiet / silence** | Flat desert highway, starlit sky, peaceful coasting, score multiplier builds |
| **Staccato / choppy rhythms** | Zigzag roads, frequent lane changes required, obstacles appear in bursts |
| **Sustained notes / legato** | Long sweeping curves, smooth terrain, flowing movement |

### Obstacles & Hazards

- **Other vehicles:** Cars, trucks, other bikes — density scales with musical intensity
- **Road debris:** Tumbleweeds, rocks, sand drifts — tied to percussive elements
- **Environmental:** Dust devils, sandstorms, canyon narrows — triggered by spectral shifts
- **Moving hazards:** Oncoming traffic on narrow roads during intense passages

### Collectibles & Scoring

- **Coins / orbs:** Appear in patterns synced to the beat — collecting on-beat gives bonus points
- **Chain multiplier:** Hitting consecutive coins without missing builds a score multiplier
- **Near-miss bonus:** Threading between obstacles at high speed gives style points
- **Quiet zone multiplier:** During calm passages, a passive multiplier builds that amplifies points during the next intense section
- **Combo streaks:** Visual feedback escalates — the bike glows brighter, trails get longer, the world gets more vivid

### Special Moments

- **Jump ramps:** Appear at musical climax points — the bike launches into the air, time slows, coins float in arcs
- **Tunnel sequences:** During dense, driving sections — tight enclosed space with neon lights streaking past
- **Split paths:** At dramatic key changes or transitions — player chooses left or right, each with different obstacle/reward layouts
- **Ghost riders:** During particularly intense moments, ghostly neon riders appear alongside you, racing in formation

---

## Visual Style

### Art Direction

- **Aesthetic:** Stylized low-poly meets neon arcade — not realistic, but evocative
- **Palette:** Desert sunset gradients (deep orange, magenta, purple) as the base, with neon accents (cyan, hot pink, electric blue) that pulse with the music
- **Inspiration:** *Sayonara Wild Hearts*, *Tron*, *80s airbrush art*, desert vaporwave
- **Time of day:** Perpetual golden hour / twilight — the sky shifts hue with the music's mood

### Environment Elements

- **Desert floor:** Stylized sand with geometric patterns, cracked earth
- **Mountains / mesas:** Flat-shaded, dramatic silhouettes on the horizon
- **Cacti and joshua trees:** Simple geometric shapes, glow at their edges
- **Sky:** Gradient dome with layered clouds, stars emerge during quiet sections
- **Road:** Black asphalt with bright lane markings that pulse with the beat
- **Signs and billboards:** Stylized roadside markers, diners, gas stations that streak past

### Visual Reactivity

- Road lane markings pulse on each beat
- The horizon line breathes with the music's dynamics
- Particle systems (dust, sparks, light motes) intensify with energy
- Color saturation increases with volume
- The bike's headlight beam widens/narrows with musical tension
- Background elements (mountains, sky) shift hue with harmonic content
- Screen-edge vignette pulses subtly on each beat

---

## Controls

### Controller (Primary — Xbox / Generic)

| Input | Action |
|---|---|
| **Left Stick** | Steer left/right |
| **A / Cross** | Jump (when ramp available) |
| **B / Circle** | Boost (spends boost meter) |
| **RT / R2** | Accelerate (override auto-speed) |
| **LT / L2** | Brake / slow down |
| **LB / RB** | Quick lane switch left/right |
| **Rumble** | Synced to bass and impacts |

### Keyboard (Secondary)

| Input | Action |
|---|---|
| **A / D or Arrow Keys** | Steer left/right |
| **Space** | Jump |
| **Shift** | Boost |
| **W / Up** | Accelerate |
| **S / Down** | Brake |
| **Q / E** | Quick lane switch |

---

## Technical Architecture

### Engine & Framework

- **Engine:** Godot 4 (GDScript + GDExtension for audio DSP)
  - Free, open-source, lightweight, excellent for stylized 3D
  - GDExtension allows C/C++ modules for real-time audio processing
  - Strong shader support for the visual effects pipeline
  - Built-in controller support

### Audio Pipeline

```
System Audio (WASAPI Loopback)
       |
   Ring Buffer
       |
  FFT Analysis (C++ GDExtension)
       |
  Feature Extraction
  - Beat detection (onset strength)
  - BPM estimation
  - Spectral band energy (low/mid/high)
  - RMS volume
  - Spectral flux
       |
  Smoothing & Mapping Layer
       |
  Gameplay Parameter Bus
  (exposed to GDScript as reactive values)
```

### Road Generation

- Chunked procedural generation — road segments generated ahead of the player
- Each chunk's properties (curvature, width, elevation, obstacle density) are set by the current audio state
- Segments blend smoothly into each other to avoid jarring transitions
- A look-ahead buffer ensures the road is always generated well before the player arrives

### Key Systems

| System | Description |
|---|---|
| **AudioReactor** | Captures and analyzes audio, exposes musical features |
| **RoadGenerator** | Procedurally builds road chunks based on audio parameters |
| **ObstacleSpawner** | Places traffic, debris, and hazards based on beat and energy |
| **CollectibleSpawner** | Places coins/orbs in beat-synced patterns |
| **VisualReactor** | Drives shaders, particles, lighting, and post-processing based on audio |
| **ScoreManager** | Tracks points, multipliers, combos, and near-misses |
| **InputManager** | Unified controller/keyboard input with rebindable controls |
| **BikeController** | Physics-lite bike movement, leaning, jumping, boosting |

---

## Milestone Plan

### Phase 1 — Prototype Core Loop
- Basic 3D scene with a straight road and a moving bike
- System audio capture and FFT analysis working
- One reactive parameter proven out (e.g., obstacle density tied to volume)
- Controller input functional
- Placeholder visuals

### Phase 2 — Road Generation & Audio Reactivity
- Procedural road generation with curves, elevation, and width variation
- Full audio feature extraction pipeline
- All major reactive mappings implemented (road shape, obstacle density, speed)
- Basic coin/collectible system
- Beat-synced visual pulses

### Phase 3 — Visual Polish & Style
- Final art direction implemented (shaders, materials, skybox)
- Particle systems (dust, sparks, neon trails)
- Post-processing (bloom, color grading, vignette)
- Bike model and animation (leaning, wheelies, jumps)
- Environment props (cacti, mesas, signs, roadside objects)

### Phase 4 — Gameplay & Scoring
- Full scoring system with multipliers and combos
- Special moments (jumps, tunnels, split paths, ghost riders)
- Difficulty curve / intensity scaling
- HUD design (score, multiplier, boost meter)
- Near-miss and style point systems

### Phase 5 — Polish & Ship
- Menu system and settings (audio device selection, sensitivity tuning, control rebinding)
- Tutorial / first-ride experience
- Performance optimization
- Extensive testing with diverse music genres
- Controller vibration tuning
- Bug fixing and edge cases (silence, very quiet audio, extreme BPM)

---

## Open Questions & Future Ideas

- **Biome variety:** Could the harmonic key of the music shift the biome? (Minor key = nighttime desert, major key = sunset canyon, etc.)
- **Bike customization:** Unlockable bike skins and trail effects earned through high scores
- **Endless vs. session mode:** Default is endless, but could offer timed sessions or "one album" mode
- **Leaderboards:** Per-song leaderboards using audio fingerprinting
- **Passenger mode:** A chill mode with no fail state — just ride and vibe
- **VR potential:** The concept would be incredible in VR, but that's a future consideration

---

*"The road is a rhythm. The desert is a stage. Every song is a new ride."*
