---
name: claude-crew
description: >-
  Manage the tmux fleet of Claude Code sessions on this host: start them,
  restart them, start a brand new conversation, clear a session's context
  (which deletes the conversation it replaces, unlike Claude Code's /clear),
  delete a conversation for good, move a conversation into a different slot,
  change a session's model or effort,
  or type keystrokes into a session's terminal input box. Use
  when asked to start/restart the claudes, switch a session, see which
  conversation is in which tmux slot, change a running session's model or effort
  level, upgrade the claude binary, unstick a session waiting at a pending
  message, or put text into another session's input box exactly as typed.
  Make sure to load this skill whenever the user mentions the claudes, the
  fleet, a slot, or names another session at all — even when they do not say
  "claude-crew" and even when the request looks like ordinary shell work.
  Triggers: crew, claude-crew, clear context, clear this session, /clear,
  restart the claudes, start the claudes, new claude session, delete a conversation, which conversation is in which slot,
  switch TR1 to Click Clack, change slot 2 to sonnet, bump effort to xhigh,
  update claude code, type this into Claude3, prompt this to Trading Research 1,
  send this to another session, unstick a stuck session. Load it also before ANY tmux command that kills, stops or restarts something, even when the fleet was never mentioned: `tmux kill-server` ends every session on this host including your own.

  Choosing between the two ways to reach a peer: SendMessage carries the
  sender's context and identity, `claude-crew prompt` carries neither, by
  design. **When the user names the mechanism — "prompt this to X" — use that
  mechanism, even if a reply is wanted.** Only when they have not named one,
  choose by whether the peer must acknowledge or reply.

  Invoke it at `~/.claude/skills/claude-crew/bin/claude-crew` when the command
  is not on PATH: a tool-call shell does not inherit the login shell's PATH.
---

# claude-crew

`claude-crew` parks the N most recently used conversations in numbered tmux sessions and
moves them around. It replaced `start_claudes.sh` and `restart_claudes.sh` on
2026-09-02.

Run it as `claude-crew <command>`, or `crew` for short. Both are on `PATH` via
`/root/Scripts/`. The Bash
tool's `PATH` does not always include `/root/Scripts`, so call it by full path
when a bare `claude-crew` fails: `/root/.claude/skills/claude-crew/bin/claude-crew`.

## The model

- A **slot** is a numbered parking space, tmux session `Claude1`..`Claude5`.
- A slot runs a **shell**. Claude is a command typed into that shell.
- Killing claude therefore leaves the pane, its scrollback, and its window name
  alive. That is what makes `switch`, `model`, and `effort` cheap.
- Slot number says nothing about which conversation is in it. Assignment is by
  recency of the last *human* turn, so a conversation moves between slots
  between runs. Always resolve by title, never by remembering a number.

## Commands

| Command | What it does |
|---|---|
| `claude-crew setup [flags]` | Write or patch `crew.conf`. Re-running with no flags keeps every value. |
| `claude-crew status` | Slot → conversation map, plus any conversation with no slot. |
| `claude-crew whoami` | Which slot is running the caller, and whether it is protected. |
| `claude-crew relabel` | Rename windows to match what each slot actually runs. |
| `claude-crew start [--rerank]` | Relaunch the saved slots, each on its saved model and effort. With nothing saved, or with `--rerank`, fill free slots from the newest N conversations. |
| `claude-crew start --dry-run` | Print the plan, launch nothing. |
| `claude-crew restart [delay]` | Save the current slots, then restart every slot via systemd, without killing the caller. |
| `claude-crew stop <target>` | Stop a slot and drop it from the saved slots, so start and restart leave it empty. The transcript is kept. |
| `claude-crew save` | Record what every slot runs, with its model and effort, as the saved slots. |
| `claude-crew boot on\|off\|status` | Install or remove a systemd unit that runs `claude-crew start` after a reboot. |
| `claude-crew new "<title>" [--slot <n> [--force]]` | Start a brand new conversation in the first free slot, or in slot n. `--force` stops what slot n runs. |
| `claude-crew clear <target> [--yes]` | Clear a slot's context: restart it on a new, empty conversation with the same title, model and effort, then delete the conversation it replaced. Without `--yes` it only prints what would happen. Not Claude Code's `/clear`. |
| `claude-crew delete <conversation> [--yes]` | Stop it if live, then delete its transcript, its sidecar directory and its uploads. Without `--yes` it only prints what would go. |
| `claude-crew switch <A> <B>` | Put conversation B in A's slot. Swaps if B is already live somewhere. |
| `claude-crew prompt <target> <text>` | Type a real prompt into that slot's running claude. |
| `claude-crew relaunch <target>` | Stop and resume one slot on the conversation, model and effort it runs now. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew update` | Upgrade the claude binary, then restart. |

The same commands are buttons on the web page in `web/`, served on this host at
`https://crew.aeugene.top`. The README has its install.

`<target>` is a slot number, a tmux session name, or a loose match on a title.
Matching lowercases, ignores a leading `[tag]`, and treats punctuation as
whitespace, so `pensi`, `Pensi` and `[VPS] Pensi` all reach the same
conversation, and the words may arrive in any order. `claude-crew switch 4 "click"`
works. A name matching more than one conversation is refused with the list of
matches, never guessed.

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
`claude-crew switch` kills and resumes instead, which is why it exists.

## It will not let you kill yourself

Every stop path is fatal when aimed at the slot you are running in: your claude
gets SIGTERM, the turn dies mid-sentence, and remote control wedges. Worse, only
the first half of the command runs. Crew is a child of your own claude, so the
tool shell dies with it and the relaunch two lines later never happens — a
self-targeted `switch` stopped the slot and left it empty, on 2026-09-15.

So `switch`, `model`, `effort`, `stop`, `start --force`, and
`new --slot <n> --force` refuse when the target is your own slot.
`claude-crew whoami` shows which slot that is.

```
claude-crew model Claude2 sonnet
crew: changing model or effort would stop the session you are running in (Claude2, 2b599c1a).
     Pass --self to run it on a timer instead, after this turn ends.
     'claude-crew restart' does the same for every slot at once.
```

The guard reads the process tree, not tmux, because `$TMUX` is not reliably
exported into a tool call. Under systemd, cron, or a plain ssh shell there is no
claude ancestor, so it stays silent — which is exactly how `claude-crew restart`
keeps doing the same work that an inline `start --force` is refused. No flag
distinguishes them; the calling context does.

`--self` does not run the command inline. It schedules the same argument line
through systemd and returns, so it fires once the turn has ended:

```
claude-crew switch 1 "Trading Research 1" --self
switch targets Claude1, the session you are running in.
scheduled crew-self-1789533704 in 15s, so it runs once this turn has ended
this session stops when it fires, and comes back on the same conversation
verify after it fires:  claude-crew status  &&  journalctl -u crew-self-1789533704
```

`--in <secs>` sets the wait, 15 by default. Give it longer when the turn still
has work to do. The deferred run has no claude ancestor, so it does the work
inline rather than deferring again.

Report it as scheduled, not as done. The result is only visible in the next
session, through `claude-crew status` and the unit's journal.

## Busy sessions are not interrupted

Commands that stop a session refuse one that is working, waiting on a question
or permission prompt, or holding an unsent draft: `stop`, `switch`, `relaunch`,
`model`, `effort`, `clear`, `new --force`, `delete` of a live conversation, and
`start --force`. When one is refused, tell the user which session is busy and
why. Pass `--interrupt` only when the user has said to interrupt it.

`restart`, `update` and anything run with `--self` wait up to 15 minutes for a
busy session to go idle instead. An unsent draft still stops them.

## Project skills

Sessions start in the crew's `WORKDIR`, so a project's own skills and
`CLAUDE.md` never load by themselves. The crew's `local-skills-guard.sh` hook
names them the first time a session touches that project, and refuses the first
write there until they are read. When it refuses, read what it lists, then retry.
Read a project's skills as plain files. The Skill tool cannot see them.

## Clearing a session's context

`claude-crew clear` is NOT Claude Code's `/clear`. Say so whenever you offer
either one.

- **Claude Code's `/clear`** starts a new conversation in the same process and
  keeps the old one on disk under the same title, so the store gets two
  conversations with one name. The user does not use it.
- **`claude-crew clear`** restarts the slot on a new, empty conversation with the
  same title, model and effort, then DELETES the old conversation, its sidecar
  and its uploads. There is no backup.

Clearing requires the user's confirmation, exactly like deleting. Run it bare
first, show the user what it printed, and add `--yes` only after they say yes.
Before asking, check its uploads: an upload can be the only copy of a file.

```
claude-crew clear 4          # prints the plan, changes nothing
claude-crew clear 4 --yes    # after the user confirms
```

Remote control gets a new link, because it follows the conversation. Aimed at
your own slot, `clear` defers onto a timer, like every other stop path.

**If a `/clear` happened anyway,** the SessionStart hook `claude-crew cleared`
has already saved the slot as holding the new conversation and put a notice in
your context. Tell the user the previous conversation still exists under the
same name, and ask before deleting it with `claude-crew delete <id> --yes`.

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
- A conversation live in a slot is stopped first. Files are removed only after
  the process has exited.
- A conversation live in a terminal outside the slots is refused. Stop that
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
claude-crew prompt 2 "status on the ingest queue?"
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

A slot with no running claude is sitting at a root shell prompt, where the text
would be executed as a command. That is refused too.

Newlines submit the box, so a multi-line prompt would arrive as several separate
turns. They are collapsed to spaces and the command says so.

## Renaming a session

Rename from inside the session with `/rename`. The conversation's own title is
the source of truth: every relaunch (start, restart, switch, model, effort)
reads the latest title from the transcript and launches under it, so the window
label and the remote-control name follow the rename on the next relaunch. Until
then `status` shows the stale window label beside the real title.

## Changing model or effort

Both are launch flags, so changing one is the same primitive as `switch`: stop
the process, start it again on the same conversation. There is no in-band
round-trip to wedge.

```
claude-crew model "Web Ko Gedy" sonnet
claude-crew effort 2 xhigh
```

Each changes only the setting it names. The conversation keeps its other
setting, and a `switch` carries both to the new slot.

A slot follows the `crew.conf` default until someone sets it. The saved slots
store `-` for a setting that follows the default, so changing the default with
`claude-crew setup --model sonnet` reaches every such slot on the next start or
restart, while a slot set with `model` or `effort` keeps its value. `default`
hands a setting back:

```
claude-crew model 2 default
claude-crew effort 2 default
```

## Saved slots

`slots.state`, beside `crew.conf`, records what each slot runs: the conversation,
its model, its effort, and its title. `start` and `restart` relaunch exactly that
set. Each conversation returns to its own slot, and a slot you emptied stays empty.

It records what is running, not what was asked for. Every command that changes a
slot rewrites it, and `restart` rewrites it just before scheduling. A slot that
has died keeps its entry, so a crashed session comes back on the next `start`.
An entry leaves only through `stop`, `delete`, or its transcript disappearing.

Ranking by recency happens only while nothing is saved, or with `start --rerank`.
Recency is not what you want once slots are settled. A restart that ranked by it
would drop a conversation you were using and pull in an older one with the same
title.

`claude-crew boot on` makes this survive a reboot. Without it, nothing starts the
fleet after the machine comes back.

## Configuration

`~/.claude/skills/claude-crew/crew.conf`, written by `claude-crew setup`. Plain `KEY=value`,
safe to edit by hand.

| Key | Default | Notes |
|---|---|---|
| `WORKDIR` | home directory (`/root` on this host) | Where every session starts, and which transcript store is read. Changing it is refused while a slot is running or saved. |
| `SLOTS` | `5` | Number of parking spaces. Raise it when `status` reports an unplaced conversation. |
| `MODEL` | `opus` | An alias resolves to the latest of that family. |
| `EFFORT` | `high` | `low` `medium` `high` `xhigh` `max` |
| `PERMISSION_MODE` | `auto` | |
| `REMOTE_CONTROL` | `on` | Named after the conversation title. |
| `AUTOCOMPACT` | `auto` | Passed as `--autocompact`: `auto`, or a window from 100k to 1M tokens. |
| `TMUX_PREFIX` | `Claude` | Session names become `Claude1`..`ClaudeN`. |
| `SHELL_CMD` | `bash` | The pane process. |
| `CLAUDE_BIN` | `claude` | A testing seam. Point it at a stub to exercise the tmux mechanics without resuming a real conversation. |

Every command except `setup` refuses to run until the config exists, so setup is
its own gate.

`crew.conf` is gitignored and no install step may overwrite it.

## A slot can be running something other than its label

`/resume` from inside a pane switches that session's conversation without
touching argv, the `-n` display name, or the tmux window name. All three keep
naming the conversation it started on, so the pane reads as one thing while
running another.

`claude-crew` resolves this from `~/.claude/sessions/<pid>.json`, which is keyed
by process id and follows the switch. `status` prints the real conversation,
flags a window whose label has drifted, and flags any conversation that two
slots hold at once. Two live processes on one transcript interleave their
writes, so stop one as soon as it shows up.

`claude-crew relabel` repairs the stale window names. Without it a drifted label
persists until that slot is relaunched.

## Never run `tmux kill-server`

It ends every session on this host, including your own. A tool shell inherits
`$TMUX`, and tmux follows `$TMUX` over `TMUX_TMPDIR`, so a server you believe is
separate is the real one.

To exercise tmux without touching the fleet, name a socket explicitly and clear
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
