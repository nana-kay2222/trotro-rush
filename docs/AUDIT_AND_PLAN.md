# Trotro Rush: Reference Audit, Godot Prototype Audit and Implementation Plan

Date: 2026-09-29. Status: **planning only. No project code, scenes or assets were changed.**

> **Gameplay logic is defined by [GAMEPLAY_SPEC.md](GAMEPLAY_SPEC.md)**: speed is fully automatic, there is no accelerate or brake input, and pickup triggers by proximity.
>
> **Superseded in part by [GAME_SPEC.md](GAME_SPEC.md) (2026-09-30), which is authoritative.** In particular:
> - There is **no brake**. Pickup happens by entering the correct bay during the passenger's window.
> - Bays must **not** alternate left/right.
> - Condition bar, repair bays and "breakdown ends the run" are **not in the spec**. They are pending the owner's decision.
> - Health bars are explicitly excluded.
>
> Where this document disagrees with the spec, the spec wins.

Evidence labels:
- **CONFIRMED**: seen directly in source code or files, or measured at runtime.
- **STRONGLY INFERRED**: backed by implementation evidence but not observed directly.
- **UNCERTAIN**: plausible, but the evidence is not strong enough to rely on.

How the evidence was gathered:
- Reference: I read every JS, HTML and CSS file in `C:\Users\sedof\Downloads\trotrorush.dev` and listed the contents of `pickup.zip`. I did not play the reference in a browser, and I did not visit any live `.dev` website.
- Godot: I read every script and scene. I also loaded `world.tscn` headlessly with the project's own Godot 4.7.2 binary and counted the nodes. That check was read-only.

---

## 1. Reference Game Technical Findings

### 1.1 What the reference actually is
| Finding | Label |
|---|---|
| The reference is not a third-party game. It is an earlier **web build of Trotro Rush itself**: the title is "Trotro Rush", the game-over text is "Trotro Broken Down… on Accra roads", and the destinations are Circle, Kaneshie, Lapaz, Madina, Tema Station and Achimota. | CONFIRMED |
| It contains 3 separate builds: **`index.html`** (the current 2.5D game), **`Trotro_Rush_Stage1_Fixed_v3.html`** (an older single-file top-down 2D game) and **`hybrid_prototype.html`** (a Three.js rendering test with no gameplay). | CONFIRMED |
| Tech stack: vanilla JavaScript classes, **Canvas 2D** (`getContext('2d')`), plain `<script>` tags, and no framework, bundler or package manager. | CONFIRMED |
| `hybrid_prototype.html` uses **Three.js** from a local `three.min.js`. I did not check which Three.js version it is. | CONFIRMED / version UNCERTAIN |
| Audio is synthesized at runtime with the Web Audio API. There are no audio files. | CONFIRMED |
| Assets: 21 vehicle sprites (7 vehicles × rear, left-rear-3q and right-rear-3q views), 21 building sprites (01–21 plus an approval sheet), and `ASSET_MANIFEST.json`. `pickup.zip` holds a copy of the vehicle sprites plus the JS files. | CONFIRMED |

### 1.2 Runtime structure of `index.html`
- `main.js` creates `GameEngine`. `GameEngine` creates `EnvironmentManager` and `World25D` (in `perspective.js`), and `World25D` owns the camera, the road, the renderers, the player, traffic, potholes, bays and scenery. **CONFIRMED**
- **Dead code:** `road.js`, `bays.js`, `traffic.js`, `potholes.js`, `scenery.js` and `buildings.js` are loaded, but their classes are never instantiated. They are left over from the top-down 2D build. **CONFIRMED** (grep found no `new` calls.)
- **Disconnected system:** `EnvironmentManager.update()` runs every frame and blends 7 biome palettes, but no `World25D` renderer reads the palette. The biome and route system has **no visible effect** in the running build. **CONFIRMED**

