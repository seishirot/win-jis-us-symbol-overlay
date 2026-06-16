# win-jis-us-symbol-overlay

`win-jis-us-symbol-overlay` is a small Windows tray utility for using a US
physical keyboard while Windows remains configured for a Japanese/JIS keyboard
layout.

It does not change Windows keyboard settings. Instead, when US overlay mode is
enabled, it intercepts a fixed set of symbol-key positions and sends the
corresponding US-layout symbol as either ASCII or a fullwidth equivalent,
depending on the current Symbol Width mode.

## Files

- `win-jis-us-symbol-overlay.ps1`: PowerShell entrypoint and tray daemon.
- `start-win-jis-us-symbol-overlay.vbs`: double-click launcher, starts hidden in
  US overlay mode with CapsLock-as-Ctrl enabled. Windows shows the default
  Windows Script Host icon for this file.
- `assets/win-jis-us-symbol-overlay.ico`: tray icon and generated shortcut
  icon.
- `assets/win-jis-us-symbol-overlay.png`: transparent source artwork for the
  icon.

Keep these files in the same folder. The VBS launcher resolves
`win-jis-us-symbol-overlay.ps1` beside it.

## Quick Start

Download or copy the whole folder to a stable location before installing at
logon. If you move the folder later, run `-Uninstall` from any current copy of
the script and then `-Install` again from the new location. The uninstall command
removes the current-user task and Startup shortcut named
`win-jis-us-symbol-overlay`. Also rerun `-CreateShortcuts` after moving the
folder because generated `.lnk` files store the script path.

Recommended double-click setup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -CreateShortcuts
```

Then start the daemon with the generated shortcut:

```powershell
.\win-jis-us-symbol-overlay.lnk
```

The generated shortcut starts hidden with US overlay and CapsLock-as-Ctrl
enabled, uses symbol width `Auto`, and uses the custom icon. The `.vbs`
launcher starts the same way, but keeps the default Windows Script Host icon:

```powershell
.\start-win-jis-us-symbol-overlay.vbs
```

The tray icon is independent of the `.lnk` file. Any startup path that runs the
PowerShell daemon from this folder, including the VBS launcher or direct
PowerShell command, uses `assets/win-jis-us-symbol-overlay.ico` for the tray
icon when the asset exists.

Generated `.lnk` files are intentionally not tracked in Git because they store
the absolute local script path. Run `-CreateShortcuts` after copying or moving
the folder.

Use the tray menu or `Ctrl+Alt+F12` to switch between ON and OFF. If a hidden
launcher fails, run PowerShell directly so errors remain visible. The plain
command starts with the safe JIS/OFF defaults:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1"
```

To test the same startup behavior as the `.lnk` and VBS launchers, add the
launcher switches:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -CapsLockAsCtrl
```

Add `-CapsLockAsCtrl` to start with CapsLock remapped to Ctrl:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -CapsLockAsCtrl
```

Symbol width defaults to `Auto`. In this mode the daemon checks the foreground
IME open/conversion status and sends fullwidth symbols such as `＠`, `？`, and
`：` when the IME reports full-shape input, or native Japanese input that is not
half-width Katakana. Use tray menu `Symbol width ASCII` or `Symbol width
Fullwidth` to force either behavior.

You can also force it from PowerShell:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -SymbolWidth Fullwidth
```

## What Gets Remapped

Only these symbol positions are remapped. The table shows the ASCII base output;
Symbol Width may emit fullwidth equivalents. Letters, IME behavior, shortcuts,
and all other keys are intentionally left alone.

```text
Physical key        US overlay output
Shift+2             @
Shift+6             ^
Shift+7             &
Shift+8             *
Shift+9             (
Shift+0             )
- / Shift+-         - / _
= / Shift+=         = / +
[ / Shift+[         [ / {
] / Shift+]         ] / }
\ / Shift+\         \ / |
; / Shift+;         ; / :
' / Shift+'         ' / "
` / Shift+`         ` / ~
/ / Shift+/         / / ?
```

