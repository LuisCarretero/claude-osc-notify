#!/bin/sh
# Full install on a local Mac: receiver (Cursor extension + patches), sender apps,
# icon, hook scripts, settings.json hooks, and shell integration.
# Idempotent — safe to re-run. Requires: macOS, Cursor installed, Homebrew (for jq).
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$REPO_ROOT/lib/common.sh"

BANNER_ID=${BANNER_ID:-com.claude-osc-notify.banner}
ALERT_ID=${ALERT_ID:-com.claude-osc-notify.alert}
ICON_DEST="$HOME/.cursor/claude-notify-icon.png"

[ "$(uname)" = "Darwin" ] || die "install-mac.sh is for macOS. On a cluster use install-remote.sh."

log "1/8  jq";            require_jq
log "2/8  hook scripts";  install_scripts
log "3/8  settings.json"; merge_settings
log "4/8  shell integration"; ensure_zshrc_block mac

log "5/8  notification icon"
mkdir -p "$HOME/.cursor"
cp "$REPO_ROOT/assets/claude-notify-icon.png" "$ICON_DEST"
ok "icon -> $ICON_DEST"

log "6/8  sender apps (Banner + Alert)"
build_sender() {
    app_dir=$1; bundle_id=$2; exec_name=$3; display=$4
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
    # Icon: build .icns from the composite png
    iconset=$(mktemp -d)/icon.iconset; mkdir -p "$iconset"
    for sz in 16 32 64 128 256 512 1024; do
        sips -z $sz $sz "$ICON_DEST" --out "$iconset/icon_${sz}x${sz}.png" >/dev/null 2>&1
    done
    mv "$iconset/icon_32x32.png"   "$iconset/icon_16x16@2x.png"
    mv "$iconset/icon_64x64.png"   "$iconset/icon_32x32@2x.png"
    cp "$iconset/icon_256x256.png" "$iconset/icon_128x128@2x.png"
    cp "$iconset/icon_512x512.png" "$iconset/icon_256x256@2x.png"
    mv "$iconset/icon_1024x1024.png" "$iconset/icon_512x512@2x.png"
    iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppIcon.icns" 2>/dev/null
    cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$exec_name</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>$display</string>
    <key>CFBundleDisplayName</key><string>$display</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    printf '#!/bin/sh\nexit 0\n' > "$app_dir/Contents/MacOS/$exec_name"
    chmod +x "$app_dir/Contents/MacOS/$exec_name"
}
mkdir -p "$HOME/Applications"
build_sender "$HOME/Applications/ClaudeBanner.app" "$BANNER_ID" "ClaudeBanner" "Claude"
build_sender "$HOME/Applications/ClaudeAlert.app"  "$ALERT_ID"  "ClaudeAlert"  "Claude (Alert)"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$HOME/Applications/ClaudeBanner.app" "$HOME/Applications/ClaudeAlert.app"
ok "sender apps built and registered"

log "7/8  Cursor extension + patches"
if ! cursor --list-extensions 2>/dev/null | grep -qi "vscode-terminal-osc-notifier"; then
    warn "extension not installed; attempting install"
    cursor --install-extension wenbopan.vscode-terminal-osc-notifier 2>/dev/null \
        || warn "marketplace install failed — sideload the .vsix manually, then re-run"
fi
# Restore the pristine extension.js first (if a prior install saved one) so the
# patches reapply cleanly with the CURRENT bundle IDs instead of being skipped
# by repair's idempotency guard when IDs change between installs.
for d in "$HOME"/.cursor/extensions/wenbopan.vscode-terminal-osc-notifier-*/; do
    [ -f "$d/dist/extension.js.orig" ] && cp "$d/dist/extension.js.orig" "$d/dist/extension.js"
done
BANNER_ID="$BANNER_ID" ALERT_ID="$ALERT_ID" sh "$REPO_ROOT/repair-extension.sh"

log "8/8  bootstrap notifications (so the apps appear in System Settings)"
TN=$(ls "$HOME"/.cursor/extensions/wenbopan.vscode-terminal-osc-notifier-*/vendor/mac.noindex/terminal-notifier.app/Contents/MacOS/terminal-notifier 2>/dev/null | head -1 || true)
if [ -n "${TN:-}" ]; then
    "$TN" -title "Claude"         -message "Banner sender registered" -sender "$BANNER_ID" >/dev/null 2>&1 || true
    "$TN" -title "Claude (Alert)" -message "Alert sender registered"  -sender "$ALERT_ID"  >/dev/null 2>&1 || true
    ok "bootstrap notifications fired"
fi

cat <<DONE

────────────────────────────────────────────────────────────────────
Install complete. Two MANUAL steps remain (macOS won't let scripts do these):

1. Fully quit & reopen Cursor (Cmd+Q) so the patched extension loads.

2. System Settings → Notifications:
     • "Claude"          → Alert style: Banners,  Play sound: on
     • "Claude (Alert)"  → Alert style: Alerts,   Play sound: on
   (Both appear after the bootstrap notifications above.)

Then test in a Cursor terminal:
     printf '\033]777;notify;Test;hello\033\\'
────────────────────────────────────────────────────────────────────
DONE
