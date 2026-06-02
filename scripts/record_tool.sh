#!/bin/sh
# PreToolUse hook: stash the upcoming tool name for the Notification hook.
# Pure-shell JSON extraction (no jq) since session_id is a UUID and tool_name
# is a bare identifier — both ASCII-safe for simple parameter-expansion.

stdin=$(cat 2>/dev/null)
[ -z "$stdin" ] && exit 0

session_id=""
tool_name=""
case "$stdin" in *'"session_id":"'*)
    s=${stdin#*'"session_id":"'}
    session_id=${s%%'"'*}
esac
case "$stdin" in *'"tool_name":"'*)
    s=${stdin#*'"tool_name":"'}
    tool_name=${s%%'"'*}
esac

if [ -n "$session_id" ] && [ -n "$tool_name" ]; then
    printf '%s\n' "$tool_name" > "/tmp/claude_pending_tool_${session_id}" 2>/dev/null
fi
exit 0
