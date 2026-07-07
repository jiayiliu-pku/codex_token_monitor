Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\CodexTokenMonitor.ps1"""
shell.Run cmd, 0, False