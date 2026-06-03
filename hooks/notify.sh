#!/usr/bin/env bash
# Windows-side bash wrapper for the Claude Code toast hook.
#
# Why bash here on Windows? Claude Code dispatches hook commands as shell
# strings, and we want the SAME hook command in the shared (synced)
# ~/.claude/settings.json on both Mac and Windows: "$HOME/.claude/hooks/notify.sh".
# Mac runs it natively; Windows runs it via Git Bash. This script then forwards
# the event to PowerShell + BurntToast (the actual toast renderer on Windows).
#
# Interface (same on Mac and Windows):
#   arg1   = event name ("Stop" or "Notification")
#   stdin  = event JSON from Claude Code (fields: message, tool_input.questions,
#            tool_input.plan, cwd, ...)

set -u

EVENT="${1:-Stop}"
JSON="$(cat)"

# Diagnostic log: prove the bash hook actually got invoked.
LOG_FILE="${TEMP:-/tmp}/claude-toast-sh.log"
# Normalize Windows-style %TEMP% (C:\Users\...) to Git Bash form so tee works.
if command -v cygpath >/dev/null 2>&1 && [[ "$LOG_FILE" == *:* ]]; then
    LOG_FILE="$(cygpath -u "$LOG_FILE")"
fi
printf '%s [%s] notify.sh invoked, json_len=%d\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$EVENT" "${#JSON}" >> "$LOG_FILE" 2>/dev/null

# Resolve Windows path to notify.ps1 (PowerShell needs a Windows-style path for -File)
PS_SCRIPT_UNIX="$HOME/.claude/hooks/notify.ps1"
if command -v cygpath >/dev/null 2>&1; then
    PS_SCRIPT_WIN="$(cygpath -w "$PS_SCRIPT_UNIX")"
else
    PS_SCRIPT_WIN="$PS_SCRIPT_UNIX"
fi

if [ ! -f "$PS_SCRIPT_UNIX" ]; then
    printf '%s [%s] ERROR: %s not found\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$EVENT" "$PS_SCRIPT_UNIX" >> "$LOG_FILE"
    exit 0
fi

# Forward to PowerShell. JSON is piped to stdin; notify.ps1 reads it the same
# way Claude Code originally piped it to PowerShell directly.
printf '%s' "$JSON" | powershell.exe \
    -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
    -File "$PS_SCRIPT_WIN" -Event "$EVENT" \
    >> "$LOG_FILE" 2>&1

printf '%s [%s] notify.sh done (ps_exit=%d)\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$EVENT" "${PIPESTATUS[1]}" >> "$LOG_FILE"

exit 0
