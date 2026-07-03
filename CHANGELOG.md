# Changelog

Newest first. Dates are commit dates.

## 2026-07-03

- **Toast titles now carry the project name** — `Claude Code [Houston] — закончил ход`.
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
