---
name: claude-crew
description: >-
  Manage the Claude Code sessions on this host, each a tmux session named
  Claude_<first 8 characters of its conversation id>: start a new one, resume a stopped conversation,
  stop, restart, clear a session's context (which deletes the conversation it
  replaces, unlike Claude Code's /clear), delete a conversation for good,
  change a session's model or effort, or type keystrokes into a session's input
  box. Load it whenever the user mentions the claudes, the crew, a session, or
  names another session at all, even without saying "claude-crew" and even when
  the request looks like ordinary shell work. Triggers: crew, claude-crew,
  restart the claudes, new claude session, resume Click Clack, stop Pensi,
  clear context, /clear, delete a conversation, what is running, change
  Trading Research 2 to sonnet, bump effort to xhigh, update claude code,
  prompt this to Trading Research 1, send this to another session, unstick a
  stuck session. Load it also before ANY tmux command that kills, stops or
  restarts something: `tmux kill-server` ends every session on this host,
  including your own.

  To reach a peer, SendMessage carries the sender's context and identity and
  `claude-crew prompt` carries neither. When the user names the mechanism
  ("prompt this to X"), use it even if a reply is wanted. Otherwise choose by
  whether the peer must reply.

  Call it as `~/.claude/skills/claude-crew/bin/claude-crew` when it is not on
  PATH: a tool-call shell does not inherit the login shell's PATH.
---

# claude-crew

`claude-crew` runs each Claude Code conversation on this host as its own tmux
session, and starts, stops, restarts and clears them.

Run it as `claude-crew <command>`, or `crew` for short. Both are on `PATH` via
`/root/Scripts/`. The Bash tool's `PATH` does not always include
`/root/Scripts`, so call it by full path when a bare `claude-crew` fails:
`/root/.claude/skills/claude-crew/bin/claude-crew`.

## The model

- Each running conversation has its own tmux session, `Claude_<short id>`, the first 8 characters of its conversation id, like `Claude_2b599c1a`.
  Starting a conversation creates it, and stopping the conversation removes it.
  There is no fixed number of sessions.
- The window name is the conversation's title. Address sessions by title or id,
  never by guessing a tmux name.
- A session runs a **shell**. Claude is a command typed into that shell, so
  restarting claude in place keeps the pane, its scrollback and its window name.

## Commands

| Command | What it does |
|---|---|
| `claude-crew setup [flags]` | Write or patch `crew.conf`. Re-running with no flags keeps every value. |
| `claude-crew status [--json]` | What runs, what is saved, and any session whose name or conversation needs attention. |
| `claude-crew new "<title>"` | Start a brand new conversation in its own session. |
| `claude-crew resume <conversation>` | Start a stopped conversation in its own session, on the model and effort it last used. |
| `claude-crew stop <target>` | Stop a session, remove it, and drop it from the saved set. The transcript is kept. |
| `claude-crew relaunch <target>` | Stop and resume one session on the conversation, model and effort it runs now. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew clear <target> [--yes]` | Clear a session's context: a new, empty conversation with the same title, model and effort, then delete the conversation it replaced. Without `--yes` it only prints what would happen. Not Claude Code's `/clear`. |
| `claude-crew delete <conversation> [--yes]` | Stop it if live, then delete its transcript, its sidecar directory and its uploads. Without `--yes` it only prints what would go. |
| `claude-crew prompt <target> <text>` | Type a real prompt into that session's running claude. |
| `claude-crew save` | Record what runs, with each session's model and effort, as the saved set. |
| `claude-crew start [--dry-run]` | Start every saved session that is not running. |
| `claude-crew restart [delay]` | Save what runs, then restart it via systemd, without killing the caller. |
| `claude-crew boot on\|off\|status` | Install or remove a systemd unit that runs `claude-crew start` after a reboot. |
| `claude-crew update` | Upgrade the claude binary, then restart. |
| `claude-crew whoami` | Which session is running the caller, and whether it is protected. |
| `claude-crew relabel` | Rename sessions and windows to match the conversation each runs. |
| `claude-crew migrate` | Rename numbered `Claude1`, `Claude2` … sessions after the conversation each runs, without stopping them. |

The same commands are buttons on the web page in `web/`, served on this host at
`https://crew.aeugene.top`. The README has its install.

