# claude-crew

Run your Claude Code conversations as long-lived tmux sessions, one per
conversation, and start, stop, restart and clear them without losing track of
which is which.

If you keep several long-running Claude Code conversations on one machine, you
end up managing them by hand: which tmux window holds which conversation, how to
restart them all without killing the one you are typing in, how to bring a
stopped one back on the model it used. `claude-crew` does that.

```
claude-crew setup
claude-crew resume "trading research"
claude-crew status
```

```
sessions (workdir /root, defaults claude-opus-5-5/medium/auto, remote-control on, autocompact auto):
  2b599c1a  working      [VPS] VPS Management
  a069d553  idle         [VPS] Trading Research 2
  86938387  idle         [VPS] DEPD
saved (what start and restart bring back):
  2b599c1a  claude-opus-5-5/high  [VPS] VPS Management
  a069d553  claude-opus-5-5/high  [VPS] Trading Research 2
  86938387  default(claude-opus-5-5)/high  [VPS] DEPD
```

`status` also flags a session that runs a different conversation than its name
says, and any conversation two sessions hold at once.

## The idea

**Each running conversation gets its own tmux session, named after it:**
`Claude_<short id>`, the first 8 characters of the conversation id, such as `Claude_2b599c1a`. Starting a conversation creates its session, and
stopping it removes the session. There is no fixed number of sessions and
nothing sits empty. The window name is the conversation's title, so `tmux ls`
stays readable, and every command accepts a title as the target.

**A session runs a shell, and claude is typed into that shell.** If claude were
the pane process, stopping it would delete the tmux session along with its
scrollback. Because it is a child of a shell, you can stop and restart claude in
place and the terminal survives. That is what makes changing a session's model
or effort cheap rather than destructive.

## Using it as intended

claude-crew works differently from the usual way of running Claude Code, and the
difference decides where each kind of project configuration belongs.

**The usual way:** you open Claude Code inside a project folder. It then loads
that folder's `CLAUDE.md`, skills, hooks, settings, commands, agents and MCP
servers, and it can write only inside that folder and folders you add.

**The crew's way:** every session starts in one parent folder, `WORKDIR` (the
home directory by default, `/root` on the host this was built for). A session can
write anywhere below it, so one conversation can work across several projects,
and a trading session can fix a deploy script without being reopened. The price
is that Claude Code loads nothing from the projects below `WORKDIR` by itself.

So configuration splits by what it is:

1. **A project's instructions go in its `CLAUDE.md` or `AGENTS.md`.**
   Conventions, host quirks, how to build and run it. A `CLAUDE.md` in a
   subfolder works too. The project hook makes a session read each one the first
   time it works in that folder, before its first write there.
2. **A project keeps its own skills only when they belong to that project:**
   version-matched framework skills (the ones `npx skills add` installs), or
   documentation of that project's own workflows. Anything useful across
   projects goes in `~/.claude/skills`, where every session sees it. The project
   hook names a project's skills on first touch, the same way it names
   instructions.
3. **Enforcement goes in global hooks that check the path.** A rule for one
   project becomes a hook in `~/.claude/settings.json` that returns early for any
   path outside that project. The crew's own hooks work this way.
4. **Do not write project hooks, settings, permissions, commands, agents or MCP
   servers for crew sessions.** Claude Code applies them only to a session
   started in that folder, so crew sessions never run them. A repository that
   other people open directly may keep them for those people. The project hook
   names any it finds, so a session can tell you that they do not run.

**Starting a session inside a project** gives you the usual way back for that
session, at the cost of writing outside the project. `WORKDIR` applies to every
session, so change it only when every session should start in the same place.

## Commands

