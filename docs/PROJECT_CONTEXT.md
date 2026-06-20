# win-jis-us-symbol-overlay Project Context

## Goal

Provide a dependency-light utility for Windows environments where the OS
keyboard layout is Japanese/JIS, but a US physical keyboard is sometimes used.

The intended v1 behavior is manual switching:

- US overlay ON when using a US physical keyboard.
- US overlay OFF when using a JIS physical keyboard.
- Optional CapsLock-as-Ctrl remapping for users who prefer Ctrl on CapsLock.
- Symbol width mode `Auto` by default, with manual `ASCII` and `Fullwidth`
  overrides.
- Fullwidth style `Japanese` by default, with `Literal` available for plain
  fullwidth ASCII-symbol equivalents.
- No administrator-only changes.
- No PowerToys, AutoHotkey, custom driver, or service dependency.

## Chosen Approach

Windows remains configured as Japanese Microsoft IME / JIS. The daemon provides
a manual "US overlay" mode. When ON, selected physical symbol-key positions are
suppressed and re-sent as US-layout symbols. The output is ASCII or a fullwidth
equivalent depending on the current Symbol Width mode.

The daemon is implemented as `win-jis-us-symbol-overlay.ps1`:

- PowerShell entrypoint.
- Embedded C# compiled via `Add-Type`.
- `SetWindowsHookEx` with `WH_KEYBOARD_LL` for low-level keyboard observation.
- `KBDLLHOOKSTRUCT.scanCode` for physical key-position mapping.
- `SendInput` with Unicode key events to emit the corrected symbol.
- `RegisterHotKey` for `Ctrl+Alt+F12` toggle.
- `NotifyIcon` for tray UI.
- Thin `.vbs` wrapper for no-console double-click startup.
- Optional custom `.ico` asset for the tray icon and generated `.lnk`
  launch shortcuts.
- IMM32 foreground IME open-status and conversion-status checks for best-effort
  fullwidth symbol output in `SymbolWidth Auto` mode.
- Default IME window fallback via `ImmGetDefaultIMEWnd` and `WM_IME_CONTROL`
  when direct foreground IMM context probing is unavailable.

This approach is intentionally user-mode and manual. Per-device keyboard layout
control normally needs driver-level support or a tool that provides its own
device-specific input layer.

## Out Of Scope For v1

- Per-device automatic detection of external versus built-in keyboard.
- Changing Windows keyboard layout settings.
- Installing drivers or services.
- AutoHotkey or PowerToys integration.
- Handling elevated/UAC secure desktop input.
- Logging typed input or collecting application text.

## CapsLock-As-Ctrl

The optional `-CapsLockAsCtrl` setting suppresses CapsLock and sends left Ctrl
down/up instead. It is implemented in the same low-level keyboard hook as the US
symbol overlay, but it is controlled separately from US overlay mode.

The included VBS launcher starts with US overlay ON and passes
`-CapsLockAsCtrl` by default. Direct PowerShell startup can omit either switch.

## Symbol Width

`-SymbolWidth Auto` is the default. In Auto mode, the daemon first checks the
foreground IME open status and conversion status through direct IMM context
probing. If that is unavailable, it falls back to the foreground window's
default IME window via `WM_IME_CONTROL`. It emits fullwidth/Japanese-style
symbols when the IME is open and either `IME_CMODE_FULLSHAPE` is reported or
`IME_CMODE_NATIVE` is reported without `IME_CMODE_KATAKANA`. `-SymbolWidth
ASCII` always emits ASCII symbols, and `-SymbolWidth Fullwidth` always emits
fullwidth output.

`-FullwidthStyle Japanese` is the default and uses Japanese IME-style output for
selected unshifted keys: `[` -> `「`, `]` -> `」`, and `/` -> `・`.
`-FullwidthStyle Literal` keeps the older literal fullwidth equivalents:
`[` -> `［`, `]` -> `］`, and `/` -> `／`.

This is best-effort because some apps and modern IME paths may not expose the
expected IMM conversion status. The tray menu can switch among Auto, ASCII,
Fullwidth, Japanese style, and Literal style at runtime.

## Mapped Keys

US overlay mode maps this fixed set. The table shows the ASCII base output and
the default Japanese fullwidth output. `-FullwidthStyle Literal` changes `「`,
`」`, and `・` back to `［`, `］`, and `／`.

