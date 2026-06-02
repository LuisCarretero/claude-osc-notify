# AGENTS.md — install & maintenance notes for agents

Context an agent (or future human) needs to install, debug, or extend this repo.
Assumes you've read the README. Detail kept because this hack has sharp edges.

## Architecture & data flow

```
Claude Code session (local Mac OR remote via Cursor Remote-SSH)
  │  hooks (PreToolUse / Stop / Notification) read JSON on stdin
  ├─ record_tool.sh   → writes /tmp/claude_pending_tool_<session_id>
  └─ notify_osc.sh    → emits OSC 777 to the controlling pty:
                          \033]777;notify;<title>;<body>\033\\
                        title carries [sound:Name] and/or [alert] prefixes
  ▼ (bytes travel the pty; over Remote-SSH they ride the same stream Cursor reads)
Cursor integrated terminal → shell integration (OSC 633) must be ON
  └─ extension wenbopan.vscode-terminal-osc-notifier (PATCHED)
       parses OSC 777, strips prefixes, picks sender app, calls node-notifier
         └─ bundled terminal-notifier → macOS Notification Center
              sender = ClaudeBanner.app (Banners) | ClaudeAlert.app (Alerts)
              activate = Cursor's bundle id (click focuses Cursor)
```

Key insight: the extension only sees terminal output **during a shell-integrated
command execution** (`onDidStartTerminalShellExecution`). No shell integration →
extension never receives the OSC → silent failure. This is the #1 cause of "nothing
happens." `$VSCODE_SHELL_INTEGRATION` must be `1` in the terminal running Claude.

## Local vs remote split

| | Local Mac | Remote host |
|---|---|---|
| Receives/renders notifications | ✅ (extension + apps live here) | ❌ |
| Runs hook scripts + emits OSC | ✅ | ✅ |
| Needs sender apps / extension patches | ✅ | ❌ |
| zshrc integration variant | `cursor --locate-shell-integration-path` | `.cursor-server` path discovery |

The remote side is **sender-only**: it just emits OSC over the SSH pty that Cursor
is already reading locally. Bundle IDs, apps, and patches are irrelevant remotely.

## Hook JSON fields used

`notify_osc.sh` reads (one `jq` pass): `hook_event_name`, `message`,
`notification_type`, `last_assistant_message`, `session_id`.
`record_tool.sh` reads `session_id`, `tool_name` (pure-shell, no jq).

Observed `notification_type` values: `permission_prompt`, `idle_prompt`.
`AskUserQuestion` **does** fire `PreToolUse` (so `record_tool.sh` catches it) but its
Notification arrives as `permission_prompt` — they're distinguished only via the
stashed pending tool name. The pending-tool file is treated as fresh for 30 s.

Why a separate `record_tool.sh`: at Notification time the transcript hasn't been
flushed with the in-flight tool_use, so you can't read the tool from the transcript
— PreToolUse is the only reliable source.

## The 5 extension patches (canonical source: `repair-extension.sh`)

Applied to `~/.cursor/extensions/wenbopan.vscode-terminal-osc-notifier-*/dist/extension.js`.
`repair-extension.sh` is idempotent (per-patch marker guards), discovers Cursor's
bundle id at runtime, and saves `extension.js.orig` (pristine) on first touch.

1. **Icon** — after `iconPathForOS = resolveVSCodeIconPath();` append a check that
   overrides `iconPathForOS` with `~/.cursor/claude-notify-icon.png` if present.
   Marker: `claude-notify-icon`.
2. **wait/timeout** — in the `opts` object, `wait: true` → `wait: false` +
   `timeout: false`. Marker: `timeout: false`. **This is the critical one.**
3. **Sender routing** — replace the hardcoded darwin block
   (`opts.sender = "com.microsoft.VSCode"` …) with
   `opts.sender = globalThis.__claudeAlert ? "<ALERT_ID>" : "<BANNER_ID>"`,
   `opts.sound = globalThis.__claudeSound`, `opts.activate = "<cursor bundle id>"`,
   and drop the `contentImage` line. Marker: `__claudeAlert ?`.
