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

# Prefer the project embedded in the click URL (claude-focus://activate/<leaf>).
# The temp file above is a SHARED fallback: with concurrent sessions any of them
# may overwrite it, so the URL is the only per-toast-accurate source.
if ($args.Count -ge 1 -and "$($args[0])" -match '^claude-focus://activate/(.+)$') {
    try {
        $urlLeaf = [Uri]::UnescapeDataString($Matches[1].TrimEnd('/'))
        if ($urlLeaf) { $target = $urlLeaf }
    } catch { }
}
Log "invoked. target='$target' args=$($args -join '|')"

# Win32: enumerate ALL top-level windows (EnumWindows) + focus one, bypassing UIPI.
# Why EnumWindows instead of Get-Process: VS Code runs every window under a single
# process, and Get-Process surfaces only ONE window per process (MainWindowHandle =
# the currently-active one). So if the active window belonged to another project, the
# focus went there. EnumWindows sees every VS Code window, so we can pick the one
# whose folder matches this Claude Code session's project.
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
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
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    delegate bool EnumProc(IntPtr h, IntPtr p);
    public struct Win { public IntPtr Hwnd; public uint Pid; public string Title; }
    public static List<Win> GetWindows() {
        var list = new List<Win>();
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h)) return true;
            int len = GetWindowTextLength(h);
            if (len == 0) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(h, sb, sb.Capacity);
            uint pid; GetWindowThreadProcessId(h, out pid);
            list.Add(new Win { Hwnd = h, Pid = pid, Title = sb.ToString() });
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

# All visible VS Code windows (by title + ownership by a Code.exe process)
$codePids = @((Get-Process -Name Code -ErrorAction SilentlyContinue).Id)
$vscode = [WinUtil]::GetWindows() | Where-Object {
    $_.Title -like '*Visual Studio Code*' -and ($codePids -contains [int]$_.Pid)
}

$match = $null
if ($target) {
    # 1) Exact title-segment match: "file - FOLDER - Visual Studio Code". VS Code joins
    #    title parts with ' - ' and the project leaf folder is one of them. Requiring an
    #    exact segment (not a substring) avoids false hits like "app" matching "app-v2".
    foreach ($w in $vscode) {
        if (($w.Title -split ' - ') -contains $target) { $match = $w; break }
    }
    # 2) Fallback to substring (custom separator / non-standard title format)
    if (-not $match) {
        $match = $vscode | Where-Object { $_.Title -like "*$target*" } | Select-Object -First 1
    }
}
# 3) Last resort — the project window is closed: bring up any VS Code window
if (-not $match) {
    $match = $vscode | Select-Object -First 1
    if ($match) { Log "target window not found; falling back to first VS Code window" }
}

if (-not $match) {
    Log "no VS Code window found (candidates=$($vscode.Count))"
    return
}

$h = $match.Hwnd
Log "match: pid=$($match.Pid) title='$($match.Title)' hwnd=$h (of $($vscode.Count) VS Code windows)"

# Restore if minimized
if ([WinUtil]::IsIconic($h)) {
    [WinUtil]::ShowWindow($h, 9) | Out-Null  # 9 = SW_RESTORE
}

# Bypass UIPI: attach our thread's input queue to the foreground window's thread.
# While attached we effectively "have" foreground rights and SetForegroundWindow works.
$thisTid = [WinUtil]::GetCurrentThreadId()
$fgHwnd = [WinUtil]::GetForegroundWindow()
$fgPid = 0
$fgTid = [WinUtil]::GetWindowThreadProcessId($fgHwnd, [ref]$fgPid)

$attached = $false
if ($fgTid -ne 0 -and $fgTid -ne $thisTid) {
    $attached = [WinUtil]::AttachThreadInput($thisTid, $fgTid, $true)
}

# Try several methods in turn — one of them will take
[WinUtil]::AllowSetForegroundWindow(-1) | Out-Null  # ASFW_ANY
[WinUtil]::BringWindowToTop($h) | Out-Null
$ok = [WinUtil]::SetForegroundWindow($h)

if ($attached) {
    [WinUtil]::AttachThreadInput($thisTid, $fgTid, $false) | Out-Null
}

# Fallback trick: if still not focused, tap Alt and retry.
# Alt releases the Windows foreground-lock.
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
