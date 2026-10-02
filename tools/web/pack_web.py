"""Gzips the Godot web build's big files and splits them into <14 MB chunks for Artifact
hosting (15 MB per-file limit). Prints a JSON manifest the loader page embeds."""
import gzip, json, os, shutil, sys

SRC = sys.argv[1]
DST = sys.argv[2]
CHUNK = 14 * 1024 * 1024
os.makedirs(DST, exist_ok=True)
for f in os.listdir(DST):
    os.remove(os.path.join(DST, f))
manifest = {}
for name, ctype in [("index.wasm", "application/wasm"), ("index.pck", "application/octet-stream")]:
    raw = open(os.path.join(SRC, name), "rb").read()
    gz = gzip.compress(raw, compresslevel=9, mtime=0)
    parts = [gz[i:i + CHUNK] for i in range(0, len(gz), CHUNK)]
    for i, p in enumerate(parts):
        # ".wasm" only so Artifact hosting will serve the file; the loader gunzips the joined parts.
        open(os.path.join(DST, f"{name}.gz.{i}.wasm"), "wb").write(p)
    manifest[name] = {"parts": len(parts), "size": len(raw), "type": ctype}
    print(f"{name}: {len(raw)/1e6:.1f} MB -> gzip {len(gz)/1e6:.1f} MB in {len(parts)} parts", file=sys.stderr)
for extra in ["index.js", "index.audio.worklet.js", "index.audio.position.worklet.js", "index.png", "index.icon.png"]:
    shutil.copy(os.path.join(SRC, extra), os.path.join(DST, extra))
# The loader page's own files: cover art, the loading-bar trotro, and the music it streams.
for src, name in [("assets/ui/cover_portrait.jpg", "cover_portrait.jpg"), ("assets/ui/cover_landscape.jpg", "cover_landscape.jpg"),
                  ("assets/ui/icon_trotro.png", "trotro.png"), ("assets/audio/music/music_main.mp3", "music_main.mp3"),
                  ("assets/audio/music/music_menu.mp3", "music_menu.mp3"),
                  ("assets/audio/ambience/amb_busy.mp3", "amb_busy.mp3"), ("assets/audio/ambience/amb_some.mp3", "amb_some.mp3"),
                  ("assets/audio/ambience/amb_quiet.mp3", "amb_quiet.mp3")]:
    shutil.copy(src, os.path.join(DST, name))
print(json.dumps(manifest))
