#!/bin/sh
# Shared helpers for the claude-osc-notify installers. POSIX sh.
# Sourced by install-mac.sh and install-remote.sh.

# Resolve the repo root regardless of where the installer is invoked from.
REPO_ROOT=${REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- jq presence --------------------------------------------------------------
require_jq() {
    if command -v jq >/dev/null 2>&1; then
        ok "jq: $(command -v jq)"
        return 0
    fi
    if [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
        log "Installing jq via Homebrew"
        brew install jq || die "brew install jq failed"
        ok "jq installed"
    else
        die "jq not found and cannot auto-install. Install jq and re-run."
    fi
}

# --- install hook scripts to ~/bin -------------------------------------------
install_scripts() {
    mkdir -p "$HOME/bin"
    cp "$REPO_ROOT/scripts/notify_osc.sh" "$HOME/bin/notify_osc.sh"
    cp "$REPO_ROOT/scripts/record_tool.sh" "$HOME/bin/record_tool.sh"
    chmod +x "$HOME/bin/notify_osc.sh" "$HOME/bin/record_tool.sh"
    ok "hook scripts -> ~/bin"
}

# --- merge hooks into ~/.claude/settings.json (idempotent, never clobbers) ----
# Sets the three keys we own; preserves everything else in the file.
merge_settings() {
    settings="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    [ -f "$settings" ] || printf '{}\n' > "$settings"
    # Back up once per run (timestamped).
    cp "$settings" "$settings.bak.$(date +%Y%m%d-%H%M%S)"
    tmp="$settings.tmp.$$"
    jq '
      .hooks.PreToolUse   = [{"matcher":"","hooks":[{"type":"command","command":"~/bin/record_tool.sh"}]}]
    | .hooks.Stop         = [{"matcher":"","hooks":[{"type":"command","command":"~/bin/notify_osc.sh '\''Claude Code'\'' '\''Turn done'\''"}]}]
    | .hooks.Notification = [{"matcher":"","hooks":[{"type":"command","command":"~/bin/notify_osc.sh '\''Claude Code'\'' '\''Needs attention'\''"}]}]
    ' "$settings" > "$tmp" || die "jq merge of settings.json failed"
    mv "$tmp" "$settings"
    ok "hooks merged into ~/.claude/settings.json"
}

# --- add shell-integration block to ~/.zshrc (idempotent via markers) ---------
# $1 = "mac" or "remote"
ensure_zshrc_block() {
    variant=$1
    rc="$HOME/.zshrc"
    marker_begin="# >>> claude-osc-notify shell integration >>>"
    marker_end="# <<< claude-osc-notify shell integration <<<"
    [ -f "$rc" ] || touch "$rc"
    if grep -qF "$marker_begin" "$rc"; then
        ok "zshrc shell-integration block already present"
        return 0
    fi
    {
        printf '\n%s\n' "$marker_begin"
        if [ "$variant" = "mac" ]; then
            cat <<'BLOCK'
# Sources Cursor/VS Code shell integration so the terminal-notifier extension
# can see OSC sequences. Without it $VSCODE_SHELL_INTEGRATION stays empty.
if [[ "$TERM_PROGRAM" == "vscode" && -z "$VSCODE_SHELL_INTEGRATION" ]]; then
  _si_path="$(command cursor --locate-shell-integration-path zsh 2>/dev/null)"
  [[ -r "$_si_path" ]] && . "$_si_path"
  unset _si_path
fi
BLOCK
        else
            cat <<'BLOCK'
# Cursor Remote-SSH: source the cursor-server shell integration script.
if [[ "$TERM_PROGRAM" == "vscode" && -z "$VSCODE_SHELL_INTEGRATION" ]]; then
  _si_path=""
  if [[ -n "$VSCODE_GIT_ASKPASS_MAIN" ]]; then
    _server_dir="${VSCODE_GIT_ASKPASS_MAIN%/extensions/git/dist/askpass-main.js}"
    _si_path="$_server_dir/out/vs/workbench/contrib/terminal/common/scripts/shellIntegration-rc.zsh"
  fi
  if [[ ! -r "$_si_path" ]]; then
    _si_path=$(ls -t ~/.cursor-server/bin/*/out/vs/workbench/contrib/terminal/common/scripts/shellIntegration-rc.zsh 2>/dev/null | head -1)
  fi
  [[ -r "$_si_path" ]] && . "$_si_path"
  unset _server_dir _si_path
fi
BLOCK
        fi
        printf '%s\n' "$marker_end"
    } >> "$rc"
    ok "added shell-integration block to ~/.zshrc ($variant variant)"
}