`<target>` is a running session: its tmux name, its conversation id or the
first 8 or more characters of one, or a loose match on its title.
`<conversation>` reaches stopped conversations too. Matching lowercases, ignores
a leading `[tag]`, and treats punctuation as whitespace, so `pensi`, `Pensi` and
`[tag] Pensi` all reach the same conversation, and the words may arrive in any
order. A name matching more than one is refused with the list of matches, never
guessed.

## Three things this host has already gotten wrong

Each one is a fact about the tooling, not a caution to be careful.

**`claude-crew start --force` inline stops the calling session's own claude mid-turn**
and wedges its remote control. `claude-crew restart` hands the job to systemd, so the
caller's shell is already gone when it fires. Use that instead.

**A zero exit code does not mean it worked.** On 2026-08-02 `claude` was not on
the systemd unit's `PATH`, every pane died instantly, `tmux new-session` had
already returned 0, and the run logged five successes while nothing was running.
`claude-crew status` and the `verify: N/N` line report the actual process state.

**An in-band `/resume` does not cleanly switch a live session.** It leaves
remote control showing the old name while the messages merge into one stream,
seen on 2026-09-02 switching Click Clack to Discretionary Backtest Platform.
To run another conversation, `stop` one and `resume` the other.

## It will not let you kill yourself

Every stop path is fatal when aimed at the session you are running in: your
claude gets SIGTERM, the turn dies mid-sentence, and remote control wedges.
Worse, only the first half of the command runs. Crew is a child of your own
claude, so the tool shell dies with it and the relaunch two lines later never
happens.

So `stop`, `relaunch`, `model`, `effort`, `clear` and `start --force` refuse
when the target is your own session. `claude-crew whoami` shows which session
that is.

```
claude-crew model "vps management" sonnet
crew: changing model or effort would stop the session you are running in (Claude_2b599c1a-…).
     Pass --self to run it on a timer instead, after this turn ends.
     'claude-crew restart' does the same for every session at once.
```

The guard reads the process tree, not tmux, because `$TMUX` is not reliably
exported into a tool call. Under systemd, cron, or a plain ssh shell there is no
claude ancestor, so it stays silent — which is exactly how `claude-crew restart`
keeps doing the same work that an inline `start --force` is refused. No flag
distinguishes them; the calling context does.

`--self` does not run the command inline. It schedules the same argument line
through systemd and returns, so it fires once the turn has ended:

```
claude-crew relaunch "vps management" --self
relaunch targets Claude_2b599c1a-…, the session you are running in.
scheduled crew-self-1789533704 in 15s, so it runs once this turn has ended
verify after it fires:  claude-crew status  &&  journalctl -u crew-self-1789533704
```

`--in <secs>` sets the wait, 15 by default. Give it longer when the turn still
has work to do. The deferred run has no claude ancestor, so it does the work
inline rather than deferring again.

Report it as scheduled, not as done. The result is only visible in the next
session, through `claude-crew status` and the unit's journal.

## Busy sessions are not interrupted

Commands that stop a session refuse one that is working, waiting on a question
or permission prompt, or holding an unsent draft: `stop`, `relaunch`, `model`,
`effort`, `clear`, `delete` of a live conversation, and `start --force`. When
one is refused, tell the user which session is busy and why. Pass `--interrupt`
only when the user has said to interrupt it.

`restart`, `update` and anything run with `--self` wait up to 15 minutes for a
busy session to go idle instead. An unsent draft still stops them.

## Project skills and instructions

Sessions start in the crew's `WORKDIR`, so a project's own skills, `CLAUDE.md`
and `AGENTS.md` never load by themselves, and neither does a `CLAUDE.md` in a
subfolder. The crew's `local-skills-guard.sh` hook names them the first time a
session touches that folder, and refuses the first write there until they are
read. When it refuses, read what it lists, then retry. Read a project's skills as
plain files. The Skill tool cannot see them.

Project hooks, settings, permissions, commands, agents and MCP servers never run
in crew sessions. When the hook names some, tell the user. When asked to add a
rule or check for one project, write a global hook in `~/.claude/settings.json`
that returns early for paths outside that project, not a project hook. The
README's "Using it as intended" section has the full split.

