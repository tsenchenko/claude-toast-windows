<#
.SYNOPSIS
    Removes Claude Code toast notifications setup from the current Windows user.

.DESCRIPTION
    Reverses what install.ps1 did: removes the hook scripts, unregisters the
    claude-focus:// URL protocol, removes the hooks block from
    ~/.claude/settings.local.json (other keys are preserved), and resets
    the Windows MessageDuration setting.

    BurntToast is left installed (you may rely on it elsewhere). Remove it
    manually with: Uninstall-Module BurntToast
#>

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }

Write-Host ""
Write-Host "Claude Code Toast Notifications — uninstaller" -ForegroundColor Magenta
Write-Host ""

# 1. Hook scripts
Write-Step "Removing hook scripts"
$hooksDir = Join-Path $HOME '.claude\hooks'
foreach ($f in @('notify.ps1', 'focus-vscode.ps1')) {
    $p = Join-Path $hooksDir $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Ok "Deleted $f" }
}
# Drop the directory only if it's now empty
if ((Test-Path $hooksDir) -and -not (Get-ChildItem $hooksDir -Force)) {
    Remove-Item $hooksDir -Force
    Write-Ok "Removed empty hooks directory"
}

# 2. URL protocol
Write-Step "Unregistering claude-focus:// URL protocol"
$key = 'HKCU:\Software\Classes\claude-focus'
if (Test-Path $key) {
    Remove-Item -Path $key -Recurse -Force
    Write-Ok "Protocol removed"
}

# 3. MessageDuration — delete the override (Windows reverts to default 5s)
Write-Step "Resetting Windows toast duration"
$accPath = "HKCU:\Control Panel\Accessibility"
if (Test-Path $accPath) {
    if ((Get-ItemProperty -Path $accPath -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'MessageDuration') {
        Remove-ItemProperty -Path $accPath -Name MessageDuration -Force
        Write-Ok "MessageDuration override removed"
    }
}

# 4. Remove hooks block from settings.local.json (keep other keys)
Write-Step "Cleaning settings.local.json"
$settingsPath = Join-Path $HOME '.claude\settings.local.json'
if (Test-Path $settingsPath) {
    try {
        $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
        if ($raw.Trim()) {
            $settings = $raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'hooks') {
                $settings.PSObject.Properties.Remove('hooks')
                $json = $settings | ConvertTo-Json -Depth 12
                [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
                Write-Ok "hooks block removed"
            }
        }
    } catch {
        Write-Host "    Could not parse settings.local.json — leaving it alone." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Restart Claude Code so it stops calling the (now missing) hooks." -ForegroundColor Green
Write-Host ""