| Command | What it does |
|---|---|
| `claude-crew setup [flags]` | Write or patch the config. Re-running with no flags keeps every value. |
| `claude-crew status [--json]` | What runs, what is saved, and any session whose name or conversation needs attention. |
| `claude-crew new "<title>"` | Start a brand new conversation in its own session. |
| `claude-crew resume <conversation>` | Start a stopped conversation in its own session, on the model and effort it last used. |
| `claude-crew stop <target>` | Stop a session, remove it, and drop it from the saved set. The transcript is kept. |
| `claude-crew relaunch <target>` | Stop and resume one session on the conversation, model and effort it runs now. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew clear <target> [--yes]` | Clear a session's context: a new, empty conversation with the same title, model and effort, then delete the conversation it replaced. Without `--yes` it only prints what would happen. Not Claude Code's `/clear`. |
| `claude-crew delete <conversation> [--yes]` | Stop it if live, then delete its transcript, its sidecar directory and its uploads. Without `--yes` it only prints what would go. There is no backup. |
| `claude-crew prompt <target> <text>` | Type keystrokes into that session's input box. Not a messaging channel — see below. |
| `claude-crew save` | Record what runs, with each session's model and effort, as the saved set. |
| `claude-crew start [--dry-run]` | Start every saved session that is not running. `--force` restarts the running ones too. |
| `claude-crew restart [delay]` | Save what runs, then restart it via systemd, without killing the caller. |
| `claude-crew boot on\|off\|status` | Install or remove a systemd unit that runs `claude-crew start` after a reboot. |
| `claude-crew update` | Upgrade the claude binary, then restart. |
| `claude-crew whoami` | Which session is running the caller, and whether it is protected. |
| `claude-crew relabel` | Rename sessions and windows to match the conversation each runs. |
| `claude-crew migrate` | Rename the numbered `Claude1`, `Claude2` … sessions of earlier versions after the conversation each runs, without stopping them. |

`<target>` is a running session: its tmux name, its conversation id or the first
8 or more characters of one, or a loose match on its title. `<conversation>`
reaches stopped conversations too, by id, id prefix or title. Matching
lowercases, ignores a leading `[tag]`, and treats punctuation as whitespace, so
`pensi`, `Pensi` and `[VPS] Pensi` all name the same thing, and the words may
arrive in any order. A name that matches more than one is refused with the list
of matches, never guessed.

## `prompt` is a keyboard, not a message bus

If your harness has inter-agent messaging, the two differ in what travels with
the words. Messaging merges context: the sender's working context rides along
and lands in the receiver's history reading as the receiver's own material. Use
it when you need the peer to acknowledge or reply.

`claude-crew prompt` types keystrokes into a tty. The words arrive exactly as
given, with no sender context and no authorship, as though typed at that
keyboard. Use it to unstick a session waiting at a pending message, or to hand
over context deliberately without authorship attached.

It adds nothing to what you pass it, on purpose.

## It will not let you kill yourself

Every stop path is fatal when aimed at the session you are running in. `stop`,
`relaunch`, `model`, `effort`, `clear` and `start --force` refuse when the target
is your own session, and `whoami` tells you which one that is.

The guard reads the process tree rather than tmux. Under systemd, cron, or a
plain ssh shell there is no claude ancestor and it stays silent, which is how
`restart` performs the same work an inline `start --force` is refused. Nothing
distinguishes them but the calling context.

`--self` does not lift the guard. It runs the same command on a timer instead:
crew hands it to systemd and returns, so it fires once your turn has ended.
`--in <secs>` sets the wait, 15 by default. The deferred run has no claude
ancestor, so it does the work inline. Stopping your own claude inline would kill
the tool shell that was about to start it again, so without the timer only the
stop would happen.

`delete` refuses your own conversation with no override, because a deleted
transcript cannot be brought back.

## Busy sessions are not interrupted

Every command that stops a session checks it first: `stop`, `relaunch`,
`model`, `effort`, `clear`, `delete` of a live conversation, and
`start --force`. A session that is working on a turn, waiting on a question or
permission prompt, or holding an unsent draft is refused, and nothing is done.
`--interrupt` acts anyway.

`restart` and `update` wait instead of refusing. At the scheduled time, each
busy session gets up to 15 minutes to finish its turn. A session still holding
an unsent draft stops the restart, since waiting will not clear it. A command a
session aims at itself with `--self` waits the same way, which lets the turn
that asked for it finish first.

The web page offers the same choice explicitly: a busy session's dialog shows an
"Interrupt & …" button, and Restart All offers "Restart When Idle" or
"Interrupt Now".

## Clearing a session's context

`claude-crew clear <target>` is not Claude Code's `/clear`, and the two do
different things.

- **Claude Code's `/clear`** starts a new conversation inside the same process
  and keeps the old one on disk. The process still carries the `-n` name it was
  launched with, so the new conversation gets the same title. The old one stays
  resumable, and the store ends up with two conversations under one name.
- **`claude-crew clear`** empties the context for good. It starts a new, empty
  conversation in its own session with the same title, model and effort, then
  deletes the conversation it replaced, with its sidecar and uploads. There is
  no backup.

Clearing deletes, so it asks first, like `delete`. A bare run prints the plan
and changes nothing. `--yes` carries it out. The web page asks in a dialog.

```
claude-crew clear "trading research 2"          # print what would be deleted
claude-crew clear "trading research 2" --yes    # clear it
```

The remote-control link changes with it, because remote control follows the
conversation.

Aimed at the session you are running in, it defers onto a timer like every
other stop path.

**A `/clear` typed anyway** is caught by a SessionStart hook. `claude-crew
cleared` renames the session after the new conversation, saves it in the saved
set, and puts a notice in the new session's context: the previous conversation
still exists under the same name, and the session should ask the user before
deleting it. The hook deletes nothing. Register it in `~/.claude/settings.json`:

```json
{"hooks": {"SessionStart": [{"matcher": "clear", "hooks": [{"type": "command",
  "command": "CREW_WEB_URL=https://crew.example.com ~/.claude/skills/claude-crew/bin/claude-crew cleared"}]}]}}