## Clearing a session's context

`claude-crew clear` is NOT Claude Code's `/clear`. Say so whenever you offer
either one.

- **Claude Code's `/clear`** starts a new conversation in the same process and
  keeps the old one on disk under the same title, so the store gets two
  conversations with one name. The user does not use it.
- **`claude-crew clear`** starts a new, empty conversation in its own session
  with the same title, model and effort, then DELETES the conversation it
  replaced, its sidecar and its uploads. There is no backup.

Clearing requires the user's confirmation, exactly like deleting. Run it bare
first, show the user what it printed, and add `--yes` only after they say yes.
Before asking, check its uploads: an upload can be the only copy of a file.

```
claude-crew clear "trading research 2"          # prints the plan, changes nothing
claude-crew clear "trading research 2" --yes    # after the user confirms
```

Remote control gets a new link, because it follows the conversation. Aimed at
your own session, `clear` defers onto a timer, like every other stop path.

**If a `/clear` happened anyway,** the SessionStart hook `claude-crew cleared`
has already renamed the session after the new conversation, saved it, and put a
notice in your context. Tell the user the previous conversation still exists
under the same name, and ask before deleting it with
`claude-crew delete <id> --yes`.

## Deleting a conversation

`claude-crew delete` removes three things: `<id>.jsonl`, the `<id>/` directory
beside it holding tool-results, subagents and `custom-title.json`, and
`~/.claude/uploads/<id>/` holding every file attached to that conversation.
Uploads sit outside the transcript store, so deleting without them strands
whatever was attached. There is no backup.

- A bare run prints the id, title, transcript path, byte size, sidecar
  directory and uploads directory, then deletes nothing. `--yes` is what deletes.
- It refuses your own conversation, and `--self` does not override that.
- An ambiguous title substring is refused with the list of matches.
- A conversation running in a session is stopped first, and its session removed.
  Files are removed only after the process has exited.
- A conversation live in a terminal outside the crew is refused. Stop that
  claude yourself first.

```
claude-crew delete "old scratch"          # shows what would go
claude-crew delete "old scratch" --yes    # deletes it
```

## Typing into another session's input box

Two routes reach another session, and they differ in what travels with the words.

**`SendMessage` is for when you need acknowledgement.** A reply, a decision, one
session acting as another's peer. It merges the two sessions' context: the
sender's working context rides along and lands in the receiver's history, where
it reads as the receiver's own material. A plaintalk sync sent from a trading
session put trading content into a mahjong app's history exactly that way on
2026-09-02.

**`claude-crew prompt` is for when you do not.** It types keystrokes into a tty.
The words arrive exactly as given, with no sender context and no authorship, as
though typed at that keyboard. Use it to unstick a session sitting at a pending
message, or to hand over context deliberately without authorship attached.

It adds nothing to what you pass it. Do not prepend a "from" line unless the
caller asked for one — carrying no authorship is the point, and the caller can
put attribution in the text when they want it there.

```
claude-crew prompt "Trading Research 1" "re-read the graph index before answering"
claude-crew prompt a069d553 "status on the ingest queue?"
```

**It reads the input box before typing, and refuses twice over.** If the box is
not on screen the session is mid-turn and would swallow the keystrokes. If the
box already holds text, someone has an unsent draft there and it is not ours to
type over. Either way nothing is typed.

**Delivery is confirmed by the box going from empty to non-empty, not by finding
the text.** A long paste is collapsed to a placeholder, so matching the text
fails on a perfectly idle session once the prompt passes a few hundred
characters. That misreported three prompts as "busy" when length was the only
problem. Emptiness does not care how long the text is.

Nothing is cleared on failure, because failure means the box came back empty and
there is nothing to clear. Do not add a cleanup step here. `C-u` does not clear
this input box at all, 700 characters survived it untouched, and `C-c` clears it
only by interrupting whatever turn the session has started since.

A session with no running claude is sitting at a root shell prompt, where the
text would be executed as a command. That is refused too.

Newlines submit the box, so a multi-line prompt would arrive as several separate
turns. They are collapsed to spaces and the command says so.

## Renaming a session

