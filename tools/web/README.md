# Web build and hosting

1. **Export:** Godot → Project → Export → Web, or headless:
   `Godot --headless --path . --export-release "Web" "build/web/index.html"`
2. **Pack for Artifact hosting:** Artifacts allow at most 15 MB per file.
   - Run `python tools/web/pack_web.py build/web <out_dir>`. It gzips `index.wasm` and `index.pck` and splits them into parts named `*.gz.N.wasm`. The `.wasm` extension is only there so the host will serve the files.
   - It prints a manifest. Copy that manifest into `PARTS` in `loader.html`, and copy the sizes into `fileSizes`.
3. **Publish:** publish `loader.html` together with these files: `index.js`, both `index.audio*.worklet.js` files, all the `*.gz.N.wasm` parts, and the three loading-screen images.
   - `trotro.png` is a copy of `assets/ui/icon_trotro.png`; it drives along the loading bar.
   - `cover_portrait.jpg` and `cover_landscape.jpg` come from `assets/ui/`.
4. **Phone play-test:** serve `build/web` on `127.0.0.1:8060` (see `.claude/launch.json`), then run `python tools/web/phone_test.py <shots_dir>`.
   - It drives headless Chrome as an Android phone: it taps to start, drags to steer and takes screenshots.
   - It reports FPS. Change `CHROME` at the top of the file if Chrome is installed elsewhere.
