#!/bin/sh
# OSC 777 notifier for Claude Code hooks (Stop / Notification).
# Title may be prefixed with [sound:Name] and [alert] which the patched
# Cursor extension strips into opts.sound and a sender-bundle switch.
# Portable across Linux (remote hosts / HPC login nodes) and Darwin (local Mac).

title="${1:-Claude}"
body="${2:-}"

if [ ! -t 0 ]; then
    stdin=$(cat 2>/dev/null)
    if [ -n "$stdin" ]; then
        SEP=$(printf '\036')
        parsed=$(printf '%s' "$stdin" | jq -j --arg s "$SEP" '
            (.hook_event_name // ""), $s,
            (.message // "" | gsub("\n";" ")), $s,
            (.notification_type // ""), $s,
            (.last_assistant_message // "" | gsub("\n";" ")), $s,
            (.session_id // "")
        ' 2>/dev/null)
        IFS=$SEP read -r evt msg ntype last session_id <<EOF
$parsed
EOF

        # Pending tool from PreToolUse hook. Try both stat flavors so it
        # works on Linux (-c %Y) and Darwin (-f %m).
        pending_tool=""
        if [ -n "$session_id" ]; then
            pf="/tmp/claude_pending_tool_${session_id}"
            if [ -r "$pf" ]; then
                mtime=$(stat -c %Y "$pf" 2>/dev/null || stat -f %m "$pf" 2>/dev/null || echo 0)
                if [ $(($(date +%s) - mtime)) -lt 30 ]; then
                    read -r pending_tool < "$pf"
                fi
            fi
        fi

        case "$evt" in
            Stop)
                title="[sound:Tink]Turn done"
                body=$last
                ;;
            Notification)
                case "$ntype" in
                    permission_prompt)
                        case "$pending_tool" in
                            AskUserQuestion)
                                title="[sound:Glass][alert] Question"
                                body="Claude is asking you a question"
                                ;;
                            "")
                                title="[sound:Funk][alert] Permission needed"
                                body=${msg:-Claude needs your permission}
                                ;;
                            *)
                                title="[sound:Funk][alert] Permission: ${pending_tool}"
                                body=${msg:-Claude needs your permission}
                                ;;
                        esac
                        ;;
                    idle|waiting|idle_prompt)
                        title="[sound:Hero][alert] Waiting for input"
                        body=${msg:-Claude is waiting for your input}
                        ;;
                    "")
                        title="[sound:Pop]Attention"
                        body=${msg:-$body}
                        ;;
                    *)
                        title="[sound:Pop][alert] ${ntype}"
                        body=${msg:-$body}
                        ;;
                esac
                ;;
        esac

        if [ ${#body} -gt 140 ]; then
            body="$(printf '%s' "$body" | cut -c1-137)…"
        fi
    fi
fi

# Locate the user's pty:
#   Linux: /proc/$PPID/fd/* (sub-millisecond)
#   Darwin: ps fallback (~30 ms) — Mac has no /proc
target=""
if [ -d /proc ]; then
    for fd in 0 1 2; do
        link=$(readlink "/proc/$PPID/fd/$fd" 2>/dev/null) || continue
        case "$link" in
            /dev/pts/*|/dev/tty[0-9]*) target=$link; break ;;
        esac
    done
fi
if [ -z "$target" ]; then
    ttyname=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
    case "$ttyname" in
        ttys*|pts/*) target="/dev/$ttyname" ;;
    esac
fi

if [ -n "$target" ] && [ -w "$target" ]; then
    printf '\033]777;notify;%s;%s\033\\' "$title" "$body" > "$target"
else
    printf '\033]777;notify;%s;%s\033\\' "$title" "$body" >&2
fi