4. **Parser callback** — where `n.title` is read, extract sound via
   `/\[sound:([A-Za-z]+)\]/` and alert via `/\[alert\]/`, store on `globalThis`,
   then strip both prefixes so the OS notification **and** the in-app toast show a
   clean title. Order-independent (don't reintroduce a position-dependent
   `indexOf("[alert] ")===0` check — the `[sound:]` prefix breaks it). Marker:
   `__claudeSound = _sm`.
5. (folded into #3) drop `contentImage` to avoid a redundant small icon.

Pristine reference for re-deriving anchors if the extension version changes:
`assets/extension-0.1.4-pristine.js.reference`. If a new extension version moves the
anchors, `repair-extension.sh` exits non-zero listing missing markers — update the
`q{...}` find strings to match the new pristine source.

### Why `timeout:false` (the expensive lesson)

node-notifier's `getOptions` forces `options.timeout = 5` (if `wait:true`) or `10`
(otherwise) unless `timeout === false`, in which case it deletes it. terminal-notifier
with `-timeout N` auto-closes after N seconds — which is indistinguishable from a
Banner even when System Settings says Alert and the sender is correct. Symptom:
"notification appears but won't stay" while a direct `terminal-notifier -sender … `
(no `-timeout`) stays fine. Only `timeout:false` yields no `-timeout` flag.

## Sender apps

Generated by `install-mac.sh` `build_sender()` (not committed). Each is a minimal
`.app`: `Info.plist` (with `CFBundleIdentifier`, `LSUIElement=true`), a no-op
executable stub, and `Resources/AppIcon.icns` generated from
`assets/claude-notify-icon.png` via `sips` + `iconutil`. Registered with
`lsregister -f`. Bundle IDs default to `com.claude-osc-notify.{banner,alert}` and
**must match** the patch (`BANNER_ID`/`ALERT_ID` env vars set both consistently).

Changing IDs requires re-patching from pristine — `install-mac.sh` restores
`extension.js.orig` before calling repair so this is automatic on re-run; if you call
`repair-extension.sh` directly with new IDs on an already-patched file, its guards
will skip and leave the old IDs. Restore `.orig` first.

## What can't be automated

macOS TCC blocks scripting Notification Center prefs. After install, set by hand:
- `Claude` → Banners + Play sound on
- `Claude (Alert)` → Alerts + Play sound on
The installer fires one bootstrap notification per app so they appear in the list.
A full Cursor quit (Cmd+Q) is required after patching — "Reload Window" is unreliable.

## Idempotency / safety

- `settings.json` is jq-merged (only the 3 hook keys are set; everything else
  preserved). A timestamped `.bak` is written each merge.
- `~/.zshrc` block is fenced by `# >>> claude-osc-notify … >>>` markers; added once.
- Scripts copy to `~/bin`. Hook commands use `~/bin/notify_osc.sh` / `record_tool.sh`.
- Everything re-runnable.

## Fast debug recipe

1. `echo $VSCODE_SHELL_INTEGRATION` in the Claude terminal → must be `1`.
2. `grep -c __claudeAlert ~/.cursor/extensions/wenbopan.*/dist/extension.js` → 0 means
   Cursor updated the extension; run `./repair-extension.sh` + Cmd+Q.
3. Temporarily log emitted titles: append to `notify_osc.sh` before the final
   `printf` a line writing `$title`/`$body` to a tmp file; trigger events; inspect.
4. Bypass the extension to isolate macOS-side issues: run the bundled
   `…/terminal-notifier.app/Contents/MacOS/terminal-notifier -sender <ALERT_ID>
   -title x -message y` — if that stays but the pipeline doesn't, the bug is in the
   extension/options (e.g. a reintroduced timeout), not System Settings.
