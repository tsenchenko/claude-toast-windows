<#
.SYNOPSIS
    Installs Claude Code toast notifications for Windows.

.DESCRIPTION
    Sets up Claude Code hooks (Stop, Notification) to fire Windows toast
    notifications. Installs the BurntToast PowerShell module, copies hook
    scripts to ~/.claude/hooks/, registers a custom URL protocol for the
    "Open VS Code" toast button, and merges the hooks block into
    ~/.claude/settings.local.json without overwriting existing keys.

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

# 1. BurntToast module
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

# 2. Hook scripts
Write-Step "Installing hook scripts to ~/.claude/hooks/"
$hooksDir = Join-Path $HOME '.claude\hooks'
New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

$files = @('notify.ps1', 'focus-vscode.ps1')
foreach ($f in $files) {
    $url  = "$RepoBaseUrl/hooks/$f"
    $dest = Join-Path $hooksDir $f
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Ok "Downloaded $f"
}

# 3. claude-focus:// URL protocol (used by the "Open VS Code" toast button)
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

# 4. Toast banner duration (60s, max is 300)
Write-Step "Setting Windows toast duration to 60 seconds"
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility" -Name MessageDuration -Value 60 -Type DWord
Write-Ok "MessageDuration = 60"

# 5. Merge hooks into ~/.claude/settings.local.json (preserves existing keys)
Write-Step "Wiring hooks into ~/.claude/settings.local.json"
$settingsPath = Join-Path $HOME '.claude\settings.local.json'
$settings = $null
if (Test-Path $settingsPath) {
    $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
    if ($raw.Trim()) {
        try { $settings = $raw | ConvertFrom-Json } catch {
            throw "settings.local.json exists but is not valid JSON. Fix it manually before re-running."
        }
    }
}
if (-not $settings) {
    New-Item -Path (Split-Path -Parent $settingsPath) -ItemType Directory -Force | Out-Null
    $settings = New-Object PSCustomObject
}

$cmdNotify = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hooksDir\notify.ps1`" -Event Notification"
$cmdStop   = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hooksDir\notify.ps1`" -Event Stop"

$hooksBlock = [PSCustomObject]@{
    Stop = @(
        [PSCustomObject]@{
            matcher = ''
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $cmdStop } )
        }
    )
    Notification = @(
        [PSCustomObject]@{
            matcher = ''
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $cmdNotify } )
        }
    )
    # PreToolUse fires for in-chat questions (AskUserQuestion) and plan-mode approval
    # (ExitPlanMode). The Notification event does NOT cover these in current Claude Code,
    # so we hook PreToolUse and reuse the same notify.ps1 with -Event Notification.
    PreToolUse = @(
        [PSCustomObject]@{
            matcher = 'AskUserQuestion|ExitPlanMode'
            hooks   = @( [PSCustomObject]@{ type = 'command'; command = $cmdNotify } )
        }
    )
}

if ($settings.PSObject.Properties.Name -contains 'hooks') {
    $settings.hooks = $hooksBlock
} else {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooksBlock -Force
}

$json = $settings | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "Hooks added"

# 6. Test toast
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
