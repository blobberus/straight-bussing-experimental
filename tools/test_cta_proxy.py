#!/usr/bin/env python3
"""Tests for tools/cta-proxy/worker.js (the owner's CTA proxy, a Cloudflare Worker) without Node or Cloudflare: the
Worker is a plain ES module, so a page in headless Edge imports it, stubs fetch with made-up CTA Bus Tracker answers and
checks the endpoint, the cache, CORS and that the key never leaves it. Usage: python tools/test_cta_proxy.py"""
import functools, http.server, os, re, shutil, subprocess, sys, tempfile, threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EDGE = os.environ.get("EDGE", r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
PAGE = Path(__file__).resolve().parent / "cta-proxy" / "test.html"


def main():
    tmp = Path(tempfile.mkdtemp(prefix="ctaproxy-"))
    try:
        shutil.copy(ROOT / "tools" / "cta-proxy" / "worker.js", tmp / "worker.js")
        shutil.copy(PAGE, tmp / "test.html")

        class H(http.server.SimpleHTTPRequestHandler):
            extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".js": "text/javascript"}

            def log_message(self, *a):
                pass

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(H, directory=str(tmp)))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{srv.server_address[1]}/test.html"
        r = subprocess.run([EDGE, "--headless=new", "--disable-gpu", f"--user-data-dir={tmp / 'prof'}",
                            "--virtual-time-budget=10000", "--dump-dom", url], capture_output=True, text=True, timeout=120)
        srv.shutdown()
        m = re.search(r"<title>TESTS pass=(\d+) fail=(\d+)</title>", r.stdout)
        pre = re.search(r'<pre id="r">(.*?)</pre>', r.stdout, re.S)
        print(pre.group(1) if pre else r.stdout[-2000:])
        if not m or int(m.group(2)):
            sys.exit(1)
        print(f"ok {m.group(1)} checks")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
