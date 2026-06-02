# claude-osc-notify

Native macOS notifications from Claude Code — local **and** remote (over Cursor
Remote-SSH to any host, e.g. an HPC login node). A Claude Code hook emits an OSC 777
escape sequence; a patched Cursor terminal extension turns it into a real macOS
notification with a custom icon, per-event sound, and Banner-vs-Alert style.

> ⚠️ Fully vibecoded over one long debugging session. Works on my machine(s);
> patches a third-party extension's compiled JS, so treat it as a personal hack,
> not production software. PRs/forks welcome, expectations low. 😄

<img src="assets/demo-notification.png" alt="Example notification" width="380">


```
Claude Code hook ──OSC 777──▶ Cursor terminal ──▶ patched extension
                                                   └─ terminal-notifier ──▶ macOS
```

## What you get

| Event | Sound | Style |
|---|---|---|
| Turn finished | Tink | Banner (auto-fades) |
| Permission prompt | Funk | Alert (stays) |
| Question (AskUserQuestion) | Glass | Alert (stays) |
| Waiting for input | Hero | Alert (stays) |

Clicking a notification focuses Cursor.

## Install

**Local Mac (receiver — required):**
```sh
git clone <repo-url> ~/claude-osc-notify && cd ~/claude-osc-notify && ./install-mac.sh
```
Then do the two manual steps it prints: restart Cursor (Cmd+Q) and set the
Notification styles in System Settings (macOS won't let scripts do those).

**Remote host (sender):** clone/scp the repo onto the login node, then:
```sh
cd ~/claude-osc-notify && ./install-remote.sh
```
Reconnect a Cursor Remote-SSH terminal so `$VSCODE_SHELL_INTEGRATION=1`.

## How it works

- `scripts/notify_osc.sh` (Stop/Notification hook) classifies the event and emits
  OSC 777 with `[sound:X]`/`[alert]` title prefixes.
- `scripts/record_tool.sh` (PreToolUse hook) stashes the tool name so a question is
  told apart from a plain permission prompt.
- `repair-extension.sh` applies 5 patches to the extension's `dist/extension.js`:
  custom icon, parse+strip the prefixes, route to a Banner/Alert sender app, drop a
  redundant image, and — the one that cost the most hair — **`wait:false` +
  `timeout:false`** (node-notifier otherwise injects a `-timeout` that
  force-dismisses Alerts after a few seconds).

## Gotchas

- **Cursor auto-updates wipe the patches** → re-run `./repair-extension.sh` + restart Cursor.
- Notification styles/sounds are set by hand in System Settings (can't be scripted).
- "Reload Window" isn't enough after patching — fully quit Cursor.
- tmux on the remote needs `set -g allow-passthrough on`.
- Sender IDs `com.claude-osc-notify.{banner,alert}` must match between the apps and
  the patch; override with `BANNER_ID`/`ALERT_ID` env vars.

## Troubleshooting

1. `$VSCODE_SHELL_INTEGRATION` is `1` in the terminal running Claude?
2. `grep -c __claudeAlert ~/.cursor/extensions/wenbopan.*/dist/extension.js` → if 0,
   run `./repair-extension.sh` and restart Cursor.
3. Both `~/Applications/Claude{Banner,Alert}.app` exist and appear in System Settings?
4. `jq` on the hook's PATH?

## More detail

See [AGENTS.md](AGENTS.md) for the full internals — data flow, the exact 5 patches,
hook JSON fields, the `timeout:false` saga, and a debug recipe — aimed at an agent
installing or maintaining this.
