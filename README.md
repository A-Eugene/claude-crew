# claude-crew

Park your Claude Code conversations in numbered tmux sessions, and move them
around without destroying the terminal they live in.

If you keep several long-running Claude Code conversations on one machine, you
end up managing them by hand: which tmux window holds which conversation, how to
restart them all without killing the one you are typing in, how to switch a
window from one conversation to another. `claude-crew` does that.

```
claude-crew setup
claude-crew start
claude-crew status
```

```
slots (prefix Claude, workdir /root, opus/high/auto, remote-control on):
  Claude1    2b599c1a  VPS Management
  Claude2    9d1dcf25  Web Ko Gedy
  Claude3    e3d089f9  Trading Research 1
  Claude4    6a2ae08d  Click Clack
  Claude5    065e1f12  Discretionary Backtest Platform
newest 5 conversations:
  2b599c1a in Claude1  VPS Management
  74dc8897 UNPLACED    Trading Research 2
```

`status` also flags a window whose label no longer matches what it runs, and any
conversation two slots hold at once.

## The idea

A **slot** is a numbered parking space, a tmux session called `Claude1`,
`Claude2`, and so on. Slots are assigned by recency of your last message, so a
conversation moves between slots over time. The number tells you nothing about
what is in it. Address conversations by title instead, which every command
accepts as a substring.

**A slot runs a shell, and claude is typed into that shell.** This is the design
decision everything else rests on. If claude were the pane process, killing it
would delete the tmux session along with its scrollback. Because it is a child
of a shell, you can stop and restart claude in place, and the terminal survives.
That is what makes switching a slot's conversation, its model, or its effort
level cheap rather than destructive.

## Commands

| Command | What it does |
|---|---|
| `claude-crew setup [flags]` | Write or patch the config. Re-running with no flags keeps every value. |
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
| `claude-crew delete <conversation> [--yes]` | Stop it if live, then delete its transcript and sidecar directory. Without `--yes` it only prints what would go. There is no backup. |
| `claude-crew switch <A> <B>` | Put conversation B in A's slot. Swaps if B is already live. |
| `claude-crew prompt <target> <text>` | Type keystrokes into that slot's input box. Not a messaging channel — see below. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew update` | Upgrade the claude binary, then restart. |

`<target>` is a slot number, a tmux session name, or a case-insensitive
substring of a title. An ambiguous substring is refused with the list of
matches, never guessed.

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

Every stop path is fatal when aimed at the slot you are running in. `switch`,
`model`, `effort`, `start --force`, and `new --slot <n> --force` refuse when the
target is your own session, and `whoami` tells you which one that is.

The guard reads the process tree rather than tmux. Under systemd, cron, or a
plain ssh shell there is no claude ancestor and it stays silent, which is how
`restart` performs the same work an inline `start --force` is refused. Nothing
distinguishes them but the calling context. `--self` overrides.

`delete` refuses your own conversation with no override, because a deleted
transcript cannot be brought back.

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

## Install

```sh
git clone https://github.com/A-Eugene/claude-crew.git
cp -r claude-crew ~/.claude/skills/claude-crew
chmod +x ~/.claude/skills/claude-crew/bin/claude-crew
ln -s ~/.claude/skills/claude-crew/bin/claude-crew /usr/local/bin/claude-crew
claude-crew setup
```

Config lands at `~/.claude/skills/claude-crew/crew.conf`. It is gitignored.
**A reinstall must not overwrite it or `slots.state`** — use
`rsync --exclude=crew.conf --exclude=slots.state` if you script the copy.

As a Claude Code skill, `SKILL.md` also lets any session drive the fleet by
asking in plain language.

## Configuration

| Key | Default | Notes |
|---|---|---|
| `WORKDIR` | `/root` | Working directory, and which transcript store is read. |
| `SLOTS` | `5` | Number of parking spaces. |
| `MODEL` | `opus` | An alias resolves to the latest of that family. |
| `EFFORT` | `high` | `low` `medium` `high` `xhigh` `max` |
| `PERMISSION_MODE` | `auto` | |
| `REMOTE_CONTROL` | `on` | Named after the conversation title. |
| `TMUX_PREFIX` | `Claude` | Session names become `Claude1`..`ClaudeN`. |
| `SHELL_CMD` | `bash` | The pane process. |
| `CLAUDE_BIN` | `claude` | A testing seam. Point it at a stub to exercise the tmux mechanics without resuming a real conversation. |

Every command except `setup` refuses to run until the config exists, so setup is
its own gate.

## Things this learned the hard way

**Recency is not intent.** Filling slots from the most recently used
conversations works until slots are settled. Then a restart drops one you are
using and pulls in an older duplicate with the same title. Slots are now saved,
and recency only fills slots while nothing is saved.

**A registry file can outlive its process.** After a reboot a new claude can
receive the pid of an old one whose `~/.claude/sessions/<pid>.json` is still on
disk. A file older than the process it names is ignored, or a save would record
the wrong conversation for that slot.

Each of these is a real failure that happened on a real host. The comments in
`bin/claude-crew` mark them at the code that prevents them.

**A zero exit code does not mean it worked.** A systemd unit's `PATH` does not
include `~/.local/bin`, where `claude` lives. Every pane died instantly while
`tmux new-session` had already returned 0, so the run logged five successes with
nothing running. `claude-crew` hardens `PATH` itself and ends with a
`verify: N/N slots hold a live claude` line, exit 4 if any slot is dead.

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
anything, and when the box is not on screen at all.

**`C-u` does not clear this input box.** 700 characters survived it untouched.
`C-c` clears it, and also interrupts a turn, so it is not a cleanup tool. There
is no cleanup path: a failed delivery leaves the box empty, so there is nothing
to remove.

**argv says what a process was launched with, never what it is running now.**
A session re-pointed from inside with `/resume` keeps its old `--resume` id, its
old `-n` name, and its old tmux window name. Reading argv therefore reported the
old conversation as live and the new one as unplaced, and a second claude got
launched onto a conversation that already had one. The per-pid registry at
`~/.claude/sessions/<pid>.json` follows the switch, so that is consulted first
and argv is only the fallback. `status` also flags any conversation held by two
slots.

**Rank by the last human turn, not file mtime.** A live session's hooks rewrite
its transcript constantly, so merely being open keeps it at the top and a
throwaway holds its slot forever.

**Stop every slot before launching any.** Conversations move between slots, so
stopping slot by slot as you launch starts the new slot 1 while that same
conversation is still live in slot 4 — two processes appending to one
transcript.

**`local n="$1" pid="${ARR[$n]:-}"` aborts under `set -u`.** Bash marks every
name in one `local` statement local before evaluating any right-hand side, so
`$n` is read while still unset. Split the declaration.

## Requirements

`bash` 4.4+, `tmux`, `python3`, `systemd` (for `restart`), and Claude Code
2.1.258 or later.

## License

MIT
