# Read the project leaf-folder name written by notify.ps1
$ErrorActionPreference = 'Continue'

$logFile = Join-Path $env:TEMP 'claude-focus.log'
function Log { param([string]$Msg)
    try { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) $Msg" | Out-File -FilePath $logFile -Append -Encoding utf8 } catch { }
}

$targetFile = Join-Path $env:TEMP 'claude-focus-target.txt'
$target = ''
if (Test-Path $targetFile) {
    try { $target = (Get-Content -Path $targetFile -Raw -Encoding UTF8 -ErrorAction Stop).Trim() } catch { $target = '' }
}
Log "invoked. target='$target' args=$($args -join '|')"

# Win32 APIs for focus, plus the calls needed to work around the UIPI restriction
# that silently blocks SetForegroundWindow when we are launched from Action Center.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinUtil {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int dwProcessId);
}
"@

# All VS Code windows with a title (one Code.exe process == one VS Code window)
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

if (-not $match) {
    Log "no VS Code window found (candidates=$($candidates.Count))"
    return
}

$h = $match.MainWindowHandle
Log "match: pid=$($match.Id) title='$($match.MainWindowTitle)' hwnd=$h"

if ([WinUtil]::IsIconic($h)) {
    [WinUtil]::ShowWindow($h, 9) | Out-Null  # 9 = SW_RESTORE
}

# UIPI workaround: when invoked from Action Center, our process has no foreground
# rights, so SetForegroundWindow silently returns false. Attaching our input queue
# to the current foreground thread temporarily grants us those rights.
$thisTid = [WinUtil]::GetCurrentThreadId()
$fgHwnd = [WinUtil]::GetForegroundWindow()
$fgPid = 0
$fgTid = [WinUtil]::GetWindowThreadProcessId($fgHwnd, [ref]$fgPid)

$attached = $false
if ($fgTid -ne 0 -and $fgTid -ne $thisTid) {
    $attached = [WinUtil]::AttachThreadInput($thisTid, $fgTid, $true)
}

[WinUtil]::AllowSetForegroundWindow(-1) | Out-Null  # ASFW_ANY
[WinUtil]::BringWindowToTop($h) | Out-Null
$ok = [WinUtil]::SetForegroundWindow($h)

if ($attached) {
    [WinUtil]::AttachThreadInput($thisTid, $fgTid, $false) | Out-Null
}

# Last-resort fallback: tap Alt to clear Windows' foreground-lock, then retry.
$nowFg = [WinUtil]::GetForegroundWindow()
if ($nowFg -ne $h) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys('%') | Out-Null
        Start-Sleep -Milliseconds 30
        [WinUtil]::SetForegroundWindow($h) | Out-Null
    } catch { }
}

Log "SetForegroundWindow returned $ok; final fg=$([WinUtil]::GetForegroundWindow())"
