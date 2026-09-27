#!/usr/bin/env python3
"""CONNECT proxy that answers 403 for the hosts named in BLOCK (comma-separated),
as the cloud's egress proxy does, and tunnels everything else. Emulates a
Custom allowlist locally for #359: BLOCK is the set the Default run refused,
minus whatever the allowlist would add. Logs one line per CONNECT to stderr."""
import os, socket, sys, threading
BLOCK = {h for h in os.environ.get("BLOCK", "").split(",") if h}
def pipe(a, b):
    try:
        while (d := a.recv(65536)):
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass
def handle(c):
    req = b""
    while b"\r\n\r\n" not in req:
        d = c.recv(4096)
        if not d: return c.close()
        req += d
    line = req.split(b"\r\n")[0].decode()
    method, target, _ = line.split(" ", 2)
    host, port = target.rsplit(":", 1)
    if method != "CONNECT" or host in BLOCK:
        print(f"403 {target}", file=sys.stderr, flush=True)
        c.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n"); return c.close()
    print(f"ok  {target}", file=sys.stderr, flush=True)
    u = socket.create_connection((host, int(port)))
    c.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
    threading.Thread(target=pipe, args=(u, c), daemon=True).start()
    pipe(c, u)
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(os.environ.get("PORT", "18888")))); s.listen(64)
while True:
    threading.Thread(target=handle, args=(s.accept()[0],), daemon=True).start()
