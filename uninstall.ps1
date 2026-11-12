<#
.SYNOPSIS
    Removes Claude Code toast notifications setup from the current Windows user.

.DESCRIPTION
    Reverses what install.ps1 did: removes the hook scripts, unregisters the
    claude-focus:// URL protocol, removes the Stop/Notification/PermissionRequest/PreToolUse
    entries from ~/.claude/settings.json (other event keys like SessionStart
    are preserved), and resets the Windows MessageDuration setting.

    BurntToast is left installed (you may rely on it elsewhere). Remove it
    manually with: Uninstall-Module BurntToast
#>

$ErrorActionPreference = 'Continue'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }

Write-Host ""
Write-Host "Claude Code Toast Notifications - uninstaller" -ForegroundColor Magenta
Write-Host ""

# 1. Hook scripts
Write-Step "Removing hook scripts"
$hooksDir = Join-Path $HOME '.claude\hooks'
foreach ($f in @('notify.sh', 'notify.ps1', 'focus-vscode.ps1')) {
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

# 3. MessageDuration - delete the override (Windows reverts to default 5s)
Write-Step "Resetting Windows toast duration"
$accPath = "HKCU:\Control Panel\Accessibility"
if (Test-Path $accPath) {
    if ((Get-ItemProperty -Path $accPath -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'MessageDuration') {
        Remove-ItemProperty -Path $accPath -Name MessageDuration -Force
        Write-Ok "MessageDuration override removed"
    }
}

# 4. Remove only the events we own from settings.json. We do NOT delete the whole
# hooks block - the user may have other event types in there (e.g. SessionStart).
Write-Step "Cleaning settings.json"
$settingsPath = Join-Path $HOME '.claude\settings.json'
if (Test-Path $settingsPath) {
    try {
        $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
        if ($raw.Trim()) {
            $settings = $raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'hooks') {
                # --- begin hook removal (same helpers as install.ps1) ---
                # Remove only OUR hook entries (notify.sh / legacy notify.ps1),
                # never whole events or groups: other commands on the same event
                # or in the same group (a cost gate, a second Stop hook) stay.
                function Test-OurHook { param($h)
                    $h -and ([string]$h.command -match '[\\/]\.claude[\\/]hooks[\\/]notify\.(sh|ps1)')
                }
                function Remove-OurHooks { param($groups)
                    $out = @()
                    foreach ($g in @($groups)) {
                        if ($g -and $g.hooks -and @(@($g.hooks) | Where-Object { Test-OurHook $_ }).Count -gt 0) {
                            $rest = @(@($g.hooks) | Where-Object { -not (Test-OurHook $_) })
                            if ($rest.Count -gt 0) { $g.hooks = $rest; $out += $g }
                        } elseif ($null -ne $g) {
                            $out += $g
                        }
                    }
                    return ,$out
                }
                $removed = @()
                foreach ($k in 'Stop','Notification','PermissionRequest','PreToolUse','PostToolUse') {
                    if ($settings.hooks.PSObject.Properties.Name -contains $k) {
                        $before = $settings.hooks.$k | ConvertTo-Json -Depth 12 -Compress
                        $kept = Remove-OurHooks $settings.hooks.$k
                        if (($kept | ConvertTo-Json -Depth 12 -Compress) -ne $before) { $removed += $k }
                        if ($kept.Count -gt 0) { $settings.hooks.$k = $kept }
                        else { $settings.hooks.PSObject.Properties.Remove($k) }
                    }
                }
                # --- end hook removal ---
                # Drop the hooks block entirely if nothing is left in it
                if (-not $settings.hooks.PSObject.Properties.Name) {
                    $settings.PSObject.Properties.Remove('hooks')
                }
                $json = $settings | ConvertTo-Json -Depth 12
                [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
                if ($removed.Count -gt 0) {
                    Write-Ok ("Removed events: " + ($removed -join ', '))
                } else {
                    Write-Ok "No matching event entries found (already clean)"
                }
            }
        }
    } catch {
        Write-Host "    Could not parse settings.json - leaving it alone." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Restart Claude Code so it stops calling the (now missing) hooks." -ForegroundColor Green
Write-Host ""