The optional CapsLock-as-Ctrl setting maps CapsLock down/up to left Ctrl
down/up. While it is enabled, CapsLock is suppressed and does not toggle Caps
Lock state.

Symbol width can be `Auto`, `ASCII`, or `Fullwidth`. `Auto` is the default and
tries to follow the foreground IME open/conversion status.

## Install At Logon

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -Install
```

`-Install` stores the current script path in a current-user scheduled task. If
scheduled task registration is blocked, it falls back to a shortcut in the
current user's Startup folder. Installed autostart begins in JIS/OFF mode unless
you pass `-StartMode US`.

To install autostart with US overlay ON and CapsLock-as-Ctrl enabled:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -CapsLockAsCtrl -Install
```

Uninstall future autostart:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -Uninstall
```

`-Uninstall` removes the scheduled task and Startup shortcut only. It does not
stop an already running tray instance. Use tray menu `Exit`, sign out, or stop
the process to end the current session.

## Testing

Quick self-test:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -SelfTest -LogPath ".\selftest-sta.log"
Remove-Item -LiteralPath ".\selftest-sta.log" -Force
```

The self-test checks embedded C# compilation, native structure definitions, and
pure key-mapping cases. It does not install the hook or start the tray daemon.

Manual test:

1. Start the daemon with `win-jis-us-symbol-overlay.lnk`, the VBS launcher, or
   the visible PowerShell command.
2. Confirm the tray icon appears.
3. Toggle US overlay with the tray menu or `Ctrl+Alt+F12`.
4. Toggle CapsLock-as-Ctrl from the tray menu if needed.
5. Open tray menu `Layout test`.
6. Type the expected symbols in Notepad, Edge/Chrome, and any target apps.
7. Confirm common shortcuts such as `Ctrl+C`, `Ctrl+V`, `Alt+Tab`, and Win-key
   shortcuts still pass through.

For Auto symbol-width issues, choose tray menu `IME diagnostics`, then focus the
target input field within 3 seconds and open the log. The diagnostic entry
records only metadata such as process name, PID/TID, HWND, window class, HKL,
IMM conversion flags, and decision reason. It does not log typed text, window
titles, URLs, clipboard content, command lines, or full filesystem paths.

## Privacy And Security

- No typed text is logged.
- Clipboard and application contents are not read.
- `IME diagnostics` logs technical environment, daemon-state, window, and IME
  metadata only; it does not log input text, window titles, URLs, command lines,
  or full filesystem paths.
- No network access is used.
- Normal use does not require administrator rights.
- `-Install` creates current-user autostart only.
- `ExecutionPolicy Bypass` is used only for the launched PowerShell process.
- Operational logs default to
  `%LOCALAPPDATA%\win-jis-us-symbol-overlay\daemon.log`.
- Console output and logs can include local filesystem paths. Redact them before
  posting public issues.
- The daemon uses `Add-Type`, `WH_KEYBOARD_LL`, and `SendInput`; inspect the
  script before running it in a sensitive environment.

## Limits

- The overlay affects all keyboards while US overlay mode is ON.
- CapsLock-as-Ctrl affects all keyboards while it is ON.
- Automatic fullwidth detection depends on the foreground app and IME exposing
  open/conversion status through Windows IMM APIs. If it does not follow
  correctly, use tray menu `Symbol width Fullwidth` or `Symbol width ASCII`.
- Tray menu `IME diagnostics` can help compare the direct IMM and default IME
  window state exposed by the foreground app without logging typed content.
- If `Ctrl+Alt+F12` is already registered by another app, the tray menu still
  works for switching US overlay ON/OFF.
- It leaves extended keys such as numpad division alone.
- It does not work on UAC secure desktop prompts.
- It may not work against apps running as administrator.
- It needs PowerShell `FullLanguage` mode because it uses `Add-Type`.

## License

MIT License. See `LICENSE`.
