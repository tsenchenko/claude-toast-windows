param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Stop', 'Notification')]
    [string]$Event
)

# Force stdin to UTF-8. Claude Code passes JSON as UTF-8, but PowerShell 5.1 reads
# stdin in the default OEM codepage and mangles non-ASCII characters in the message.
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$logFile = Join-Path $env:TEMP 'claude-toast.log'
function Log { param([string]$Msg)
    try { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) [$Event] $Msg" | Out-File -FilePath $logFile -Append -Encoding utf8 } catch { }
}

# Previously this script suppressed the Stop toast when VS Code was the foreground
# window ("you're looking at it, you don't need a toast"). In practice users live in
# VS Code all day, and the suppress branch fired on almost every turn — so they never
# saw a toast. Removed: toasts now always show.

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

if ([string]::IsNullOrEmpty($body)) { $body = ' ' }
# Toast body has length limits
if ($body.Length -gt 200) { $body = $body.Substring(0, 197) + '...' }

try {
    Import-Module BurntToast -ErrorAction Stop

    # -ActivationType Protocol is the default in BurntToast 1.1.0, but spell it out
    # so the chain doesn't break if a future version changes the default.
    $btnOpen = New-BTButton -Content 'Open VS Code' -Arguments 'claude-focus://activate' -ActivationType Protocol
    $btnDismiss = New-BTButton -Dismiss

    $textTitle = New-BTText -Text $title
    $textBody = New-BTText -Text $body
    $binding = New-BTBinding -Children $textTitle, $textBody
    $visual = New-BTVisual -BindingGeneric $binding
    $action = New-BTAction -Buttons $btnOpen, $btnDismiss

    # -Launch + -ActivationType Protocol on the content makes the ENTIRE toast
    # clickable, not just the button. Critical when the toast has slid into the
    # Action Center and only the title is visible, or the user mis-clicks past
    # the small button.
    $content = New-BTContent -Visual $visual -Actions $action `
        -Launch 'claude-focus://activate' -ActivationType Protocol

    Submit-BTNotification -Content $content
    Log "submitted: '$title' / '$body'"
} catch {
    # Never break the Claude Code session over a failed notification
    Log "FAILED: $($_.Exception.Message)"
    exit 0
}
