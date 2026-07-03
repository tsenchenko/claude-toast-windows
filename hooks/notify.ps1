param(
    [Parameter(Mandatory = $true)]
    [string]$Event
)

# Read stdin as UTF-8 (Claude Code sends UTF-8 JSON; without this PS 5.1 mangles Cyrillic)
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$logFile = Join-Path $env:TEMP 'claude-toast.log'
function Log { param([string]$Msg)
    try { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) [$Event] $Msg" | Out-File -FilePath $logFile -Append -Encoding utf8 } catch { }
}

# Read the event JSON from stdin
$stdin = [Console]::In.ReadToEnd()
$data = $null
if ($stdin) {
    try { $data = $stdin | ConvertFrom-Json } catch { $data = $null }
}

# Project leaf name: goes into the toast title, into the click URL, and into
# %TEMP% as a fallback for focus-vscode.ps1 window lookup.
$leaf = ''
if ($data -and $data.cwd) {
    try {
        $leaf = Split-Path -Leaf ([string]$data.cwd)
        if ($leaf) {
            $leaf | Out-File -FilePath (Join-Path $env:TEMP 'claude-focus-target.txt') -Encoding utf8 -Force
        }
    } catch { }
}

# Dump the last JSON of each event type — to inspect the schema and narrow
# filtering when needed. Does not grow over time (Force overwrites).
if ($stdin) {
    try { $stdin | Out-File -FilePath (Join-Path $env:TEMP "claude-event-$Event-last.json") -Encoding utf8 -Force } catch { }
}

# Suppress the toast if the foreground window is THIS project's VS Code window —
# the user is looking at it, so the answer/question/dialog is already on screen.
# In other VS Code windows, the browser, etc. the toast IS shown. Matching is the
# same as in focus-vscode.ps1: the project folder name is a separate segment of
# the "file - FOLDER - Visual Studio Code" title. NO substring matching — a
# redundant toast beats a missed one. A match requires both the 'Code' process
# and the exact title segment.
# Debug/"always show" override: $env:CLAUDE_TOAST_ALWAYS=1
if ($leaf -and -not $env:CLAUDE_TOAST_ALWAYS) {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FgWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
}
"@ -ErrorAction Stop

        $fg = [FgWin]::GetForegroundWindow()
        $fgPid = 0
        [FgWin]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null
        $proc = if ($fgPid -ne 0) { Get-Process -Id $fgPid -ErrorAction SilentlyContinue } else { $null }

        if ($proc -and $proc.ProcessName -eq 'Code') {
            $len = [FgWin]::GetWindowTextLength($fg)
            $sb = New-Object System.Text.StringBuilder ($len + 1)
            [FgWin]::GetWindowText($fg, $sb, $sb.Capacity) | Out-Null
            $fgTitle = $sb.ToString()

            if (($fgTitle -split ' - ') -contains $leaf) {
                Log "suppressed: project window '$leaf' is foreground (title='$fgTitle')"
                exit 0
            }
        }
    } catch { Log "foreground check failed: $($_.Exception.Message)" }
}

# Tag every toast with its project. With several concurrent sessions an
# unlabeled Stop toast from a background project looks like the ACTIVE
# session toasting mid-work for no reason.
$projTag = if ($leaf) { " [$leaf]" } else { '' }

# Decide what to show — title, body, and whether to show anything at all.
# Toast strings are user-facing UI and stay in Russian by design.
$title = $null
$body  = $null

