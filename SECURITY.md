# Security Policy

## Privacy

`win-jis-us-symbol-overlay` is a local-only keyboard utility.

- It does not log typed text.
- It does not read clipboard contents.
- It does not inspect application contents.
- It does not use network access.
- During normal operation, it stores only operational log entries such as
  startup, shutdown, mode changes, and errors.
- The explicit tray-menu `IME diagnostics` action additionally logs technical
  IME/window metadata such as process name, PID/TID, HWND, window class, HKL,
  IMM conversion flags, and decision reason. It does not log typed text, window
  titles, URLs, clipboard contents, command lines, or full filesystem paths.
- Console output and logs may contain local filesystem paths. Redact those paths
  before posting public reports.

## Execution Model

The daemon uses PowerShell `Add-Type` to compile embedded C# and call Win32 APIs
for a low-level keyboard hook and `SendInput`. Review the script before running
it in a sensitive environment.

Normal use is intended to run as the current user without administrator rights.
It may not work against elevated applications or UAC secure desktop prompts.

## Reporting Issues

Use GitHub private vulnerability reporting if it is enabled for the repository.
If it is not enabled, open a minimal public issue that asks for a private contact
channel without including exploit details.

For any security-sensitive report, avoid including typed text, screenshots with
private content, organization-specific policy details, or logs that contain
private local paths.
