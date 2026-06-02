#!/bin/sh
# Idempotently (re)apply the claude-osc-notify patches to the Cursor extension
# wenbopan.vscode-terminal-osc-notifier. Safe to run repeatedly. This is also
# the RECOVERY tool: Cursor wipes these patches whenever it auto-updates the
# extension, after which notifications silently stop — just re-run this.
#
# After running, FULLY restart Cursor (Cmd+Q, reopen). "Reload Window" is not
# reliable for picking up extension changes.
set -eu

BANNER_ID=${BANNER_ID:-com.claude-osc-notify.banner}
ALERT_ID=${ALERT_ID:-com.claude-osc-notify.alert}

# Locate Cursor.app and read its bundle id dynamically (differs per build / VS Code).
CURSOR_APP=${CURSOR_APP:-/Applications/Cursor.app}
[ -d "$CURSOR_APP" ] || CURSOR_APP="$HOME/Applications/Cursor.app"
[ -d "$CURSOR_APP" ] || { echo "error: Cursor.app not found; set CURSOR_APP=/path/to/Cursor.app" >&2; exit 1; }
CURSOR_ID=$(defaults read "$CURSOR_APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null) \
    || { echo "error: could not read Cursor bundle id" >&2; exit 1; }

# Newest installed version of the extension.
EXT_DIR=$(ls -d "$HOME"/.cursor/extensions/wenbopan.vscode-terminal-osc-notifier-*/ 2>/dev/null | sort -V | tail -1 || true)
[ -n "${EXT_DIR:-}" ] || { echo "error: extension not installed. Run: cursor --install-extension wenbopan.vscode-terminal-osc-notifier" >&2; exit 1; }
JS="${EXT_DIR%/}/dist/extension.js"
[ -f "$JS" ] || { echo "error: $JS not found" >&2; exit 1; }

# Preserve a pristine copy the first time we ever touch this file.
[ -f "$JS.orig" ] || cp "$JS" "$JS.orig"

echo "Patching: $JS"
echo "  Cursor bundle id: $CURSOR_ID"
echo "  senders: $BANNER_ID / $ALERT_ID"

CURSOR_ID="$CURSOR_ID" BANNER_ID="$BANNER_ID" ALERT_ID="$ALERT_ID" \
perl -0777 -i -pe '
    my $cid    = $ENV{CURSOR_ID};
    my $banner = $ENV{BANNER_ID};
    my $alert  = $ENV{ALERT_ID};

    # Patch 1: icon override (guard: skip if already present)
    unless (/claude-notify-icon/) {
        my $find = q{  iconPathForOS = resolveVSCodeIconPath();};
        my $repl = $find . q{ { const _custom = require("path").join(require("os").homedir(), ".cursor", "claude-notify-icon.png"); if (require("fs").existsSync(_custom)) iconPathForOS = _custom; }};
        s/\Q$find\E/$repl/;
    }

    # Patch 2: opts wait/timeout -> false (guard: skip if timeout:false present)
    unless (/timeout: false/) {
        my $find = qq{      wait: true,\n      // Required so click events are delivered\n      tid};
        my $repl = qq{      wait: false,\n      timeout: false,\n      tid};
        s/\Q$find\E/$repl/;
    }

    # Patch 3: darwin sender/sound routing + drop contentImage (guard: __claudeAlert)
    unless (/__claudeAlert \?/) {
        my $find = qq{      opts.sender = "com.microsoft.VSCode";\n      opts.activate = "com.microsoft.VSCode";\n      if (iconPathForOS) opts.contentImage = iconPathForOS;};
        my $repl = qq{      opts.sender = globalThis.__claudeAlert ? "$alert" : "$banner";\n      if (globalThis.__claudeSound) opts.sound = globalThis.__claudeSound;\n      opts.activate = "$cid";};
        s/\Q$find\E/$repl/;
    }

    # Patch 4: parser callback - extract sound/alert, strip prefixes (guard: __claudeSound = _sm)
    unless (/__claudeSound = _sm/) {
        my $find = qq{          const title = n.kind === "osc777" ? n.title || "Terminal" : "Terminal";\n          const body = n.body;\n          sendOsNotification(tid, title, body);};
        my $repl = q{          let title = n.kind === "osc777" ? n.title || "Terminal" : "Terminal";} . "\n"
                 . q{          const body = n.body;} . "\n"
                 . q{          const _sm = title.match(/\[sound:([A-Za-z]+)\]/);} . "\n"
                 . q{          globalThis.__claudeSound = _sm ? _sm[1] : void 0;} . "\n"
                 . q{          globalThis.__claudeAlert = /\[alert\]/.test(title);} . "\n"
                 . q{          title = title.replace(/\[sound:[A-Za-z]+\]/g, "").replace(/\[alert\]\s*/g, "").trim();} . "\n"
                 . q{          sendOsNotification(tid, title, body);};
        s/\Q$find\E/$repl/;
    }
' "$JS"

# Verify all five markers are present.
missing=0
for marker in "claude-notify-icon" "timeout: false" "__claudeAlert ?" "__claudeSound = _sm" "$ALERT_ID"; do
    grep -qF "$marker" "$JS" || { echo "  MISSING patch marker: $marker" >&2; missing=1; }
done
if [ "$missing" -eq 0 ]; then
    echo "All patches present. Now fully restart Cursor (Cmd+Q, reopen)."
else
    echo "error: some patches did not apply. The extension version may have changed;" >&2
    echo "       compare against assets/extension-0.1.4-pristine.js.reference and update anchors." >&2
    exit 1
fi
