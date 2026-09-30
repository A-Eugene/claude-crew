#!/usr/bin/env bash
# PreToolUse(Edit|Write|Bash) hook: when a tool first touches a folder below
# WORKDIR that carries its own skills or instructions (CLAUDE.md, AGENTS.md), name
# them, and refuse the first MUTATING call until they have been read. Project
# hooks, settings, commands, agents and MCP servers are named as not running.
#
# Crew sessions start in WORKDIR (crew.conf), not in a project. Claude Code
# registers skills from the starting directory only, so a project's own
# .claude/skills and CLAUDE.md never load in a crew session. Bash reads and
# writes trigger no lazy discovery at all, and Edit/Write load nested skills
# only after the edit is issued. This hook fires before the tool runs, which is
# the only point where a version-matched skill still helps.
#
# Fires once per session per folder, so a nested CLAUDE.md is named the first
# time the session reaches its folder. A non-mutating touch gets context. The
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


SKILL_DIRS = (".claude/skills", ".agents/skills")
DOCS = ("CLAUDE.md", "AGENTS.md")


def skills_in(d):
    return sorted({n for s in SKILL_DIRS if os.path.isdir(os.path.join(d, s))
                   for n in os.listdir(os.path.join(d, s)) if not n.startswith(".")})


def docs_in(d):
    return [os.path.join(d, f) for f in DOCS if os.path.isfile(os.path.join(d, f))]


def not_run_in(d):
    """Project config that Claude Code loads only for a session started in d."""
    found = []
    for f in (".claude/settings.json", ".claude/settings.local.json"):
        try:
            keys = json.load(open(os.path.join(d, f)))
        except Exception:
            continue
        found += [f"{k} in {f}" for k in ("hooks", "permissions", "env", "mcpServers") if k in keys]
    for sub in (".claude/commands", ".claude/agents"):
        if os.path.isdir(os.path.join(d, sub)) and os.listdir(os.path.join(d, sub)):
            found.append(sub)
    if os.path.isfile(os.path.join(d, ".mcp.json")):
        found.append(".mcp.json")
    return found


def context_dirs(path):
    """Every folder from the path up to (not including) the working directory
    that carries skills or instructions, innermost first."""
    p = os.path.realpath(path)
    if not inside(p, workdir) or p == workdir:
        return []
    if not os.path.isdir(p):
        p = os.path.dirname(p)
    out = []
    # Claude Code's own config folder holds the user's CLAUDE.md, which every
    # session already has.
    if inside(p, os.path.join(home, ".claude")):
        return []
    while inside(p, workdir) and p not in (workdir, home, "/"):
        if skills_in(p) or docs_in(p):
            out.append(p)
        p = os.path.dirname(p)
    return out


dirs = next((c for c in map(context_dirs, paths) if c), [])
# A session started inside a folder already has that folder's skills and
# instructions, and those of every folder above it.
dirs = [d for d in dirs if not inside(cwd, d)]
if not dirs:
    sys.exit(0)

mutating = tool in ("Edit", "Write", "MultiEdit", "NotebookEdit") or (
    tool == "Bash" and re.search(r"sed -i| > | >> |\btee |\bcp |\bmv |\brm ", cmd) is not None)

marks = "/tmp/claude-local-skills"
os.makedirs(marks, exist_ok=True)
fresh = []
for d in dirs:
    mark = os.path.join(marks, sid + d.replace("/", "_") + (".deny" if mutating else ".ctx"))
    if not os.path.exists(mark):
        open(mark, "w").close()
        fresh.append(d)
if not fresh:
    sys.exit(0)

parts = []
for d in reversed(fresh):                      # outermost first, as Claude Code reads them
    docs, names, extra = docs_in(d), skills_in(d), not_run_in(d)
    line = f"{d}:"
    if docs:
        line += (f" read {' and '.join(docs)}, which {'carry' if len(docs) > 1 else 'carries'} "
                 f"this folder's conventions and host quirks.")
    if names:
        line += (f" It ships its own skills: {', '.join(names)}. They are version-matched to this "
                 f"repo and override what you would write from memory. Read the ones covering what "
                 f"you are about to touch (cat {d}/.agents/skills/<name>/SKILL.md or "
                 f"{d}/.claude/skills/<name>/SKILL.md), then say which you loaded and which you skipped.")
    if extra:
        line += (f" It also defines {', '.join(extra)}. Claude Code applies those only to a session "
                 f"started in that folder, so this session does not run them. Tell the user.")
    parts.append(line)
body = "This session started outside the project, so none of this was loaded. " + " ".join(parts)
out = {"hookEventName": "PreToolUse"}
if mutating:
    out["permissionDecision"] = "deny"
    out["permissionDecisionReason"] = (
        body + " This first write is refused so the reading happens before the change, not "
        "after. Retry the write once you have read them. This fires once per folder per session.")
else:
    out["additionalContext"] = body
print(json.dumps({"hookSpecificOutput": out}))
PY