switch ($Event) {
    'Stop' {
        $title = "Claude Code$projTag — закончил ход"
        $body  = 'Готов к следующей задаче'
    }
    'Notification' {
        $title = "Claude Code$projTag — нужно твоё внимание"
        if ($data -and $data.message) {
            $body = [string]$data.message
        } else {
            $body = 'Жду твоего ответа в VS Code'
        }
    }
    'PermissionRequest' {
        # Claude Code's dedicated event: a "Do you want to proceed?" dialog appeared
        # (Bash/PowerShell/MCP/any tool not on the allowlist). This is exactly what
        # the user sees on screen. Historically no toast reached here: the project
        # listened only to Notification (which the VS Code extension does not send
        # for permission prompts) and to a dead permission-field check in PreToolUse
        # (no such field exists in that payload).
        $tool = if ($data) { [string]$data.tool_name } else { '' }
        # AskUserQuestion/ExitPlanMode also arrive as PermissionRequest, but the
        # PreToolUse handler already toasts them (with the actual question/plan
        # text) 1-2s earlier — skip the duplicate.
        if ($tool -eq 'AskUserQuestion' -or $tool -eq 'ExitPlanMode') {
            Log "skipped: tool=$tool (PreToolUse already toasts it)"
            exit 0
        }
        $title = if ($tool) { "Claude Code$projTag — нужно разрешение ($tool)" } else { "Claude Code$projTag — нужно разрешение" }
        # Show the command/description/path — whatever Claude wants to run
        $desc = ''
        if ($data -and $data.tool_input) {
            if ($data.tool_input.description) { $desc = [string]$data.tool_input.description }
            elseif ($data.tool_input.command) { $desc = [string]$data.tool_input.command }
            elseif ($data.tool_input.file_path) { $desc = [string]$data.tool_input.file_path }
        }
        $body = if ($desc) { $desc } else { "Tool: $tool" }
    }
    'PreToolUse' {
        # PreToolUse fires for a TON of events. A toast is only needed for the two
        # tools the user must react to in chat: AskUserQuestion (in-chat question)
        # and ExitPlanMode (plan approval). Permission prompts themselves are
        # handled by PermissionRequest (which skips these two as duplicates).
        $tool = if ($data) { [string]$data.tool_name } else { '' }

        if ($tool -eq 'AskUserQuestion' -and $data.tool_input.questions -and $data.tool_input.questions.Count -gt 0) {
            $title = "Claude Code$projTag — вопрос"
            $body  = [string]$data.tool_input.questions[0].question
        }
        elseif ($tool -eq 'ExitPlanMode') {
            $title = "Claude Code$projTag — нужен апрув плана"
            $body  = 'Claude предлагает план — твоё подтверждение'
        }
        else {
            # Auto-approved action (Read/Edit/Write etc.) — no toast needed
            Log "skipped: tool=$tool (no toast for this PreToolUse)"
            exit 0
        }
    }
    'PostToolUse' {
        # No toast for tool completion — that's noise
        Log "skipped: PostToolUse (no toast for tool completion)"
        exit 0
    }
    default {
        Log "skipped: unknown event '$Event' (no toast handler)"
        exit 0
    }
}

if ([string]::IsNullOrEmpty($body)) { $body = ' ' }
if ($body.Length -gt 200) { $body = $body.Substring(0, 197) + '...' }

# Click target: embed the project in the URL so focus-vscode.ps1 focuses THIS
# toast's project. The shared %TEMP% target file races between concurrent
# sessions (kept only as a fallback for URLs without a leaf).
$launchUrl = 'claude-focus://activate'
if ($leaf) { $launchUrl = "claude-focus://activate/$([Uri]::EscapeDataString($leaf))" }

try {
    Import-Module BurntToast -ErrorAction Stop

    $btnOpen = New-BTButton -Content 'Открыть VS Code' -Arguments $launchUrl -ActivationType Protocol
    $btnDismiss = New-BTButton -Dismiss

    $textTitle = New-BTText -Text $title
    $textBody  = New-BTText -Text $body
    $binding = New-BTBinding -Children $textTitle, $textBody
    $visual  = New-BTVisual -BindingGeneric $binding
    $action  = New-BTAction -Buttons $btnOpen, $btnDismiss

    # -Launch + -ActivationType Protocol => the whole toast is clickable, not just the button
    $content = New-BTContent -Visual $visual -Actions $action `
        -Launch $launchUrl -ActivationType Protocol

    Submit-BTNotification -Content $content
    Log "submitted: '$title' / '$body'"
} catch {
    Log "FAILED: $($_.Exception.Message)"
    exit 0
}
