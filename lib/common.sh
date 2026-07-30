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

# --- the fenced ~/.zshrc block, printed to stdout ----------------------------
# $1 = "mac" or "remote". Includes the markers, so the output is byte-comparable
# against what is already in the file (see ensure_zshrc_block).
ZSHRC_MARKER_BEGIN="# >>> claude-osc-notify shell integration >>>"
ZSHRC_MARKER_END="# <<< claude-osc-notify shell integration <<<"

zshrc_block() {
    printf '%s\n' "$ZSHRC_MARKER_BEGIN"
    if [ "$1" = "mac" ]; then
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
    # Cursor ships two layouts: ~/.cursor-server/bin/<hash>/ (older) and
    # ~/.cursor-server/bin/<arch>/<hash>/ (current, e.g. bin/linux-x64/<hash>/).
    # Glob both depths. (Nom) = nullglob + newest-first, so a missing directory
    # expands to nothing instead of erroring, and the newest server wins.
    _si_rel=out/vs/workbench/contrib/terminal/common/scripts/shellIntegration-rc.zsh
    _si_path=$(print -rl -- ~/.cursor-server/bin/*/$_si_rel(Nom) \
                            ~/.cursor-server/bin/*/*/$_si_rel(Nom) 2>/dev/null | head -1)
  fi
  [[ -r "$_si_path" ]] && . "$_si_path"
  unset _server_dir _si_path _si_rel
fi
BLOCK
    fi
    printf '%s\n' "$ZSHRC_MARKER_END"
}

# --- add/refresh shell-integration block in ~/.zshrc -------------------------
# $1 = "mac" or "remote"
# Re-runnable in the real sense: a block written by an OLDER version is replaced,
# so fixes (e.g. a new cursor-server layout) actually reach hosts that already
# installed. Only the fenced region is touched; a timestamped .bak is kept.
ensure_zshrc_block() {
    variant=$1
    rc="$HOME/.zshrc"
    [ -f "$rc" ] || touch "$rc"
    desired=$(zshrc_block "$variant")

    if grep -qF "$ZSHRC_MARKER_BEGIN" "$rc"; then
        current=$(awk -v b="$ZSHRC_MARKER_BEGIN" -v e="$ZSHRC_MARKER_END" \
            'index($0,b){f=1} f{print} index($0,e){f=0}' "$rc")
        if [ "$current" = "$desired" ]; then
            ok "zshrc shell-integration block already up to date"
            return 0
        fi
        cp "$rc" "$rc.bak.$(date +%Y%m%d-%H%M%S)"
        tmp="$rc.tmp.$$"
        awk -v b="$ZSHRC_MARKER_BEGIN" -v e="$ZSHRC_MARKER_END" \
            'index($0,b){f=1} !f{print} index($0,e){f=0}' "$rc" > "$tmp" \
            || die "failed to strip old zshrc block"
        printf '%s\n' "$desired" >> "$tmp"
        mv "$tmp" "$rc"
        ok "refreshed outdated zshrc shell-integration block ($variant variant)"
        return 0
    fi

    printf '\n%s\n' "$desired" >> "$rc"
    ok "added shell-integration block to ~/.zshrc ($variant variant)"
}