```text
Physical       ASCII    Japanese fullwidth
Shift+2        @        ＠
Shift+6        ^        ＾
Shift+7        &        ＆
Shift+8        *        ＊
Shift+9        (        （
Shift+0        )        ）
SC00C          -        －
Shift+SC00C    _        ＿
SC00D          =        ＝
Shift+SC00D    +        ＋
SC01A          [        「
Shift+SC01A    {        ｛
SC01B          ]        」
Shift+SC01B    }        ｝
SC02B          \        ＼
Shift+SC02B    |        ｜
SC027          ;        ；
Shift+SC027    :        ：
SC028          '        ＇
Shift+SC028    "        ＂
SC029          `        ｀
Shift+SC029    ~        ～
SC035          /        ・
Shift+SC035    ?        ？
```

While US overlay is ON, these mappings apply globally to the current user
desktop. Users must switch the overlay OFF before using a JIS physical keyboard
normally.

## Commands

Self-test:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -SelfTest
```

Create the recommended icon-bearing double-click launcher:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -CreateShortcuts
```

Recommended manual start:

```powershell
.\win-jis-us-symbol-overlay.lnk
```

The generated `.lnk` is local-only because it stores the resolved script path.
It should not be committed or distributed. The tray icon does not depend on the
`.lnk`; the daemon loads `assets\win-jis-us-symbol-overlay.ico` at runtime for
any startup path.

Fallback no-console manual start without a custom file icon:

```powershell
.\start-win-jis-us-symbol-overlay.vbs
```

Visible PowerShell start for diagnostics:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1"
```

The visible diagnostic command above starts with safe JIS/OFF defaults. Add
`-StartMode US -CapsLockAsCtrl` to match the `.lnk` and VBS launcher behavior.

PowerShell equivalent for US overlay ON:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US
```

Force fullwidth symbol output:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -SymbolWidth Fullwidth
```

PowerShell equivalent for literal fullwidth symbols:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -SymbolWidth Fullwidth -FullwidthStyle Literal
```

Capture foreground IME diagnostics:

1. Start the daemon.
2. Choose tray menu `IME diagnostics`.
3. Focus the target input field within 3 seconds.
4. Open the log with tray menu `Open log`.

The diagnostic log records process name, PID/TID, HWND, window class, HKL, IMM
conversion flags, and decision reason. It intentionally avoids input text,
window titles, URLs, clipboard content, command lines, and full filesystem
paths.

Install at logon:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -Install
```

Install at logon with CapsLock-as-Ctrl enabled:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -CapsLockAsCtrl -Install
```

Install at logon with US overlay ON and CapsLock-as-Ctrl enabled:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -StartMode US -CapsLockAsCtrl -Install
```

Uninstall future autostart:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-jis-us-symbol-overlay.ps1" -Uninstall
```

## Operational Notes

- `-Install` first tries a current-user scheduled task with an `AtLogOn`
  trigger.
- If scheduled task registration is blocked, it falls back to creating a
  shortcut in the current user's Startup folder.
- `-Install` stores the current script path. Move the folder before installing,
  or uninstall/reinstall after moving it.
- `-StartMode US -Install` persists US overlay ON in the autostart command;
  without `-StartMode US`, installed autostart uses the safe JIS/OFF default.
- `-CreateShortcuts` stores the current script path in the generated `.lnk`.
  Rerun it after moving the folder.
- `-CapsLockAsCtrl -Install` persists CapsLock-as-Ctrl in the autostart command.
- `-Uninstall` removes autostart entries only; it does not stop the current tray
  process.
- Logs default to `%LOCALAPPDATA%\win-jis-us-symbol-overlay\daemon.log`.
- Normal logs should remain operational: startup, shutdown, mode changes, and
  errors.
- User-triggered `IME diagnostics` may log technical IME/window metadata such as
  process name, PID/TID, HWND, window class, HKL, IMM flags, and decision reason.
- Never log typed text, window titles, URLs, clipboard contents, command lines,
  full filesystem paths, or application contents.

## Validation

Before committing changes, run:

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\win-jis-us-symbol-overlay.ps1 -SelfTest -LogPath .\selftest-sta.log
Remove-Item -LiteralPath .\selftest-sta.log -Force
```

The self-test verifies embedded C# compilation, native structure definitions,
and pure key-mapping cases. Manual behavior still requires an interactive
Windows desktop test.
