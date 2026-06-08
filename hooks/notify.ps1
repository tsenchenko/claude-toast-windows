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
    'PreToolUse' {
        # PreToolUse прилетает на КУЧУ событий (Read/Edit/Write при каждом действии).
        # Тостов хотим ТОЛЬКО когда Claude реально требует от пользователя реакции:
        #  - AskUserQuestion: внутренний вопрос
        #  - ExitPlanMode: апрув плана
        #  - permission-prompt: tool ждёт одобрения (Bash/PowerShell/любой, не в allowlist)
        # Всё остальное (auto-approved Read/Edit/Write) — тихо exit.
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
            # Permission-prompt детектируем по полю permission_decision == 'ask'
            # (новое API Claude Code; точное имя может отличаться, поэтому пробуем варианты)
            $needsPermission = $false
            if ($data) {
                foreach ($prop in 'permission_decision','permissionDecision','permission_required','permissionRequired') {
                    if ($data.PSObject.Properties.Name -contains $prop) {
                        $v = [string]$data.$prop
                        if ($v -eq 'ask' -or $v -eq 'true' -or $v -eq 'True') { $needsPermission = $true; break }
                    }
                }
            }
            if ($needsPermission) {
                $title = "Claude Code — нужно разрешение ($tool)"
                # Покажем команду/описание (то что Claude хочет выполнить)
                $desc = ''
                if ($data.tool_input) {
                    if ($data.tool_input.description) { $desc = [string]$data.tool_input.description }
                    elseif ($data.tool_input.command) { $desc = [string]$data.tool_input.command }
                }
                $body = if ($desc) { $desc } else { "Tool: $tool" }
            } else {
                # Авто-разрешённое действие — тост не нужен
                Log "skipped: tool=$tool (auto-approved, no toast)"
                exit 0
            }
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
