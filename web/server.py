#!/usr/bin/env python3
"""Claude Crew web: a page for the claude-crew fleet.

Every action runs one claude-crew command. The page holds no fleet logic of its
own, so a fix to claude-crew is a fix here too.

  python3 server.py                 serve on 127.0.0.1:$CREW_WEB_PORT (3115)
  python3 server.py set-password    set the login password (read from stdin)
"""
import getpass
import hashlib
import hmac
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST, PORT = "127.0.0.1", int(os.environ.get("CREW_WEB_PORT", "3115"))
ROOT = Path(__file__).resolve().parent
CREW = os.environ.get("CREW_BIN", str(ROOT.parent / "bin" / "claude-crew"))
CONFIG = Path(os.environ.get("CREW_WEB_CONFIG", "/root/.config/claude-crew-web"))
PASSWORD_FILE = CONFIG / "password"
TOKENS_FILE = CONFIG / "tokens.json"
REFRESH_S = 15
TOKEN_DAYS = 30
ENV = {**os.environ, "HOME": os.environ.get("HOME", "/root"),
       "PATH": "/root/.local/bin:/root/.nvm/versions/node/v22.23.1/bin:/usr/local/bin:/usr/bin:/bin"}

MODELS = ("claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-sonnet-5",
          "claude-fable-5-1", "claude-haiku-4-5", "opus", "sonnet", "fable", "haiku")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
PERMISSION_MODES = ("acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan")
TITLE_RE = re.compile(r"^[^\x00-\x1f\x7f]{1,80}$")
PROMPT_RE = re.compile(r"^[^\x00-\x09\x0b-\x1f\x7f]{1,4000}$")
AUTOCOMPACT_RE = re.compile(r"^(auto|[0-9]+[kKmM]?)$")

_state = {"data": None, "updated": 0.0, "error": None}
_lock = threading.Lock()
_wake = threading.Event()


# --- password and tokens -------------------------------------------------------
def hash_password(pw, salt=None, rounds=600_000):
    salt = salt or secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, rounds)
    return f"pbkdf2_sha256${rounds}${salt.hex()}${dk.hex()}"


def check_password(pw):
    try:
        _, rounds, salt, want = PASSWORD_FILE.read_text().strip().split("$")
    except (OSError, ValueError):
        return False
    got = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), int(rounds)).hex()
    return hmac.compare_digest(got, want)


def write_private(path, text):
    CONFIG.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


