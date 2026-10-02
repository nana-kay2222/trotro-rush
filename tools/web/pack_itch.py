"""Builds the itch.io upload: one zip with index.html at its root. itch serves the files
whole (up to 200 MB each) and gzips .wasm/.pck itself, so unlike the Artifact pack there is
no splitting: the loader page is used as-is with an empty PARTS table.
Usage: python tools/web/pack_itch.py build/web build/trotro_rush_itch.zip"""
import os, re, sys, zipfile

SRC, OUT = sys.argv[1], sys.argv[2]
page = open("tools/web/loader.html", encoding="utf-8").read()
page = re.sub(r"const PARTS = \{.*?\};", "const PARTS = {};", page, flags=re.S)
# The gzip check only matters for the split Artifact files.
page = page.replace("if (typeof DecompressionStream === 'undefined') missing.push('DecompressionStream (update your browser)');\n", "")
# itch embeds the game in an iframe without the Artifact page skeleton, so add the basics.
page = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">\n'
        '</head>\n<body>\n' + page + '\n</body>\n</html>\n')
files = {name: os.path.join(SRC, name) for name in
         ["index.js", "index.wasm", "index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js"]}
files.update({"cover_portrait.jpg": "assets/ui/cover_portrait.jpg", "cover_landscape.jpg": "assets/ui/cover_landscape.jpg",
              "trotro.png": "assets/ui/icon_trotro.png", "music_main.mp3": "assets/audio/music/music_main.mp3",
              "music_menu.mp3": "assets/audio/music/music_menu.mp3",
              "amb_busy.mp3": "assets/audio/ambience/amb_busy.mp3", "amb_some.mp3": "assets/audio/ambience/amb_some.mp3",
              "amb_quiet.mp3": "assets/audio/ambience/amb_quiet.mp3"})
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr("index.html", page)
    for name, path in files.items():
        z.write(path, name)
print(f"{OUT}: {os.path.getsize(OUT) / 1e6:.1f} MB, {len(files) + 1} files")
