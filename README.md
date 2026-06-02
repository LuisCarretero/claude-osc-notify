# claude-osc-notify

Native macOS notifications from Claude Code sessions — local **and** remote (over
Cursor Remote-SSH to any host, e.g. an HPC login node). A Claude Code hook emits an
OSC 777 escape sequence; a patched Cursor terminal extension turns it into a real
macOS notification with a custom icon, per-event sound, and Banner-vs-Alert style.

```
Claude Code hook ──OSC 777──▶ Cursor integrated terminal
   (notify_osc.sh)             └─ wenbopan.vscode-terminal-osc-notifier (patched)
                                   └─ terminal-notifier ──▶ macOS Notification Center
                                        sender = ClaudeBanner.app / ClaudeAlert.app
```

## What you get

| Event | Title | Sound | Style |
|---|---|---|---|
| Turn finished (Stop) | Turn done | Tink | Banner (auto-fades) |
| Permission prompt | Permission: \<tool\> | Funk | Alert (stays) |
| Question (AskUserQuestion) | Question | Glass | Alert (stays) |
| Waiting for input (idle) | Waiting for input | Hero | Alert (stays) |

Clicking a notification focuses Cursor.

## Install

### Local Mac (receiver — required)
```sh
git clone <repo-url> ~/claude-osc-notify
cd ~/claude-osc-notify
./install-mac.sh
```
Then do the two manual steps it prints (full Cursor restart + set the Notification
styles in System Settings — macOS does not allow scripting those).

### Remote cluster (sender)
Get the repo onto the login node and run the remote installer there:
```sh
git clone <repo-url> ~/claude-osc-notify   # or scp/rsync the folder up
cd ~/claude-osc-notify
./install-remote.sh
```
Reconnect a Cursor Remote-SSH terminal afterwards so `$VSCODE_SHELL_INTEGRATION=1`.

## Components

- `scripts/notify_osc.sh` — Stop/Notification hook. Parses hook JSON (one `jq`
  pass), classifies the event, emits OSC 777 with `[sound:X]` / `[alert]` prefixes.
  Finds the user's pty via `/proc` (Linux) or `ps` (macOS). ~50 ms.
- `scripts/record_tool.sh` — PreToolUse hook. Stashes the upcoming tool name so an
  MCQ (`AskUserQuestion`) can be told apart from an ordinary permission prompt. ~8 ms.
- `lib/common.sh` — shared install helpers (jq check, ~/bin copy, idempotent
  settings.json jq-merge, idempotent ~/.zshrc block).
- `repair-extension.sh` — (re)applies the 5 extension patches. **Run this whenever
  Cursor auto-updates the extension and notifications go silent.**
- `mac/compose.swift` + `assets/*` — the diagonal Claude/Cursor icon and its source.

## The extension patches (`repair-extension.sh`)

Cursor's marketplace extension is patched in `dist/extension.js`:
1. Use `~/.cursor/claude-notify-icon.png` as the notification icon.
2. Parse `[sound:X]` and `[alert]` from the title; strip them so both the OS
   notification and the in-app toast show a clean title.
3. Route to sender `ClaudeAlert.app` (Alerts) or `ClaudeBanner.app` (Banners);
   keep `activate` = Cursor so clicks focus Cursor.
4. Drop the redundant `contentImage`.
5. **`wait:false` + `timeout:false`** — the critical one. node-notifier otherwise
   injects a `-timeout` that force-dismisses the notification after 5–10 s, which
   looks exactly like a Banner even when System Settings says Alert. `timeout:false`
   is the only value node-notifier treats as "no timeout".

These are wiped on extension auto-update — just re-run `repair-extension.sh`, then
fully restart Cursor.

## Known manual / fragile bits

- **Notification styles & sound toggles** in System Settings are manual (macOS TCC
  blocks scripting them). The installer fires bootstrap notifications so both apps
  appear in the list.
- **Full Cursor restart** (Cmd+Q) is required after patching; "Reload Window" is
  unreliable.
- **tmux on the remote** needs `set -g allow-passthrough on`.
- Sender bundle IDs (`com.claude-osc-notify.{banner,alert}`) are arbitrary but must
  match between the `.app` bundles and the extension patch; override both via the
  `BANNER_ID` / `ALERT_ID` env vars if desired. `install-mac.sh` restores the
  pristine extension before patching, so changing the IDs and re-running applies
  cleanly.

## Troubleshooting

1. `echo $VSCODE_SHELL_INTEGRATION` is `1` in the terminal running Claude?
2. Patches present? `grep -c __claudeAlert ~/.cursor/extensions/wenbopan.*/dist/extension.js`
   → if 0, run `./repair-extension.sh` and restart Cursor.
3. Both `.app` bundles registered? `~/Applications/Claude{Banner,Alert}.app` exist
   and appear in System Settings → Notifications.
4. `jq` on the hook's PATH?