Rename from inside the session with `/rename`. The conversation's own title is
the source of truth: every relaunch (start, restart, relaunch, model, effort)
reads the latest title from the transcript and launches under it, so the window
label and the remote-control name follow the rename on the next relaunch.
`claude-crew relabel` updates the window label without a relaunch.

## Changing model or effort

Both are launch flags, so changing one means stopping the process and starting
it again on the same conversation, in the same pane. There is no in-band
round-trip to wedge.

```
claude-crew model "Web Ko Gedy" sonnet
claude-crew effort "trading research 2" xhigh
```

Each changes only the setting it names. The conversation keeps its other
setting, and `resume` brings a stopped conversation back on both.

A session follows the `crew.conf` default until someone sets it. The saved set
stores `-` for a setting that follows the default, so changing the default with
`claude-crew setup --model sonnet` reaches every such session on the next start
or restart, while a session set with `model` or `effort` keeps its value.
`default` hands a setting back:

```
claude-crew model "trading research 2" default
claude-crew effort "trading research 2" default
```

## Saved sessions

`sessions.state`, beside `crew.conf`, records what runs: one line per
conversation with its model, its effort and its title. `start` and `restart`
bring back exactly that set.

It records what is running, not what was asked for. Every command that starts
or stops a session rewrites it, and `restart` rewrites it just before
scheduling. A session that died keeps its entry, so a crash comes back on the
next `start`. An entry leaves only through `stop`, `delete`, `clear`, or a
stopped conversation whose transcript is gone.

`claude-crew boot on` makes this survive a reboot. Without it, nothing starts the
sessions after the machine comes back.

## Configuration

`~/.claude/skills/claude-crew/crew.conf`, written by `claude-crew setup`. Plain `KEY=value`,
safe to edit by hand.

| Key | Default | Notes |
|---|---|---|
| `WORKDIR` | home directory (`/root` on this host) | Where every session starts, and which transcript store is read. Changing it is refused while a session is running or saved. |
| `MODEL` | `claude-opus-5-5` | A model ID, or an alias such as `opus`, which resolves to the latest of that family. |
| `EFFORT` | `medium` | `low` `medium` `high` `xhigh` `max` |
| `PERMISSION_MODE` | `auto` | |
| `AUTOCOMPACT` | `auto` | Passed as `--autocompact`: `auto`, or a window from 100k to 1M tokens. |
| `TMUX_PREFIX` | `Claude` | Sessions are named `Claude_<short id>`. Letters and digits only. |
| `SHELL_CMD` | `bash` | The pane process. |
| `CLAUDE_BIN` | `claude` | A testing seam. Point it at a stub to exercise the tmux mechanics without resuming a real conversation. |

Every command except `setup` refuses to run until the config exists, so setup is
its own gate.

`crew.conf` and `sessions.state` are gitignored, and no install step may
overwrite them.

## A session can be running something other than its name

`/resume` or `/clear` from inside a pane switches that session's conversation
without touching argv, the `-n` display name, the tmux session name or the
window name. All of them keep naming the conversation it started on, so the
session reads as one thing while running another.

`claude-crew` resolves this from `~/.claude/sessions/<pid>.json`, which is keyed
by process id and follows the switch. `status` prints the real conversation,
flags a session whose name has drifted, and flags any conversation that two
sessions hold at once. Two live processes on one transcript interleave their
writes, so stop one as soon as it shows up.

`claude-crew relabel` renames drifted sessions and windows.

## Never run `tmux kill-server`

It ends every session on this host, including your own. A tool shell inherits
`$TMUX`, and tmux follows `$TMUX` over `TMUX_TMPDIR`, so a server you believe is
separate is the real one.

To exercise tmux without touching the crew, name a socket explicitly and clear
`$TMUX` first:

```bash
env -u TMUX tmux -L test new-session -d -s probe
env -u TMUX tmux -L test kill-session -t probe
```

Remove test sessions one at a time by name. Never by killing a server.

## The `pgrep -f` trap

`pgrep -f` and `pkill -f` match against a flattened command line, so a pattern
like `--resume <id>`, a session title, or a script path also matches the shell
that invoked you. It killed a live session twice while this skill was being
built. `claude-crew` reads argv out of `/proc` for the processes inside its own panes
instead, which is the narrow question actually being asked.
