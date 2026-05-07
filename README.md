# claude-toast-windows

> Windows toast notifications for Claude Code in VS Code — know when Claude finishes a turn or needs your attention, even when you're in another window.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](#requirements)

## The problem

Claude Code in the VS Code extension on Windows has no native desktop notifications. There's a built-in setting (`preferredNotifChannel`) but it only works in terminal emulators like iTerm2, Ghostty, or Kitty — not in the VS Code extension.

So if you walk away from your machine, you have no way to know when:

- Claude has **finished its turn** and is waiting for your next prompt
- Claude is **asking a question** or **requesting permission** to run a tool

You either keep VS Code in focus and watch the screen, or you lose minutes every time you context-switch back.

## The solution

This repo wires Claude Code's built-in **hooks** (`Stop` and `Notification` events) into Windows toast notifications. You get a toast in the corner of the screen the moment Claude returns control to you. The Notification toast even shows the actual question text so you know what's pending without switching apps.

Click "Open VS Code" on the toast to bring the right VS Code window forward (matched by project folder).

## Features

- Toast on `Stop` event (Claude finishes its turn)
- Toast on `Notification` event (permission prompts, idle prompts), showing the actual prompt text
- Toast on `PreToolUse` for `AskUserQuestion` and `ExitPlanMode` — covers in-chat questions and plan-mode approval, which Claude Code does **not** dispatch through the `Notification` event
- The question text is surfaced in the toast body, so you know what's being asked without switching apps
- "Open VS Code" button focuses the correct window — even if you have multiple VS Code windows open, it picks the one running this Claude Code session
- The Stop toast is **suppressed** when VS Code is already foreground (low-priority "I'm done" event); question/permission toasts always show, since at hook-dispatch time you may not have switched away yet
- Toasts auto-dismiss after 60 seconds (configurable via `MessageDuration`)
- Per-user install — no admin rights needed
- Lives in `~/.claude/settings.local.json` so it doesn't interfere with anything synced via `~/.claude/settings.json`

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (default on every modern Windows) or PowerShell 7+
- [Claude Code](https://claude.com/claude-code) installed (CLI or VS Code extension)
- Internet for first-time install (downloads the BurntToast PowerShell module)

## Install

One line in PowerShell:

```powershell
irm https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main/install.ps1 | iex
```

The installer will:

1. Install the [BurntToast](https://github.com/Windos/BurntToast) PowerShell module (CurrentUser scope, no admin)
2. Copy `notify.ps1` and `focus-vscode.ps1` to `~/.claude/hooks/`
3. Register the `claude-focus://` URL protocol under `HKCU\Software\Classes\claude-focus`
4. Set toast banner duration to 60 seconds (`HKCU:\Control Panel\Accessibility\MessageDuration`)
5. Merge `Stop`, `Notification`, and `PreToolUse` (matched on `AskUserQuestion|ExitPlanMode`) hooks into `~/.claude/settings.local.json` (other keys are preserved)
6. Send a test toast to confirm it works

After install, **restart any open Claude Code session** so it picks up the new hooks.

## Customize

Open `~/.claude/hooks/notify.ps1` and edit. Common tweaks:

- **Change the text** — find the `$title` and `$body` lines and rewrite
- **Disable the foreground-window check** (always notify, even when VS Code is focused) — delete the `try { Add-Type ...` block at the top
- **Change the buttons** — see [BurntToast docs](https://github.com/Windos/BurntToast#new-btbutton)

The hook reads the script fresh on every event, so no reinstall is needed after edits.

To change the dismiss timeout:

```powershell
# Max value is 300 seconds
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility" -Name MessageDuration -Value 60 -Type DWord
```

## Uninstall

```powershell
irm https://raw.githubusercontent.com/tsenchenko/claude-toast-windows/main/uninstall.ps1 | iex
```

This removes the hook scripts, unregisters the URL protocol, removes the `hooks` block from `settings.local.json`, and resets `MessageDuration`. BurntToast itself stays installed in case you use it elsewhere — remove it manually with `Uninstall-Module BurntToast` if you want.

## How it works

```
┌──────────────┐      Stop / Notification event       ┌──────────────┐
│ Claude Code  ├──────────────────────────────────────►│  notify.ps1  │
└──────────────┘   (event JSON piped to script stdin)  └──────┬───────┘
                                                              │
                                       VS Code in foreground? │
                                       └─ yes → exit silently │
                                       └─ no  → continue ─────┤
                                                              ▼
                                                       ┌──────────────┐
                                                       │  BurntToast  │──► Windows Toast
                                                       └──────────────┘
                                                              │
                                            user clicks "Open VS Code"
                                                              ▼
                                              claude-focus:// URL protocol
                                                              │
                                                              ▼
                                                       ┌──────────────────┐
                                                       │ focus-vscode.ps1 │
                                                       └──────────────────┘
                                                              │
                                                              ▼
                                            Win32: SetForegroundWindow +
                                                   SwitchToThisWindow on
                                            the VS Code window whose title
                                            matches the project folder
```

### Components

- **Hooks in `settings.local.json`** — Claude Code natively supports running shell commands on lifecycle events. We attach to three:
  - `Stop` — turn complete
  - `Notification` — permission prompts and idle prompts
  - `PreToolUse` matched on `AskUserQuestion|ExitPlanMode` — fires for in-chat questions and plan-mode approval (these don't go through the `Notification` event in current Claude Code)

  [Hook docs.](https://docs.claude.com/en/docs/claude-code/hooks)
- **`notify.ps1`** — receives event JSON on stdin. First checks `GetForegroundWindow` + process name to skip when VS Code is already focused. Then either uses the hardcoded "turn complete" text (Stop) or the `message` field from the event JSON (Notification). Renders the toast through BurntToast.
- **`focus-vscode.ps1`** — invoked when the toast button is clicked. Reads the project folder name (saved by `notify.ps1`) and matches it against `MainWindowTitle` of running `Code.exe` processes to pick the right window, then brings it forward via Win32 API.
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
    ├── notify.ps1       # the toast renderer
    └── focus-vscode.ps1 # the "Open VS Code" handler
```

The `hooks/` folder is the source of truth — `install.ps1` downloads those files into `~/.claude/hooks/` on your machine.

## Credits

- [BurntToast](https://github.com/Windos/BurntToast) by Joshua King — the heavy lifting of generating Windows toasts from PowerShell.

## License

MIT — see [LICENSE](LICENSE).
