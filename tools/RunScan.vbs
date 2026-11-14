' RunScan.vbs - silently run one scan (invoked by Task Scheduler)
' Started through wscript.exe, so no console window flashes.
' NOTE: keep this file ASCII-only - cscript reads .vbs as ANSI on Chinese Windows.

Option Explicit

Dim fso, shell, base, script, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' This file lives in <project>\tools\, so the project root is one level up.
base = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
script = base & "\backup-log.ps1"

If Not fso.FileExists(script) Then
    WScript.Quit 2
End If

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """ -Action scan"

' 0 = hidden window, False = do not wait
shell.Run cmd, 0, False
