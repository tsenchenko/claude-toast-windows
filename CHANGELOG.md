# Changelog

Newest first. Dates are commit dates.

## 2026-11-12

- **Fixed: focused-window suppression silently stopped working.** The project
  leaf came from the event's `cwd`, which follows every `cd` the session makes
  (`my-app` → `my-app/tools`). The drifted leaf matched no VS Code window title,
  so the toast fired even with the project window in front — labeled with the
  wrong project, and its click fell back to a random window. Now the leaf comes
  from `CLAUDE_PROJECT_DIR` (the session root, set by Claude Code for hooks);
  `cwd` is only a fallback.
- **Fixed: every question or permission prompt toasted twice.** Current Claude
  Code also sends a `Notification` with `notification_type: permission_prompt`
  ("Claude needs your permission to use …") for the same prompt that
  `PermissionRequest` / `PreToolUse` already toasted. It landed 15–30 s later,
  often after the prompt was answered. That notification type is now skipped;
  other `Notification` types (e.g. `idle_prompt`) still toast.
- **Cheap skip for events that never toast.** If `settings.json` hooks every
  Read/Edit/Write — e.g. it is shared with an older `claude-banners-macos` install
  that used a "waiting detector" — each tool call launched PowerShell (several
  seconds under load, blocking the call) only to be skipped. `notify.sh` now drops
  `PostToolUse` and non-question `PreToolUse` events in bash, before PowerShell.
  Keep the `PreToolUse` matcher at `AskUserQuestion|ExitPlanMode` (what
  `install.ps1` sets) so these hooks don't run at all.
- **Fixed: install/uninstall deleted other hooks.** `install.ps1` replaced the
  whole `Stop` / `Notification` / `PermissionRequest` / `PreToolUse` arrays, so
  re-running it wiped any other hook on those events (e.g. a `PreToolUse` cost
  gate, a second `Stop` command). `uninstall.ps1` removed a whole event when its
  first command was ours, or left our entry when it wasn't first. Both now
  remove only `notify.sh` hook entries inside each group; the installer also
  drops a leftover `notify.sh` `PostToolUse` entry. Verified under Windows
  PowerShell 5.1 against a real shared `settings.json`: idempotent, other hooks
  kept.
- **Fixed: running `uninstall.ps1` from a file failed in Windows PowerShell 5.1.**
  The file has no BOM, so 5.1 read it as ANSI and an em-dash inside a string
  turned into a closing quote (parse error). The `irm … | iex` path was not
  affected. `install.ps1` and `uninstall.ps1` are now ASCII-only.
- **Logs rotate at 1 MB** (`claude-toast.log`, `claude-toast-sh.log` → `.old`,
  one generation kept). They used to grow without limit.
- **No toasts from background (headless) sessions.** `claude -p` runs (orchestrator
  workers, scripted jobs) have nobody to react;
  the orchestrating interactive session reports their results. notify.ps1 looks up
  the Claude process for the event's `session_id` in `~/.claude/sessions/<pid>.json`
  and skips the toast when its command line has `-p`/`--print`. The registry's own
  `kind` field is useless here (workers inherit the parent's env and report
  `interactive`); a process-tree walk is the fallback only, because Git Bash exec
  can leave a dead parent PID in the chain. Checked against 13 live sessions (8
  headless, 5 interactive): all classified correctly.

## 2026-07-03

- **Toast titles now carry the project name** — `Claude Code [my-app] — закончил ход`.
  Root cause of "toast fires while Claude is just narrating": with several concurrent
  sessions, a background project's legit Stop toast was indistinguishable from the
  active session's, so it read as a spurious mid-turn toast.
- **Killed the duplicate question toast** — AskUserQuestion/ExitPlanMode fire both
  PreToolUse and PermissionRequest; PermissionRequest now skips them (PreToolUse
  toasts 1–2 s earlier with the actual question/plan text).
- **Toast click now focuses the right project** — the click URL embeds the project
  leaf (`claude-focus://activate/<leaf>`, percent-encoded). Previously the target
  came only from a shared `%TEMP%` file that any concurrent session could overwrite
  between toast and click; the file remains as a fallback for bare/legacy URLs.
- Translated notify.ps1 comments to English (toast strings stay Russian — user-facing UI).

## 2026-06-19

- Suppress a toast only when the foreground window is **this project's** VS Code
  window (exact title-segment match). Toasts still show over other VS Code windows,
  the browser, etc.

## 2026-06-11

- Toast click focuses the correct VS Code window via Win32 `EnumWindows`.
  `Get-Process` exposes only one window per process, so with several VS Code
  windows the focus could land on another project.

## 2026-06-10

- Toast on the dedicated `PermissionRequest` event — the real fix for
  "Do you want to proceed?" prompts. The VS Code extension does not emit
  `Notification` for permission prompts, and the old PreToolUse permission-field
  detection checked a field that does not exist.

## 2026-06-08

- Handle `PreToolUse`/`PostToolUse` events without crashing.

## 2026-06-03

- Portable hook commands (`"$HOME/.claude/hooks/notify.sh"` via Git Bash) so the
  same synced `settings.json` works on both Mac and Windows.

## 2026-06-01

- Always show the Stop toast; removed the blanket "any VS Code window is
  foreground" suppression (superseded on 2026-06-19 by per-project suppression).

## 2026-05-18

- Fixed toast click not focusing VS Code; made the whole toast clickable, not
  just the button (`-Launch` + `-ActivationType Protocol`).

## 2026-05-07

- Initial release: Windows toasts (BurntToast) for Claude Code lifecycle events —
  turn finished (`Stop`), attention needed (`Notification`), in-chat question /
  plan approval (`PreToolUse`: AskUserQuestion, ExitPlanMode). UTF-8 stdin fix so
  Cyrillic renders correctly. `claude-focus://` protocol + focus script to bring
  the project's VS Code window forward on click.
