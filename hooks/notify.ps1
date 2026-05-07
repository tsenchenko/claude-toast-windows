param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Stop', 'Notification')]
    [string]$Event
)

# Force stdin to UTF-8. Claude Code passes JSON as UTF-8, but PowerShell 5.1 reads
# stdin in the default OEM codepage and mangles non-ASCII characters in the message.
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Suppress only the Stop toast when VS Code is foreground — turn-complete is low-priority.
# Notification toasts (questions, permission requests) always show: at the moment the hook
# fires VS Code is usually still focused (the user just sent a prompt), and missing a
# question is far worse than a redundant toast.
if ($Event -eq 'Stop') {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FgUtil {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@ -ErrorAction Stop

        $hwnd = [FgUtil]::GetForegroundWindow()
        $targetPid = 0
        [FgUtil]::GetWindowThreadProcessId($hwnd, [ref]$targetPid) | Out-Null
        if ($targetPid -ne 0) {
            $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'Code') {
                exit 0
            }
        }
    } catch { }
}

# Read event context (JSON) from stdin
$stdin = [Console]::In.ReadToEnd()
$data = $null
if ($stdin) {
    try { $data = $stdin | ConvertFrom-Json } catch { $data = $null }
}

# Persist project leaf folder so focus-vscode.ps1 can pick the right window later
if ($data -and $data.cwd) {
    try {
        $leaf = Split-Path -Leaf ([string]$data.cwd)
        if ($leaf) {
            $leaf | Out-File -FilePath (Join-Path $env:TEMP 'claude-focus-target.txt') -Encoding utf8 -Force
        }
    } catch { }
}

if ($Event -eq 'Notification') {
    $title = 'Claude Code: needs your attention'
    if ($data -and $data.message) {
        # Plain Notification event (permission_prompt, idle_prompt, etc.)
        $body = [string]$data.message
    } elseif ($data -and $data.tool_input -and $data.tool_input.questions -and $data.tool_input.questions.Count -gt 0) {
        # PreToolUse on AskUserQuestion — surface the first question's text
        $body = [string]$data.tool_input.questions[0].question
    } elseif ($data -and $data.tool_input -and $data.tool_input.plan) {
        # PreToolUse on ExitPlanMode — Claude is asking you to approve a plan
        $body = 'Claude is proposing a plan — your approval is needed'
    } else {
        $body = 'Waiting for your input in VS Code'
    }
} else {
    $title = 'Claude Code: turn complete'
    $body = 'Ready for your next prompt'
}

# Toast body has length limits
if ($body.Length -gt 200) {
    $body = $body.Substring(0, 197) + '...'
}

try {
    Import-Module BurntToast -ErrorAction Stop

    $btnOpen = New-BTButton -Content 'Open VS Code' -Arguments 'claude-focus://activate'
    $btnDismiss = New-BTButton -Dismiss

    $textTitle = New-BTText -Text $title
    $textBody = New-BTText -Text $body
    $binding = New-BTBinding -Children $textTitle, $textBody
    $visual = New-BTVisual -BindingGeneric $binding
    $action = New-BTAction -Buttons $btnOpen, $btnDismiss
    $content = New-BTContent -Visual $visual -Actions $action

    Submit-BTNotification -Content $content
} catch {
    # Never break the Claude Code session over a failed notification
    exit 0
}
