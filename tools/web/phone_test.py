"""Minimal Chrome DevTools Protocol client (stdlib only) to play-test the web build as a phone.

Usage: python cdp.py <out_dir> [steps...]
Launches headless Chrome, emulates an Android phone, loads the game, taps to start, then
runs a scripted drive (drags left/right), taking screenshots and reporting FPS + console.
"""
import base64, json, os, socket, struct, subprocess, sys, time, urllib.request

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT = 9333
URL = "http://127.0.0.1:8060/index.html"
OUT = sys.argv[1]
W, H, DPR = 390, 844, 2.0


class WS:
    def __init__(self, url):
        host_port, path = url[len("ws://"):].split("/", 1)
        host, port = host_port.split(":")
        self.s = socket.create_connection((host, int(port)))
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.s.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0
        self.events = []

    def _recv_exact(self, n):
        while len(self.rest) < n:
            chunk = self.s.recv(1 << 20)
            if not chunk:
                raise EOFError
            self.rest += chunk
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def recv(self):
        data = b""
        while True:
            b1, b2 = self._recv_exact(2)
            fin, op = b1 & 0x80, b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._recv_exact(8))[0]
            data += self._recv_exact(n)
            if fin:
                return json.loads(data.decode())

    def send(self, obj):
        payload = json.dumps(obj).encode()
        mask = os.urandom(4)
        hdr = bytes([0x81])
        n = len(payload)
        if n < 126:
            hdr += bytes([0x80 | n])
        elif n < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack(">Q", n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.s.sendall(hdr + mask + masked)

    def call(self, method, **params):
        self.next_id += 1
        mid = self.next_id
        self.send({"id": mid, "method": method, "params": params})
        while True:
            msg = self.recv()
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            self.events.append(msg)

    def drain_console(self):
        lines = []
        for e in self.events:
            if e.get("method") == "Runtime.consoleAPICalled":
                lines.append(" ".join(str(a.get("value", a.get("description", ""))) for a in e["params"]["args"]))
            elif e.get("method") == "Runtime.exceptionThrown":
                lines.append("EXCEPTION " + e["params"]["exceptionDetails"].get("text", ""))
        self.events = []
        return lines


def evaluate(ws, expr, await_promise=False):
    r = ws.call("Runtime.evaluate", expression=expr, awaitPromise=await_promise, returnByValue=True)
    return r.get("result", {}).get("value")


def shot(ws, name):
    r = ws.call("Page.captureScreenshot", format="png")
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(base64.b64decode(r["data"]))


def touch(ws, kind, x, y):
    pts = [] if kind == "touchEnd" else [{"x": x, "y": y, "id": 1}]
    ws.call("Input.dispatchTouchEvent", type=kind, touchPoints=pts)


def fps(ws, seconds=2.0):
    return evaluate(ws, f"""new Promise(r=>{{let n=0;const t0=performance.now();function f(){{n++;
        if(performance.now()-t0<{seconds*1000}) requestAnimationFrame(f); else r(n/{seconds});}} requestAnimationFrame(f);}})""", True)


def main():
    os.makedirs(OUT, exist_ok=True)
    prof = os.path.join(OUT, "chrome_profile")
    proc = subprocess.Popen([CHROME, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}",
                             "--enable-gpu", "--ignore-gpu-blocklist", "--use-angle=d3d11", "--autoplay-policy=no-user-gesture-required",
                             "--window-size=390,844", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json").read())
                page = next(t for t in targets if t["type"] == "page")
                break
            except Exception:
                time.sleep(0.2)
        ws = WS(page["webSocketDebuggerUrl"])
        ws.call("Runtime.enable")
        ws.call("Page.enable")
        ws.call("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=DPR, mobile=True)
        ws.call("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
        ws.call("Emulation.setUserAgentOverride", userAgent="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36")
        t0 = time.time()
        ws.call("Page.navigate", url=URL)
        # Wait for Godot to start (canvas + engine log line).
        started = False
        for _ in range(240):
            time.sleep(0.5)
            evaluate(ws, "1")
            log = ws.drain_console()
            for l in log:
                print("console:", l)
            if any("Build configuration" in l for l in log) or started:
                started = True
                break
        print(f"engine up after {time.time()-t0:.1f}s")
        time.sleep(4)
        for l in ws.drain_console():
            print("console:", l)
        print("canvas:", evaluate(ws, "(()=>{const c=document.querySelector('canvas');return [c.width,c.height,c.clientWidth,c.clientHeight]})()"))
        shot(ws, "web_0_start.png")
        print("fps on start screen:", fps(ws))
        # Tap to start.
        touch(ws, "touchStart", W / 2, H * 0.81)
        time.sleep(0.1)
        touch(ws, "touchEnd", W / 2, H * 0.81)
        time.sleep(3)
        shot(ws, "web_1_driving.png")
        print("fps driving:", fps(ws, 3.0))
        # Drive: hold and drag left, then right, like a player dodging.
        x = W / 2
        touch(ws, "touchStart", x, H * 0.75)
        for target, name in [(W * 0.25, "web_2_left.png"), (W * 0.75, "web_3_right.png"), (W * 0.5, "web_4_centre.png")]:
            steps = 12
            for i in range(steps):
                x += (target - x) / (steps - i)
                touch(ws, "touchMove", x, H * 0.75)
                time.sleep(0.05)
            time.sleep(1.2)
            shot(ws, name)
        touch(ws, "touchEnd", x, H * 0.75)
        # Let it run a while, snapshotting.
        for i in range(6):
            time.sleep(5)
            shot(ws, f"web_run_{i}.png")
        print("fps later:", fps(ws, 3.0))
        for l in ws.drain_console():
            print("console:", l)
    finally:
        proc.kill()


if __name__ == "__main__":
    main()
