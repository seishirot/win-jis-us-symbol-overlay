param(
    [ValidateSet("JIS", "US")]
    [string]$StartMode = "JIS",

    [switch]$CapsLockAsCtrl,

    [ValidateSet("Auto", "ASCII", "Fullwidth")]
    [string]$SymbolWidth = "Auto",

    [ValidateSet("Japanese", "Literal")]
    [string]$FullwidthStyle = "Japanese",

    [ValidateSet("On", "Off")]
    [string]$ShortcutOverlay = "On",

    [switch]$Install,
    [switch]$Uninstall,
    [switch]$CreateShortcuts,
    [switch]$SelfTest,

    [string]$LogPath = "$env:LOCALAPPDATA\win-jis-us-symbol-overlay\daemon.log"
)

$ErrorActionPreference = "Stop"

$TaskName = "win-jis-us-symbol-overlay"
$ShortcutName = "win-jis-us-symbol-overlay.lnk"

function Get-ThisScriptPath {
    if ($PSCommandPath) {
        return $PSCommandPath
    }

    return $MyInvocation.MyCommand.Path
}

function Get-WindowsPowerShellPath {
    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return "powershell.exe"
}

function Get-StartupShortcutPath {
    $startup = [Environment]::GetFolderPath("Startup")
    return Join-Path $startup $ShortcutName
}

function Get-IconPathForScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $scriptDir = Split-Path -Parent $ScriptPath
    if (-not $scriptDir) {
        return $null
    }

    $iconPath = Join-Path $scriptDir "assets\win-jis-us-symbol-overlay.ico"
    if (Test-Path -LiteralPath $iconPath) {
        return $iconPath
    }

    return $null
}

function New-DaemonArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [ValidateSet("JIS", "US")]
        [string]$StartMode = "JIS",

        [bool]$CapsLockAsCtrl,

        [ValidateSet("Auto", "ASCII", "Fullwidth")]
        [string]$SymbolWidth = "Auto",

        [ValidateSet("Japanese", "Literal")]
        [string]$FullwidthStyle = "Japanese",

        [ValidateSet("On", "Off")]
        [string]$ShortcutOverlay = "On"
    )

    $arguments = '-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ScriptPath
    if ($StartMode -eq "US") {
        $arguments += " -StartMode US"
    }

    if ($CapsLockAsCtrl) {
        $arguments += " -CapsLockAsCtrl"
    }

    if ($SymbolWidth -ne "Auto") {
        $arguments += " -SymbolWidth $SymbolWidth"
    }

    if ($FullwidthStyle -ne "Japanese") {
        $arguments += " -FullwidthStyle $FullwidthStyle"
    }

    if ($ShortcutOverlay -ne "On") {
        $arguments += " -ShortcutOverlay $ShortcutOverlay"
    }

    return $arguments
}

function Install-StartupShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [string]$IconPath
    )

    $shortcutPath = Get-StartupShortcutPath
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $PowerShellPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.WindowStyle = 7
    $shortcut.Description = "win-jis-us-symbol-overlay tray daemon"
    if ($IconPath) {
        $shortcut.IconLocation = "$IconPath,0"
    }

    $shortcut.Save()

    Write-Host "Created startup shortcut: $shortcutPath"
}

function New-LaunchShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [string]$IconPath
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $PowerShellPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.WindowStyle = 7
    $shortcut.Description = $Description
    if ($IconPath) {
        $shortcut.IconLocation = "$IconPath,0"
    }

    $shortcut.Save()
    Write-Host "Created launcher shortcut: $ShortcutPath"
}

function Install-WinJisUsSymbolOverlayDaemon {
    $scriptPath = Get-ThisScriptPath
    if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath)) {
        throw "Cannot resolve this script path. Save the script before running -Install."
    }

    $powerShellPath = Get-WindowsPowerShellPath
    $iconPath = Get-IconPathForScript -ScriptPath $scriptPath
    $arguments = New-DaemonArguments -ScriptPath $scriptPath -StartMode $StartMode -CapsLockAsCtrl ([bool]$CapsLockAsCtrl) -SymbolWidth $SymbolWidth -FullwidthStyle $FullwidthStyle -ShortcutOverlay $ShortcutOverlay

    try {
        $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal = New-ScheduledTaskPrincipal `
            -UserId $user `
            -LogonType Interactive `
            -RunLevel Limited

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Manual US symbol overlay for JIS Windows keyboard layout" `
            -Force | Out-Null

        $shortcutPath = Get-StartupShortcutPath
        if (Test-Path -LiteralPath $shortcutPath) {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Host "Removed fallback startup shortcut: $shortcutPath"
        }

        Write-Host "Registered scheduled task: $TaskName"
        return
    }
    catch {
        Write-Warning "Scheduled task registration failed: $($_.Exception.Message)"
        Write-Warning "Falling back to the Startup folder shortcut."
    }

    Install-StartupShortcut -ScriptPath $scriptPath -PowerShellPath $powerShellPath -Arguments $arguments -IconPath $iconPath
}

function New-WinJisUsSymbolOverlayLaunchShortcuts {
    $scriptPath = Get-ThisScriptPath
    if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath)) {
        throw "Cannot resolve this script path. Save the script before running -CreateShortcuts."
    }

    $scriptDir = Split-Path -Parent $scriptPath
    $powerShellPath = Get-WindowsPowerShellPath
    $iconPath = Get-IconPathForScript -ScriptPath $scriptPath

    New-LaunchShortcut `
        -ShortcutPath (Join-Path $scriptDir "win-jis-us-symbol-overlay.lnk") `
        -ScriptPath $scriptPath `
        -PowerShellPath $powerShellPath `
        -Arguments (New-DaemonArguments -ScriptPath $scriptPath -StartMode US -CapsLockAsCtrl $true -SymbolWidth $SymbolWidth -FullwidthStyle $FullwidthStyle -ShortcutOverlay $ShortcutOverlay) `
        -Description "Start win-jis-us-symbol-overlay with US overlay ON" `
        -IconPath $iconPath
}

function Uninstall-WinJisUsSymbolOverlayDaemon {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Removed scheduled task: $TaskName"
        }
    }
    catch {
        Write-Warning "Scheduled task removal failed: $($_.Exception.Message)"
    }

    $shortcutPath = Get-StartupShortcutPath
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host "Removed startup shortcut: $shortcutPath"
    }
}

if ($Install) {
    Install-WinJisUsSymbolOverlayDaemon
    return
}

if ($Uninstall) {
    Uninstall-WinJisUsSymbolOverlayDaemon
    return
}

if ($CreateShortcuts) {
    New-WinJisUsSymbolOverlayLaunchShortcuts
    return
}

$startupLogPath = $LogPath
function Write-StartupLog {
    param([string]$Message)

    try {
        $logDir = Split-Path -Parent $startupLogPath
        if ($logDir) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }

        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -LiteralPath $startupLogPath -Value $line -Encoding UTF8
    }
    catch {
        # Startup logging is best-effort.
    }
}

if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-StartupLog "Fatal initialization error: PowerShell LanguageMode is '$($ExecutionContext.SessionState.LanguageMode)'."
    throw "PowerShell LanguageMode is '$($ExecutionContext.SessionState.LanguageMode)'. This script needs FullLanguage because it uses Add-Type."
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-StartupLog "Fatal initialization error while loading assemblies: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    throw
}

