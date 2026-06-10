param(
    [Parameter(Mandatory = $true)]
    [string]$Event
)

# stdin как UTF-8 (Claude Code шлёт JSON в UTF-8, PS 5.1 без этого ломает кириллицу)
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$logFile = Join-Path $env:TEMP 'claude-toast.log'
function Log { param([string]$Msg)
    try { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) [$Event] $Msg" | Out-File -FilePath $logFile -Append -Encoding utf8 } catch { }
}

# Читаем JSON со stdin
$stdin = [Console]::In.ReadToEnd()
$data = $null
if ($stdin) {
    try { $data = $stdin | ConvertFrom-Json } catch { $data = $null }
}

# Имя проекта в %TEMP% — focus-vscode.ps1 ищет по нему окно
if ($data -and $data.cwd) {
    try {
        $leaf = Split-Path -Leaf ([string]$data.cwd)
        if ($leaf) {
            $leaf | Out-File -FilePath (Join-Path $env:TEMP 'claude-focus-target.txt') -Encoding utf8 -Force
        }
    } catch { }
}

# Дамп последнего JSON каждого типа события — чтобы при необходимости подсмотреть
# структуру и сузить фильтрацию. Не растёт со временем (Force перезаписывает).
if ($stdin) {
    try { $stdin | Out-File -FilePath (Join-Path $env:TEMP "claude-event-$Event-last.json") -Encoding utf8 -Force } catch { }
}

# Решаем, что показывать — заголовок, тело, и нужно ли показывать вообще.
$title = $null
$body  = $null

switch ($Event) {
    'Stop' {
        $title = 'Claude Code — закончил ход'
        $body  = 'Готов к следующей задаче'
    }
    'Notification' {
        $title = 'Claude Code — нужно твоё внимание'
        if ($data -and $data.message) {
            $body = [string]$data.message
        } else {
            $body = 'Жду твоего ответа в VS Code'
        }
    }
    'PermissionRequest' {
        # Выделенное событие Claude Code: появился диалог "Do you want to proceed?"
        # (Bash/PowerShell/MCP/любой tool не из allowlist). Это ровно то, что
        # пользователь видит на экране. Раньше сюда тост не доходил: проект слушал
        # только Notification (его VS Code-расширение для permission-промптов не шлёт)
        # и мёртвый детект permission-поля в PreToolUse (такого поля на входе нет).
        $tool = if ($data) { [string]$data.tool_name } else { '' }
        $title = if ($tool) { "Claude Code — нужно разрешение ($tool)" } else { 'Claude Code — нужно разрешение' }
        # Покажем команду/описание/путь — то, что Claude хочет выполнить
        $desc = ''
        if ($data -and $data.tool_input) {
            if ($data.tool_input.description) { $desc = [string]$data.tool_input.description }
            elseif ($data.tool_input.command) { $desc = [string]$data.tool_input.command }
            elseif ($data.tool_input.file_path) { $desc = [string]$data.tool_input.file_path }
        }
        $body = if ($desc) { $desc } else { "Tool: $tool" }
    }
    'PreToolUse' {
        # PreToolUse прилетает на КУЧУ событий. Тост нужен только для двух tool'ов,
        # которые НЕ идут через PermissionRequest: AskUserQuestion (вопрос в чате) и
        # ExitPlanMode (апрув плана). Сами permission-промпты ловит PermissionRequest.
        $tool = if ($data) { [string]$data.tool_name } else { '' }

        if ($tool -eq 'AskUserQuestion' -and $data.tool_input.questions -and $data.tool_input.questions.Count -gt 0) {
            $title = 'Claude Code — вопрос'
            $body  = [string]$data.tool_input.questions[0].question
        }
        elseif ($tool -eq 'ExitPlanMode') {
            $title = 'Claude Code — нужен апрув плана'
            $body  = 'Claude предлагает план — твоё подтверждение'
        }
        else {
            # Авто-разрешённое действие (Read/Edit/Write и т.п.) — тост не нужен
            Log "skipped: tool=$tool (no toast for this PreToolUse)"
            exit 0
        }
    }
    'PostToolUse' {
        # На завершение тула тост не нужен — это шум
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

try {
    Import-Module BurntToast -ErrorAction Stop

    $btnOpen = New-BTButton -Content 'Открыть VS Code' -Arguments 'claude-focus://activate' -ActivationType Protocol
    $btnDismiss = New-BTButton -Dismiss

    $textTitle = New-BTText -Text $title
    $textBody  = New-BTText -Text $body
    $binding = New-BTBinding -Children $textTitle, $textBody
    $visual  = New-BTVisual -BindingGeneric $binding
    $action  = New-BTAction -Buttons $btnOpen, $btnDismiss

    # -Launch + -ActivationType Protocol => кликабелен весь тост, не только кнопка
    $content = New-BTContent -Visual $visual -Actions $action `
        -Launch 'claude-focus://activate' -ActivationType Protocol

    Submit-BTNotification -Content $content
    Log "submitted: '$title' / '$body'"
} catch {
    Log "FAILED: $($_.Exception.Message)"
    exit 0
}
