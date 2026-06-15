Option Explicit

Dim shell
Dim fso
Dim scriptDir
Dim powerShellExe
Dim command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
powerShellExe = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(powerShellExe) Then
    powerShellExe = "powershell.exe"
End If

command = """" & powerShellExe & """ -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\win-jis-us-symbol-overlay.ps1" & """ -StartMode US -CapsLockAsCtrl"
shell.Run command, 0, False
