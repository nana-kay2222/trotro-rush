"""Writes pack_web.py's manifest into loader.html (PARTS and fileSizes) and copies the
result into the pack folder as trotro_rush.html.
Usage: python tools/web/pack_web.py build/web <pack_dir> > <pack_dir>/manifest.json
       python tools/web/set_sizes.py <pack_dir>"""
import json, re, sys

pack_dir = sys.argv[1]
manifest = json.load(open(pack_dir + "/manifest.json", encoding="utf-8-sig"))
path = "tools/web/loader.html"
t = open(path, encoding="utf-8").read()
t = re.sub(r"const PARTS = \{.*?\};", lambda m: "const PARTS = " + json.dumps(manifest) + ";", t, flags=re.S)
sizes = {"index.pck": manifest["index.pck"]["size"], "index.wasm": manifest["index.wasm"]["size"]}
t = re.sub(r'"fileSizes":\{[^}]*\}', lambda m: '"fileSizes":' + json.dumps(sizes, separators=(",", ":")), t)
open(path, "w", encoding="utf-8").write(t)
open(pack_dir + "/trotro_rush.html", "w", encoding="utf-8").write(t)
print("sizes set:", sizes)
