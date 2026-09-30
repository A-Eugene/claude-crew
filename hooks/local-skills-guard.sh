#!/usr/bin/env bash
# PreToolUse(Edit|Write|Bash) hook: when a tool first touches a project that ships
# its own skills, name them and the project's CLAUDE.md, and refuse the first
# MUTATING call until they have been read.
#
# Crew sessions start in WORKDIR (crew.conf), not in a project. Claude Code
# registers skills from the starting directory only, so a project's own
# .claude/skills and CLAUDE.md never load in a crew session. Bash reads and
# writes trigger no lazy discovery at all, and Edit/Write load nested skills
# only after the edit is issued. This hook fires before the tool runs, which is
# the only point where a version-matched skill still helps.
#
# Fires once per session per project. A non-mutating touch gets context. The
# first mutating one is denied, so the read happens before the code.
#
# Keep two markers per session per project (.ctx for the notice, .deny for the
# block). With one, a first `ls` spends it on a notice that gets ignored, and the
# write that follows goes through unread.
CREW_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
PY=python3; [ -x /usr/bin/python3 ] && PY=/usr/bin/python3
exec "$PY" - "$CREW_DIR/crew.conf" 3<&0 <<'PY'
import json, os, re, sys

try:
    d = json.load(os.fdopen(3))
except Exception:
    sys.exit(0)

home = os.path.realpath(os.path.expanduser("~"))
workdir = home
try:
    for line in open(sys.argv[1]):
        m = re.match(r"^WORKDIR=(.*)$", line.strip())
        if m:
            workdir = os.path.realpath(os.path.expanduser(m.group(1).strip("'\"")))
except OSError:
    pass

tool = d.get("tool_name", "")
ti = d.get("tool_input") or {}
sid = re.sub(r"[^A-Za-z0-9_-]", "", d.get("session_id") or "nosession")
cwd = os.path.realpath(d.get("cwd") or workdir)
cmd = ti.get("command") or ""

paths = [p for p in (ti.get("file_path"), ti.get("notebook_path")) if p]
if tool == "Bash":
    paths += re.findall(r"(?<![\w.-])(/[^\s'\"`;|&<>()]+)", cmd)


def inside(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")


def has_skills(d):
    return any(os.path.isdir(os.path.join(d, s)) and os.listdir(os.path.join(d, s))
               for s in (".claude/skills", ".agents/skills"))


def project_of(path):
    """Nearest directory below the working directory that ships skills."""
    p = os.path.realpath(path)
    if not inside(p, workdir) or p == workdir:
        return None
    if not os.path.isdir(p):
        p = os.path.dirname(p)
    while inside(p, workdir) and p not in (workdir, home, "/"):
        if has_skills(p):
            return p
        p = os.path.dirname(p)
    return None


proj = next((q for q in map(project_of, paths) if q), None)
# A session started inside the project already has its skills.
if not proj or inside(cwd, proj):
    sys.exit(0)

names = sorted({n for s in (".claude/skills", ".agents/skills")
                for n in (os.listdir(os.path.join(proj, s)) if os.path.isdir(os.path.join(proj, s)) else [])
                if not n.startswith(".")})

mutating = tool in ("Edit", "Write", "MultiEdit", "NotebookEdit") or (
    tool == "Bash" and re.search(r"sed -i| > | >> |\btee |\bcp |\bmv |\brm ", cmd) is not None)

marks = "/tmp/claude-local-skills"
os.makedirs(marks, exist_ok=True)
mark = os.path.join(marks, sid + proj.replace("/", "_") + (".deny" if mutating else ".ctx"))
if os.path.exists(mark):
    sys.exit(0)
open(mark, "w").close()

# The repo's root docs carry this project's conventions and host quirks, which
# no skill knows. A run that read only the skills still proposed `npx prisma`,
# which is the wrong CLI on this host.
roots = [f"{proj}/{f}" for f in ("CLAUDE.md", "AGENTS.md") if os.path.isfile(f"{proj}/{f}")]
md = (f"Read {' and '.join(roots)} first. They carry this repo's conventions and host "
      f"quirks that no skill knows. ") if roots else ""
body = (f"{proj} ships its own skills: {', '.join(names)}. {md}"
        f"The skills are version-matched to THIS repo's dependencies and override what "
        f"you would otherwise write from memory. Read the ones covering what you are "
        f"about to touch (cat {proj}/.agents/skills/<name>/SKILL.md, or "
        f"{proj}/.claude/skills/<name>/SKILL.md), then say which you loaded and which "
        f"you skipped, by name.")
out = {"hookEventName": "PreToolUse"}
if mutating:
    out["permissionDecision"] = "deny"
    out["permissionDecisionReason"] = (
        body + " This first write is refused so the read happens before the code, not "
        "after. Reading them afterwards is worthless, because the mistake is already in "
        "the file. Retry the write once you have read them. This fires only once per "
        "project per session.")
else:
    out["additionalContext"] = body
print(json.dumps({"hookSpecificOutput": out}))
PY
