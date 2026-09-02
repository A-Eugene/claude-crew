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
  Claude1    74dc8897  Trading Research 2
  Claude2    2b599c1a  VPS Management
  Claude3    e3d089f9  Trading Research 1
  Claude4    6a2ae08d  Click Clack
  Claude5    9d1dcf25  Web Ko Gedy
newest 5 conversations:
  2b599c1a in Claude2  VPS Management
  065e1f12 UNPLACED    Discretionary Backtest Platform
```

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
| `claude-crew start` | Fill free slots from the newest N conversations. |
| `claude-crew start --dry-run` | Print the plan, launch nothing. |
| `claude-crew restart [delay]` | Restart every slot via systemd, without killing the caller. |
| `claude-crew switch <A> <B>` | Put conversation B in A's slot. Swaps if B is already live. |
| `claude-crew prompt <target> <text>` | Type a real prompt into that slot's running claude. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew update` | Upgrade the claude binary, then restart. |

`<target>` is a slot number, a tmux session name, or a case-insensitive
substring of a title. An ambiguous substring is refused with the list of
matches, never guessed.

## It will not let you kill yourself

Every stop path is fatal when aimed at the slot you are running in. `switch`,
`model`, `effort`, and `start --force` refuse when the target is your own
session, and `whoami` tells you which one that is.

The guard reads the process tree rather than tmux. Under systemd, cron, or a
plain ssh shell there is no claude ancestor and it stays silent, which is how
`restart` performs the same work an inline `start --force` is refused. Nothing
distinguishes them but the calling context. `--self` overrides.

## Install

```sh
git clone https://github.com/A-Eugene/claude-crew.git
cp -r claude-crew ~/.claude/skills/claude-crew
chmod +x ~/.claude/skills/claude-crew/bin/claude-crew
ln -s ~/.claude/skills/claude-crew/bin/claude-crew /usr/local/bin/claude-crew
claude-crew setup
```

Config lands at `~/.claude/skills/claude-crew/crew.conf`. It is gitignored.
**A reinstall must not overwrite it** — use `rsync --exclude=crew.conf` if you
script the copy.

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
keystrokes, not that claude was in a state to receive them. A session that is
compacting swallows them silently while the command reports success. `prompt`
now types without Enter, reads the pane back, and submits only once the text is
visibly in the input box.

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
