#!/usr/bin/env python3
"""panelprobe.py — measure the state of the WebView2 panels via the CDP.

Why: a screenshot of the X window says nothing about whether the panel has content.
Under Wayland (KWin) the Xwayland root is empty, and the panel windows only draw the
Chromium content via the dcomp shim. The only reliable way is the DevTools protocol
(CDP): WebView2 is started with --remote-debugging-port, then
    Page.captureScreenshot
delivers the content that is actually rendered.

Usage:
    panelprobe.py report PORT              # state report as JSON (one line)
    panelprobe.py shot PORT OUT.png        # screenshot of the content window
    panelprobe.py menu PORT OUT.png        # screenshot of the menu window
    panelprobe.py list PORT                # list all targets
    panelprobe.py click PORT NEEDLE X Y

Standard library only. Exit: 0 = menu visible and filled, 1 = menu empty,
2 = no menu target found, 3 = CDP not reachable.
"""
import base64, json, os, socket, struct, sys, urllib.request

# ----------------------------------------------------------------- WebSocket
class WS:
    """Minimal WebSocket client (stdlib only)."""

    def __init__(self, url, host="127.0.0.1"):
        _, _, rest = url.partition("://")
        hostport, _, path = rest.partition("/")
        h, _, p = hostport.partition(":")
        self.s = socket.create_connection((h or host, int(p or 80)), timeout=15)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               f"Sec-WebSocket-Version: 13\r\n\r\n")
        self.s.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.s.recv(4096)
            if not chunk:
                raise EOFError("Handshake abgebrochen")
            buf += chunk
        if b"101" not in buf.split(b"\r\n")[0]:
            raise EOFError("Handshake: " + buf.split(b"\r\n")[0].decode("utf8", "replace"))
        self.rest = buf.split(b"\r\n\r\n", 1)[1]

    def _recv(self, n):
        out = self.rest[:n]
        self.rest = self.rest[n:]
        while len(out) < n:
            chunk = self.s.recv(n - len(out))
            if not chunk:
                raise EOFError("connection closed")
            out += chunk
        return out

    def send(self, obj):
        data = json.dumps(obj).encode()
        mask = os.urandom(4)
        head = bytearray([0x81])
        n = len(data)
        if n < 126:
            head.append(0x80 | n)
        elif n < 65536:
            head.append(0x80 | 126); head += struct.pack(">H", n)
        else:
            head.append(0x80 | 127); head += struct.pack(">Q", n)
        head += mask
        self.s.sendall(bytes(head) + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def recv(self):
        payload = b""
        while True:
            b0, b1 = self._recv(2)
            fin, opcode = b0 & 0x80, b0 & 0x0F
            ln = b1 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv(8))[0]
            data = self._recv(ln)
            if opcode == 0x8:
                raise EOFError("Close-Frame")
            if opcode == 0x9:
                self.s.sendall(b"\x8a\x80" + os.urandom(4))
                continue
            if opcode in (0x1, 0x2, 0x0):
                payload += data
            if fin:
                return payload.decode("utf8", "replace")

    def close(self):
        try:
            self.s.close()
        except Exception:
            pass


def call(ws, method, params=None, _id=[0]):
    _id[0] += 1
    ws.send({"id": _id[0], "method": method, "params": params or {}})
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == _id[0]:
            return msg


# --------------------------------------------------------------------- CDP
def targets(port):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=6) as r:
        return json.load(r)


def pick(port, needle):
    n = needle.lower()
    for t in targets(port):
        if n in (t.get("title", "") + " " + t.get("url", "")).lower():
            return t
    return None


def js(port, needle, expr):
    t = pick(port, needle)
    if not t:
        return None
    ws = WS(t["webSocketDebuggerUrl"])
    try:
        r = call(ws, "Runtime.evaluate",
                 {"expression": expr, "returnByValue": True, "awaitPromise": True})
        return r.get("result", {}).get("result", {}).get("value")
    finally:
        ws.close()