### 1.3 Systems
| System | Behaviour in `index.html` | Label |
|---|---|---|
| **Projection / camera** | Custom pseudo-3D: `scale = focal(220)/z`, horizon at 28% of screen height, camera height 98, zNear 45, zFar 1200. Portrait canvas, max 480×860. No camera movement. The world scrolls toward a fixed player at `zw = 78`. | CONFIRMED |
| **Lanes** | 3 lanes centred at xw = −40, 0 and +40. Road half-width is 60, lane dividers are at ±20, and bay docking positions are at ±71. | CONFIRMED |
| **Controls** | A quick swipe (<160 ms, >30 px) moves one lane. Hold and drag steers continuously within ±50. ←/→ and A/D move one lane. Mouse mirrors touch. **There is no accelerate or brake input.** | CONFIRMED |
| **Lateral motion** | Exponential smoothing (`xw += diff·14·dt`), with a visual tilt of up to ±0.15 rad. | CONFIRMED |
| **Speed** | Automatic. Starts at 230 and rises +0.8/s up to 420, which takes about 4 minutes. Speed is ×0.45 while docking or merging and 0 while stopped. | CONFIRMED |
| **Traffic** | A fixed pool of 6 vehicles (taxi, sedan, SUV, pickup, van, rival_trotro) that is recycled when a vehicle passes behind the camera. Each recycled vehicle gets a random lane, speed 65–90 and type. Vehicles follow a leader: under 85 units apart they drop to 0.85× the leader's speed. They yield to 35 when the player docks in their lane. **They never change lanes.** | CONFIRMED |
| **Traffic spawn safety** | Recycling picks a lane with no spacing or lane-blocking check (the unused 2D `TrafficManager` had those checks). Vehicles can overlap, or all 3 lanes can be blocked. | STRONGLY INFERRED |
| **Obstacles** | Only potholes. A spawn is attempted every 1.4 s with a 65% chance, at z = 900. There are never more than 2 within 120 units, which guarantees an open lane. No potholes spawn near bays. | CONFIRMED |
| **Collision** | World-space checks, only in the NORMAL state. Potholes use a radial test (radius + 5) for **18 damage**. Vehicles use AABB tests (player ±7/±11, vehicle ±6/±10) for **32 damage**. A hit gives 0.9 s of immunity and a screen shake. There is no physics. | CONFIRMED |
| **Bus stops / bays** | One bay spawns every 2200 distance units, alternating left and right. If the player is damaged, a bay has a 28% chance of being a repair bay. **Docking is automatic**: if the player is in lane 0 (left bay) or lane 2 (right bay) when the bay passes z 50–90, the trotro steers in, stops (boarding 1.8 s, repair 2.2 s) and merges back. Passing the bay in the wrong lane shows a "MISSED STOP" banner. | CONFIRMED |
| **Passengers** | Passengers are painted figures under the shelter. They do not wave, have no timer and have no individual state. Stopping at a stop drops off everyone on board and boards 2 or 3 new passengers (`floor(rand·2)+2`; the code comment says 2–4). The HUD shows capacity 4. | CONFIRMED |
| **Scoring** | A drop-off pays passengers × 100 and a boarding pays new passengers × 25. The destination name advances through the 6 Accra names. There are no fines or penalties. | CONFIRMED |
| **Difficulty** | Only the speed ramp. Spawn rates never change. | CONFIRMED |
| **Game states** | Playing and GameOver. The game ends when damage reaches 100. The modal shows score, passengers delivered and distance, and has a restart button. There is no title screen and no pause. | CONFIRMED |
| **HUD** | DOM overlay showing destination, passengers/capacity, delivered count, score, a condition bar (green, then amber, then red) and a timed event banner. | CONFIRMED |
| **Audio** | Synthesized pothole thud, crash noise, ding and wrench sounds. No engine loop and no music. | CONFIRMED |
| **Environment generation** | 4 recycled chunks of 320 units. Each side gets 1 procedural canvas building (from 10 archetypes), 1 tree and 1 prop. The **21 building PNGs are not used** by `index.html`. | CONFIRMED |
| **Scenery speed** | Chunks move at **0.65×** the speed of the road, bays and potholes, so buildings slide more slowly than the ground under them. Whether this is intentional parallax or a bug is **UNCERTAIN**. | CONFIRMED (the behaviour) |
| **Vehicle rendering** | Sprites are drawn back to front (painter's sort by z). One of 3 views is chosen from the vehicle's **lateral position**, not its steering direction, with hysteresis (switch at ±9, return at ±4.5). The player sprite has per-view anchor metadata. There is an elliptical blob shadow. | CONFIRMED |
| **Procedural route data** | `ROUTE_ACCRA_OUTBOUND` defines 7 segments (Urban → Peri-urban → Informal → Rural → Wetland → Market town → Industrial), each with density, architecture and vegetation sets. It is well structured data, but it is not wired to anything. | CONFIRMED |
| **Hybrid Three.js test** | Proves the "low-poly geometry + UV-mapped sprite artwork" approach for the compound house and mosque, with 2/4/10/20-building perf scenarios. This is the direct ancestor of the Godot prototype. | CONFIRMED |

### 1.4 Spec features that the reference does not have (all CONFIRMED absent)
EMPTY/FULL handling, recklessness meter, police motorbike and fines, rival competition for a passenger, last-second boost, waving passengers with a reaction window, stalled vehicles, player-controlled stopping, and difficulty scaling beyond speed.

---

## 2. Godot Prototype Audit

### 2.1 Project settings
| Item | Value | Notes |
|---|---|---|
| Engine | **Godot 4.7.2** (`config/features "4.7"`; the editor metadata points to `Godot_v4.7.2-stable_win64.exe`) | CONFIRMED |
| Renderer | `gl_compatibility` on desktop and mobile | Good for low-end mobile. |
| Physics | Jolt is enabled, but there are **no physics bodies, areas or shapes** anywhere | CONFIRMED |
| Stretch | `canvas_items` / `expand`. No viewport size or orientation is set, so it defaults to **landscape** 1152×648 | The reference is **portrait**. See Question 1. |
| Autoloads | None | CONFIRMED |
| Input map | **No custom actions.** The code uses `ui_*` actions plus raw `KEY_A`, `KEY_D`, `KEY_W`, `KEY_S` and `KEY_1`–`KEY_4` | CONFIRMED (runtime) |
| Signals | None declared or connected | CONFIRMED |
| VCS | Not a git repo. The project is inside **OneDrive**, which also syncs `.godot/` | Risk. See Section 6. |

### 2.2 Scenes and scripts
| File | Purpose |
|---|---|
| `scripts/build_prototype_scenes.gd` | `@tool` SceneTree script that **generates and overwrites** all 5 `.tscn` files: road, trotro, compound house, mosque and world. |
| `scenes/road.tscn` | A static 360 m road (z +60 to −300) that is 11 m wide (3 lanes of about 3.67 m). Curbs and gutters are boxes, and laterite shoulders are 160 m planes. 10 utility poles and 8 palms built from cylinders and prisms. |
| `scenes/compound_house.tscn` | Hybrid building: a box core, a rectified side-wall texture quad, front facade and porch cards, a pitched roof and a breeze-block perimeter wall. |
| `scenes/mosque.tscn` | Prayer hall with a rectified facade, pilasters, an entrance pavilion, a dome, and a tiered minaret with fretwork cards. |
| `scenes/player_trotro.tscn` + `player_trotro.gd` | A `Sprite3D` using the rear view only, plus a blob-shadow quad. Steering is **free-form, not lane-based** (target_x ±3.8 m at 7 m/s). W/S accelerate and brake, Space toggles cruise, and there is suspension roll and bob. At z < −260 the trotro **teleports back to z = 25**. |
| `scripts/camera_controller.gd` | Chase camera (+6.2 z, 2.3 y, −6° pitch, 0.7× lateral follow) plus 3 fixed debug views on keys 1–4. |
| `scenes/world.tscn` + `world.gd` | Main scene: environment, sun with shadows, road, one house at (−13.5, −45), one mosque at (15, −105), the player, the camera and a text label. `world.gd` is a **screenshot-capture harness** (P, C and `--auto-capture`). |
| `scripts/*.py`, `*.ps1` | Offline texture tooling: perspective rectification of source sprites into orthographic wall textures, crops, and generated road, curb, laterite and shadow textures. |

### 2.3 Classification

**Works (preserve):**
- The hybrid building approach, meaning rectified sprite-derived wall textures on low-poly volumes. The screenshots show it reads well; the compound house is especially convincing.
- The compound house and mosque scenes as landmark assets.
- Chase camera framing: road, trotro and roadside all read clearly in `5_driver_chase_cam.png`.
- The player sprite, blob shadow, roll and bob.
- The GL Compatibility renderer choice.
- The texture rectification pipeline (`prepare_modular_textures.py`, `build_compound_textures.py`).
- The generated road, curb and laterite textures.

**Partially works:**
- **Player controller:** smooth motion, but free steering with no lanes, and the teleport loop is not an endless world.
- **Camera:** gameplay-ready in CHASE mode. The debug modes should be moved behind a debug flag.
- **Road:** a single static mesh with no streaming.
- **Screenshot harness:** useful, but it lives in the gameplay root script.

**Broken:**
1. **`world.tscn` loads every sub-scene twice (CONFIRMED at runtime).** The builder's `set_owner_recursive` set the owner of instanced children to `World`, so the saved scene re-declares all their nodes on top of the instances. Measured visual nodes:

   | Node | In `world.tscn` | Standalone scene |
   |---|---|---|
   | Road | 166 | 83 |
   | CompoundHouse | 50 | 25 |
   | Mosque | 72 | 36 |
   | Total | **292** | 146 expected |

   Consequences:
   - Double draw calls.
   - Z-fighting surfaces (STRONGLY INFERRED).
   - **Two player `VisualHolder`s.** Only the first one gets roll and bob, so the static copy should ghost during steering (STRONGLY INFERRED).
2. **Builder script is destructive.** Re-running it regenerates every scene and reproduces bug 1. Any hand edits in the editor would be lost.
3. **Texture imports use lossless compression with mipmaps disabled (CONFIRMED).**
   - No mipmaps on distant 3D surfaces causes shimmer and aliasing (STRONGLY INFERRED).
   - Uncompressed textures of about 1500×1000 cost roughly 6 MB of VRAM each. That will not scale to 21 vehicle and 21 building assets on mobile.
4. **The teleport loop moves only the player.** The same house and mosque repeat about every 18 s, and there is a visible world jump whenever the loop wraps.

**Missing** (compared with the spec):
- Lanes, traffic, potholes and stalled vehicles.
- Collision of any kind.
- Passengers, pickup bays, EMPTY/FULL, fares and scoring.
- Recklessness meter, police and fines.
- Rival trotro and boost.
- HUD, game states (title, playing, game over, restart), audio and touch input.
- World streaming and pooling.
- The other 19 buildings.
- The other 6 vehicle types (they exist only in the reference folder).
- The left and right 3q player sprites exist in `assets/vehicles/player_trotro/` but are not used.

**Refactor:**
- `world.gd`: split the capture harness into a debug node.
- `player_trotro.gd`: switch to lane-based targets and read input from the InputMap.
- `camera_controller.gd`: keep CHASE and gate the debug modes.
- Builder script: stop it from writing `world.tscn`, or retire it once scenes are edited by hand. See Question 6.

**Replace:**
- The static road → pooled road chunks.
- The cylinder/prism palms → billboard vegetation cards.
- The teleport loop → streaming plus origin rebase.

**Leave alone (do not delete yet):**
- About 25 `*_test.png`, `*_original.png` and unused intermediate textures in `assets/buildings/`. They are unreferenced (CONFIRMED by grep), but they are source material for the pipeline. Move them to an `_source/` folder with a `.gdignore` later, with your approval.

---

## 3. Feature Comparison and Gap Analysis

Req column:
- **SPEC** = explicitly required by the Trotro Rush description.
- **REF** = borrowed from the reference as design inspiration.
- **ASK** = present in the reference and listed in your Phase 5, but not in the spec (needs your decision).

| System | Reference | Godot now | Req | Gap → Recommendation | Files | Pri |
|---|---|---|---|---|---|---|
| Lanes | 3 lanes, discrete snap | 11 m road, free steer | SPEC | Lane centres at x = −3.67, 0, +3.67. One lane per input, with smoothing and roll. Keep hold-drag fine steer optional. | `player_trotro.gd`, new `lane_config` | P0 |
| Speed / brake | Auto ramp, no brake | W/S manual, cruise | SPEC (stop to collect) | Auto cruise ramp **plus a brake input**, so the player can "stop" in the bay. | `player_trotro.gd` | P0 |
| Endless world | Recycled chunks | Static road + teleport | SPEC (implicit) | Pooled road and scenery chunks ahead of the player, plus an origin rebase. | new `world_streamer.gd`, `road_chunk.tscn` | P0 |
| Traffic | 6 pooled vehicles, following, yield | None | SPEC | Port the pool, following and yield logic. **Add spawn-lane safety** (always leave ≥1 lane free) and use all 6 sprite types with 3-view selection. | new `traffic_manager.gd`, `traffic_vehicle.tscn` | P0 |
| Potholes | Timed spawn, lane-free guarantee | None | SPEC | Port directly: decal quads on the road with an Area3D. | new `hazard_manager.gd`, `pothole.tscn` | P0 |
| Stalled vehicles | None | None | SPEC | Stationary traffic sprite with flashing hazards, spawned by `hazard_manager` under the same free-lane rule. | same | P1 |
| Collision | Math AABB + immunity | None | SPEC | Area3D boxes on layers (player / traffic / hazard / bay). Keep the 0.9 s immunity and screen shake. | player scene, hazard/traffic scenes | P0 |
| Pickup bays | Auto-dock in the correct outer lane | None | SPEC | Bay pocket geometry beside the curb. **Pickup is player-driven**: be laterally inside the bay, below the speed threshold, within the bay's z range, and boarding happens after a short dwell. | new `pickup_manager.gd`, `pickup_bay.tscn` | P0 |
| Passengers | Static figures | None | SPEC | Billboard sprite that waves and calls (bob tween plus an icon), with a visible countdown. When the window closes the passenger is missed and the fare is lost. | new `passenger.tscn` | P0 |
| EMPTY/FULL | None (capacity 4, cosmetic) | None | SPEC | `is_full` flag. When full: slower lateral response, slower acceleration, and a hit-penalty multiplier (e.g. ×1.5). How the trotro becomes empty again is undefined; see Question 2. | `player_trotro.gd`, `game_state.gd` | P0 |
| Scoring | Deliveries + boardings | None | SPEC | `score = fares − fines`, tracked in the GameState autoload with signals. | new `game_state.gd` | P0 |
| Recklessness | None | None | SPEC | Meter that fills from sustained speed above a threshold, rapid lane weaving and collisions, and decays while driving calmly. When full, the police sequence starts. | `recklessness.gd` (on player) | P1 |
| Police | None | None | SPEC | Motorbike sprite approaches from behind, forces a pull-over (short scripted stop) and deducts a fine. The meter then resets. | new `police_manager.gd`, `police_bike.tscn` | P1 |
| Rival trotro | Traffic skin only | None | SPEC | Occasionally spawns before a pickup, heads for the same bay and "steals" the passenger if it stops first. | new `rival_trotro.gd` | P1 |
| Last-second boost | None | None | SPEC | If boarding completes while the passenger's timer is below X%, give a timed speed boost with a FOV kick. | `player_trotro.gd`, camera | P2 |
| Condition / repairs | Damage 0–100, repair bays, breakdown ends the run | None | ASK | Recommended: keep condition, breakdown and repair bays, reusing the bay system. | `pickup_manager.gd` | P1 |
| Game states | Playing / GameOver | None | SPEC (implied) | Title → Playing → Paused → GameOver → Restart. | `game_state.gd`, `ui/*.tscn` | P0 |
| HUD | DOM cards + banner | Debug label | SPEC | Fares, fines, score, EMPTY/FULL badge, recklessness meter, condition bar (if kept), event banner, pickup countdown. | `ui/hud.tscn` | P0 |
| Difficulty | Speed ramp only | None | REF | `DifficultyCurve` resource that ramps speed, traffic density, pothole rate and the rival/police chance. | `difficulty.tres` | P2 |
| Environment profiles | 7 biome palettes + sets (not wired) | 2 hand-placed buildings | REF | Port the route and profile data into Godot Resources, keeping the focus on Accra. | `data/*.tres` | P2 |
| Buildings | Procedural canvas | 2 hybrid landmarks | SPEC (identity) | Generic "building kit" for the 21 sprites, plus hero landmarks. See §4.3. | tooling + `buildings/*.tscn` | P2 |
| Vegetation / props | Canvas palms, neems, poles | Crude 3D palms, poles | SPEC | Billboard cards (palm, neem, plantain), MultiMesh poles, and roadside props (kiosks, umbrellas). | `props/*.tscn` | P2 |
| Audio | 4 synth SFX | None | SPEC (polish) | Engine loop pitched by speed, horn, crash, pothole, passenger call ("Circle! Circle!"), police siren, fare ding. | `audio_manager.gd` | P3 |
| Controls (touch) | Swipe + hold-drag | Keyboard only | SPEC (mobile) | InputMap actions and a touch handler: swipe to change lane, plus a brake control. See Question 4. | `input_handler.gd` | P1 |

---

## 4. Recommended Architecture

### 4.1 Coordinate model
- Keep the existing model: the player moves along −Z and the camera follows it. It already works and preserves `player_trotro.gd` and `camera_controller.gd`.
- Add an **origin rebase**: when the player passes z = −2000, shift the player, the camera and `WorldRoot` by +2000 in a single frame. This avoids float drift and keeps chunk maths simple.
- Units are metres. Lane width is 3.67 m.

### 4.2 Scene tree (target)
```
World (world.gd: state wiring only)
├─ WorldEnvironment, SunLight (shadows off on mobile; blob shadows instead)
├─ WorldRoot                      # everything that streams / rebases
│   ├─ RoadStreamer               # pooled road_chunk.tscn (e.g. 6 × 40 m)
│   ├─ SceneryStreamer            # places buildings/props per EnvironmentProfile
│   ├─ TrafficManager             # pooled traffic_vehicle.tscn
│   ├─ HazardManager              # potholes, stalled vehicles
│   ├─ PickupManager              # bays, passengers, repair bays
│   ├─ RivalManager
│   └─ PoliceManager
├─ PlayerTrotro (Area3D child for overlaps; recklessness.gd component)
├─ CameraRig
├─ UI (CanvasLayer): HUD, TitleScreen, PauseMenu, GameOver
└─ Debug (capture harness, debug cams; only in debug builds)
Autoloads: GameState (score/fares/fines/state enum + signals), Config (loads tuning .tres), AudioManager
```

### 4.3 Key design decisions
- **Collision:** use Area3D with collision layers rather than Jolt bodies. Areas are cheap, easy to debug visually and signal-driven. Driving is kinematic, so no rigid-body physics is needed.
- **Signals:** use the GameState autoload as the hub:
  - `fare_earned(amount)`
  - `fine_issued(amount)`
  - `passenger_missed`
  - `load_state_changed(is_full)`
  - `recklessness_changed(v)`
  - `state_changed(s)`
  - `player_hit(kind)`

  Managers emit to GameState and the HUD listens. Managers never reference each other directly, except that they all read the player position.
- **Data:** tuning goes into `Resource` scripts, not magic numbers.
  - `DrivingTuning` (empty and full variants)
  - `SpawnTuning`
  - `DifficultyCurve`
  - `EnvironmentProfile` (palette, building weights, vegetation, density)
  - `JourneyRoute` (a list of profiles plus distances, ported from `ROUTE_ACCRA_OUTBOUND`)
  - `VehicleSpriteSet` (3 textures plus anchor metadata, ported from `VehicleSpriteManager`)
- **Pooling:** every spawned entity is pooled (road chunks, traffic, potholes, passengers, props). Nothing calls `queue_free` during play.
- **Culling:**
  - Recycle chunks once they are behind the camera.
  - Set `visibility_range_end` on props.
  - Use distance fog so objects fade in instead of popping.
  - Keep a far skyline layer of billboard cards at a fixed distance that moves with the camera. This gives a parallax horizon.
- **Vehicle rendering:**
  - `Sprite3D` with alpha scissor (avoids transparent sorting artifacts) and a blob-shadow quad.
  - Choose among the 3 views from x relative to the camera, using the reference's hysteresis.
  - Resize sprites to about 512 px wide.
- **Buildings, in three tiers:**
  - (a) **Hero landmarks** (mosque, church, fuel station) as custom hybrid scenes, like the existing mosque.
  - (b) **Building kit**: one parametric scene (box volume, rectified side-wall quad, front-end quad, roof) fed by a per-building JSON of source-quad corners, which extends `prepare_modular_textures.py`.
  - (c) **Far cards**: the original sprite on a single quad for the background row.
- **Save/state:** `ConfigFile` at `user://save.cfg` for best score and settings. There is no mid-run save.
- **Performance targets:**
  - Fewer than 150 draw calls.
  - Textures at most 1024 px, with VRAM compression (ETC2/ASTC) and mipmaps on for all 3D textures.
  - MultiMesh for poles and lane dashes.
  - Directional shadows off on mobile.

---

## 5. Implementation Roadmap
Each stage leaves the project runnable and testable.

| # | Goal | Create | Modify | Depends | Test / Definition of done |
|---|---|---|---|---|---|
| 0 | **Stabilize baseline** | `.gitignore` check, `project.godot` input actions | `world.tscn` (remove duplicate nodes), builder (stop writing `world.tscn` or fix owner logic), texture `.import` (mipmaps + VRAM compression), move capture harness to a `Debug` node | none | The headless count gives **146** visual nodes, the capture screenshots match the current ones, and the game runs with no errors. |
| 1 | **Lane controller + input** | `lane_config` resource, `input_handler.gd` | `player_trotro.gd` (lanes, brake, auto-cruise ramp), `camera_controller.gd` (CHASE default, debug modes gated) | 0 | Keys and swipe move exactly one lane. Brake reaches 0. Roll and bob are preserved. |
| 2 | **Endless world** | `road_chunk.tscn`, `world_streamer.gd`, origin rebase | `world.tscn` (WorldRoot), `road.tscn` becomes the chunk template | 1 | 10 minutes of driving with no jump, no gaps and a stable draw-call count. House and mosque are reused as chunk content. |
| 3 | **Hazards, traffic, collision, core loop** | `game_state.gd` (autoload), `traffic_manager.gd`, `traffic_vehicle.tscn`, `hazard_manager.gd`, `pothole.tscn`, `stalled_vehicle.tscn`, `ui/hud.tscn`, `ui/game_over.tscn` | player (Area3D, hit handling), import of the 6 vehicle sprite sets | 2 | There is always ≥1 free lane. Hits register once each. The game ends per the rule from Question 3. Restart fully resets the run. |
| 4 | **Passenger pickup + EMPTY/FULL + fares** | `pickup_manager.gd`, `pickup_bay.tscn`, `passenger.tscn` | player (full/empty tuning), HUD | 3 | A passenger waves with a visible timer. Stopping in the bay boards them, and missing the window loses the fare. Handling is measurably heavier when full. Score equals fares. |
| 5 | **Recklessness + police + fines** | `recklessness.gd`, `police_manager.gd`, `police_bike.tscn` | HUD, GameState | 4 | The meter fills and decays per tuning. A full meter triggers a pull-over and a fine. **Final score = fares − fines.** |
| 6 | **Rival trotro + last-second boost** | `rival_trotro.gd` | pickup_manager, player, camera | 4 | The rival can win a passenger. A last-second pickup boosts, and the boost is visible in HUD and FOV. |
| 7 | **Ghanaian world build-out** | `EnvironmentProfile` / `JourneyRoute` `.tres`, building kit scene + texture JSON, vegetation and prop cards, skyline layer | streamer, texture tooling | 2 (can run in parallel with 3–6) | At least 8 of the 21 buildings are in rotation. Profile transitions are visible. Performance stays within target. |
| 8 | **Repairs/condition (if kept), difficulty, audio, polish, mobile export** | `difficulty.tres`, `audio_manager.gd`, title and pause screens | various | 3–7 | Android export runs at ≥50 fps on the target device. Audio covers all events. |

Stages 0 to 4 form the **core loop**. Stages 5 and 6 complete the spec. Stages 7 and 8 are identity and polish.

---

## 6. Technical Risks
1. **No version control, and the project is inside OneDrive.** There is no rollback, and OneDrive syncing `.godot/imported` can cause file locks and conflicts. I recommend `git init` before stage 0.
2. **The builder script regenerates all scenes.** It must be fixed or retired before anyone edits scenes by hand, or work will be silently overwritten.
3. **Sprite viewpoint mismatch.** The vehicle sprites are 3/4 rear renders from a fixed elevation. At the Godot camera (2.3 m high, 6.2 m behind), near traffic may look "flat" or wrongly angled. I'd tune camera height against the sprites early.
4. **Alpha sorting.** Overlapping `Sprite3D`s and transparent cards (porch, fretwork) can sort incorrectly. Use alpha scissor wherever possible.
5. **VRAM and download size.** 42 source sprites of about 2 MB each would be heavy on mobile. They need resizing and compression.
6. **Authoring cost of 21 buildings.** Hand-built hybrid scenes do not scale. The building-kit approach depends on the sprites having usable rectifiable walls; this is true for the 2 done so far and UNCERTAIN for the rest (e.g. the fuel station and the market structure).
7. **Readability at speed.** Pickup bays and waving passengers must be readable far enough ahead at mobile resolution. That might need UI markers, such as an arrow or a lane hint.
8. **Spec ambiguities** (Section 7) directly affect stages 3 to 5.
9. **Portrait versus landscape** changes the FOV, the HUD layout and how much roadside is visible.

## 7. Questions to Resolve Before Implementation
1. **Orientation:** portrait (like the web reference, 480×800) or landscape (the current Godot default)?
2. **Fares and EMPTY/FULL:**
   - Is a fare earned at pickup, or on drop-off?
   - Is "FULL" one passenger load (binary), or a seat count?
   - How does the trotro become EMPTY again: drop-off at the next stop, timed alighting, or something else?
3. **Run end:** what ends a run? Breakdown (reference), a timed shift, or reaching the end of a journey? And are **condition and repair bays** in scope, given that the spec does not mention them?
4. **Stopping and controls:** should pickup require the player to brake to a stop in the bay (my reading of the spec), or auto-dock like the reference? If it is manual, what is the mobile brake control: a hold button, swipe down, or tap-and-hold?
5. **Police:**
   - Can the player evade the motorbike?
   - Is the fine fixed or scaled?
   - Does the pull-over stop the trotro for a few seconds?
6. **Source of truth:**
   - May I run `git init` and commit the current state as a baseline?
   - After stage 0, should scenes be edited as `.tscn` files, with the builder script retired, or should the generator stay canonical?
7. **Reference:** is this local `trotrorush.dev` folder the complete reference, or is there a live `.dev` URL that may differ?
