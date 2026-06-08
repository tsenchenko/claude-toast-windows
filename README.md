# claude-toast-windows

> Windows toast notifications for Claude Code in VS Code — know when Claude finishes a turn or needs your attention, even when you're in another window.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](#requirements)

## The problem

Claude Code in the VS Code extension on Windows has no native desktop notifications. There's a built-in setting (`preferredNotifChannel`) but it only works in terminal emulators like iTerm2, Ghostty, or Kitty — not in the VS Code extension.

Switch to another window while Claude is running and you won't know when it:

- finishes a turn and is waiting for your next prompt
- asks a question or requests permission to run a tool

## The solution

This repo wires Claude Code's built-in **hooks** (`Stop` and `Notification` events) into Windows toast notifications. You get a toast in the corner of the screen the moment Claude returns control to you. The Notification toast even shows the actual question text so you know what's pending without switching apps.

Click "Open VS Code" on the toast to bring the right VS Code window forward (matched by project folder).

## Features

- Toast on `Stop` event (Claude finishes its turn)
- Toast on `Notification` event (permission prompts, idle prompts), showing the actual prompt text
- Toast on `PreToolUse` for `AskUserQuestion` and `ExitPlanMode` — covers in-chat questions and plan-mode approval, which Claude Code does **not** dispatch through the `Notification` event
- The question text is surfaced in the toast body, so you know what's being asked without switching apps
- "Open VS Code" button focuses the correct window — even if you have multiple VS Code windows open, it picks the one running this Claude Code session
- Toasts always show — including for Stop events. (An earlier version suppressed Stop when VS Code was foreground, but in practice you live in VS Code all day and that branch fired on almost every turn, so you never saw a toast.)
- Toasts auto-dismiss after 60 seconds (configurable via `MessageDuration`)
- Per-user install — no admin rights needed
- Lives in `~/.claude/settings.local.json` so it doesn't interfere with anything synced via `~/.claude/settings.json`

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (default on every modern Windows) or PowerShell 7+
- **[Git for Windows](https://git-scm.com/download/win)** — Claude Code dispatches hook commands through Git Bash on Windows. The hook command in `settings.json` is a single portable `"$HOME/.claude/hooks/notify.sh"` line that works on both Mac and Windows; Git Bash is what executes it on Windows.
- [Claude Code](https://claude.com/claude-code) in the **VS Code extension**. The CLI works for notifications too, but the "Open VS Code" toast button targets a VS Code window — there's no equivalent for terminal sessions
- Internet for first-time install (downloads the BurntToast PowerShell module)

## Install

One line in PowerShell:

```powershell
irm https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main/install.ps1 | iex
```

The installer will:

1. Verify Git for Windows / Git Bash is present (required to run hook commands)
2. Install the [BurntToast](https://github.com/Windos/BurntToast) PowerShell module (CurrentUser scope, no admin)
3. Copy `notify.sh`, `notify.ps1`, and `focus-vscode.ps1` to `~/.claude/hooks/`
4. Register the `claude-focus://` URL protocol under `HKCU\Software\Classes\claude-focus`
5. Set toast banner duration to 60 seconds (`HKCU:\Control Panel\Accessibility\MessageDuration`)
6. Merge `Stop`, `Notification`, and `PreToolUse` (matched on `AskUserQuestion|ExitPlanMode`) hooks into `~/.claude/settings.json` using the portable command form `"$HOME/.claude/hooks/notify.sh" <Event>`. Existing event entries are preserved.
7. Send a test toast to confirm it works

After install, **restart any open Claude Code session** so it picks up the new hooks (`Ctrl+Shift+P` → `Developer: Reload Window`).

### Sharing settings.json across machines

The hook command (`"$HOME/.claude/hooks/notify.sh" <Event>`) is intentionally portable — same string on Mac and Windows. If you sync `~/.claude/settings.json` between machines (Dropbox, Google Drive, Syncthing, dotfiles), the same `hooks` block works on both, as long as each OS has its own `notify.sh` locally. The macOS counterpart of this project provides the Mac-side `notify.sh`.

## Customize

The toast itself is rendered in `~/.claude/hooks/notify.ps1` (PowerShell + BurntToast). `notify.sh` is a thin bash wrapper that forwards the event to it. Common tweaks all live in `notify.ps1`:

- **Change the text** — find the `$title` and `$body` lines and rewrite
- **Re-add a foreground-window check** (skip the toast when VS Code is focused) — wrap the body in a `GetForegroundWindow` + process-name check; see git history for the old block
- **Change the buttons** — see [BurntToast docs](https://github.com/Windos/BurntToast#new-btbutton)

Both scripts are read fresh on every event, so no reinstall is needed after edits.

To change the dismiss timeout:

```powershell
# Max value is 300 seconds
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility" -Name MessageDuration -Value 60 -Type DWord
```

## Uninstall

```powershell
irm https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main/uninstall.ps1 | iex
```

This removes the hook scripts, unregisters the URL protocol, removes the `Stop` / `Notification` / `PreToolUse` entries from `~/.claude/settings.json` (other event keys like `SessionStart` are preserved), and resets `MessageDuration`. BurntToast and Git for Windows stay installed in case you use them elsewhere — remove BurntToast manually with `Uninstall-Module BurntToast` if you want.

## How it works

```
┌──────────────┐    Stop / Notification event     ┌──────────┐      ┌────────────┐
│ Claude Code  ├──────────────────────────────────►│ Git Bash ├─────►│ notify.sh  │
└──────────────┘  ("$HOME/.claude/hooks/notify.sh" └──────────┘      └─────┬──────┘
                   <Event> — same on Mac & Win)                           │ forward
                                                                          │ (JSON on stdin,
                                                                          │  event as arg)
                                                                          ▼
                                                                   ┌──────────────┐
                                                                   │  notify.ps1  │
                                                                   └──────┬───────┘
                                                                          │
                                                                          ▼
                                                                   ┌──────────────┐
                                                                   │  BurntToast  │──► Toast
                                                                   └──────────────┘
                                                                          │
                                                user clicks "Open VS Code"│
                                                                          ▼
                                                            claude-focus:// URL protocol
                                                                          │
                                                                          ▼
                                                                   ┌──────────────────┐
                                                                   │ focus-vscode.ps1 │
                                                                   └──────────────────┘
                                                                          │
                                                                          ▼
                                                       Win32: AttachThreadInput + SetForegroundWindow
                                                       on the VS Code window whose title matches the
                                                       project's leaf folder (from event.cwd)
```

### Components

- **Hooks in `settings.json`** — Claude Code natively supports running shell commands on lifecycle events. We attach to three:
  - `Stop` — turn complete
  - `Notification` — permission prompts and idle prompts
  - `PreToolUse` matched on `AskUserQuestion|ExitPlanMode` — fires for in-chat questions and plan-mode approval (these don't go through the `Notification` event in current Claude Code)

  All three use the same portable command `"$HOME/.claude/hooks/notify.sh" <Event>`. On Windows Claude Code dispatches it through Git Bash. [Hook docs.](https://docs.claude.com/en/docs/claude-code/hooks)
- **`notify.sh`** — thin bash wrapper. Logs the invocation to `%TEMP%\claude-toast-sh.log` (proves the hook fired), then pipes the event JSON to `notify.ps1`. Same interface as the macOS counterpart, so the `hooks` block in `settings.json` is identical across machines.
- **`notify.ps1`** — receives event JSON on stdin and renders the toast through BurntToast. Per-event behavior:
  - `Stop` — hardcoded "turn complete" toast
  - `Notification` — uses the `message` field from the event JSON
  - `PreToolUse` — toasts only when there's something to react to: `AskUserQuestion` (shows the question text), `ExitPlanMode` (plan approval), or a permission-prompt (detected via a `permission_decision` / `permissionRequired` field on the event). Auto-approved tool calls (Read/Edit/Write on allow-listed files) are silently skipped to avoid spam.
  - `PostToolUse` — silently skipped (tool completion is not a toast-worthy moment)
  - Logs every decision to `%TEMP%\claude-toast.log`. Also writes the last raw JSON of each event type to `%TEMP%\claude-event-<Event>-last.json` for debugging when Claude Code changes its event schema.
- **`focus-vscode.ps1`** — invoked when the toast button is clicked. Reads the project folder name (saved by `notify.ps1`) and matches it against `MainWindowTitle` of running `Code.exe` processes to pick the right window, then brings it forward via Win32 API. Uses `AttachThreadInput` + `AllowSetForegroundWindow` to bypass UIPI — Action Center launches the protocol handler without foreground rights, so a plain `SetForegroundWindow` silently fails.
- **`claude-focus://` URL protocol** — Windows toast buttons can only trigger one of three activation types: a URL protocol, foreground app activation (needs a registered AppUserModelID), or background COM activation. We use a custom URL protocol because it's the simplest to register from a per-user installer.

### Why a custom URL protocol instead of `vscode://`?

`vscode://` is registered by VS Code, but it's primarily for opening files (`vscode://file/<path>`) or extension-defined routes. A bare `vscode://` URL doesn't reliably bring an existing window forward — and even when it does, it picks the most-recently-active VS Code window, which may not be the one running your Claude Code session if you have multiple windows.

Our `claude-focus://` protocol points at a script that explicitly targets the project's window by matching the leaf folder name from Claude Code's `cwd` against the window title.

## Tested on

- Windows 11 Pro 23H2 (build 26100)
- PowerShell 5.1.26100
- VS Code with the Claude Code extension
- BurntToast 1.1.0

Should work on Windows 10 (1809+) and PowerShell 7. PRs welcome if you hit issues elsewhere.

## Files in this repo

```
claude-toast-windows/
├── README.md
├── LICENSE
├── install.ps1          # one-shot installer
├── uninstall.ps1        # one-shot uninstaller
└── hooks/
    ├── notify.sh        # bash entry point (called by Claude Code via Git Bash)
    ├── notify.ps1       # the toast renderer (called by notify.sh)
    └── focus-vscode.ps1 # the "Open VS Code" handler
```

The `hooks/` folder is the source of truth — `install.ps1` downloads those files into `~/.claude/hooks/` on your machine.

## Credits

- [BurntToast](https://github.com/Windos/BurntToast) by Joshua King — the heavy lifting of generating Windows toasts from PowerShell.

## License

MIT — see [LICENSE](LICENSE).