```

`CREW_WEB_URL` is optional. When set, the notice points at the web page.

## Saved sessions

`sessions.state`, beside `crew.conf`, records what runs: one line per
conversation with its model, its effort and its title. `-` in model or effort
means "follow crew.conf". `start` and `restart` bring back exactly that set.

It records what is running, not what was asked for. Every command that starts
or stops a session rewrites it, and `restart` rewrites it just before
scheduling. A session that died keeps its entry, so a crash comes back on the
next `start`. An entry leaves only through `stop`, `delete`, `clear`, or a
stopped conversation whose transcript is gone.

`claude-crew boot on` makes this survive a reboot. Without it, nothing starts the
sessions after the machine comes back.

## Install

[INSTALL.md](INSTALL.md) has the steps, written so a person or an AI agent can
follow them and check each one.

Config lands at `~/.claude/skills/claude-crew/crew.conf`. It is gitignored.
**A reinstall must not overwrite it or `sessions.state`.** Use
`rsync --exclude=crew.conf --exclude=sessions.state --exclude=slots.state` if
you script the copy.

As a Claude Code skill, `SKILL.md` also lets any session drive the crew by
asking in plain language.

## Project skills and instructions

Every crew session starts in `WORKDIR`, and Claude Code loads skills and
instructions only from the folder a session starts in and the folders above it.
A project below `WORKDIR` therefore never has its `.claude/skills`,
`.agents/skills`, `CLAUDE.md` or `AGENTS.md` loaded. Bash commands trigger no
discovery at all, and Edit and Write load nested skills only after the edit is
issued.

`hooks/local-skills-guard.sh` covers this. It is a PreToolUse hook on
`Edit|Write|Bash`. The first time a session touches a folder that carries skills
or instructions, it names them, and the first write into that folder is refused
until they have been read. This happens once per folder per session, so a
`CLAUDE.md` in a subfolder is named when the session first reaches that
subfolder. The hook also names any project hooks, settings, commands, agents and
MCP servers, because crew sessions do not run them. A session started inside a
folder already has that folder's configuration, so the hook leaves it alone.

It keeps two markers per session and folder, one for the notice and one for the
refusal. With one shared marker, a first `ls` spends it on a notice that gets
ignored, and the write that follows goes through unread. The Bash test for a
write matches `rm`, `mv`, `cp`, redirects and `sed -i`, so an unrelated command
naming a project path can use up the one refusal.

## Web page

`web/` holds a page for the crew. Sessions lists what runs, each with Open,
Restart, Send Prompt, Clear Context and Stop, and a New Session button above it.
Stopped lists the other conversations, each with Start and Delete. It warns
before starting a session when the host is low on memory. Every action runs one
`claude-crew` command, and the page reads `claude-crew status --json`, so it
holds no crew logic of its own. Model and effort for a single session are
changed inside that session, through remote control. The page changes the
defaults.

```
web/server.py                  Python standard-library server on 127.0.0.1:3115
web/index.html                 the page, no build step
web/claude-crew-web.service    systemd unit
web/nginx.conf                 HTTPS proxy, with crew.example.com to replace
```

It signs in with one password. The server keeps a PBKDF2 hash of it and issues a
30-day login token in an HttpOnly cookie. Five wrong passwords from one address
lock that address out for 15 minutes.

[INSTALL.md](INSTALL.md) covers the service and the HTTPS proxy.

The password hash and the login tokens live in `~/.config/claude-crew-web/`,
outside the repository. Setting a new password signs every browser out.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `WORKDIR` | your home directory | Where every session starts, and which transcript store is read. Changing it is refused while a session is running or saved. |
| `MODEL` | `claude-opus-5-5` | A model ID, or an alias such as `opus`, which resolves to the latest of that family. |
| `EFFORT` | `medium` | `low` `medium` `high` `xhigh` `max` |
| `PERMISSION_MODE` | `auto` | |
| `REMOTE_CONTROL` | `on` | Named after the conversation title. |
| `AUTOCOMPACT` | `auto` | Passed as `--autocompact`: `auto`, or a window from 100k to 1M tokens. |
| `TMUX_PREFIX` | `Claude` | Sessions are named `Claude_<short id>`. Letters and digits only. |
| `SHELL_CMD` | `bash` | The pane process. |
| `CLAUDE_BIN` | `claude` | A testing seam. Point it at a stub to exercise the tmux mechanics without resuming a real conversation. |

Every command except `setup` refuses to run until the config exists, so setup is
its own gate.

## Things this learned the hard way

**A registry file can outlive its process.** After a reboot a new claude can
receive the pid of an old one whose `~/.claude/sessions/<pid>.json` is still on
disk. A file older than the process it names is ignored, or a save would record
the wrong conversation for that session.

Each of these is a real failure that happened on a real host. The comments in
`bin/claude-crew` mark them at the code that prevents them.

**A zero exit code does not mean it worked.** A systemd unit's `PATH` does not
include `~/.local/bin`, where `claude` lives. Every pane died instantly while
`tmux new-session` had already returned 0, so the run logged five successes with
nothing running. `claude-crew` hardens `PATH` itself and ends with a
`verify: N/N sessions hold a live claude` line, exit 4 if any is dead.

**Never `pgrep -f` on a pattern that could be in your own command line.** It
matches the flattened command line, so `--resume <id>` also matches the shell
that invoked you. It killed a live session twice during development, and using
it for launch verification means the check can pass while nothing started —
the exact failure the check exists to catch. `claude-crew` reads argv from
`/proc` for processes inside its own panes.

**`send-keys` returning 0 is not delivery.** It means tmux accepted the
keystrokes, not that claude was in a state to receive them. A compacting session
swallows them silently while the command reports success. `prompt` reads the
input box before typing and again after, and submits only once the box has gone
from empty to non-empty.

**Confirm delivery by emptiness, not by finding the text.** A long paste is
collapsed to a placeholder, so past a few hundred characters none of the text is
on screen and a text match fails on a perfectly idle session. Three prompts were
reported as "busy" when length was the only problem.

**Do not type into a box you have not looked at.** A draft someone left unsent
sits in that box, and typing appends to it. `prompt` refuses when the box holds
anything, and when the box is not on screen at all. Past prompts in the
conversation carry the same `❯` mark as the box, so only the region between the
box's two rules counts.

**`C-u` does not clear this input box.** 700 characters survived it untouched.
`C-c` clears it, and also interrupts a turn, so it is not a cleanup tool. There
is no cleanup path: a failed delivery leaves the box empty, so there is nothing
to remove.

**argv says what a process was launched with, never what it is running now.**
A session re-pointed from inside with `/resume` keeps its old `--resume` id, its
old `-n` name, its old tmux session name and its old window name. Reading argv
therefore reported the old conversation as live and the new one as stopped, and
a second claude got launched onto a conversation that already had one. The
per-pid registry at `~/.claude/sessions/<pid>.json` follows the switch, so that
is consulted first and argv is only the fallback. `status` flags the mismatch
and `relabel` renames the session.

**Rank by the last human turn, not file mtime.** A live session's hooks rewrite
its transcript constantly, so merely being open keeps it at the top of any
list sorted by mtime.

**Stop every session before launching any.** `start --force` stops everything
first, in a separate pass. Starting a conversation while its old process is
still alive puts two processes on one transcript.

**`local n="$1" pid="${ARR[$n]:-}"` aborts under `set -u`.** Bash marks every
name in one `local` statement local before evaluating any right-hand side, so
`$n` is read while still unset. Split the declaration.

## Requirements

`bash` 4.4+, `tmux`, `python3`, `systemd` (for `restart`), and Claude Code
2.1.258 or later.

## License

MIT
