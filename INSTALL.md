# Installing claude-crew

These steps work for a person at a terminal and for an AI agent running shell
commands. Each step says how to check it worked. An agent should run the check
and stop at the first one that fails.

## 0. Requirements

| Needs | Check |
|---|---|
| Linux with systemd | `systemctl --version` |
| bash 4.4 or later | `bash --version` |
| tmux | `tmux -V` |
| python3 (standard library only) | `python3 --version` |
| git | `git --version` |
| Claude Code 2.1.258 or later, signed in | `claude --version` |

`restart`, `update`, `boot` and `--self` hand work to systemd, so they need it.
The rest runs without it.

## 1. Get the files

```sh
git clone https://github.com/A-Eugene/claude-crew.git /tmp/claude-crew
mkdir -p ~/.claude/skills
rsync -a --exclude=.git --exclude=crew.conf --exclude=slots.state \
  /tmp/claude-crew/ ~/.claude/skills/claude-crew/
chmod +x ~/.claude/skills/claude-crew/bin/claude-crew ~/.claude/skills/claude-crew/hooks/*.sh
ln -sf ~/.claude/skills/claude-crew/bin/claude-crew /usr/local/bin/claude-crew
```

Without root, link into `~/.local/bin` instead, and make sure it is on `PATH`.

Check: `claude-crew --help` prints the command list.

The directory must be `~/.claude/skills/claude-crew`. Claude Code finds the skill
there, and the hooks and the web page locate the CLI relative to it.

## 2. Write the config

```sh
claude-crew setup
```

This writes `~/.claude/skills/claude-crew/crew.conf` with the defaults:

| Key | Default |
|---|---|
| `WORKDIR` | your home directory |
| `SLOTS` | `5` |
| `MODEL` | `claude-opus-5-5` |
| `EFFORT` | `medium` |
| `PERMISSION_MODE` | `auto` |
| `REMOTE_CONTROL` | `on` |
| `AUTOCOMPACT` | `auto` |
| `TMUX_PREFIX` | `Claude` |

`WORKDIR` is the directory every session starts in, and it decides which
transcript store the crew reads. Set it now if your sessions should start
somewhere else:

```sh
claude-crew setup --workdir /path/to/work --slots 4 --model claude-opus-5-5 --effort high
```

The crew refuses to change `WORKDIR` later while a slot is running or saved,
because a conversation resumes only from the directory it started in.

Check: `claude-crew status` prints one line per slot.

## 3. Register the hooks

Add both entries to the `hooks` object in `~/.claude/settings.json`. **Merge them
into the existing file. Do not replace the file**, since it holds your other
settings and hooks.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [{ "type": "command",
                    "command": "~/.claude/skills/claude-crew/hooks/local-skills-guard.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "clear",
        "hooks": [{ "type": "command",
                    "command": "~/.claude/skills/claude-crew/bin/claude-crew cleared" }]
      }
    ]
  }
}
```

- **`local-skills-guard.sh`**: every crew session starts in `WORKDIR`, so Claude
  Code never loads the skills and `CLAUDE.md` of a project below it. The hook
  names them the first time a session touches that project, and refuses the
  first write until they have been read.
- **`claude-crew cleared`**: Claude Code's `/clear` keeps the previous
  conversation under the same name. The hook records the new conversation as
  the slot's, and has the session ask before the previous one is deleted. To
  name the web page in that notice, prefix the command with
  `CREW_WEB_URL=https://crew.example.com `.

Check: `python3 -m json.tool ~/.claude/settings.json` succeeds, and both commands
appear in it. Sessions pick the hooks up when they next start.

## 4. Start the fleet

```sh
claude-crew start       # fills the slots from your newest conversations
claude-crew status
claude-crew save        # keeps this set for later starts and restarts
claude-crew boot on     # optional: start the saved slots after a reboot
```

Check: `claude-crew status` shows a conversation in each started slot. Attach
to one with `tmux attach -t Claude1`, and leave with `Ctrl-b d`.

## 5. The web page (optional)

The page runs every command as a button. It listens on `127.0.0.1:3115` and
needs a reverse proxy with HTTPS in front of it.

```sh
python3 ~/.claude/skills/claude-crew/web/server.py set-password
cp ~/.claude/skills/claude-crew/web/claude-crew-web.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now claude-crew-web
```

Check: `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3115/api/state`
prints `401`.

The unit resolves `%h` to root's home, so it runs as root. To run it as another
user, add `User=<name>` under `[Service]`.

For HTTPS with nginx and Let's Encrypt, replace `crew.example.com` with your host
name:

```sh
certbot certonly --nginx -d crew.example.com
sed 's/crew.example.com/<your host>/g' ~/.claude/skills/claude-crew/web/nginx.conf \
  > /etc/nginx/conf.d/claude-crew-web.conf
nginx -t && systemctl reload nginx
```

Use `certbot certonly`, not `certbot --nginx` alone. With a wildcard or
catch-all server block already present, `--nginx` can install the new
certificate into that block and break the sites it serves.

Check: the host name shows a password field, and a wrong password is refused.

## Updating

```sh
git -C /tmp/claude-crew pull
rsync -a --exclude=.git --exclude=crew.conf --exclude=slots.state \
  /tmp/claude-crew/ ~/.claude/skills/claude-crew/
systemctl restart claude-crew-web    # only if the web page is installed
```

`crew.conf` and `slots.state` hold your settings and saved slots. The excludes
keep them. Never copy over them.

## Rules for an AI agent doing this

- Run `claude-crew start --force`, `restart` and `stop` only when asked. Each one
  stops running sessions, and one of them may be your own.
- Never run `tmux kill-server`. It ends every tmux session on the machine,
  including the one you are running in.
- Never kill processes with `pkill -f` or `pgrep -f` patterns. The pattern can
  match your own shell.
- Merge `settings.json`. Do not overwrite it.
- Report each check's actual output, not the expected one.
