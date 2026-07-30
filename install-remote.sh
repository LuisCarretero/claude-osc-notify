#!/bin/sh
# Install on a remote host / cluster login node (the SENDER side only).
# Copy this repo to the cluster (git clone or scp/rsync) and run this there.
# Installs the hook scripts, merges settings.json hooks, and adds the
# cursor-server shell-integration block to ~/.zshrc. Idempotent.
#
# The receiving Mac must already be set up with install-mac.sh — this side only
# emits OSC sequences; the local Cursor extension turns them into notifications.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$REPO_ROOT/lib/common.sh"

log "1/4  jq";                require_jq
log "2/4  hook scripts";      install_scripts
log "3/4  settings.json";     merge_settings
log "4/4  shell integration"; ensure_zshrc_block remote

# Quoted delimiter: the text below mentions $VSCODE_SHELL_INTEGRATION literally,
# which `set -u` would otherwise treat as an unbound variable and abort on.
cat <<'DONE'

────────────────────────────────────────────────────────────────────
Remote install complete.

Open a NEW Cursor (Remote-SSH) terminal on this host and confirm:
     echo "SI=$VSCODE_SHELL_INTEGRATION"      # expect SI=1

Then a Claude Code session here will notify your Mac on Stop / permission /
question events. If $VSCODE_SHELL_INTEGRATION is empty, the integration block
didn't load — make sure you reconnected the terminal after install.

Note: if you use tmux on this host, add to ~/.tmux.conf:
     set -g allow-passthrough on
────────────────────────────────────────────────────────────────────
DONE
