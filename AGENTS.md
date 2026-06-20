# Repository Instructions

## Purpose

This repository contains a small Windows-only PowerShell tray daemon for using
a US physical keyboard while Windows remains configured as Japanese/JIS.

The implementation target is a restricted Windows environment:

- No administrator rights assumed.
- No PowerToys or AutoHotkey dependency.
- Windows keyboard layout settings may be policy-restricted.
- The v1 behavior is manual ON/OFF switching, not per-device auto detection.

For project background, see `docs/PROJECT_CONTEXT.md`.

## Implementation Rules

- Keep the tool as a single PowerShell entrypoint: `win-jis-us-symbol-overlay.ps1`.
- Keep the single `.vbs` launcher as a thin no-console double-click wrapper
  around the PowerShell entrypoint. It starts with US overlay ON and
  CapsLock-as-Ctrl enabled.
- Do not add duplicate `-us` launchers; keep alternate start modes as
  command-line switches.
- Keep icon assets under `assets/`; the `.ico` is used by the tray icon and
  generated `.lnk` shortcuts.
- Keep generated `.lnk` files ignored because they contain local absolute paths.
  The tray icon must continue to work without a `.lnk` by loading the `.ico`
  asset from the script directory.
- Do not add external runtime dependencies unless explicitly requested.
- Use Windows PowerShell-compatible code. Primary launch command:
  `powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\win-jis-us-symbol-overlay.ps1`.
- Embedded C# via `Add-Type` is acceptable and currently required for Win32 API
  calls.
- Keep user-facing daemon UI/log strings ASCII unless there is a specific reason
  to change encoding behavior.
- Do not log typed text, clipboard content, or application contents.
- Do not add network access.
- Do not require elevation or write to machine-wide locations for normal use.
- Keep the default startup mode safe: JIS/OFF unless `-StartMode US` is provided.
- Preserve the single-instance guard so double-click launchers or shortcuts do not create
  duplicate keyboard hooks.
- Keep public docs generic. Do not include personal workflows, workplace names,
  user names, local absolute paths, or private environment notes.
- Put any local-only notes under `.local/`, `local/`, `personal/`, or `work/`;
  these paths are ignored by Git.

## Keyboard Behavior

- Use `WH_KEYBOARD_LL` and `KBDLLHOOKSTRUCT.scanCode` for physical key position
  mapping.
- Mark own `SendInput` events with `dwExtraInfo` and ignore those injected
  events before updating modifier state. Treat other injected input as
  pass-through to avoid recursive remapping.
- Preserve shortcuts by default, but allow the narrow Ctrl shortcut overlay:
  while US overlay and shortcut overlay are ON, remap only fixed unextended US
  OEM symbol-key positions to matching `VK_OEM_*` key events. Leave letter
  shortcuts, `Alt`, `Win`, and `Ctrl+Alt` chords alone.
- Track active shortcut remaps from keydown through keyup, and release all
  active target keys when shortcut overlay, US overlay, the hook, or the daemon
  turns off.
- For text symbol mapping, treat `Shift` only as a symbol variant selector.
- Leave extended keys alone, including numpad division.
- Keep symbol width handling separate from US overlay mode. `Auto` should
  best-effort follow foreground IME open/conversion status; `ASCII` and
  `Fullwidth` are manual overrides.
- Keep fullwidth style handling separate from symbol width detection. `Japanese`
  is the default style for fullwidth output, while `Literal` preserves plain
  fullwidth ASCII-symbol equivalents.
- In the low-level hook, only query foreground IME state after confirming the
  scan code belongs to the overlay map. Auto fullwidth detection should require
  the foreground IME context to be open and either full-shape or native
  non-Katakana.
- Keep Auto fallback work lightweight in the low-level hook. Use a short cache,
  avoid sentence-mode probing on the hook path, and keep slow/default IME window
  calls bounded with short timeouts.
- Keep IME diagnostics explicit and user-triggered. Diagnostics may log process
  name, PID/TID, HWND, window class, HKL, IMM flags, and decision reason, but
  must not log typed text, window titles, URLs, clipboard content, command
  lines, or full filesystem paths.
- Keep CapsLock-as-Ctrl separate from US overlay mode. It should suppress
  CapsLock and send left Ctrl down/up only while enabled.
- Track physical Ctrl state so CapsLock-as-Ctrl does not release a Ctrl key that
  the user is still holding.
- Track left/right Ctrl, Alt, Win, and Shift separately; include the synthetic
  CapsLock-as-Ctrl state only when computing whether Ctrl is down.
- Release synthetic Ctrl if CapsLock-as-Ctrl is disabled or the hook is
  uninstalled.
- v1 maps only the fixed US symbol overlay set documented in
  `docs/PROJECT_CONTEXT.md`.

## Verification

Run the self-test after edits:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\win-jis-us-symbol-overlay.ps1 -SelfTest -LogPath .\selftest-sta.log
Remove-Item -LiteralPath .\selftest-sta.log -Force
```

Manual functional checks require an interactive Windows desktop:

- Start the daemon with `-STA`.
- Use the tray menu or `Ctrl+Alt+F12` to toggle US overlay.
- Use the tray menu to toggle CapsLock-as-Ctrl.
- Use the tray menu to toggle Shortcut overlay if shortcut behavior is under
  test.
- Open `Layout test` from the tray menu.
- Verify `Ctrl+=`, `Ctrl+Shift+=`, `Ctrl+-`, `Ctrl+\`, and `Ctrl+backtick` in
  VS Code or a comparable app when shortcut overlay behavior changed.
- Verify key output in Notepad, Edge/Chrome, and representative target apps when
  possible.

## Known Limits

- The overlay affects all keyboards while ON.
- Shortcut overlay affects all keyboards while US overlay is ON.
- It will not work on UAC secure desktop prompts.
- It may not work in elevated applications because `SendInput` is subject to
  Windows integrity-level restrictions.
- Automatic fullwidth detection is best-effort and may not work in every app or
  IME path.
- If PowerShell is in `ConstrainedLanguageMode`, or `Add-Type`/hooks are blocked
  by policy or EDR, this approach may not be usable.
