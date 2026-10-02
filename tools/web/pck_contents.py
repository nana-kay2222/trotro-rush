"""Lists what's inside an exported Godot 4 .pck, biggest first, grouped by folder.
Usage: python tools/web/pck_contents.py build/web/index.pck"""
import collections, struct, sys

data = open(sys.argv[1], "rb").read()
assert data[:4] == b"GDPC", "not a pck"
fmt, major, minor, patch, flags, files_base = struct.unpack_from("<IIIIIQ", data, 4)
pos = 4 + 4 * 5 + 8
if fmt >= 3:
    dir_offset = struct.unpack_from("<Q", data, pos)[0]
    pos = dir_offset
else:
    pos += 16 * 4
count = struct.unpack_from("<I", data, pos)[0]
pos += 4
files = []
for _ in range(count):
    n = struct.unpack_from("<I", data, pos)[0]; pos += 4
    path = data[pos:pos + n].rstrip(b"\0").decode("utf-8", "replace"); pos += n
    ofs, size = struct.unpack_from("<QQ", data, pos); pos += 16
    pos += 16  # md5
    pos += 4   # flags
    files.append((size, path))
files.sort(reverse=True)
groups = collections.Counter()
for size, path in files:
    p = path.replace("res://", "")
    key = "/".join(p.split("/")[:3]) if p.startswith(".godot/imported") else "/".join(p.split("/")[:2])
    if p.startswith(".godot/imported/"):
        name = p.split("/")[-1]
        key = "imported:" + name.split("-")[0].rsplit(".", 1)[0].rsplit("_", 1)[0]
    groups[key] += size
print(f"{count} files, {sum(s for s, _ in files) / 1e6:.1f} MB")
for size, path in files[:40]:
    print(f"{size / 1e6:7.2f} MB  {path}")
