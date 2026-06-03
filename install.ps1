<#
.SYNOPSIS
    Installs Claude Code toast notifications for Windows.

.DESCRIPTION
    Sets up Claude Code hooks (Stop, Notification, PreToolUse) to fire Windows
    toast notifications. Installs the BurntToast PowerShell module, copies the
    hook scripts to ~/.claude/hooks/, registers a custom URL protocol for the
    "Open VS Code" toast button, and merges the hooks block into
    ~/.claude/settings.json without overwriting existing keys.

    Hook commands are written using the PORTABLE form $HOME/.claude/hooks/notify.sh
    so the same settings.json works across machines (e.g. a Mac/Windows pair that
    shares settings.json via Dropbox / Google Drive / Syncthing). Claude Code on
    Windows dispatches hook commands through Git Bash, which is why Git for
    Windows is a requirement.

.PARAMETER RepoBaseUrl
    Override the source location for hook scripts. Defaults to the upstream
    repo on GitHub. Useful if you fork or self-host.

.EXAMPLE
    irm https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main/install.ps1 | iex
#>

param(
    [string]$RepoBaseUrl = 'https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main'
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Claude Code Toast Notifications for Windows" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

if ($env:OS -ne 'Windows_NT') {
    throw "This installer is for Windows only."
}

# 1. Git for Windows (Claude Code dispatches hook commands through Git Bash on Windows)
Write-Step "Checking Git for Windows / Git Bash"
$gitBashCandidates = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files\Git\usr\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe'
)
$gitBash = $gitBashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $gitBash) {
    Write-Warn "Git Bash not found. Install Git for Windows: https://git-scm.com/download/win"
    Write-Warn "Then re-run this installer."
    throw "Git for Windows is required (Claude Code uses bash to run hooks on Windows)."
}
Write-Ok "Git Bash found at $gitBash"

# 2. BurntToast module
Write-Step "Checking BurntToast PowerShell module"
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Warn "Not found. Installing into CurrentUser scope (no admin needed)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop } catch { }
    Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
}
Write-Ok "BurntToast ready"

# 3. Hook scripts
Write-Step "Installing hook scripts to ~/.claude/hooks/"
$hooksDir = Join-Path $HOME '.claude\hooks'
New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

$files = @('notify.sh', 'notify.ps1', 'focus-vscode.ps1')
foreach ($f in $files) {
    $url  = "$RepoBaseUrl/hooks/$f"
    $dest = Join-Path $hooksDir $f
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Ok "Downloaded $f"
}

# Normalize notify.sh: strip BOM, convert CRLF -> LF (Git Bash chokes otherwise)
$shPath = Join-Path $hooksDir 'notify.sh'
$shText = [System.IO.File]::ReadAllText($shPath, [System.Text.UTF8Encoding]::new($true))
if ($shText.Length -gt 0 -and [int]$shText[0] -eq 0xFEFF) { $shText = $shText.Substring(1) }
$shText = $shText -replace "`r`n","`n" -replace "`r","`n"
[System.IO.File]::WriteAllText($shPath, $shText, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "Normalized notify.sh (LF, no BOM)"

# 4. claude-focus:// URL protocol (used by the "Open VS Code" toast button)
Write-Step "Registering claude-focus:// URL protocol"
$key = 'HKCU:\Software\Classes\claude-focus'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name '(default)'    -Value 'URL:Claude Focus' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'URL Protocol' -Value ''                 -PropertyType String -Force | Out-Null
$cmdKey = "$key\shell\open\command"
New-Item -Path $cmdKey -Force | Out-Null
$focusCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hooksDir\focus-vscode.ps1`" `"%1`""
New-ItemProperty -Path $cmdKey -Name '(default)' -Value $focusCmd -PropertyType String -Force | Out-Null
Write-Ok "Protocol registered"

# 5. Toast banner duration (60s, max is 300)
Write-Step "Setting Windows toast duration to 60 seconds"
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility" -Name MessageDuration -Value 60 -Type DWord
Write-Ok "MessageDuration = 60"

# 6. Merge hooks into ~/.claude/settings.json (preserves existing keys).
# We use portable $HOME paths so the same settings.json can be shared across
# Mac/Windows. A matching notify.sh must live in ~/.claude/hooks/ on each OS.
Write-Step "Wiring hooks into ~/.claude/settings.json"
$settingsPath = Join-Path $HOME '.claude\settings.json'
$settings = $null
if (Test-Path $settingsPath) {
    $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
    if ($raw.Trim()) {
        try { $settings = $raw | ConvertFrom-Json } catch {
            throw "settings.json exists but is not valid JSON. Fix it manually before re-running."
        }
    }
}
if (-not $settings) {
    New-Item -Path (Split-Path -Parent $settingsPath) -ItemType Directory -Force | Out-Null
    $settings = New-Object PSCustomObject
}

$notifyCmd = '"$HOME/.claude/hooks/notify.sh" Notification'
$stopCmd   = '"$HOME/.claude/hooks/notify.sh" Stop'

$hooksBlock = [PSCustomObject]@{
    Stop = @(
        [PSCustomObject]@{
            matcher = ''
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $stopCmd } )
        }
    )
    Notification = @(
        [PSCustomObject]@{
            matcher = ''
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $notifyCmd } )
        }
    )
    # PreToolUse fires for in-chat questions (AskUserQuestion) and plan-mode approval
    # (ExitPlanMode). The Notification event does NOT cover these in current Claude Code,
    # so we hook PreToolUse and dispatch the same notify.sh with the Notification event.
    PreToolUse = @(
        [PSCustomObject]@{
            matcher = 'AskUserQuestion|ExitPlanMode'
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $notifyCmd } )
        }
    )
}

if ($settings.PSObject.Properties.Name -contains 'hooks') {
    # Merge: preserve any existing event keys we don't manage (e.g. SessionStart).
    foreach ($k in 'Stop','Notification','PreToolUse') {
        if ($settings.hooks.PSObject.Properties.Name -contains $k) {
            $settings.hooks.$k = $hooksBlock.$k
        } else {
            $settings.hooks | Add-Member -NotePropertyName $k -NotePropertyValue $hooksBlock.$k -Force
        }
    }
} else {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooksBlock -Force
}

$json = $settings | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "Hooks added"

# 7. Test toast
Write-Step "Sending test toast"
try {
    Import-Module BurntToast -ErrorAction Stop
    New-BurntToastNotification -Text 'Claude Code', 'Notifications installed successfully.'
    Write-Ok "Test toast sent"
} catch {
    Write-Warn "Test toast failed: $_"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Restart any open Claude Code session so it picks up the new hooks." -ForegroundColor Green
Write-Host ""
