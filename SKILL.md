---
name: claude-crew
description: >-
  Manage the tmux fleet of Claude Code sessions on this host: start them,
  restart them, move a conversation into a different slot, change a session's
  model or effort, or type a prompt into another session's input box. Use when
  asked to start/restart the claudes, switch a session, see which conversation
  is in which tmux slot, prompt or message another session, change a running
  session's model or effort level, or upgrade the claude binary. Triggers: crew,
  restart the claudes, start the claudes, which session is in which slot, switch
  TR1 to Click Clack, prompt the other session, tell Claude3 to, change slot 2 to
  sonnet, bump effort to xhigh, update claude code.
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
| `claude-crew start` | Fill free slots from the newest N conversations. |
| `claude-crew start --dry-run` | Print the plan, launch nothing. |
| `claude-crew restart [delay]` | Restart every slot via systemd, without killing the caller. |
| `claude-crew switch <A> <B>` | Put conversation B in A's slot. Swaps if B is already live somewhere. |
| `claude-crew prompt <target> <text>` | Type a real prompt into that slot's running claude. |
| `claude-crew model <target> <model>` | Relaunch that conversation on a different model. |
| `claude-crew effort <target> <level>` | Relaunch it at a different effort level. |
| `claude-crew update` | Upgrade the claude binary, then restart. |

`<target>` is a slot number, a tmux session name, or a case-insensitive
substring of a title. `claude-crew switch 4 "click"` works. An ambiguous substring is
refused with the list of matches, never guessed.

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

## Prompting another session

`claude-crew prompt` types into the target's tty. Use it when remote control is wedged
at a pending message, which happens routinely after a model or effort change.

```
claude-crew prompt "Trading Research 1" "re-read the vault index before answering"
```

It refuses when the target slot has no running claude. That guard is load
bearing: with shell-first panes, a slot whose claude has exited is sitting at a
root shell prompt, and the prompt text would be executed as a command.

Newlines submit the input box, so a multi-line prompt would arrive as several
separate turns. `claude-crew prompt` collapses them to spaces and says so.

## Changing model or effort

Both are launch flags, so changing one is the same primitive as `switch`: stop
the process, start it again on the same conversation. There is no in-band
round-trip to wedge.

```
claude-crew model "Web Ko Gedy" sonnet
claude-crew effort 2 xhigh
```

These change one running session only. To change the default for every future
launch, use `claude-crew setup --model sonnet` and then `claude-crew restart`.

## Configuration

`~/.claude/skills/claude-crew/crew.conf`, written by `claude-crew setup`. Plain `KEY=value`,
safe to edit by hand.

| Key | Default | Notes |
|---|---|---|
| `WORKDIR` | `/root` | Working directory, and which transcript store is read. |
| `SLOTS` | `5` | Number of parking spaces. Raise it when `status` reports an unplaced conversation. |
| `MODEL` | `opus` | An alias resolves to the latest of that family. |
| `EFFORT` | `high` | `low` `medium` `high` `xhigh` `max` |
| `PERMISSION_MODE` | `auto` | |
| `REMOTE_CONTROL` | `on` | Named after the conversation title. |
| `TMUX_PREFIX` | `Claude` | Session names become `Claude1`..`ClaudeN`. |
| `SHELL_CMD` | `bash` | The pane process. |
| `CLAUDE_BIN` | `claude` | A testing seam. Point it at a stub to exercise the tmux mechanics without resuming a real conversation. |

Every command except `setup` refuses to run until the config exists, so setup is
its own gate.

`crew.conf` is gitignored and no install step may overwrite it.

## The `pgrep -f` trap

`pgrep -f` and `pkill -f` match against a flattened command line, so a pattern
like `--resume <id>`, a session title, or a script path also matches the shell
that invoked you. It killed a live session twice while this skill was being
built. `claude-crew` reads argv out of `/proc` for the processes inside its own panes
instead, which is the narrow question actually being asked.