def shot(port, needle, out, beyond=False):
    t = pick(port, needle)
    if not t:
        return None
    ws = WS(t["webSocketDebuggerUrl"])
    try:
        r = call(ws, "Page.captureScreenshot",
                 {"format": "png", "captureBeyondViewport": beyond})
        b64 = r.get("result", {}).get("data")
        if not b64:
            return None
        raw = base64.b64decode(b64)
        with open(out, "wb") as fh:
            fh.write(raw)
        return len(raw)
    finally:
        ws.close()


def color_count(path):
    """Number of different colours in the PNG — a rough measure for 'there is content'."""
    try:
        from PIL import Image
    except Exception:
        return -1
    try:
        im = Image.open(path).convert("RGB")
    except Exception:
        return -1
    try:
        return len(im.getcolors(im.width * im.height) or [])
    except Exception:
        return -1


# ------------------------------------------------------------------ report
MENU_STATE = r"""(()=>{
  const de = document.documentElement, b = document.body;
  const tx = b ? b.innerText.replace(/\s+/g,' ') : '';
  return JSON.stringify({
    iw: innerWidth, ih: innerHeight,
    de: [de.offsetWidth, de.offsetHeight],
    n: document.querySelectorAll('*').length,
    items: document.querySelectorAll('[parts-menu]').length,
    text: tx.slice(0, 120)
  });})()"""


def content_page(port):
    """The Hub content area: everything that is not a file page."""
    for t in targets(port):
        if t.get("type") != "page":
            continue
        u = t.get("url", "")
        if u.startswith("file:") or u.startswith("about:"):
            continue
        return t
    return None


def report(port):
    out = {"port": port, "menu_found": False, "menu_iw": 0, "menu_h": 0,
           "menu_items": 0, "menu_text": "", "content_url": "", "content_title": "",
           "content_text": "", "content_403": False, "content_els": 0}
    st = js(port, "menu.html", MENU_STATE)
    if st:
        d = json.loads(st)
        out.update(menu_found=True, menu_iw=d["iw"], menu_h=d["ih"],
                   menu_items=d["items"], menu_text=d["text"])
    t = content_page(port)
    if t:
        s = js(port, t["url"][-40:], r"""(()=>{const b=document.body;
          return JSON.stringify({u:location.href, t:document.title.slice(0,70),
            n:document.querySelectorAll('*').length,
            tx:(b?b.innerText.replace(/\s+/g,' '):'').slice(0,160)});})()""")
        if s:
            d = json.loads(s)
            out.update(content_url=d["u"], content_title=d["t"],
                       content_els=d["n"], content_text=d["tx"])
            blob = (d["t"] + " " + d["tx"]).lower()
            out["content_403"] = ("403 forbidden" in blob or "403 - forbidden" in blob)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 64
    port = int(argv[2])
    cmd = argv[1]
    try:
        if cmd == "list":
            for t in targets(port):
                print(f"{t.get('type','?'):7s} | {t.get('title','')[:58]:58s} | "
                      f"{t.get('url','')[:88]}")
            return 0
        if cmd == "report":
            r = report(port)
            print(json.dumps(r, ensure_ascii=False))
            if not r["menu_found"]:
                return 2
            # menu visible and filled? 1x1 = collapsed, >100 = open and filled.
            return 0 if r["menu_iw"] > 100 else 1
        if cmd == "shot":
            n = shot(port, argv[3], argv[4])
            if n is None:
                print("no target / no image")
                return 2
            print(f"{argv[4]} {n} B colors={color_count(argv[4])}")
            return 0
        if cmd == "menu":
            n = shot(port, "menu.html", argv[3], beyond=True)
            if n is None:
                print("no menu target")
                return 2
            c = color_count(argv[3])
            print(f"{argv[3]} {n} B colors={c}")
            return 0 if c > 500 else 1
        if cmd == "click":
            needle, x, y = argv[3], float(argv[4]), float(argv[5])
            t = pick(port, needle)
            if not t:
                return 2
            ws = WS(t["webSocketDebuggerUrl"])
            try:
                for typ in ("mouseMoved", "mousePressed", "mouseReleased"):
                    call(ws, "Input.dispatchMouseEvent",
                         {"type": typ, "x": x, "y": y, "button": "left",
                          "clickCount": 1})
            finally:
                ws.close()
            return 0
    except (EOFError, OSError) as e:
        print(f"CDP not reachable: {e}")

        return 3
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
