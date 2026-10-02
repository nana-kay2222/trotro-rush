# Drop-in audio

The game plays these automatically as soon as the files exist. No code changes are needed.
Use `.ogg` if you can (smallest for mobile web). `.mp3` and `.wav` also work.

## Music: `assets/audio/music/`
| File | Plays |
|---|---|
| `music_main.ogg` | The main loop, all the time (Afrobeat / highlife, 2–3 min, seamless loop) |
| `music_intense.ogg` | Optional. Crossfades in during tense moments: a rival chase, the police, a go-slow. Best if it's the same song with more drums/energy, so the fade is smooth. |

## Sound effects: `assets/audio/sfx/`
If one of these files exists, it replaces the built-in synthesised sound:
| File | Used for |
|---|---|
| `engine_loop.ogg` | The trotro engine, looped; its pitch rises with speed. A diesel minibus idle/drive loop works best. |
| `horn.ogg` | Rival horn, jam honking, the pedestrian warning |
| `crash.ogg` | Crashes and bumps |
| `pothole.ogg` | Potholes and speed bumps |
| `siren.ogg` | Police |
| `coin.ogg` | Fare collected |
| `drop.ogg` | Passengers dropping off, fines |
| `whoosh.ogg` | Boost and near-miss rush |
| `click.ogg` | Button taps |

## Where to get them
- **Sound effects:** freesound.org. Filter by the CC0 licence. Search for "diesel minibus", "car horn Ghana", "Accra street", "car crash".
- **Music:**
  - a Ghanaian producer (local, or via Fiverr) for an original track;
  - Pixabay Music (free; check each track's licence);
  - AI tools such as Suno or Udio (read their commercial-use terms first).