$source = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace WinJisUsSymbolOverlay
{
    internal static class Logger
    {
        private static readonly object SyncRoot = new object();
        private static string logPath;

        public static string LogPath
        {
            get { return logPath; }
        }

        public static void Configure(string path)
        {
            if (String.IsNullOrWhiteSpace(path))
            {
                throw new ArgumentException("Log path is empty.", "path");
            }

            logPath = path;
            string dir = Path.GetDirectoryName(logPath);
            if (!String.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }
        }

        public static void Write(string message)
        {
            try
            {
                lock (SyncRoot)
                {
                    File.AppendAllText(
                        logPath,
                        "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message + Environment.NewLine
                    );
                }
            }
            catch
            {
                // Logging must never break keyboard input.
            }
        }

        public static void WriteBlock(string message)
        {
            if (message == null)
            {
                return;
            }

            string normalized = message.Replace("\r\n", "\n").Replace("\r", "\n");
            string[] lines = normalized.Split('\n');
            foreach (string line in lines)
            {
                if (line.Length > 0)
                {
                    Write(line);
                }
            }
        }
    }

    internal enum SymbolWidthMode
    {
        Auto,
        Ascii,
        Fullwidth
    }

    internal enum FullwidthStyleMode
    {
        Japanese,
        Literal
    }

    internal enum SymbolWidthDecision
    {
        Ascii,
        Fullwidth,
        Unknown
    }

    internal sealed class ImeProbeResult
    {
        public string Source;
        public string Method;
        public IntPtr TargetHwnd;
        public IntPtr ContextHwnd;
        public IntPtr ImeWindowHwnd;
        public bool ContextAvailable;
        public int ContextError;
        public bool OpenAvailable;
        public bool Open;
        public int OpenError;
        public bool ConversionAvailable;
        public int Conversion;
        public int Sentence;
        public int ConversionError;
        public bool TimedOut;
        public SymbolWidthDecision Decision;
        public string Reason;
    }

    internal static class NativeMethods
    {
        public const int WH_KEYBOARD_LL = 13;
        public const int WM_KEYDOWN = 0x0100;
        public const int WM_KEYUP = 0x0101;
        public const int WM_SYSKEYDOWN = 0x0104;
        public const int WM_SYSKEYUP = 0x0105;
        public const uint WM_IME_CONTROL = 0x0283;
        public const int WM_HOTKEY = 0x0312;

        public const int VK_SHIFT = 0x10;
        public const int VK_CONTROL = 0x11;
        public const int VK_MENU = 0x12;
        public const int VK_LSHIFT = 0xA0;
        public const int VK_RSHIFT = 0xA1;
        public const int VK_LCONTROL = 0xA2;
        public const int VK_RCONTROL = 0xA3;
        public const int VK_LMENU = 0xA4;
        public const int VK_RMENU = 0xA5;
        public const int VK_LWIN = 0x5B;
        public const int VK_RWIN = 0x5C;
        public const int VK_F12 = 0x7B;
        public const int VK_CAPITAL = 0x14;
        public const int VK_OEM_1 = 0xBA;
        public const int VK_OEM_PLUS = 0xBB;
        public const int VK_OEM_MINUS = 0xBD;
        public const int VK_OEM_2 = 0xBF;
        public const int VK_OEM_3 = 0xC0;
        public const int VK_OEM_4 = 0xDB;
        public const int VK_OEM_5 = 0xDC;
        public const int VK_OEM_6 = 0xDD;
        public const int VK_OEM_7 = 0xDE;

        public const ushort SC_LEFT_CONTROL = 0x1D;

        public const int LLKHF_EXTENDED = 0x01;
        public const int LLKHF_LOWER_IL_INJECTED = 0x02;
        public const int LLKHF_INJECTED = 0x10;
        public const int LLKHF_ALTDOWN = 0x20;
        public const int LLKHF_UP = 0x80;

        public const int INPUT_KEYBOARD = 1;
        public const int KEYEVENTF_EXTENDEDKEY = 0x0001;
        public const int KEYEVENTF_KEYUP = 0x0002;
        public const int KEYEVENTF_UNICODE = 0x0004;
        public const int KEYEVENTF_SCANCODE = 0x0008;

        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_NOREPEAT = 0x4000;

        public const uint SMTO_ABORTIFHUNG = 0x0002;
        public const uint SMTO_ERRORONEXIT = 0x0020;
        public const int ERROR_TIMEOUT = 1460;

        public const int IMC_GETCONVERSIONMODE = 0x0001;
        public const int IMC_GETSENTENCEMODE = 0x0003;
        public const int IMC_GETOPENSTATUS = 0x0005;

        public const int IME_CMODE_NATIVE = 0x0001;
        public const int IME_CMODE_KATAKANA = 0x0002;
        public const int IME_CMODE_ROMAN = 0x0010;
        public const int IME_CMODE_CHARCODE = 0x0020;
        public const int IME_CMODE_HANJACONVERT = 0x0040;
        public const int IME_CMODE_SOFTKBD = 0x0080;
        public const int IME_CMODE_NOCONVERSION = 0x0100;
        public const int IME_CMODE_EUDC = 0x0200;
        public const int IME_CMODE_SYMBOL = 0x0400;
        public const int IME_CMODE_FIXED = 0x0800;
        public const int IME_CMODE_FULLSHAPE = 0x0008;

        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public int type;
            public INPUTUNION U;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION
        {
            [FieldOffset(0)]
            public MOUSEINPUT mi;

            [FieldOffset(0)]
            public KEYBDINPUT ki;

            [FieldOffset(0)]
            public HARDWAREINPUT hi;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct GUITHREADINFO
        {
            public int cbSize;
            public int flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern IntPtr GetKeyboardLayout(uint idThread);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

        [DllImport("kernel32.dll")]
        public static extern void SetLastError(uint dwErrCode);

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern IntPtr ImmGetContext(IntPtr hWnd);

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern bool ImmGetOpenStatus(IntPtr hIMC);

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern bool ImmGetConversionStatus(IntPtr hIMC, out int conversion, out int sentence);

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern bool ImmReleaseContext(IntPtr hWnd, IntPtr hIMC);

        [DllImport("imm32.dll", SetLastError = true)]
        public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

        [DllImport("imm32.dll")]
        public static extern bool ImmIsIME(IntPtr hkl);
    }

    internal static class KeyboardHook
    {
        private struct ShortcutRemapState
        {
            public int ScanCode;
            public bool Extended;
            public ushort TargetVirtualKey;
        }

        private static IntPtr hookHandle = IntPtr.Zero;
        private static NativeMethods.LowLevelKeyboardProc hookProc = HookCallback;
        private static readonly IntPtr selfInjectedExtraInfo = new IntPtr(0x574A5553);
        private static readonly object shortcutSyncRoot = new object();
        private static bool usMode;
        private static bool capsLockAsCtrl;
        private static bool shortcutOverlay = true;
        private static SymbolWidthMode symbolWidthMode = SymbolWidthMode.Auto;
        private static FullwidthStyleMode fullwidthStyleMode = FullwidthStyleMode.Japanese;
        private static bool capsLockCtrlDown;
        private static bool capsLockCtrlReleasePending;
        private static bool capsLockPhysicalDown;
        private static bool capsLockPassThrough;
        private static bool physicalLeftCtrlDown;
        private static bool physicalRightCtrlDown;
        private static bool physicalLeftAltDown;
        private static bool physicalRightAltDown;
        private static bool physicalLeftWinDown;
        private static bool physicalRightWinDown;
        private static bool physicalLeftShiftDown;
        private static bool physicalRightShiftDown;
        private static Func<ushort, bool, string, bool> shortcutKeySender = SendShortcutVirtualKey;
        private static readonly System.Collections.Generic.HashSet<int> suppressedScanCodes =
            new System.Collections.Generic.HashSet<int>();
        private static readonly System.Collections.Generic.Dictionary<int, ShortcutRemapState> activeShortcutRemaps =
            new System.Collections.Generic.Dictionary<int, ShortcutRemapState>();
        private static readonly System.Collections.Generic.HashSet<ushort> pendingShortcutKeyUps =
            new System.Collections.Generic.HashSet<ushort>();
        private static readonly System.Collections.Generic.HashSet<int> releasedShortcutRemapKeys =
            new System.Collections.Generic.HashSet<int>();
        private static readonly object autoDecisionCacheSyncRoot = new object();
        private static readonly TimeSpan autoDecisionCacheTtl = TimeSpan.FromMilliseconds(150);
        private static IntPtr cachedAutoDecisionHwnd = IntPtr.Zero;
        private static DateTime cachedAutoDecisionExpiresUtc = DateTime.MinValue;
        private static ImeProbeResult cachedAutoDecision;
        private static DateTime lastSendInputFailureUtc = DateTime.MinValue;
        private static DateTime lastShortcutKeyUpFailureUtc = DateTime.MinValue;
        private static DateTime lastHookFailureUtc = DateTime.MinValue;
        private static DateTime lastCapsLockCtrlReleaseWarningUtc = DateTime.MinValue;

        public static bool UsMode
        {
            get { return usMode; }
        }

        public static bool CapsLockAsCtrl
        {
            get { return capsLockAsCtrl; }
        }

        public static bool ShortcutOverlay
        {
            get { return shortcutOverlay; }
        }

        public static SymbolWidthMode SymbolWidth
        {
            get { return symbolWidthMode; }
        }

        public static FullwidthStyleMode FullwidthStyle
        {
            get { return fullwidthStyleMode; }
        }

        public static void SetUsMode(bool enabled, string reason)
        {
            if (usMode == enabled)
            {
                return;
            }

            usMode = enabled;
            if (!usMode)
            {
                ReleaseAllShortcutTargets("US overlay disabled", true);
            }

            Logger.Write("US overlay " + (usMode ? "ON" : "OFF") + ". reason=" + reason);
        }

        public static void SetCapsLockAsCtrl(bool enabled, string reason)
        {
            if (capsLockAsCtrl == enabled)
            {
                return;
            }

            capsLockAsCtrl = enabled;
            if (!capsLockAsCtrl)
            {
                ReleaseCapsLockCtrl("disabled");
                capsLockPhysicalDown = false;
                capsLockPassThrough = false;
            }

            Logger.Write("CapsLock as Ctrl " + (capsLockAsCtrl ? "ON" : "OFF") + ". reason=" + reason);
        }

        public static void SetShortcutOverlayMode(string mode, string reason)
        {
            bool enabled;
            if (!TryParseOnOffMode(mode, out enabled))
            {
                throw new ArgumentException("Unknown shortcut overlay mode: " + mode, "mode");
            }

            if (shortcutOverlay == enabled)
            {
                return;
            }

            shortcutOverlay = enabled;
            if (!shortcutOverlay)
            {
                ReleaseAllShortcutTargets("shortcut overlay disabled", true);
            }

            Logger.Write("Shortcut overlay " + (shortcutOverlay ? "ON" : "OFF") + ". reason=" + reason);
        }

        private static bool TryParseOnOffMode(string mode, out bool enabled)
        {
            if (String.Equals(mode, "On", StringComparison.OrdinalIgnoreCase))
            {
                enabled = true;
                return true;
            }

            if (String.Equals(mode, "Off", StringComparison.OrdinalIgnoreCase))
            {
                enabled = false;
                return true;
            }

            enabled = true;
            return false;
        }

        public static void SetSymbolWidthMode(string mode, string reason)
        {
            SymbolWidthMode parsed;
            if (!TryParseSymbolWidthMode(mode, out parsed))
            {
                throw new ArgumentException("Unknown symbol width mode: " + mode, "mode");
            }

            if (symbolWidthMode == parsed)
            {
                return;
            }

            symbolWidthMode = parsed;
            Logger.Write("Symbol width mode " + GetSymbolWidthModeLabel(symbolWidthMode) + ". reason=" + reason);
        }

        public static string GetSymbolWidthModeLabel(SymbolWidthMode mode)
        {
            if (mode == SymbolWidthMode.Ascii)
            {
                return "ASCII";
            }

            return mode.ToString();
        }

        private static bool TryParseSymbolWidthMode(string mode, out SymbolWidthMode parsed)
        {
            if (String.Equals(mode, "Auto", StringComparison.OrdinalIgnoreCase))
            {
                parsed = SymbolWidthMode.Auto;
                return true;
            }

            if (String.Equals(mode, "ASCII", StringComparison.OrdinalIgnoreCase) ||
                String.Equals(mode, "Ascii", StringComparison.OrdinalIgnoreCase))
            {
                parsed = SymbolWidthMode.Ascii;
                return true;
            }

            if (String.Equals(mode, "Fullwidth", StringComparison.OrdinalIgnoreCase))
            {
                parsed = SymbolWidthMode.Fullwidth;
                return true;
            }

            parsed = SymbolWidthMode.Auto;
            return false;
        }

        public static void SetFullwidthStyleMode(string style, string reason)
        {
            FullwidthStyleMode parsed;
            if (!TryParseFullwidthStyleMode(style, out parsed))
            {
                throw new ArgumentException("Unknown fullwidth style mode: " + style, "style");
            }

            if (fullwidthStyleMode == parsed)
            {
                return;
            }

            fullwidthStyleMode = parsed;
            Logger.Write("Fullwidth style " + fullwidthStyleMode.ToString() + ". reason=" + reason);
        }

        private static bool TryParseFullwidthStyleMode(string style, out FullwidthStyleMode parsed)
        {
            if (String.Equals(style, "Japanese", StringComparison.OrdinalIgnoreCase))
            {
                parsed = FullwidthStyleMode.Japanese;
                return true;
            }

            if (String.Equals(style, "Literal", StringComparison.OrdinalIgnoreCase))
            {
                parsed = FullwidthStyleMode.Literal;
                return true;
            }

            parsed = FullwidthStyleMode.Japanese;
            return false;
        }

        public static void Install()
        {
            if (hookHandle != IntPtr.Zero)
            {
                return;
            }

            InitializeModifierState();

            IntPtr moduleHandle = NativeMethods.GetModuleHandle(null);
            hookHandle = NativeMethods.SetWindowsHookEx(
                NativeMethods.WH_KEYBOARD_LL,
                hookProc,
                moduleHandle,
                0
            );

            if (hookHandle == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWindowsHookEx failed.");
            }

            Logger.Write("Keyboard hook installed.");
        }

        public static void Uninstall()
        {
            if (hookHandle == IntPtr.Zero)
            {
                return;
            }

            ReleaseAllShortcutTargets("hook uninstall", true);
            ReleaseCapsLockCtrl("hook uninstall");

            if (!NativeMethods.UnhookWindowsHookEx(hookHandle))
            {
                Logger.Write("UnhookWindowsHookEx failed. error=" + Marshal.GetLastWin32Error().ToString());
            }
            else
            {
                Logger.Write("Keyboard hook uninstalled.");
            }

            hookHandle = IntPtr.Zero;
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                return HookCallbackCore(nCode, wParam, lParam);
            }
            catch (Exception ex)
            {
                try
                {
                    ReleaseAllShortcutTargets("hook callback exception", true);
                }
                catch
                {
                    // Hook failure cleanup is best-effort.
                }

                DateTime now = DateTime.UtcNow;
                if ((now - lastHookFailureUtc).TotalSeconds > 5)
                {
                    lastHookFailureUtc = now;
                    Logger.Write("Hook callback failed open. error=" + ex.GetType().FullName + " message=" + ex.Message);
                }

                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }
        }

        private static IntPtr HookCallbackCore(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode < 0)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            int message = wParam.ToInt32();
            bool isKeyDown = message == NativeMethods.WM_KEYDOWN || message == NativeMethods.WM_SYSKEYDOWN;
            bool isKeyUp = message == NativeMethods.WM_KEYUP || message == NativeMethods.WM_SYSKEYUP;

            if (!isKeyDown && !isKeyUp)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            NativeMethods.KBDLLHOOKSTRUCT info =
                (NativeMethods.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(
                    lParam,
                    typeof(NativeMethods.KBDLLHOOKSTRUCT)
                );

            if (IsSelfInjectedEvent(info))
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            if ((info.flags & NativeMethods.LLKHF_INJECTED) != 0)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            int scanCode = (int)info.scanCode;
            int vkCode = (int)info.vkCode;
            bool isExtended = (info.flags & NativeMethods.LLKHF_EXTENDED) != 0;

            UpdateModifierState(vkCode, scanCode, isExtended, isKeyDown, isKeyUp);
            RetryPendingCapsLockCtrlRelease("hook event");
            EnsureCapsLockCtrlDownForHeldCaps("physical Ctrl released while CapsLock held");
            RetryPendingShortcutKeyUps("hook event");

            if (HandleCapsLockAsCtrl(vkCode, isKeyDown, isKeyUp))
            {
                return new IntPtr(1);
            }

            bool shortcutSuppress;
            bool canStartShortcutRemap =
                usMode &&
                shortcutOverlay &&
                ShouldStartShortcutRemap(IsShortcutCtrlDown(), IsAltDown(), IsWinDown());
            if (TryHandleShortcutOverlayEvent(scanCode, isExtended, isKeyDown, isKeyUp, canStartShortcutRemap, out shortcutSuppress))
            {
                return new IntPtr(1);
            }

            if (isKeyUp && !isExtended && suppressedScanCodes.Contains(scanCode))
            {
                suppressedScanCodes.Remove(scanCode);
                return new IntPtr(1);
            }

            if (!usMode)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            if (!isKeyDown)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            if (IsShortcutCtrlDown() || IsAltDown() || IsWinDown())
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            if (isExtended)
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            char mapped;
            bool shiftDown = IsShiftDown();
            if (!TryMapScanCode(scanCode, shiftDown, false, FullwidthStyleMode.Literal, out mapped))
            {
                return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
            }

            if (ShouldUseFullWidthSymbols())
            {
                TryMapScanCode(scanCode, shiftDown, true, fullwidthStyleMode, out mapped);
            }

            if (SendUnicodeChar(mapped))
            {
                suppressedScanCodes.Add(scanCode);
                return new IntPtr(1);
            }

            return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
        }

        private static bool IsSelfInjectedEvent(NativeMethods.KBDLLHOOKSTRUCT info)
        {
            return info.dwExtraInfo == selfInjectedExtraInfo;
        }

        private static void InitializeModifierState()
        {
            physicalLeftCtrlDown = IsVirtualKeyDown(NativeMethods.VK_LCONTROL);
            physicalRightCtrlDown = IsVirtualKeyDown(NativeMethods.VK_RCONTROL);
            physicalLeftAltDown = IsVirtualKeyDown(NativeMethods.VK_LMENU);
            physicalRightAltDown = IsVirtualKeyDown(NativeMethods.VK_RMENU);
            physicalLeftWinDown = IsVirtualKeyDown(NativeMethods.VK_LWIN);
            physicalRightWinDown = IsVirtualKeyDown(NativeMethods.VK_RWIN);
            physicalLeftShiftDown = IsVirtualKeyDown(NativeMethods.VK_LSHIFT);
            physicalRightShiftDown = IsVirtualKeyDown(NativeMethods.VK_RSHIFT);
        }

        private static bool IsVirtualKeyDown(int virtualKey)
        {
            return (NativeMethods.GetAsyncKeyState(virtualKey) & unchecked((short)0x8000)) != 0;
        }

        private static void UpdateModifierState(int vkCode, int scanCode, bool isExtended, bool isKeyDown, bool isKeyUp)
        {
            if (!isKeyDown && !isKeyUp)
            {
                return;
            }

            bool down = isKeyDown;
            if (vkCode == NativeMethods.VK_LCONTROL ||
                (vkCode == NativeMethods.VK_CONTROL && !isExtended))
            {
                physicalLeftCtrlDown = down;
            }
            else if (vkCode == NativeMethods.VK_RCONTROL ||
                (vkCode == NativeMethods.VK_CONTROL && isExtended))
            {
                physicalRightCtrlDown = down;
            }
            else if (vkCode == NativeMethods.VK_LMENU ||
                (vkCode == NativeMethods.VK_MENU && !isExtended))
            {
                physicalLeftAltDown = down;
            }
            else if (vkCode == NativeMethods.VK_RMENU ||
                (vkCode == NativeMethods.VK_MENU && isExtended))
            {
                physicalRightAltDown = down;
            }
            else if (vkCode == NativeMethods.VK_LWIN)
            {
                physicalLeftWinDown = down;
            }
            else if (vkCode == NativeMethods.VK_RWIN)
            {
                physicalRightWinDown = down;
            }
            else if (vkCode == NativeMethods.VK_LSHIFT ||
                (vkCode == NativeMethods.VK_SHIFT && scanCode == 0x2A))
            {
                physicalLeftShiftDown = down;
            }
            else if (vkCode == NativeMethods.VK_RSHIFT ||
                (vkCode == NativeMethods.VK_SHIFT && scanCode == 0x36))
            {
                physicalRightShiftDown = down;
            }
        }

        private static bool IsShortcutCtrlDown()
        {
            return physicalLeftCtrlDown || physicalRightCtrlDown || capsLockCtrlDown;
        }

        private static bool IsAltDown()
        {
            return physicalLeftAltDown || physicalRightAltDown;
        }

        private static bool IsWinDown()
        {
            return physicalLeftWinDown || physicalRightWinDown;
        }

        private static bool IsShiftDown()
        {
            return physicalLeftShiftDown || physicalRightShiftDown;
        }

        private static bool ShouldStartShortcutRemap(bool ctrlDown, bool altDown, bool winDown)
        {
            return ctrlDown && !altDown && !winDown;
        }

        private static bool TryHandleShortcutOverlayEvent(int scanCode, bool isExtended, bool isKeyDown, bool isKeyUp, bool canStartNewRemap, out bool suppress)
        {
            suppress = false;

            int key = GetShortcutRemapKey(scanCode, isExtended);
            bool releasedBeforeKeyUp;
            lock (shortcutSyncRoot)
            {
                releasedBeforeKeyUp = releasedShortcutRemapKeys.Contains(key);
                if (releasedBeforeKeyUp && isKeyUp)
                {
                    releasedShortcutRemapKeys.Remove(key);
                }
            }

            if (releasedBeforeKeyUp)
            {
                suppress = true;
                return true;
            }

            ShortcutRemapState active;
            bool hasActive;
            lock (shortcutSyncRoot)
            {
                hasActive = activeShortcutRemaps.TryGetValue(key, out active);
            }

            if (hasActive)
            {
                suppress = true;

                if (isKeyUp)
                {
                    lock (shortcutSyncRoot)
                    {
                        activeShortcutRemaps.Remove(key);
                    }

                    if (!shortcutKeySender(active.TargetVirtualKey, true, "shortcut key up"))
                    {
                        AddPendingShortcutKeyUp(active.TargetVirtualKey);
                        LogShortcutKeyUpFailure(active.TargetVirtualKey, "shortcut key up");
                    }

                    return true;
                }

                if (isKeyDown)
                {
                    if (!shortcutKeySender(active.TargetVirtualKey, false, "shortcut repeat key down"))
                    {
                        LogShortcutKeyDownFailure(active.TargetVirtualKey, "shortcut repeat key down");
                    }

                    return true;
                }

                return true;
            }

            if (!isKeyDown || !canStartNewRemap || isExtended)
            {
                return false;
            }

            ushort targetVirtualKey;
            if (!TryMapShortcutScanCode(scanCode, out targetVirtualKey))
            {
                return false;
            }

            if (!shortcutKeySender(targetVirtualKey, false, "shortcut key down"))
            {
                LogShortcutKeyDownFailure(targetVirtualKey, "shortcut key down");
                return false;
            }

            ShortcutRemapState state = new ShortcutRemapState();
            state.ScanCode = scanCode;
            state.Extended = isExtended;
            state.TargetVirtualKey = targetVirtualKey;

            lock (shortcutSyncRoot)
            {
                activeShortcutRemaps[key] = state;
            }

            suppress = true;
            return true;
        }

        private static int GetShortcutRemapKey(int scanCode, bool isExtended)
        {
            return (isExtended ? 0x10000 : 0) | (scanCode & 0xFFFF);
        }

        private static bool TryMapShortcutScanCode(int scanCode, out ushort targetVirtualKey)
        {
            switch (scanCode)
            {
                case 0x0C:
                    targetVirtualKey = NativeMethods.VK_OEM_MINUS;
                    return true;
                case 0x0D:
                    targetVirtualKey = NativeMethods.VK_OEM_PLUS;
                    return true;
                case 0x1A:
                    targetVirtualKey = NativeMethods.VK_OEM_4;
                    return true;
                case 0x1B:
                    targetVirtualKey = NativeMethods.VK_OEM_6;
                    return true;
                case 0x2B:
                    targetVirtualKey = NativeMethods.VK_OEM_5;
                    return true;
                case 0x27:
                    targetVirtualKey = NativeMethods.VK_OEM_1;
                    return true;
                case 0x28:
                    targetVirtualKey = NativeMethods.VK_OEM_7;
                    return true;
                case 0x29:
                    targetVirtualKey = NativeMethods.VK_OEM_3;
                    return true;
                case 0x35:
                    targetVirtualKey = NativeMethods.VK_OEM_2;
                    return true;
                default:
                    targetVirtualKey = 0;
                    return false;
            }
        }

        private static void AddPendingShortcutKeyUp(ushort targetVirtualKey)
        {
            lock (shortcutSyncRoot)
            {
                pendingShortcutKeyUps.Add(targetVirtualKey);
            }
        }

        public static void RetryPendingShortcutKeyUps(string reason)
        {
            ushort[] pending;
            lock (shortcutSyncRoot)
            {
                if (pendingShortcutKeyUps.Count == 0)
                {
                    return;
                }

                pending = new ushort[pendingShortcutKeyUps.Count];
                pendingShortcutKeyUps.CopyTo(pending);
            }

            for (int i = 0; i < pending.Length; i++)
            {
                ushort targetVirtualKey = pending[i];
                if (shortcutKeySender(targetVirtualKey, true, reason + " pending shortcut key up"))
                {
                    lock (shortcutSyncRoot)
                    {
                        pendingShortcutKeyUps.Remove(targetVirtualKey);
                    }
                }
                else
                {
                    LogShortcutKeyUpFailure(targetVirtualKey, reason + " pending shortcut key up");
                }
            }
        }

        private static void ReleaseAllShortcutTargets(string reason, bool keepPendingFailures)
        {
            System.Collections.Generic.HashSet<ushort> targetKeys = new System.Collections.Generic.HashSet<ushort>();
            lock (shortcutSyncRoot)
            {
                foreach (int activeKey in activeShortcutRemaps.Keys)
                {
                    releasedShortcutRemapKeys.Add(activeKey);
                }

                foreach (ShortcutRemapState state in activeShortcutRemaps.Values)
                {
                    targetKeys.Add(state.TargetVirtualKey);
                }

                activeShortcutRemaps.Clear();

                foreach (ushort targetVirtualKey in pendingShortcutKeyUps)
                {
                    targetKeys.Add(targetVirtualKey);
                }

                pendingShortcutKeyUps.Clear();
            }

            foreach (ushort targetVirtualKey in targetKeys)
            {
                if (!shortcutKeySender(targetVirtualKey, true, reason + " shortcut key cleanup"))
                {
                    if (keepPendingFailures)
                    {
                        AddPendingShortcutKeyUp(targetVirtualKey);
                    }

                    LogShortcutKeyUpFailure(targetVirtualKey, reason + " shortcut key cleanup");
                }
            }
        }

        private static int GetActiveShortcutRemapCountForSelfTest()
        {
            lock (shortcutSyncRoot)
            {
                return activeShortcutRemaps.Count;
            }
        }

        private static int GetPendingShortcutKeyUpCountForSelfTest()
        {
            lock (shortcutSyncRoot)
            {
                return pendingShortcutKeyUps.Count;
            }
        }

        private static void ResetShortcutStateForSelfTest()
        {
            lock (shortcutSyncRoot)
            {
                activeShortcutRemaps.Clear();
                pendingShortcutKeyUps.Clear();
                releasedShortcutRemapKeys.Clear();
            }

            suppressedScanCodes.Clear();
            capsLockCtrlDown = false;
            capsLockCtrlReleasePending = false;
            capsLockPhysicalDown = false;
            capsLockPassThrough = false;
            physicalLeftCtrlDown = false;
            physicalRightCtrlDown = false;
            physicalLeftAltDown = false;
            physicalRightAltDown = false;
            physicalLeftWinDown = false;
            physicalRightWinDown = false;
            physicalLeftShiftDown = false;
            physicalRightShiftDown = false;
        }

        private static bool ShouldUseFullWidthSymbols()
        {
            if (symbolWidthMode == SymbolWidthMode.Fullwidth)
            {
                return true;
            }

            if (symbolWidthMode == SymbolWidthMode.Ascii)
            {
                return false;
            }

            return GetAutoSymbolWidthDecision().Decision == SymbolWidthDecision.Fullwidth;
        }

        private static ImeProbeResult GetAutoSymbolWidthDecision()
        {
            return GetAutoSymbolWidthDecision(true);
        }

        private static ImeProbeResult GetAutoSymbolWidthDecision(bool useCache)
        {
            IntPtr hWnd = GetImeContextWindow();
            DateTime now = DateTime.UtcNow;

            ImeProbeResult cached;
            if (useCache && TryGetCachedAutoDecision(hWnd, now, out cached))
            {
                return cached;
            }

            ImeProbeResult direct = ProbeDirectImm("auto-direct-focus", hWnd);
            if (direct.Decision != SymbolWidthDecision.Unknown)
            {
                if (useCache)
                {
                    CacheAutoDecision(hWnd, direct, now);
                }

                return direct;
            }

            ImeProbeResult fallback = ProbeDefaultImeWindow("auto-default-ime-focus", hWnd, false, 30);
            if (useCache)
            {
                CacheAutoDecision(hWnd, fallback, now);
            }

            return fallback;
        }

        private static bool TryGetCachedAutoDecision(IntPtr hWnd, DateTime now, out ImeProbeResult result)
        {
            lock (autoDecisionCacheSyncRoot)
            {
                if (hWnd != IntPtr.Zero &&
                    hWnd == cachedAutoDecisionHwnd &&
                    cachedAutoDecision != null &&
                    now <= cachedAutoDecisionExpiresUtc)
                {
                    result = cachedAutoDecision;
                    return true;
                }
            }

            result = null;
            return false;
        }

        private static void CacheAutoDecision(IntPtr hWnd, ImeProbeResult result, DateTime now)
        {
            lock (autoDecisionCacheSyncRoot)
            {
                cachedAutoDecisionHwnd = hWnd;
                cachedAutoDecision = result;
                cachedAutoDecisionExpiresUtc = now.Add(autoDecisionCacheTtl);
            }
        }

        private static ImeProbeResult ProbeDirectImm(string source, IntPtr hWnd)
        {
            ImeProbeResult result = NewUnknownProbe(source, "direct-imm", hWnd, "NO_TARGET_HWND");
            if (hWnd == IntPtr.Zero)
            {
                return result;
            }

            NativeMethods.SetLastError(0);
            IntPtr hImc = NativeMethods.ImmGetContext(hWnd);
            result.ContextError = Marshal.GetLastWin32Error();
            if (hImc == IntPtr.Zero)
            {
                result.Reason = "IMM_CONTEXT_UNAVAILABLE";
                return result;
            }

            result.ContextAvailable = true;
            result.ContextHwnd = hImc;
            try
            {
                NativeMethods.SetLastError(0);
                result.Open = NativeMethods.ImmGetOpenStatus(hImc);
                result.OpenError = Marshal.GetLastWin32Error();
                result.OpenAvailable = true;
                if (!result.Open)
                {
                    result.Decision = SymbolWidthDecision.Ascii;
                    result.Reason = "IME_CLOSED";
                    return result;
                }

                int conversion;
                int sentence;
                NativeMethods.SetLastError(0);
                if (!NativeMethods.ImmGetConversionStatus(hImc, out conversion, out sentence))
                {
                    result.ConversionError = Marshal.GetLastWin32Error();
                    result.Reason = "IMM_CONVERSION_UNAVAILABLE";
                    return result;
                }

                result.ConversionAvailable = true;
                result.Conversion = conversion;
                result.Sentence = sentence;
                ApplyConversionDecision(result);
                return result;
            }
            finally
            {
                NativeMethods.ImmReleaseContext(hWnd, hImc);
            }
        }

        private static ImeProbeResult ProbeDefaultImeWindow(string source, IntPtr hWnd, bool includeSentence, uint timeoutMs)
        {
            ImeProbeResult result = NewUnknownProbe(source, "default-ime-window", hWnd, "NO_TARGET_HWND");
            if (hWnd == IntPtr.Zero)
            {
                return result;
            }

            NativeMethods.SetLastError(0);
            IntPtr imeWindow = NativeMethods.ImmGetDefaultIMEWnd(hWnd);
            result.ContextError = Marshal.GetLastWin32Error();
            result.ImeWindowHwnd = imeWindow;
            if (imeWindow == IntPtr.Zero)
            {
                result.Reason = "DEFAULT_IME_WINDOW_UNAVAILABLE";
                return result;
            }

            result.ContextAvailable = true;

            IntPtr openValue;
            if (!TrySendImeControl(imeWindow, NativeMethods.IMC_GETOPENSTATUS, timeoutMs, out openValue, out result.OpenError, out result.TimedOut))
            {
                result.Reason = result.TimedOut ? "DEFAULT_IME_OPEN_TIMEOUT" : "DEFAULT_IME_OPEN_UNAVAILABLE";
                return result;
            }

            result.OpenAvailable = true;
            result.Open = openValue != IntPtr.Zero;
            if (!result.Open)
            {
                result.Decision = SymbolWidthDecision.Ascii;
                result.Reason = "IME_CLOSED";
                return result;
            }

            IntPtr conversionValue;
            if (!TrySendImeControl(imeWindow, NativeMethods.IMC_GETCONVERSIONMODE, timeoutMs, out conversionValue, out result.ConversionError, out result.TimedOut))
            {
                result.Reason = result.TimedOut ? "DEFAULT_IME_CONVERSION_TIMEOUT" : "DEFAULT_IME_CONVERSION_UNAVAILABLE";
                return result;
            }

            result.ConversionAvailable = true;
            result.Conversion = unchecked((int)conversionValue.ToInt64());

            if (includeSentence)
            {
                IntPtr sentenceValue;
                int sentenceError;
                bool sentenceTimedOut;
                if (TrySendImeControl(imeWindow, NativeMethods.IMC_GETSENTENCEMODE, timeoutMs, out sentenceValue, out sentenceError, out sentenceTimedOut))
                {
                    result.Sentence = unchecked((int)sentenceValue.ToInt64());
                }
            }

            ApplyConversionDecision(result);
            return result;
        }

        private static ImeProbeResult NewUnknownProbe(string source, string method, IntPtr hWnd, string reason)
        {
            ImeProbeResult result = new ImeProbeResult();
            result.Source = source;
            result.Method = method;
            result.TargetHwnd = hWnd;
            result.Decision = SymbolWidthDecision.Unknown;
            result.Reason = reason;
            return result;
        }

        private static bool TrySendImeControl(IntPtr imeWindow, int command, uint timeoutMs, out IntPtr value, out int lastError, out bool timedOut)
        {
            value = IntPtr.Zero;
            lastError = 0;
            timedOut = false;

            NativeMethods.SetLastError(0);
            IntPtr callResult = NativeMethods.SendMessageTimeout(
                imeWindow,
                NativeMethods.WM_IME_CONTROL,
                new IntPtr(command),
                IntPtr.Zero,
                NativeMethods.SMTO_ABORTIFHUNG | NativeMethods.SMTO_ERRORONEXIT,
                timeoutMs,
                out value
            );
            lastError = Marshal.GetLastWin32Error();
            if (callResult != IntPtr.Zero)
            {
                return true;
            }

            timedOut = IsSendMessageTimeoutError(lastError);
            return false;
        }

        private static bool IsSendMessageTimeoutError(int lastError)
        {
            return lastError == NativeMethods.ERROR_TIMEOUT;
        }

        private static void ApplyConversionDecision(ImeProbeResult result)
        {
            if (IsFullWidthImeConversionMode(result.Conversion))
            {
                result.Decision = SymbolWidthDecision.Fullwidth;
                result.Reason = GetFullWidthConversionReason(result.Conversion);
                return;
            }

            result.Decision = SymbolWidthDecision.Ascii;
            result.Reason = GetAsciiConversionReason(result.Conversion);
        }

        private static bool IsFullWidthImeConversionMode(int conversion)
        {
            if ((conversion & NativeMethods.IME_CMODE_FULLSHAPE) != 0)
            {
                return true;
            }

            bool native = (conversion & NativeMethods.IME_CMODE_NATIVE) != 0;
            bool katakana = (conversion & NativeMethods.IME_CMODE_KATAKANA) != 0;
            return native && !katakana;
        }

        private static string GetFullWidthConversionReason(int conversion)
        {
            if ((conversion & NativeMethods.IME_CMODE_FULLSHAPE) != 0)
            {
                return "FULLSHAPE";
            }

            return "NATIVE_NON_KATAKANA";
        }

        private static string GetAsciiConversionReason(int conversion)
        {
            bool native = (conversion & NativeMethods.IME_CMODE_NATIVE) != 0;
            bool katakana = (conversion & NativeMethods.IME_CMODE_KATAKANA) != 0;
            if (native && katakana)
            {
                return "NATIVE_KATAKANA_HALFSHAPE";
            }

            return "ALPHANUMERIC_OR_HALFSHAPE";
        }

        private static IntPtr GetImeContextWindow()
        {
            IntPtr foreground = NativeMethods.GetForegroundWindow();
            if (foreground == IntPtr.Zero)
            {
                return IntPtr.Zero;
            }

            uint processId;
            uint threadId = NativeMethods.GetWindowThreadProcessId(foreground, out processId);
            if (threadId == 0)
            {
                return foreground;
            }

            NativeMethods.GUITHREADINFO info = new NativeMethods.GUITHREADINFO();
            info.cbSize = Marshal.SizeOf(typeof(NativeMethods.GUITHREADINFO));
            if (NativeMethods.GetGUIThreadInfo(threadId, ref info) && info.hwndFocus != IntPtr.Zero)
            {
                return info.hwndFocus;
            }

            return foreground;
        }

        public static void LogImeDiagnostics()
        {
            try
            {
                Logger.WriteBlock(BuildImeDiagnostics());
            }
            catch (Exception ex)
            {
                Logger.Write("IME diagnostics failed. error=" + ex.GetType().FullName + " message=" + ex.Message);
            }
        }

        private static string BuildImeDiagnostics()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("IME diagnostics begin. No input text, window titles, URLs, clipboard, command lines, or full paths are logged.");
            sb.AppendLine("environment os=" + SafeLogValue(Environment.OSVersion.VersionString) + " process64=" + Environment.Is64BitProcess.ToString() + " os64=" + Environment.Is64BitOperatingSystem.ToString());
            sb.AppendLine("state usOverlay=" + usMode.ToString() + " capsLockAsCtrl=" + capsLockAsCtrl.ToString() + " shortcutOverlay=" + shortcutOverlay.ToString() + " symbolWidth=" + GetSymbolWidthModeLabel(symbolWidthMode) + " fullwidthStyle=" + fullwidthStyleMode.ToString());

            IntPtr foreground = NativeMethods.GetForegroundWindow();
            uint foregroundPid;
            uint foregroundTid = foreground == IntPtr.Zero ? 0 : NativeMethods.GetWindowThreadProcessId(foreground, out foregroundPid);

            NativeMethods.GUITHREADINFO info = new NativeMethods.GUITHREADINFO();
            info.cbSize = Marshal.SizeOf(typeof(NativeMethods.GUITHREADINFO));
            bool guiInfoOk = foregroundTid != 0 && NativeMethods.GetGUIThreadInfo(foregroundTid, ref info);
            int guiInfoError = guiInfoOk ? 0 : Marshal.GetLastWin32Error();

            IntPtr focus = guiInfoOk ? info.hwndFocus : IntPtr.Zero;
            IntPtr active = guiInfoOk ? info.hwndActive : IntPtr.Zero;
            IntPtr caret = guiInfoOk ? info.hwndCaret : IntPtr.Zero;
            sb.AppendLine("gui foreground=" + FormatHandle(foreground) + " foregroundTid=" + foregroundTid.ToString() + " getGuiThreadInfo=" + guiInfoOk.ToString() + " getGuiThreadInfoError=" + guiInfoError.ToString() + " active=" + FormatHandle(active) + " focus=" + FormatHandle(focus) + " caret=" + FormatHandle(caret));

            AppendWindowSummary(sb, "foreground", foreground);
            AppendWindowSummary(sb, "focus", focus);
            AppendWindowSummary(sb, "active", active);
            AppendWindowSummary(sb, "caret", caret);

            ImeProbeResult autoResult = GetAutoSymbolWidthDecision(false);
            AppendProbeSummary(sb, autoResult);
            AppendProbeSummary(sb, ProbeDirectImm("diagnostic-direct-focus", focus));
            AppendProbeSummary(sb, ProbeDirectImm("diagnostic-direct-foreground", foreground));
            AppendProbeSummary(sb, ProbeDefaultImeWindow("diagnostic-default-ime-focus", focus, true, 100));
            AppendProbeSummary(sb, ProbeDefaultImeWindow("diagnostic-default-ime-foreground", foreground, true, 100));
            sb.AppendLine("IME diagnostics end.");
            return sb.ToString();
        }

        private static void AppendWindowSummary(StringBuilder sb, string label, IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero)
            {
                sb.AppendLine("window " + label + " hwnd=0x0");
                return;
            }

            uint processId;
            uint threadId = NativeMethods.GetWindowThreadProcessId(hWnd, out processId);
            IntPtr hkl = threadId == 0 ? IntPtr.Zero : NativeMethods.GetKeyboardLayout(threadId);
            long hklValue = hkl.ToInt64();
            int langId = (int)(hklValue & 0xFFFF);
            int layoutId = (int)((hklValue >> 16) & 0xFFFF);
            bool isIme = hkl != IntPtr.Zero && NativeMethods.ImmIsIME(hkl);

            sb.AppendLine(
                "window " + label +
                " hwnd=" + FormatHandle(hWnd) +
                " class=" + SafeLogValue(GetClassNameSafe(hWnd)) +
                " pid=" + processId.ToString() +
                " tid=" + threadId.ToString() +
                " process=" + SafeLogValue(GetProcessNameSafe(processId)) +
                " hkl=" + FormatHandle(hkl) +
                " langId=0x" + langId.ToString("X4") +
                " layoutId=0x" + layoutId.ToString("X4") +
                " immIsIme=" + isIme.ToString()
            );
        }

        private static void AppendProbeSummary(StringBuilder sb, ImeProbeResult result)
        {
            sb.AppendLine(
                "imeProbe source=" + SafeLogValue(result.Source) +
                " method=" + SafeLogValue(result.Method) +
                " target=" + FormatHandle(result.TargetHwnd) +
                " context=" + FormatHandle(result.ContextHwnd) +
                " imeWindow=" + FormatHandle(result.ImeWindowHwnd) +
                " imeWindowClass=" + SafeLogValue(GetClassNameSafe(result.ImeWindowHwnd)) +
                " contextAvailable=" + result.ContextAvailable.ToString() +
                " contextError=" + result.ContextError.ToString() +
                " openAvailable=" + result.OpenAvailable.ToString() +
                " open=" + result.Open.ToString() +
                " openError=" + result.OpenError.ToString() +
                " conversionAvailable=" + result.ConversionAvailable.ToString() +
                " conversion=0x" + result.Conversion.ToString("X8") +
                " conversionFlags=" + DecodeConversionFlags(result.Conversion) +
                " sentence=0x" + result.Sentence.ToString("X8") +
                " conversionError=" + result.ConversionError.ToString() +
                " timedOut=" + result.TimedOut.ToString() +
                " decision=" + result.Decision.ToString() +
                " reason=" + SafeLogValue(result.Reason)
            );
        }

        private static string DecodeConversionFlags(int conversion)
        {
            if (conversion == 0)
            {
                return "ALPHANUMERIC";
            }

            List<string> flags = new List<string>();
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_NATIVE, "NATIVE");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_KATAKANA, "KATAKANA");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_FULLSHAPE, "FULLSHAPE");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_ROMAN, "ROMAN");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_CHARCODE, "CHARCODE");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_HANJACONVERT, "HANJACONVERT");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_SOFTKBD, "SOFTKBD");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_NOCONVERSION, "NOCONVERSION");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_EUDC, "EUDC");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_SYMBOL, "SYMBOL");
            AppendFlag(flags, conversion, NativeMethods.IME_CMODE_FIXED, "FIXED");
            if (flags.Count == 0)
            {
                return "UNKNOWN_BITS";
            }

            return String.Join(",", flags.ToArray());
        }

        private static void AppendFlag(List<string> flags, int conversion, int bit, string name)
        {
            if ((conversion & bit) != 0)
            {
                flags.Add(name);
            }
        }

        private static string GetClassNameSafe(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero)
            {
                return "none";
            }

            StringBuilder buffer = new StringBuilder(256);
            int length = NativeMethods.GetClassName(hWnd, buffer, buffer.Capacity);
            if (length <= 0)
            {
                return "unavailable";
            }

            return buffer.ToString();
        }

        private static string GetProcessNameSafe(uint processId)
        {
            if (processId == 0)
            {
                return "none";
            }

            try
            {
                using (Process process = Process.GetProcessById((int)processId))
                {
                    return process.ProcessName + ".exe";
                }
            }
            catch
            {
                return "unavailable";
            }
        }

        private static string FormatHandle(IntPtr value)
        {
            if (value == IntPtr.Zero)
            {
                return "0x0";
            }

            ulong raw = unchecked((ulong)value.ToInt64());
            return "0x" + raw.ToString(IntPtr.Size == 8 ? "X16" : "X8");
        }

        private static string SafeLogValue(string value)
        {
            if (String.IsNullOrEmpty(value))
            {
                return "none";
            }

            return value.Replace("\r", " ").Replace("\n", " ").Replace("\t", " ");
        }

        private static bool HandleCapsLockAsCtrl(int vkCode, bool isKeyDown, bool isKeyUp)
        {
            if (!capsLockAsCtrl || vkCode != NativeMethods.VK_CAPITAL)
            {
                return false;
            }

            if (isKeyDown)
            {
                capsLockPhysicalDown = true;

                if (!capsLockCtrlDown)
                {
                    if (IsPhysicalCtrlDown())
                    {
                        capsLockPassThrough = false;
                        return true;
                    }

                    if (!SendKeyboardScanCode(NativeMethods.SC_LEFT_CONTROL, false, false, "CapsLock as Ctrl down"))
                    {
                        capsLockPassThrough = true;
                        return false;
                    }

                    capsLockPassThrough = false;
                    capsLockCtrlDown = true;
                }

                return true;
            }

            if (isKeyUp)
            {
                capsLockPhysicalDown = false;

                if (capsLockPassThrough)
                {
                    capsLockPassThrough = false;
                    return false;
                }

                ReleaseCapsLockCtrl("CapsLock key up");
                return true;
            }

            return false;
        }

        public static void RetryPendingCapsLockCtrlRelease(string reason)
        {
            if (capsLockCtrlReleasePending)
            {
                ReleaseCapsLockCtrl(reason);
            }
        }

        private static void EnsureCapsLockCtrlDownForHeldCaps(string reason)
        {
            if (!capsLockAsCtrl || !capsLockPhysicalDown || capsLockPassThrough ||
                capsLockCtrlDown || IsPhysicalCtrlDown())
            {
                return;
            }

            if (SendKeyboardScanCode(NativeMethods.SC_LEFT_CONTROL, false, false, reason))
            {
                capsLockCtrlDown = true;
                capsLockCtrlReleasePending = false;
            }
            else
            {
                capsLockPassThrough = true;
            }
        }

        private static bool ReleaseCapsLockCtrl(string reason)
        {
            if (!capsLockCtrlDown)
            {
                capsLockCtrlReleasePending = false;
                return true;
            }

            if (physicalLeftCtrlDown)
            {
                capsLockCtrlDown = false;
                capsLockCtrlReleasePending = false;
                return true;
            }

            if (SendKeyboardScanCode(NativeMethods.SC_LEFT_CONTROL, false, true, reason))
            {
                capsLockCtrlDown = false;
                capsLockCtrlReleasePending = false;
                return true;
            }

            capsLockCtrlReleasePending = true;
            LogCapsLockCtrlReleasePending(reason + "; SendInput key-up failed");
            return false;
        }

        private static bool IsPhysicalCtrlDown()
        {
            return physicalLeftCtrlDown || physicalRightCtrlDown;
        }

        private static void LogCapsLockCtrlReleasePending(string reason)
        {
            DateTime now = DateTime.UtcNow;
            if ((now - lastCapsLockCtrlReleaseWarningUtc).TotalSeconds <= 5)
            {
                return;
            }

            lastCapsLockCtrlReleaseWarningUtc = now;
            Logger.Write("CapsLock as Ctrl release pending. reason=" + reason);
        }

        private static void LogShortcutKeyDownFailure(ushort targetVirtualKey, string reason)
        {
            DateTime now = DateTime.UtcNow;
            if ((now - lastSendInputFailureUtc).TotalSeconds <= 5)
            {
                return;
            }

            lastSendInputFailureUtc = now;
            Logger.Write("SendInput shortcut key-down failed. reason=" + reason + " vk=0x" + targetVirtualKey.ToString("X2"));
        }

        private static void LogShortcutKeyUpFailure(ushort targetVirtualKey, string reason)
        {
            DateTime now = DateTime.UtcNow;
            if ((now - lastShortcutKeyUpFailureUtc).TotalSeconds <= 5)
            {
                return;
            }

            lastShortcutKeyUpFailureUtc = now;
            Logger.Write("SendInput shortcut key-up pending. reason=" + reason + " vk=0x" + targetVirtualKey.ToString("X2"));
        }

        private static bool SendShortcutVirtualKey(ushort virtualKey, bool keyUp, string reason)
        {
            NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[1];
            inputs[0].type = NativeMethods.INPUT_KEYBOARD;
            inputs[0].U.ki.wVk = virtualKey;
            inputs[0].U.ki.wScan = 0;
            inputs[0].U.ki.dwFlags = keyUp ? (uint)NativeMethods.KEYEVENTF_KEYUP : 0;
            inputs[0].U.ki.time = 0;
            inputs[0].U.ki.dwExtraInfo = selfInjectedExtraInfo;

            uint sent = NativeMethods.SendInput(1, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
            if (sent == 1)
            {
                return true;
            }

            DateTime now = DateTime.UtcNow;
            if ((now - lastSendInputFailureUtc).TotalSeconds > 5)
            {
                lastSendInputFailureUtc = now;
                Logger.Write("SendInput virtual key failed. reason=" + reason + " vk=0x" + virtualKey.ToString("X2") + " keyUp=" + keyUp.ToString() + " sent=" + sent.ToString() + " error=" + Marshal.GetLastWin32Error().ToString());
            }

            return false;
        }

        private static bool SendKeyboardScanCode(ushort scanCode, bool extended, bool keyUp, string reason)
        {
            NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[1];
            inputs[0].type = NativeMethods.INPUT_KEYBOARD;
            inputs[0].U.ki.wVk = 0;
            inputs[0].U.ki.wScan = scanCode;
            inputs[0].U.ki.dwFlags = NativeMethods.KEYEVENTF_SCANCODE;
            if (extended)
            {
                inputs[0].U.ki.dwFlags |= NativeMethods.KEYEVENTF_EXTENDEDKEY;
            }

            if (keyUp)
            {
                inputs[0].U.ki.dwFlags |= NativeMethods.KEYEVENTF_KEYUP;
            }

            inputs[0].U.ki.time = 0;
            inputs[0].U.ki.dwExtraInfo = selfInjectedExtraInfo;

            uint sent = NativeMethods.SendInput(1, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
            if (sent == 1)
            {
                return true;
            }

            DateTime now = DateTime.UtcNow;
            if ((now - lastSendInputFailureUtc).TotalSeconds > 5)
            {
                lastSendInputFailureUtc = now;
                Logger.Write("SendInput scan code failed. reason=" + reason + " scanCode=" + scanCode.ToString("X2") + " extended=" + extended.ToString() + " keyUp=" + keyUp.ToString() + " sent=" + sent.ToString() + " error=" + Marshal.GetLastWin32Error().ToString());
            }

            return false;
        }

        private static bool TryMapScanCode(int scanCode, bool shift, bool fullWidth, FullwidthStyleMode fullwidthStyle, out char value)
        {
            value = '\0';

            switch (scanCode)
            {
                case 0x03:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF20' : '@';
                        return true;
                    }
                    return false;
                case 0x07:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF3E' : '^';
                        return true;
                    }
                    return false;
                case 0x08:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF06' : '&';
                        return true;
                    }
                    return false;
                case 0x09:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF0A' : '*';
                        return true;
                    }
                    return false;
                case 0x0A:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF08' : '(';
                        return true;
                    }
                    return false;
                case 0x0B:
                    if (shift)
                    {
                        value = fullWidth ? '\uFF09' : ')';
                        return true;
                    }
                    return false;
                case 0x0C:
                    value = fullWidth ? (shift ? '\uFF3F' : '\uFF0D') : (shift ? '_' : '-');
                    return true;
                case 0x0D:
                    value = fullWidth ? (shift ? '\uFF0B' : '\uFF1D') : (shift ? '+' : '=');
                    return true;
                case 0x1A:
                    if (fullWidth && !shift && fullwidthStyle == FullwidthStyleMode.Japanese)
                    {
                        value = '\u300C';
                        return true;
                    }

                    value = fullWidth ? (shift ? '\uFF5B' : '\uFF3B') : (shift ? '{' : '[');
                    return true;
                case 0x1B:
                    if (fullWidth && !shift && fullwidthStyle == FullwidthStyleMode.Japanese)
                    {
                        value = '\u300D';
                        return true;
                    }

                    value = fullWidth ? (shift ? '\uFF5D' : '\uFF3D') : (shift ? '}' : ']');
                    return true;
                case 0x2B:
                    value = fullWidth ? (shift ? '\uFF5C' : '\uFF3C') : (shift ? '|' : '\\');
                    return true;
                case 0x27:
                    value = fullWidth ? (shift ? '\uFF1A' : '\uFF1B') : (shift ? ':' : ';');
                    return true;
                case 0x28:
                    value = fullWidth ? (shift ? '\uFF02' : '\uFF07') : (shift ? '"' : '\'');
                    return true;
                case 0x29:
                    value = fullWidth ? (shift ? '\uFF5E' : '\uFF40') : (shift ? '~' : '`');
                    return true;
                case 0x35:
                    if (fullWidth && !shift && fullwidthStyle == FullwidthStyleMode.Japanese)
                    {
                        value = '\u30FB';
                        return true;
                    }

                    value = fullWidth ? (shift ? '\uFF1F' : '\uFF0F') : (shift ? '?' : '/');
                    return true;
                default:
                    return false;
            }
        }

        private static bool SendUnicodeChar(char value)
        {
            NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[2];

            inputs[0].type = NativeMethods.INPUT_KEYBOARD;
            inputs[0].U.ki.wVk = 0;
            inputs[0].U.ki.wScan = value;
            inputs[0].U.ki.dwFlags = NativeMethods.KEYEVENTF_UNICODE;
            inputs[0].U.ki.time = 0;
            inputs[0].U.ki.dwExtraInfo = selfInjectedExtraInfo;

            inputs[1].type = NativeMethods.INPUT_KEYBOARD;
            inputs[1].U.ki.wVk = 0;
            inputs[1].U.ki.wScan = value;
            inputs[1].U.ki.dwFlags = NativeMethods.KEYEVENTF_UNICODE | NativeMethods.KEYEVENTF_KEYUP;
            inputs[1].U.ki.time = 0;
            inputs[1].U.ki.dwExtraInfo = selfInjectedExtraInfo;

            uint sent = NativeMethods.SendInput(2, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
            if (sent == 2)
            {
                return true;
            }

            if (sent == 1)
            {
                NativeMethods.INPUT[] keyUpOnly = new NativeMethods.INPUT[1];
                keyUpOnly[0].type = NativeMethods.INPUT_KEYBOARD;
                keyUpOnly[0].U.ki.wVk = 0;
                keyUpOnly[0].U.ki.wScan = value;
                keyUpOnly[0].U.ki.dwFlags = NativeMethods.KEYEVENTF_UNICODE | NativeMethods.KEYEVENTF_KEYUP;
                keyUpOnly[0].U.ki.time = 0;
                keyUpOnly[0].U.ki.dwExtraInfo = selfInjectedExtraInfo;
                uint cleanupSent = NativeMethods.SendInput(1, keyUpOnly, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
                if (cleanupSent == 1)
                {
                    return true;
                }

                DateTime cleanupNow = DateTime.UtcNow;
                if ((cleanupNow - lastSendInputFailureUtc).TotalSeconds > 5)
                {
                    lastSendInputFailureUtc = cleanupNow;
                    Logger.Write("SendInput Unicode cleanup failed after partial insert. value=" + ((int)value).ToString("X4") + " cleanupSent=" + cleanupSent.ToString() + " error=" + Marshal.GetLastWin32Error().ToString());
                }

                return true;
            }

            if (sent != 2)
            {
                DateTime now = DateTime.UtcNow;
                if ((now - lastSendInputFailureUtc).TotalSeconds > 5)
                {
                    lastSendInputFailureUtc = now;
                    Logger.Write("SendInput failed or was blocked. sent=" + sent.ToString() + " error=" + Marshal.GetLastWin32Error().ToString());
                }
            }

            return false;
        }

        public static void RunPureSelfTests()
        {
            AssertSendMessageTimeoutError(NativeMethods.ERROR_TIMEOUT, true);
            AssertSendMessageTimeoutError(0, false);
            AssertSendMessageTimeoutError(5, false);

            AssertFullWidthConversionMode(NativeMethods.IME_CMODE_FULLSHAPE, true);
            AssertFullWidthConversionMode(NativeMethods.IME_CMODE_NATIVE, true);
            AssertFullWidthConversionMode(NativeMethods.IME_CMODE_FULLSHAPE | NativeMethods.IME_CMODE_NATIVE, true);
            AssertFullWidthConversionMode(NativeMethods.IME_CMODE_NATIVE | NativeMethods.IME_CMODE_KATAKANA, false);
            AssertFullWidthConversionMode(NativeMethods.IME_CMODE_FULLSHAPE | NativeMethods.IME_CMODE_NATIVE | NativeMethods.IME_CMODE_KATAKANA, true);
            AssertFullWidthConversionMode(0, false);

            AssertShortcutMap(0x0C, NativeMethods.VK_OEM_MINUS);
            AssertShortcutMap(0x0D, NativeMethods.VK_OEM_PLUS);
            AssertShortcutMap(0x1A, NativeMethods.VK_OEM_4);
            AssertShortcutMap(0x1B, NativeMethods.VK_OEM_6);
            AssertShortcutMap(0x2B, NativeMethods.VK_OEM_5);
            AssertShortcutMap(0x27, NativeMethods.VK_OEM_1);
            AssertShortcutMap(0x28, NativeMethods.VK_OEM_7);
            AssertShortcutMap(0x29, NativeMethods.VK_OEM_3);
            AssertShortcutMap(0x35, NativeMethods.VK_OEM_2);
            AssertNoShortcutMap(0x03);
            AssertShortcutStartPolicy();
            AssertShortcutStateTransitions();

            AssertMap(0x03, true, false, '@');
            AssertMap(0x03, true, true, '\uFF20');
            AssertNoMap(0x03, false, false);
            AssertNoMap(0x03, false, true);
            AssertMap(0x07, true, false, '^');
            AssertMap(0x07, true, true, '\uFF3E');
            AssertMap(0x08, true, false, '&');
            AssertMap(0x08, true, true, '\uFF06');
            AssertMap(0x09, true, false, '*');
            AssertMap(0x09, true, true, '\uFF0A');
            AssertMap(0x0A, true, false, '(');
            AssertMap(0x0A, true, true, '\uFF08');
            AssertMap(0x0B, true, false, ')');
            AssertMap(0x0B, true, true, '\uFF09');
            AssertMap(0x0C, false, false, '-');
            AssertMap(0x0C, false, true, '\uFF0D');
            AssertMap(0x0C, true, false, '_');
            AssertMap(0x0C, true, true, '\uFF3F');
            AssertMap(0x0D, false, false, '=');
            AssertMap(0x0D, false, true, '\uFF1D');
            AssertMap(0x0D, true, false, '+');
            AssertMap(0x0D, true, true, '\uFF0B');
            AssertMap(0x1A, false, false, '[');
            AssertMap(0x1A, false, true, '\uFF3B');
            AssertMapStyle(0x1A, false, true, FullwidthStyleMode.Japanese, '\u300C');
            AssertMap(0x1A, true, false, '{');
            AssertMap(0x1A, true, true, '\uFF5B');
            AssertMapStyle(0x1A, true, true, FullwidthStyleMode.Japanese, '\uFF5B');
            AssertMap(0x1B, false, false, ']');
            AssertMap(0x1B, false, true, '\uFF3D');
            AssertMapStyle(0x1B, false, true, FullwidthStyleMode.Japanese, '\u300D');
            AssertMap(0x1B, true, false, '}');
            AssertMap(0x1B, true, true, '\uFF5D');
            AssertMapStyle(0x1B, true, true, FullwidthStyleMode.Japanese, '\uFF5D');
            AssertMap(0x2B, false, false, '\\');
            AssertMap(0x2B, false, true, '\uFF3C');
            AssertMap(0x2B, true, false, '|');
            AssertMap(0x2B, true, true, '\uFF5C');
            AssertMap(0x27, false, false, ';');
            AssertMap(0x27, false, true, '\uFF1B');
            AssertMap(0x27, true, false, ':');
            AssertMap(0x27, true, true, '\uFF1A');
            AssertMap(0x28, false, false, '\'');
            AssertMap(0x28, false, true, '\uFF07');
            AssertMap(0x28, true, false, '"');
            AssertMap(0x28, true, true, '\uFF02');
            AssertMap(0x29, false, false, '`');
            AssertMap(0x29, false, true, '\uFF40');
            AssertMap(0x29, true, false, '~');
            AssertMap(0x29, true, true, '\uFF5E');
            AssertMap(0x35, false, false, '/');
            AssertMap(0x35, false, true, '\uFF0F');
            AssertMapStyle(0x35, false, true, FullwidthStyleMode.Japanese, '\u30FB');
            AssertMap(0x35, true, false, '?');
            AssertMap(0x35, true, true, '\uFF1F');
            AssertMapStyle(0x35, true, true, FullwidthStyleMode.Japanese, '\uFF1F');
        }

        private static void AssertShortcutStartPolicy()
        {
            AssertShortcutStart(true, false, false, true);
            AssertShortcutStart(false, false, false, false);
            AssertShortcutStart(true, true, false, false);
            AssertShortcutStart(true, false, true, false);
        }

        private static void AssertShortcutStart(bool ctrlDown, bool altDown, bool winDown, bool expected)
        {
            bool actual = ShouldStartShortcutRemap(ctrlDown, altDown, winDown);
            if (actual != expected)
            {
                throw new InvalidOperationException("Shortcut start policy test failed. ctrl=" + ctrlDown.ToString() + " alt=" + altDown.ToString() + " win=" + winDown.ToString() + " expected=" + expected.ToString());
            }
        }

        private static void AssertShortcutStateTransitions()
        {
            Func<ushort, bool, string, bool> originalSender = shortcutKeySender;
            List<string> sends = new List<string>();

            try
            {
                shortcutKeySender = delegate(ushort virtualKey, bool keyUp, string reason)
                {
                    sends.Add(virtualKey.ToString("X2") + ":" + (keyUp ? "up" : "down"));
                    return true;
                };

                bool suppress;
                ResetShortcutStateForSelfTest();
                if (!TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress) || !suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: keydown was not suppressed.");
                }

                physicalLeftCtrlDown = false;
                if (!TryHandleShortcutOverlayEvent(0x0D, false, false, true, false, out suppress) || !suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: keyup after Ctrl release was not suppressed.");
                }

                AssertShortcutSendSequence(sends, "BB:down", "BB:up");
                AssertShortcutCounts(0, 0);

                sends.Clear();
                ResetShortcutStateForSelfTest();
                TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress);
                TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress);
                TryHandleShortcutOverlayEvent(0x0D, false, false, true, false, out suppress);
                AssertShortcutSendSequence(sends, "BB:down", "BB:down", "BB:up");
                AssertShortcutCounts(0, 0);

                ResetShortcutStateForSelfTest();
                physicalLeftCtrlDown = true;
                capsLockCtrlDown = true;
                if (!IsShortcutCtrlDown())
                {
                    throw new InvalidOperationException("Shortcut state test failed: physical Ctrl plus CapsLock-as-Ctrl was not treated as Ctrl.");
                }

                capsLockCtrlDown = false;
                if (!IsShortcutCtrlDown())
                {
                    throw new InvalidOperationException("Shortcut state test failed: physical Ctrl was cleared by synthetic Ctrl release.");
                }

                physicalLeftCtrlDown = false;
                if (IsShortcutCtrlDown())
                {
                    throw new InvalidOperationException("Shortcut state test failed: Ctrl remained active after all sources released.");
                }

                ResetShortcutStateForSelfTest();
                capsLockCtrlDown = true;
                physicalLeftCtrlDown = true;
                if (!ReleaseCapsLockCtrl("self-test physical left Ctrl held") || capsLockCtrlDown)
                {
                    throw new InvalidOperationException("Shortcut state test failed: CapsLock-as-Ctrl release disturbed held physical left Ctrl.");
                }

                sends.Clear();
                ResetShortcutStateForSelfTest();
                TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress);
                ReleaseAllShortcutTargets("self-test overlay off", true);
                if (!TryHandleShortcutOverlayEvent(0x0D, false, true, false, false, out suppress) || !suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: cleaned-up repeat keydown was not suppressed.");
                }

                if (!TryHandleShortcutOverlayEvent(0x0D, false, false, true, false, out suppress) || !suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: cleaned-up physical keyup was not suppressed.");
                }

                AssertShortcutSendSequence(sends, "BB:down", "BB:up");
                AssertShortcutCounts(0, 0);

                ResetShortcutStateForSelfTest();
                shortcutKeySender = delegate(ushort virtualKey, bool keyUp, string reason)
                {
                    sends.Add(virtualKey.ToString("X2") + ":" + (keyUp ? "up" : "down"));
                    return false;
                };

                sends.Clear();
                if (TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress) || suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: failed keydown was suppressed.");
                }

                AssertShortcutCounts(0, 0);

                ResetShortcutStateForSelfTest();
                shortcutKeySender = delegate(ushort virtualKey, bool keyUp, string reason)
                {
                    sends.Add(virtualKey.ToString("X2") + ":" + (keyUp ? "up" : "down"));
                    return !keyUp;
                };

                sends.Clear();
                TryHandleShortcutOverlayEvent(0x0D, false, true, false, true, out suppress);
                if (!TryHandleShortcutOverlayEvent(0x0D, false, false, true, false, out suppress) || !suppress)
                {
                    throw new InvalidOperationException("Shortcut state test failed: failed keyup did not suppress original event.");
                }

                AssertShortcutCounts(0, 1);

                shortcutKeySender = delegate(ushort virtualKey, bool keyUp, string reason)
                {
                    sends.Add(virtualKey.ToString("X2") + ":" + (keyUp ? "retry-up" : "down"));
                    return true;
                };
                RetryPendingShortcutKeyUps("self-test retry");
                AssertShortcutCounts(0, 0);

                NativeMethods.KBDLLHOOKSTRUCT info = new NativeMethods.KBDLLHOOKSTRUCT();
                info.dwExtraInfo = selfInjectedExtraInfo;
                if (!IsSelfInjectedEvent(info))
                {
                    throw new InvalidOperationException("Shortcut state test failed: self-injected marker was not recognized.");
                }
            }
            finally
            {
                shortcutKeySender = originalSender;
                ResetShortcutStateForSelfTest();
            }
        }

        private static void AssertShortcutSendSequence(List<string> actual, params string[] expected)
        {
            if (actual.Count != expected.Length)
            {
                throw new InvalidOperationException("Shortcut send sequence length mismatch. expected=" + expected.Length.ToString() + " actual=" + actual.Count.ToString());
            }

            for (int i = 0; i < expected.Length; i++)
            {
                if (!String.Equals(actual[i], expected[i], StringComparison.Ordinal))
                {
                    throw new InvalidOperationException("Shortcut send sequence mismatch at " + i.ToString() + ". expected=" + expected[i] + " actual=" + actual[i]);
                }
            }
        }

        private static void AssertShortcutCounts(int expectedActive, int expectedPending)
        {
            int active = GetActiveShortcutRemapCountForSelfTest();
            int pending = GetPendingShortcutKeyUpCountForSelfTest();
            if (active != expectedActive || pending != expectedPending)
            {
                throw new InvalidOperationException("Shortcut state count mismatch. expectedActive=" + expectedActive.ToString() + " active=" + active.ToString() + " expectedPending=" + expectedPending.ToString() + " pending=" + pending.ToString());
            }
        }

        private static void AssertMap(int scanCode, bool shift, bool fullWidth, char expected)
        {
            AssertMapStyle(scanCode, shift, fullWidth, FullwidthStyleMode.Literal, expected);
        }

        private static void AssertMapStyle(int scanCode, bool shift, bool fullWidth, FullwidthStyleMode fullwidthStyle, char expected)
        {
            char actual;
            if (!TryMapScanCode(scanCode, shift, fullWidth, fullwidthStyle, out actual) || actual != expected)
            {
                throw new InvalidOperationException("Mapping test failed for scanCode=" + scanCode.ToString("X2") + " shift=" + shift.ToString() + " fullWidth=" + fullWidth.ToString() + " fullwidthStyle=" + fullwidthStyle.ToString());
            }
        }

        private static void AssertNoMap(int scanCode, bool shift, bool fullWidth)
        {
            char actual;
            if (TryMapScanCode(scanCode, shift, fullWidth, FullwidthStyleMode.Literal, out actual))
            {
                throw new InvalidOperationException("Unexpected mapping for scanCode=" + scanCode.ToString("X2") + " shift=" + shift.ToString() + " fullWidth=" + fullWidth.ToString());
            }
        }

        private static void AssertShortcutMap(int scanCode, int expectedVirtualKey)
        {
            ushort actual;
            if (!TryMapShortcutScanCode(scanCode, out actual) || actual != expectedVirtualKey)
            {
                throw new InvalidOperationException("Shortcut mapping test failed for scanCode=" + scanCode.ToString("X2") + " expectedVk=0x" + expectedVirtualKey.ToString("X2"));
            }
        }

        private static void AssertNoShortcutMap(int scanCode)
        {
            ushort actual;
            if (TryMapShortcutScanCode(scanCode, out actual))
            {
                throw new InvalidOperationException("Unexpected shortcut mapping for scanCode=" + scanCode.ToString("X2"));
            }
        }

        private static void AssertFullWidthConversionMode(int conversion, bool expected)
        {
            bool actual = IsFullWidthImeConversionMode(conversion);
            if (actual != expected)
            {
                throw new InvalidOperationException("IME conversion mode test failed for conversion=" + conversion.ToString() + " expected=" + expected.ToString());
            }
        }

        private static void AssertSendMessageTimeoutError(int lastError, bool expected)
        {
            bool actual = IsSendMessageTimeoutError(lastError);
            if (actual != expected)
            {
                throw new InvalidOperationException("SendMessageTimeout error test failed for lastError=" + lastError.ToString() + " expected=" + expected.ToString());
            }
        }
    }

    internal sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int ToggleHotkeyId = 1200;
        private readonly TrayContext owner;
        private bool registered;

        public HotkeyWindow(TrayContext owner)
        {
            this.owner = owner;
            CreateHandle(new CreateParams());
        }

        public bool Register()
        {
            registered = NativeMethods.RegisterHotKey(
                Handle,
                ToggleHotkeyId,
                NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | NativeMethods.MOD_NOREPEAT,
                NativeMethods.VK_F12
            );

            if (!registered)
            {
                Logger.Write("RegisterHotKey Ctrl+Alt+F12 failed. error=" + Marshal.GetLastWin32Error().ToString());
            }
            else
            {
                Logger.Write("Registered toggle hotkey Ctrl+Alt+F12.");
            }

            return registered;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_HOTKEY && m.WParam.ToInt32() == ToggleHotkeyId)
            {
                owner.ToggleMode("hotkey");
                return;
            }

            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (registered)
            {
                NativeMethods.UnregisterHotKey(Handle, ToggleHotkeyId);
                registered = false;
                Logger.Write("Unregistered toggle hotkey.");
            }

            DestroyHandle();
        }
    }

    internal sealed class TrayContext : ApplicationContext
    {
        private readonly NotifyIcon notifyIcon;
        private readonly ToolStripMenuItem onItem;
        private readonly ToolStripMenuItem offItem;
        private readonly ToolStripMenuItem capsCtrlItem;
        private readonly ToolStripMenuItem shortcutOverlayItem;
        private readonly ToolStripMenuItem symbolWidthAutoItem;
        private readonly ToolStripMenuItem symbolWidthAsciiItem;
        private readonly ToolStripMenuItem symbolWidthFullwidthItem;
        private readonly ToolStripMenuItem fullwidthStyleJapaneseItem;
        private readonly ToolStripMenuItem fullwidthStyleLiteralItem;
        private readonly HotkeyWindow hotkeyWindow;
        private readonly System.Windows.Forms.Timer capsCtrlReleaseRetryTimer;
        private readonly System.Windows.Forms.Timer imeDiagnosticsTimer;
        private readonly Icon customIcon;
        private bool disposed;

        public TrayContext(string startMode, bool capsLockAsCtrl, string symbolWidth, string fullwidthStyle, string shortcutOverlay, string logPath, string iconPath)
        {
            Logger.Configure(logPath);
            Logger.Write("win-jis-us-symbol-overlay daemon starting. startMode=" + startMode + " capsLockAsCtrl=" + capsLockAsCtrl.ToString() + " symbolWidth=" + symbolWidth + " fullwidthStyle=" + fullwidthStyle + " shortcutOverlay=" + shortcutOverlay);

            KeyboardHook.SetUsMode(String.Equals(startMode, "US", StringComparison.OrdinalIgnoreCase), "startup");
            KeyboardHook.SetCapsLockAsCtrl(capsLockAsCtrl, "startup");
            KeyboardHook.SetSymbolWidthMode(symbolWidth, "startup");
            KeyboardHook.SetFullwidthStyleMode(fullwidthStyle, "startup");
            KeyboardHook.SetShortcutOverlayMode(shortcutOverlay, "startup");
            KeyboardHook.Install();

            capsCtrlReleaseRetryTimer = new System.Windows.Forms.Timer();
            capsCtrlReleaseRetryTimer.Interval = 500;
            capsCtrlReleaseRetryTimer.Tick += delegate
            {
                KeyboardHook.RetryPendingCapsLockCtrlRelease("timer");
                KeyboardHook.RetryPendingShortcutKeyUps("timer");
            };
            capsCtrlReleaseRetryTimer.Start();

            imeDiagnosticsTimer = new System.Windows.Forms.Timer();
            imeDiagnosticsTimer.Interval = 3000;
            imeDiagnosticsTimer.Tick += delegate
            {
                imeDiagnosticsTimer.Stop();
                RunImeDiagnostics();
            };

            notifyIcon = new NotifyIcon();
            customIcon = LoadCustomIcon(iconPath);
            notifyIcon.Icon = customIcon ?? SystemIcons.Application;
            notifyIcon.Visible = true;
            notifyIcon.DoubleClick += delegate { ToggleMode("tray-double-click"); };

            ContextMenuStrip menu = new ContextMenuStrip();
            onItem = new ToolStripMenuItem("US overlay ON");
            offItem = new ToolStripMenuItem("US overlay OFF");
            capsCtrlItem = new ToolStripMenuItem("CapsLock as Ctrl");
            shortcutOverlayItem = new ToolStripMenuItem("Shortcut overlay");
            symbolWidthAutoItem = new ToolStripMenuItem("Symbol width Auto");
            symbolWidthAsciiItem = new ToolStripMenuItem("Symbol width ASCII");
            symbolWidthFullwidthItem = new ToolStripMenuItem("Symbol width Fullwidth");
            fullwidthStyleJapaneseItem = new ToolStripMenuItem("Fullwidth style Japanese");
            fullwidthStyleLiteralItem = new ToolStripMenuItem("Fullwidth style Literal");
            ToolStripMenuItem testItem = new ToolStripMenuItem("Layout test");
            ToolStripMenuItem diagnosticsItem = new ToolStripMenuItem("IME diagnostics");
            ToolStripMenuItem logItem = new ToolStripMenuItem("Open log");
            ToolStripMenuItem exitItem = new ToolStripMenuItem("Exit");

            onItem.Click += delegate { SetMode(true, "menu"); };
            offItem.Click += delegate { SetMode(false, "menu"); };
            capsCtrlItem.Click += delegate { SetCapsLockAsCtrl(!KeyboardHook.CapsLockAsCtrl, "menu"); };
            shortcutOverlayItem.Click += delegate { SetShortcutOverlay(!KeyboardHook.ShortcutOverlay, "menu"); };
            symbolWidthAutoItem.Click += delegate { SetSymbolWidthMode("Auto", "menu"); };
            symbolWidthAsciiItem.Click += delegate { SetSymbolWidthMode("ASCII", "menu"); };
            symbolWidthFullwidthItem.Click += delegate { SetSymbolWidthMode("Fullwidth", "menu"); };
            fullwidthStyleJapaneseItem.Click += delegate { SetFullwidthStyleMode("Japanese", "menu"); };
            fullwidthStyleLiteralItem.Click += delegate { SetFullwidthStyleMode("Literal", "menu"); };
            testItem.Click += delegate { ShowLayoutTest(); };
            diagnosticsItem.Click += delegate { ScheduleImeDiagnostics(); };
            logItem.Click += delegate { OpenLog(); };
            exitItem.Click += delegate { ExitThread(); };

            menu.Items.Add(onItem);
            menu.Items.Add(offItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(capsCtrlItem);
            menu.Items.Add(shortcutOverlayItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(symbolWidthAutoItem);
            menu.Items.Add(symbolWidthAsciiItem);
            menu.Items.Add(symbolWidthFullwidthItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(fullwidthStyleJapaneseItem);
            menu.Items.Add(fullwidthStyleLiteralItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(testItem);
            menu.Items.Add(diagnosticsItem);
            menu.Items.Add(logItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);
            notifyIcon.ContextMenuStrip = menu;

            hotkeyWindow = new HotkeyWindow(this);
            bool hotkeyRegistered = hotkeyWindow.Register();
            UpdateTray();

            if (!hotkeyRegistered)
            {
                notifyIcon.ShowBalloonTip(
                    3000,
                    "win-jis-us-symbol-overlay",
                    "Ctrl+Alt+F12 is already in use. Use the tray menu to switch modes.",
                    ToolTipIcon.Warning
                );
            }

            Logger.Write("win-jis-us-symbol-overlay daemon started.");
        }

        private static Icon LoadCustomIcon(string iconPath)
        {
            if (String.IsNullOrWhiteSpace(iconPath) || !File.Exists(iconPath))
            {
                return null;
            }

            try
            {
                return new Icon(iconPath);
            }
            catch (Exception ex)
            {
                Logger.Write("Custom icon load failed. path=" + iconPath + " error=" + ex.GetType().FullName + " message=" + ex.Message);
                return null;
            }
        }

        public void ToggleMode(string reason)
        {
            SetMode(!KeyboardHook.UsMode, reason);
        }

        private void SetMode(bool enabled, string reason)
        {
            KeyboardHook.SetUsMode(enabled, reason);
            UpdateTray();
            notifyIcon.ShowBalloonTip(
                1200,
                "win-jis-us-symbol-overlay",
                enabled ? "US overlay ON" : "US overlay OFF",
                ToolTipIcon.Info
            );
        }

        private void SetCapsLockAsCtrl(bool enabled, string reason)
        {
            KeyboardHook.SetCapsLockAsCtrl(enabled, reason);
            UpdateTray();
            notifyIcon.ShowBalloonTip(
                1200,
                "win-jis-us-symbol-overlay",
                enabled ? "CapsLock as Ctrl ON" : "CapsLock as Ctrl OFF",
                ToolTipIcon.Info
            );
        }

        private void SetShortcutOverlay(bool enabled, string reason)
        {
            KeyboardHook.SetShortcutOverlayMode(enabled ? "On" : "Off", reason);
            UpdateTray();
            notifyIcon.ShowBalloonTip(
                1200,
                "win-jis-us-symbol-overlay",
                enabled ? "Shortcut overlay ON" : "Shortcut overlay OFF",
                ToolTipIcon.Info
            );
        }

        private void SetSymbolWidthMode(string mode, string reason)
        {
            KeyboardHook.SetSymbolWidthMode(mode, reason);
            UpdateTray();
            notifyIcon.ShowBalloonTip(
                1200,
                "win-jis-us-symbol-overlay",
                "Symbol width " + KeyboardHook.GetSymbolWidthModeLabel(KeyboardHook.SymbolWidth),
                ToolTipIcon.Info
            );
        }

        private void SetFullwidthStyleMode(string mode, string reason)
        {
            KeyboardHook.SetFullwidthStyleMode(mode, reason);
            UpdateTray();
            notifyIcon.ShowBalloonTip(
                1200,
                "win-jis-us-symbol-overlay",
                "Fullwidth style " + KeyboardHook.FullwidthStyle.ToString(),
                ToolTipIcon.Info
            );
        }

        private void UpdateTray()
        {
            bool enabled = KeyboardHook.UsMode;
            onItem.Checked = enabled;
            offItem.Checked = !enabled;
            capsCtrlItem.Checked = KeyboardHook.CapsLockAsCtrl;
            shortcutOverlayItem.Checked = KeyboardHook.ShortcutOverlay;
            symbolWidthAutoItem.Checked = KeyboardHook.SymbolWidth == SymbolWidthMode.Auto;
            symbolWidthAsciiItem.Checked = KeyboardHook.SymbolWidth == SymbolWidthMode.Ascii;
            symbolWidthFullwidthItem.Checked = KeyboardHook.SymbolWidth == SymbolWidthMode.Fullwidth;
            fullwidthStyleJapaneseItem.Checked = KeyboardHook.FullwidthStyle == FullwidthStyleMode.Japanese;
            fullwidthStyleLiteralItem.Checked = KeyboardHook.FullwidthStyle == FullwidthStyleMode.Literal;
            notifyIcon.Text = enabled ? "win-jis-us-symbol-overlay - US overlay ON" : "win-jis-us-symbol-overlay - US overlay OFF";
        }

        private void ShowLayoutTest()
        {
            Form form = new Form();
            form.Text = "win-jis-us-symbol-overlay layout test";
            form.StartPosition = FormStartPosition.CenterScreen;
            form.Width = 620;
            form.Height = 320;
            form.MinimizeBox = false;
            form.MaximizeBox = false;

            Label expected = new Label();
            expected.Left = 12;
            expected.Top = 12;
            expected.Width = 580;
            expected.Height = 60;
            expected.Text = "Expected US symbols:\r\n@ ^ & * ( ) - _ = + [ { ] } \\ | ; : ' \" ` ~ / ?";

            TextBox box = new TextBox();
            box.Left = 12;
            box.Top = 82;
            box.Width = 580;
            box.Height = 145;
            box.Multiline = true;
            box.ScrollBars = ScrollBars.Vertical;
            box.AcceptsReturn = true;
            box.AcceptsTab = true;

            Button close = new Button();
            close.Text = "Close";
            close.Left = 500;
            close.Top = 238;
            close.Width = 90;
            close.Click += delegate { form.Close(); };

            form.Controls.Add(expected);
            form.Controls.Add(box);
            form.Controls.Add(close);
            form.Shown += delegate { box.Focus(); };
            form.ShowDialog();
            form.Dispose();
        }

        private void ScheduleImeDiagnostics()
        {
            imeDiagnosticsTimer.Stop();
            imeDiagnosticsTimer.Start();
            notifyIcon.ShowBalloonTip(
                2200,
                "win-jis-us-symbol-overlay",
                "IME diagnostics will run in 3 seconds. Focus the target input field now.",
                ToolTipIcon.Info
            );
            Logger.Write("IME diagnostics scheduled. Focus the target input field within 3 seconds.");
        }

        private void RunImeDiagnostics()
        {
            KeyboardHook.LogImeDiagnostics();
            notifyIcon.ShowBalloonTip(
                1600,
                "win-jis-us-symbol-overlay",
                "IME diagnostics written to log.",
                ToolTipIcon.Info
            );
        }

        private void OpenLog()
        {
            try
            {
                Logger.Write("Open log requested.");
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "notepad.exe";
                psi.Arguments = "\"" + Logger.LogPath.Replace("\"", "\\\"") + "\"";
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "win-jis-us-symbol-overlay", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        protected override void ExitThreadCore()
        {
            Cleanup();
            base.ExitThreadCore();
        }

        private void Cleanup()
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            Logger.Write("win-jis-us-symbol-overlay daemon stopping.");

            if (capsCtrlReleaseRetryTimer != null)
            {
                capsCtrlReleaseRetryTimer.Stop();
                capsCtrlReleaseRetryTimer.Dispose();
            }

            if (imeDiagnosticsTimer != null)
            {
                imeDiagnosticsTimer.Stop();
                imeDiagnosticsTimer.Dispose();
            }

            if (hotkeyWindow != null)
            {
                hotkeyWindow.Dispose();
            }

            KeyboardHook.Uninstall();

            if (notifyIcon != null)
            {
                notifyIcon.Visible = false;
                notifyIcon.Dispose();
            }

            if (customIcon != null)
            {
                customIcon.Dispose();
            }

            Logger.Write("win-jis-us-symbol-overlay daemon stopped.");
        }
    }

    public static class KeyboardOverlayApp
    {
        public static void Run(string startMode, bool capsLockAsCtrl, string symbolWidth, string fullwidthStyle, string shortcutOverlay, string logPath, string iconPath)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new TrayContext(startMode, capsLockAsCtrl, symbolWidth, fullwidthStyle, shortcutOverlay, logPath, iconPath));
        }

        public static void SelfTest(string logPath)
        {
            Logger.Configure(logPath);
            Logger.Write("SelfTest started.");

            IntPtr moduleHandle = NativeMethods.GetModuleHandle(null);
            if (moduleHandle == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetModuleHandle failed.");
            }

            NativeMethods.INPUT[] inputs = new NativeMethods.INPUT[0];
            int inputSize = Marshal.SizeOf(typeof(NativeMethods.INPUT));
            int hookSize = Marshal.SizeOf(typeof(NativeMethods.KBDLLHOOKSTRUCT));

            if (inputSize <= 0 || hookSize <= 0 || inputs == null)
            {
                throw new InvalidOperationException("Native structure validation failed.");
            }

            KeyboardHook.RunPureSelfTests();
            Logger.Write("SelfTest passed. INPUT size=" + inputSize.ToString() + " KBDLLHOOKSTRUCT size=" + hookSize.ToString());
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $source -ReferencedAssemblies @("System.Windows.Forms.dll", "System.Drawing.dll")
}
catch {
    Write-StartupLog "Fatal initialization error while compiling embedded C#: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    throw
}

if ($SelfTest) {
    [WinJisUsSymbolOverlay.KeyboardOverlayApp]::SelfTest($LogPath)
    Write-Host "SelfTest passed. Log: $LogPath"
    return
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $scriptPath = Get-ThisScriptPath
    Write-StartupLog "Fatal initialization error: daemon was not started in STA mode."
    throw "Run the daemon in STA mode: powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
}

$createdMutex = $false
$singleInstanceMutex = [System.Threading.Mutex]::new($true, "Local\win-jis-us-symbol-overlay", [ref]$createdMutex)
if (-not $createdMutex) {
    [System.Windows.Forms.MessageBox]::Show(
        "win-jis-us-symbol-overlay is already running.",
        "win-jis-us-symbol-overlay",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    $singleInstanceMutex.Dispose()
    return
}

try {
    $iconPath = Get-IconPathForScript -ScriptPath (Get-ThisScriptPath)
    [WinJisUsSymbolOverlay.KeyboardOverlayApp]::Run($StartMode, [bool]$CapsLockAsCtrl, $SymbolWidth, $FullwidthStyle, $ShortcutOverlay, $LogPath, $iconPath)
}
catch {
    Write-StartupLog "Fatal startup/runtime error: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    throw
}
finally {
    if ($singleInstanceMutex) {
        $singleInstanceMutex.ReleaseMutex()
        $singleInstanceMutex.Dispose()
    }
}