class Tokens:
    """Login tokens, stored as SHA-256 digests so the file cannot be replayed."""

    def __init__(self):
        self.lock = threading.Lock()
        try:
            self.t = json.loads(TOKENS_FILE.read_text())
        except (OSError, ValueError):
            self.t = {}

    @staticmethod
    def digest(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def _save(self):
        now = time.time()
        self.t = {k: v for k, v in self.t.items() if v > now}
        write_private(TOKENS_FILE, json.dumps(self.t))

    def issue(self):
        token = secrets.token_urlsafe(32)
        with self.lock:
            self.t[self.digest(token)] = time.time() + TOKEN_DAYS * 86400
            self._save()
        return token

    def valid(self, token):
        if not token:
            return False
        with self.lock:
            return self.t.get(self.digest(token), 0) > time.time()

    def revoke(self, token):
        with self.lock:
            if self.t.pop(self.digest(token or ""), None) is not None:
                self._save()


TOKENS = None
_fails = {}          # ip -> [failure times]
_fails_lock = threading.Lock()
FAIL_LIMIT, FAIL_WINDOW = 5, 900


def throttled(ip):
    now = time.time()
    with _fails_lock:
        recent = [t for t in _fails.get(ip, []) if now - t < FAIL_WINDOW]
        _fails[ip] = recent
        return len(recent) >= FAIL_LIMIT


def record_fail(ip):
    with _fails_lock:
        _fails.setdefault(ip, []).append(time.time())


# --- fleet ----------------------------------------------------------------------
def crew(*args, timeout=180):
    p = subprocess.run([CREW, *args], capture_output=True, text=True, env=ENV,
                       timeout=timeout, cwd=ENV["HOME"])
    return p.returncode, (p.stdout + p.stderr).strip()


def refresh():
    code, out = crew("status", "--json", timeout=120)
    data = json.loads(out.splitlines()[-1]) if code == 0 else None
    with _lock:
        if data is not None:
            _state.update(data=data, updated=time.time(), error=None)
        else:
            _state["error"] = out[-300:]


def refresher():
    while True:
        try:
            refresh()
        except Exception as e:
            with _lock:
                _state["error"] = str(e)
        _wake.wait(REFRESH_S)
        _wake.clear()


def known(kind):
    with _lock:
        d = _state["data"] or {}
    if kind == "slots":
        return {s["slot"] for s in d.get("slots", [])}
    ids = {s["id"] for s in d.get("slots", []) if s.get("id")}
    return ids | {c["id"] for c in d.get("conversations", [])}


def defaults_args(a):
    args = []
    if a.get("model") is not None:
        if a["model"] not in MODELS:
            return None, "Unknown model."
        args += ["--model", a["model"]]
    if a.get("effort") is not None:
        if a["effort"] not in EFFORTS:
            return None, "Unknown effort."
        args += ["--effort", a["effort"]]
    if a.get("slots") is not None:
        if not (isinstance(a["slots"], int) and 1 <= a["slots"] <= 12):
            return None, "Slots must be 1–12."
        args += ["--slots", str(a["slots"])]
    if a.get("remote_control") is not None:
        if a["remote_control"] not in ("on", "off"):
            return None, "Remote control is on or off."
        args += ["--remote-control", a["remote_control"]]
    if a.get("permission_mode") is not None:
        if a["permission_mode"] not in PERMISSION_MODES:
            return None, "Unknown permission mode."
        args += ["--permission-mode", a["permission_mode"]]
    if a.get("autocompact") is not None:
        if not AUTOCOMPACT_RE.match(str(a["autocompact"])):
            return None, "Auto-compact is auto or a size such as 400k."
        args += ["--autocompact", str(a["autocompact"])]
    if not args:
        return None, "Nothing to change."
    return args, None


def run_action(a):
    """Returns (exit code, output, message). The message is what the page shows on success."""
    op, slot, conv = a.get("op"), a.get("slot"), a.get("conv")
    if slot is not None and slot not in known("slots"):
        return 400, "Unknown slot. Refresh and try again.", None
    if conv is not None and conv not in known("convs"):
        return 400, "Unknown conversation. Refresh and try again.", None
    s = str(slot)
    if op == "stop" and slot:
        return (*crew("stop", s), "Stopped.")
    if op == "relaunch" and slot:
        return (*crew("relaunch", s), "Restarted.")
    if op == "switch" and slot and conv:
        return (*crew("switch", s, conv), "Done.")
    if op in ("new", "clear") and slot:
        title = (a.get("title") or "").strip()
        if op == "new" or title:
            if not TITLE_RE.match(title):
                return 400, "Title needs 1–80 printable characters.", None
        if op == "new":
            return (*crew("new", title, "--slot", s), "Started.")
        return (*crew("clear", s, *([title] if title else [])), "Started a new conversation.")
    if op == "prompt" and slot:
        text = (a.get("text") or "").strip()
        if not PROMPT_RE.match(text):
            return 400, "The prompt needs 1–4000 characters.", None
        return (*crew("prompt", s, text), "Sent.")
    if op == "delete" and conv:
        return (*crew("delete", conv, "--yes"), "Deleted.")
    if op == "defaults":
        args, err = defaults_args(a)
        if err:
            return 400, err, None
        return (*crew("setup", *args), "Defaults saved.")
    if op == "boot" and a.get("value") in ("on", "off"):
        return (*crew("boot", a["value"]), "Starts on boot." if a["value"] == "on" else "Does not start on boot.")
    if op == "start":
        return (*crew("start", timeout=600), "Saved sessions started.")
    if op == "save":
        return (*crew("save"), "Current sessions saved.")
    if op == "relabel":
        return (*crew("relabel"), "Window labels updated.")
    if op == "restart":
        return (*crew("restart"), "Restarting every session in 15 seconds.")
    if op == "update":
        return (*crew("update", timeout=600), "Updated. Restarting every session in 15 seconds.")
    return 400, "Unknown action.", None


# --- http -----------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "claude-crew-web"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="application/json", headers=()):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def ip(self):
        return self.headers.get("X-Real-IP") or self.client_address[0]

    def token(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "crew_token":
                return v
        return None

    def authed(self):
        return TOKENS.valid(self.token())

    def body(self):
        n = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(min(n, 8192)) or b"{}")

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self.send(200, (ROOT / "index.html").read_bytes(), "text/html")
        if self.path == "/api/state":
            if not self.authed():
                return self.send(401, '{"error":"login"}')
            with _lock:
                body = json.dumps({**_state, "now": time.time()})
            return self.send(200, body)
        self.send(404, '{"error":"not found"}')

    def do_POST(self):
        # A custom header cannot be sent cross-site without a preflight, which
        # this server never answers, so a foreign page cannot post here.
        if self.headers.get("X-Crew") != "1":
            return self.send(403, '{"error":"forbidden"}')
        try:
            a = self.body()
        except Exception:
            return self.send(400, '{"error":"bad request"}')
        if self.path == "/api/login":
            return self.login(a)
        if self.path == "/api/logout":
            TOKENS.revoke(self.token())
            return self.send(200, '{"ok":true}', headers=[("Set-Cookie", cookie("", 0))])
        if self.path != "/api/action":
            return self.send(404, '{"error":"not found"}')
        if not self.authed():
            return self.send(401, '{"error":"login"}')
        code, out, msg = run_action(a)
        print(f"action ip={self.ip()} op={a.get('op')} slot={a.get('slot')} "
              f"conv={a.get('conv')} code={code}", flush=True)
        ok = code == 0
        if ok:
            try:
                refresh()
            except Exception:
                pass
        _wake.set()
        self.send(200 if ok else (code if code >= 400 else 500),
                  json.dumps({"ok": ok, "message": msg if ok else None, "output": out[-2000:]}))

    def login(self, a):
        ip = self.ip()
        if throttled(ip):
            return self.send(429, '{"error":"Too many attempts. Wait 15 minutes."}')
        if not check_password(str(a.get("password", ""))):
            record_fail(ip)
            print(f"login failed ip={ip}", flush=True)
            return self.send(401, '{"error":"Wrong password."}')
        print(f"login ok ip={ip}", flush=True)
        return self.send(200, '{"ok":true}', headers=[("Set-Cookie", cookie(TOKENS.issue(), TOKEN_DAYS * 86400))])


def cookie(value, max_age):
    return f"crew_token={value}; Max-Age={max_age}; Path=/; HttpOnly; Secure; SameSite=Strict"


def set_password():
    pw = getpass.getpass("New password: ") if sys.stdin.isatty() else sys.stdin.readline().rstrip("\n")
    if len(pw) < 8:
        sys.exit("The password needs at least 8 characters.")
    write_private(PASSWORD_FILE, hash_password(pw) + "\n")
    write_private(TOKENS_FILE, "{}")
    print(f"Password set in {PASSWORD_FILE}. Every existing login was signed out.")


if __name__ == "__main__":
    if sys.argv[1:] == ["set-password"]:
        set_password()
        sys.exit(0)
    if not PASSWORD_FILE.exists():
        sys.exit(f"No password yet. Run: python3 {__file__} set-password")
    TOKENS = Tokens()
    threading.Thread(target=refresher, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
