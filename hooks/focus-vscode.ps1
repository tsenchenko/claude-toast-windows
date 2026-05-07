# Read the project leaf-folder name written by notify.ps1
$targetFile = Join-Path $env:TEMP 'claude-focus-target.txt'
$target = ''
if (Test-Path $targetFile) {
    try { $target = (Get-Content -Path $targetFile -Raw -Encoding UTF8 -ErrorAction Stop).Trim() } catch { $target = '' }
}

# Win32 API to bring a window to the foreground
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinUtil {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SwitchToThisWindow(IntPtr hWnd, bool fAltTab);
}
"@

# All VS Code windows with a title
$candidates = Get-Process -Name Code -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle }

# Prefer the window whose title contains the project leaf folder
$match = $null
if ($target) {
    $match = $candidates | Where-Object { $_.MainWindowTitle -like "*$target*" } | Select-Object -First 1
}
# Fallback: any VS Code window
if (-not $match) {
    $match = $candidates | Select-Object -First 1
}

if ($match) {
    $h = $match.MainWindowHandle
    if ([WinUtil]::IsIconic($h)) {
        [WinUtil]::ShowWindow($h, 9) | Out-Null  # 9 = SW_RESTORE
    }
    [WinUtil]::SwitchToThisWindow($h, $true) | Out-Null
    [WinUtil]::SetForegroundWindow($h) | Out-Null
}
