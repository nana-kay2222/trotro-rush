# Trotro Rush: Current Status

Last updated: 2026-10-01. Engine: Godot 4.7.2 (GL Compatibility). Orientation: portrait.

## How to play (in the editor)
Press **F5**. On the start screen, tap or click to begin.

- **Steer:** hold and drag anywhere on the screen. On desktop, drag with the mouse, or use A/D or the arrow keys.
- **Speed:** there is no accelerate or brake. The trotro drives itself and gradually speeds up. A crash or a police stop resets it to the base speed.
- **Pause:** the **II** button or Esc.
- **Menus (owner's button art, `assets/ui/buttons/`):** every button squeezes when pressed and springs back when released.
  - **Main menu:** PLAY, TUTORIAL, SETTINGS.
  - **Settings:** SOUND (everything), MUSIC (songs only), TUTORIAL, and EXIT, which closes the panel.
  - **Pause:** RESUME, RESTART, SOUND, MAIN MENU.
  - **Game over:** RESTART, MAIN MENU.
  - **Day complete:** NEXT DAY.
  - The device remembers the sound and music settings.
- **Tutorial** (`scripts/tutorial.gd`): it plays on the first PLAY, and any time from TUTORIAL. It's a real drive on a quiet road.
  - Each lesson pauses the game, dims it, and points an arrow at the thing.
  - The lessons: steering, a slow car, a pothole, a bus stop, the sales target, health/recklessness and a mechanic stop, the booster, a police checkpoint, a rival, and go-slow/market tips.
  - SKIP is always on screen. Nothing can end the run during the tutorial, and the clock is stopped.
  - The practice money isn't kept: a fresh day 1 follows.

## What's built, against the spec

### Driving
- **Driving:** automatic forward speed. It starts at about 70 km/h and creeps up while you drive cleanly. Above about 90 km/h you are "speeding". Steering is left/right only (GAMEPLAY_SPEC §2–4).
- **Touch steering:** the trotro follows your finger closely.
- **Lanes and bays:** 3 active lanes. Bus-stop pockets on both sides at random, never strictly alternating. You can only steer into a pocket while it's alongside (§8).

### Passengers and the working day
- **15 seats.** Stops have groups of 1–4 people. Each person pays a fare and takes a seat. The seats badge shows how full you are (e.g. "9/15").
  - A fuller trotro steers heavier and takes more damage.
  - Riders get off at bus bays: a few at every stop, more at stops with nobody waiting.
- **Daily sales target.** Each day runs on a clock from 6 AM to 6 PM: 4 minutes on day 1, a little shorter each day. Reach the day's sales target (GHS) before the day ends.
  - Hit it and you get the "AYEKOO!" screen, an overnight repair, and a higher target the next day.
  - Miss it and the run ends.
- **Stopping at a stop:** swing into a pocket and the trotro brakes by itself, harder if you came in late, so it comes to a full halt beside the passengers (or the fitter). It waits while they board, then pulls away. A stopped trotro can't slide sideways.
- **Bus-stop shelters:** three 3D shelters along every bus stop (blue curved corrugated roofs with a yellow trim, steel posts, slatted benches).
- **Stop spacing:** a bus stop every 170–260 m, 90% with people waiting. From day 4, stops are 3% closer together each day, up to 15% closer from day 8 (every ~145–220 m). Mechanic stops are extra stops slotted in between and never replace a bus stop. They only appear when health is under 80%.
- **The mate:**
  - He leans out of the side window (head, shoulder and waving arm) when a stop is coming up, while stopped, and to shout route calls and reactions.
  - On empty stretches he ducks inside for a few seconds now and then.
  - Flavour only; he doesn't change gameplay.
- **Missed passengers:** no fare, the game continues (§9). Swinging into a pocket late gives a short boost (§19).

### Road events (one every ~600 m, in rotation)
- **Go-slow:** rows of crawling cars. The open lane holds for a few rows; when it moves, both lanes stay open for two rows (~22 m) so there's room to change lanes. Hawkers work the lane lines between the cars and sometimes cross the road. Bumps in the jam only do light damage.
- **Market stretch:** stalls and crowds on both walkways; shoppers cross the road.
- **People on the road** (go-slow hawkers, market shoppers):
  - Hitting one costs 10 health and adds recklessness.
  - A near miss makes them jump back, startled, and adds a little recklessness.
- **Police checkpoint:** applies to the trotro only. A cone line turns the right lane into the checkpoint lane, and the officer stands on the walkway.
  - If he waves you through, drive on.
  - If he flags you, get into the coned lane before the cones start; the trotro stops beside him by itself.
  - If you skip it, a police bike chases you down and fines you GHS 25.
  - The warning (banner, siren and the officer's signal) comes about 90 m before the first cone, about 4 s of driving.
- **Speed bumps:** slow the trotro down and jolt it.

### Hazards
- **Potholes** in lanes (§15): deep holes with broken-asphalt rubble on the rim and a hard jolt. There are never any in the outer lane beside a bus stop or mechanic.
  - A pothole only counts while its middle is under the trotro's body.
  - A pothole hit has no red screen flash (that's for crashes), and the mate has his own lines for it.
- **Car hit areas:** a little smaller than the cars: about 20 cm of side overlap and 30 cm of front/back overlap are forgiven, so a bare graze doesn't count. Close calls still use the full size.
- **Working day:** 4 minutes on day 1, 8 seconds shorter each day, never under 2.5 minutes. The target is GHS 60 on day 1, then +5 a day (day 10: 2:48 and GHS 105). It's endless, with no last day.
- **Fares:** GHS 4–7 per head, +15% on each pickup, rounded to the nearest cedi.
- **Vehicle pictures** (owner direction): a car straight ahead shows its rear; any other car shows its near-rear picture (mostly the rear plus a sliver of the side) all the way past.
  - Pictures always face the camera at their own proportions, never stretched.
  - Motorbikes always show their rear.
  - No brand badges.
  - The wider three-quarter, side and high-angle pictures are still in `assets/vehicles` but aren't used.
- **Traffic:** taxis, sedans, SUVs, pickups, vans and okadas. At least one lane is always open (§16).
- **Stalled vehicles** with blinking hazard lights (§17).
- **Near-miss rush:** squeezing past a car very closely briefly slows time, with a whoosh and "CLOSE CALL!".
- **Damage** scales with how hard you hit.

### Turbo (owner design)
- **When it's offered:** at random, every 20–40 s of driving (start to start), anywhere in the game, if you can afford it. The turbo icon appears bottom-right for 5 s, with both prices and a timer bar.
- **Two separate boosts, one per appearance:**
  - **One tap (x1):** GHS 10. A modest 130 km/h for 5 s, with no flames and a blue "x1 BOOST".
  - **Double tap (x2):** GHS 15 in all. The full 200 km/h for 5 s with the flames and a red "x2 BOOST". It goes straight to x2 and never starts x1 first.
  - A single tap waits 0.35 s to see if a second tap follows.
- **Rules while boosting:**
  - It ignores go-slow, market and bump speed limits.
  - It isn't speeding (no recklessness, no police).
  - Near misses don't trigger slow-motion.
- **Shield:** while it holds, crashes, potholes and people do no harm. Cars are knocked aside.
  - It shatters on the 4th car hit. After that, crashes count as normal.
- **Looks:** the trotro surges ahead of the camera and the screen edges blur, both stronger for x2. Only x2 has the two flame jets under the rear.

### Health and police
- **Health meter.** At zero the run ends. The trotro gets grimier as health drops, with a thin wisp of smoke below 50%.
- **Roadside fitter (mechanic):** about one stop in five is a mechanic stop on the right instead of a bus stop, and more often when health is under 50%.
  - The stop is marked in blue (bus stops are yellow), with "MECHANIC" painted in it, and a fitter waving a spanner under a "Come fix your car!" callout.
  - His workshop is a 3D building like the roadside ones (FITTER sign, open garage, tyres), running the whole length of the stop.
  - Swinging in late gives the same speed boost as a bus stop.
  - A blue arrow shows "Mechanic" and the distance, and the mate calls it out.
  - Enter the blue pocket and the trotro stops for 3 s: +30 health, never past 80%, for GHS 15.
  - The cost counts against the score and the day's sales, like a fine.
  - With less than GHS 15, the fitter waves you on, so a repair never puts you in the red.
- **Recklessness meter:** fills from speeding, near misses and crashes. It drains slowly once you drive calmly.
  - When it's full, a police bike pulls you over and fines you GHS 10.
  - A negative balance ends the run.

### Rival trotros (§18, owner direction)
- **Arrival:** a rival comes **from behind** for a passenger, horn blaring, with camera shake and a "RIVAL BEHIND" alert.
- **How often:** at least one rival every day. If none has come by the day's 2nd or 3rd stop with people waiting, that stop gets one. Every other waiting stop also has a 14% chance.
- **Aggression:** each day it charges 1% faster: 1.20× the trotro's speed on day 1, up to 1.30× from day 11.
- **Countering it:** steer across its path to block it. A bump stuns it and it drops back.
- **The race:** whoever reaches the passenger first gets them.
- **Liveries:** GYE NYAME and SEA NEVER DRY. Rivals never appear as normal traffic.

### Score, world and presentation
- **Score** = fares − fines (§21). The best score is saved on the device.
- **World:**
  - Approved Accra buildings, a landmark mosque, and worn asphalt.
  - Kerbs, open drains, power lines and trees.
  - Kiosks, umbrella stalls and polytank stands between buildings.
  - A hazy skyline.
- **Street background (owner's recordings, `assets/audio/ambience/`):** plays quietly under the music while driving.
  - "Busy" at markets and go-slows, "some people" near a bus stop with passengers (and while stopped), "quiet" otherwise. It crossfades between them.
  - On the web the loader page streams the recordings (`trotroAmbience()`), so they aren't in the game download.
  - SOUND off mutes them; MUSIC off doesn't.
- **Voices (owner's recordings, `assets/audio/voice/`):** cleaned (rumble and hiss filtered, silence trimmed, levels evened) with a very slight room echo. They sit under the music and street mix.
  - **The mate:** every line he shows has its recording, in the owner's wording. He speaks at a steady level from the trotro.
    - Route calls are long, so they come 14–22 s apart and never overlap him.
    - He stops talking when the police pull you over.
  - **Passengers:** the front person's line, by gender: women "Trotro! Trotro!", men "Bossu, stop stop!".
    - Heard at ~55 m and again at ~22 m, quieter with distance (about −6 dB per doubling past 8 m).
    - Destination calls ("Driver, Kasoa!") show on the sign but are silent for now.
  - **The fitter:** "Chale, come fix your car!", the same way.
- **Horn:** the owner's car horn recording (`assets/audio/sfx/horn.mp3`), turned down 5 dB, and spaced out because it's 2.8 s long.
- **Rival vs the booster:**
  - x1: days 1–4 it falls away. From day 5 it gains a little more each day, and it overtakes from day ~9 if it started 12 m back.
  - x2: days 1–5 it falls away. Days 6–8 it hangs on. From day 10 it's about 2% faster, so it can just edge past if it's already close.
  - A rival turning up also brings a booster offer.
- **Audio:** synthesised sounds are built in. Real sound files and music can be dropped in with no code changes; see `assets/audio/README.md`. The music crossfades to an intense track during chases, police and go-slows.

## Tuning knobs (quick changes)
| What | Where |
|---|---|
| Base / top speed, speed creep, speeding threshold | `scripts/player_trotro.gd` (top of file) |
| Day length, sales target, target growth | `scripts/game_state.gd` constants |
| Crash damage, traffic density, near-miss rush | `scripts/traffic_manager.gd` |
| Road event spacing, checkpoint flag chance, jam size | `scripts/road_events.gd` exports |
| Stop spacing, group sizes, fares, rival chance | `scripts/pickup_manager.gd` exports |
| Recklessness rates, fine amount | `scripts/police_manager.gd` exports |
| Camera | constants at the top of `scripts/camera_controller.gd` |

## Web / mobile build
See `tools/web/README.md` for exporting, packing for Artifact hosting, and the headless phone play-test. For itch.io, see `docs/ITCH_PAGE.md`: the upload zip comes from `tools/web/pack_itch.py`.
- **Shadows:** no real-time sun shadows on the web (they doubled first-visit shader compile time). Vehicles keep painted contact shadows.
- **Canvas density:** capped at 1.5× pixel density; the browser scales it up. At a phone's full 3×, the copy to the screen cost more than the game itself.
- **Phones:**
  - 3D renders at 70% resolution, dropping to 55% if the frame rate stays under 24 fps.
  - The roadside is drawn 220 m ahead (260 m on desktop), with the same light haze as desktop.
- **Textures:** 512 px for buildings, props and people, and 1024 for the road, stored as Basis Universal with RDO 3.0.
  - RDO cut those textures by ~22% with no visible change (checked side by side and by PSNR).
  - Vehicles and characters stay as lossy WebP: smaller to download, but more GPU memory. Basis would add ~5 MB of download.
  - The cover posters are loaded only while the cover is up, which frees ~10 MB of GPU memory while driving.
- **Download before play:** about 27.5 MB: the engine is about 10.1 MB gzipped, and the game data about 17.3 MB, including the voices.
  - The music (~6.8 MB) and the street recordings (~1.9 MB) stream afterwards.
  - The loading screen shows a bar only, with no sizes (owner).
- **Not exported:** the vehicle pictures the game no longer uses (3/4, side and high-angle views). They stay in `assets/`, and `tools/web/pck_contents.py` lists what's inside the game data.
- **Loading:** the loading screen stays up until the first frame is drawn. Effects that only appear later in a run are pre-warmed behind the start screen.
- **Leaving the game:** switching app or tab pauses the run. A portrait-only prompt appears on phones held sideways.
- **Diagnostics:** add `?perf` to the address to log fps, the per-system script time and hitches in the console.

## Known issues / to decide
- **Balance needs human play-testing:** the day target, damage and fines were tuned with bots.
- **Music on the web:** the loader page streams the two songs itself (`trotroMusic()` in `tools/web/loader.html`). They aren't part of the game download, and they play on the browser's own audio. Elsewhere, Godot plays them.
- **Music:** the owner's tracks are in `assets/audio/music/`.
  - `music_menu.mp3` ("Griot Strings") plays on the cover, day-complete and game-over screens.
  - `music_main.mp3` ("Savanna Drive") plays while driving and pauses with the pause menu.
  - They crossfade over 1.2 s. Browsers only allow sound after the first tap.
- **First visit is slow:** a browser's first visit spends a while compiling graphics shaders, partly Godot's own. Later visits are much faster.

## Image generation
The tool is in `tools/imagegen/`, and every call is recorded in `tools/imagegen/ledger.json`. About **$2.59 of the $3.00** budget has been spent. The API key is stored outside the project, at `%USERPROFILE%\.trotro_rush\openai_api_key`.
