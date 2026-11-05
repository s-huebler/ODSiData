#!/usr/bin/env python3
"""Local claim review viewer for the GVHD claims network.

Usage (from the ODSiData repo root):
    python3 claim-network/scripts/viewer/review_server.py guo2024

Opens http://localhost:8765 in your browser. Every Approve / Reject / Discuss click is written
immediately to claim-network/reviews/<paper>/decisions.json (source of truth) and mirrored to
decisions.csv. Standard library only. Stop with Ctrl+C.
"""
import json, os, sys, threading, webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from claimlib import REVIEWS, SKILLS, load_json, write_json, write_decisions_csv  # noqa: E402

PORT = int(os.environ.get("REVIEW_PORT", "8765"))
LOCK = threading.Lock()


def save_decision(paper, rec):
    d = REVIEWS / paper
    with LOCK:
        dec = load_json(d / "decisions.json", {})
        if rec.get("decision") is None:
            dec.pop(rec["id"], None)
        else:
            old = dec.get(rec["id"], {})
            if old.get("discussion"):
                rec["discussion"] = old["discussion"]
            rec["decided_at"] = datetime.now().isoformat(timespec="seconds")
            dec[rec["id"]] = rec
        write_json(d / "decisions.json", dec)
        write_decisions_csv(d, dec, load_json(d / "proposals.json"))
        return dec


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False)
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def static(self, path):
        types = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                 ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".css": "text/css"}
        if not path.is_file():
            return self.send(404, {"error": "not found"})
        self.send(200, path.read_bytes(), types.get(path.suffix.lower(), "application/octet-stream"))

    def do_GET(self):
        p = unquote(self.path.split("?")[0])
        if p in ("/", "/index.html"):
            return self.static(HERE / "viewer.html")
        if p == "/marked.min.js":
            return self.static(HERE / "marked.min.js")
        if p == "/api/papers":
            return self.send(200, sorted(x.parent.name for x in REVIEWS.glob("*/proposals.json")))
        if p.startswith("/api/paper/"):
            key = p.rsplit("/", 1)[1]
            prop = load_json(REVIEWS / key / "proposals.json")
            if prop is None:
                return self.send(404, {"error": f"no reviews/{key}/proposals.json"})
            md = (SKILLS / prop["skill"] / "references" / "paper.md").read_text(encoding="utf-8")
            dec = load_json(REVIEWS / key / "decisions.json", {})
            return self.send(200, {"proposals": prop, "markdown": md, "decisions": dec})
        if p.startswith("/skill/"):
            parts = p.split("/")  # /skill/<skill>/assets/...
            target = (SKILLS / parts[2]).joinpath(*parts[3:]).resolve()
            if SKILLS.resolve() not in target.parents:
                return self.send(403, {"error": "forbidden"})
            return self.static(target)
        self.send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/decision":
            return self.send(404, {"error": "not found"})
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        dec = save_decision(body["paper"], body["record"])
        self.send(200, {"ok": True, "n": len(dec)})


def main():
    paper = sys.argv[1] if len(sys.argv) > 1 else ""
    if paper and not (REVIEWS / paper / "proposals.json").exists():
        sys.exit(f"No proposals at {REVIEWS / paper / 'proposals.json'}")
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    url = f"http://localhost:{PORT}/" + (f"?paper={paper}" if paper else "")
    print(f"Claim review viewer running at {url}\nDecisions are saved to {REVIEWS / (paper or '<paper>')}\nCtrl+C to stop.")
    if not os.environ.get("REVIEW_NO_BROWSER"):
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
