# Putting Trotro Rush on itch.io

## Files ready to upload
| File | What it is |
|---|---|
| `build/trotro_rush_itch.zip` | The game (36.6 MB, 11 files, `index.html` at the root). Rebuild it with `python tools/web/pack_itch.py build/web build/trotro_rush_itch.zip` after a web export. |
| `build/itch_assets/cover_630x500.png` | The page thumbnail (itch's 630×500 cover size). |
| `build/itch_assets/shot_*.png` | Screenshots: the road, the x1 boost, the x2 boost, and a phone-sized view. |

The itch build is the same game and loading screen as the Artifact link, with the music streaming in the same way. itch allows 200 MB per file and compresses the files itself, so nothing is split.

## Creating the page (you do this; it needs your itch.io account)
1. Sign in at itch.io → **Dashboard → Create new project**.
2. **Title:** Trotro Rush. **Project URL:** e.g. `trotro-rush`.
3. **Kind of project:** HTML.
4. **Uploads:** upload `trotro_rush_itch.zip` and tick **"This file will be played in the browser"**.
5. **Embed options:**
   - **Viewport dimensions:** 405 × 720 (portrait).
   - Tick **Mobile friendly**, with orientation **Portrait**.
   - Tick **Automatically start on page load**, or leave click-to-play on. Click-to-play also counts as the first tap that browsers need before they allow sound.
   - Tick **Fullscreen button**. Leave **Enable scrollbars** off.
   - **SharedArrayBuffer support:** leave it **off**. The build doesn't use threads.
6. **Cover image:** `cover_630x500.png`. **Screenshots:** the `shot_*.png` files.
7. **Genre:** Racing (or Action). **Tags:** e.g. arcade, driving, endless, ghana, africa, mobile, one-button. Your choice.
8. **Visibility:** start with **Draft** or **Restricted** to test it on your phone, then set it to **Public** when you're happy.

## Suggested page text (edit freely)
> **Trotro Rush**: drive an Accra trotro through a working day.
>
> Hold and drag to steer. The trotro drives itself and speeds up as you drive cleanly.
> Swing into the bus stops to pick up passengers and hit the day's sales target before 6 PM.
> Dodge taxis, okadas, potholes, go-slows and market crowds. Race rival trotros to the passenger,
> stop for the police when they flag you, and pull into the fitter when the trotro is hurting.
> Tap the turbo when it pops up for a quick boost, or double-tap for the full 200 km/h blast.
>
> Plays in the browser on phones and computers. Best in portrait.

## Notes
- The first load takes a while on a phone, because the browser prepares the graphics. Later visits are faster.
- The music and the GHS amounts are part of the game; nothing on the page charges money. If you want donations or a price, that's a separate setting under **Pricing**.
