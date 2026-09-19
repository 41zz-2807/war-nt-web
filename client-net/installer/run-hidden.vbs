' ============================================================================
'  run-hidden.vbs - peluncur agen client warnet (tanpa jendela konsol)
'  Dipanggil oleh Scheduled Task saat user login.
'  Sekaligus menerapkan registry hardening per user (HKCU).
' ============================================================================
Option Explicit

Dim fso, shell, dir, exe, hkcu
Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' Hardening per user yang sedang login
hkcu = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies"
On Error Resume Next
shell.RegWrite hkcu & "\System\DisableTaskMgr",      1, "REG_DWORD"
shell.RegWrite hkcu & "\NoRun",                      1, "REG_DWORD"
shell.RegWrite hkcu & "\System\DisableRegistryTools",1, "REG_DWORD"
shell.RegWrite hkcu & "\System\DisableCMD",          1, "REG_DWORD"
On Error GoTo 0

' Jalankan agen dari folder yang sama dengan skrip ini, tersembunyi
dir = fso.GetParentFolderName(WScript.ScriptFullName)
exe = fso.BuildPath(dir, "client-net.exe")
If fso.FileExists(exe) Then
    shell.Run """" & exe & """", 0, False
End If