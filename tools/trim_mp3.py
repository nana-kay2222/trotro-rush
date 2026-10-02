"""Cuts an MP3 at a whole-frame boundary near a given time, without re-encoding.
Used to drop the trailing silence from the music so it loops without a gap.
Usage: python tools/trim_mp3.py <in.mp3> <out.mp3> <seconds>"""
import sys

BITRATES = {  # MPEG-1 Layer III, kbps
    1: 32, 2: 40, 3: 48, 4: 56, 5: 64, 6: 80, 7: 96, 8: 112, 9: 128, 10: 160, 11: 192, 12: 224, 13: 256, 14: 320}
RATES = {0: 44100, 1: 48000, 2: 32000}

src, dst, cut = sys.argv[1], sys.argv[2], float(sys.argv[3])
data = open(src, "rb").read()
pos = 0
if data[:3] == b"ID3":  # skip an ID3v2 tag
    size = (data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]
    pos = 10 + size
start = pos
t = 0.0
frames = 0
while pos + 4 <= len(data):
    h = data[pos:pos + 4]
    if h[0] != 0xFF or (h[1] & 0xE0) != 0xE0:
        pos += 1  # resync
        continue
    version = (h[1] >> 3) & 3   # 3 = MPEG-1
    layer = (h[1] >> 1) & 3     # 1 = Layer III
    br = BITRATES.get(h[2] >> 4)
    sr = RATES.get((h[2] >> 2) & 3)
    if version != 3 or layer != 1 or not br or not sr:
        pos += 1
        continue
    pad = (h[2] >> 1) & 1
    length = 144 * br * 1000 // sr + pad
    if t >= cut:
        break
    t += 1152 / sr
    frames += 1
    pos += length
open(dst, "wb").write(data[:pos])
print(f"{src}: kept {frames} frames = {t:.2f} s, {pos} of {len(data)} bytes")
