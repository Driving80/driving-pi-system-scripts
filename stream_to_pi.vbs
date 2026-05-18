' stream_to_pi.vbs -- Invisible launcher for stream_to_pi.ps1
' Use this from Task Scheduler instead of powershell.exe directly,
' so no console window ever flashes on screen (SW_HIDE = 0).
'
' Hands-off: VBS resolves its own folder, builds the PS1 path, and
' kicks off PowerShell with -WindowStyle Hidden -NoProfile.

Dim shell, fso, scriptDir, psScript, cmd
Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript  = scriptDir & "\stream_to_pi.ps1"

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """"

' 0 = SW_HIDE (no window), False = do not wait for the child to exit.
shell.Run cmd, 0, False
