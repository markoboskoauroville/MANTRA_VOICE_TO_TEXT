# A take while the desktop has the focus: it must not land, the blob stays, COPY turns white; then COPY is pressed
# (through UI Automation) and the clipboard checked; the clipboard is given back as it was (it is shared with the Mac).
$env:DOTNET_ROOT = 'C:\dotnet'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class D { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
$old = Get-Clipboard -Raw
$log = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\log.txt'; $before = (Get-Content $log).Count
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K2 { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n); }
"@
Start-Process 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\VoiceToTextMantra.exe' -ArgumentList '--take','Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\test\en-test.wav','--press','copy','75'
Start-Sleep 2
# Win+D: the desktop gets the focus
[K2]::keybd_event(0x5B,0,0,[IntPtr]::Zero); [K2]::keybd_event(0x44,0,0,[IntPtr]::Zero); [K2]::keybd_event(0x44,0,2,[IntPtr]::Zero); [K2]::keybd_event(0x5B,0,2,[IntPtr]::Zero)
Start-Sleep 1
$sb = New-Object System.Text.StringBuilder 256; [K2]::GetClassName([K2]::GetForegroundWindow(), $sb, 256) | Out-Null; "foreground: $sb"
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline) { Start-Sleep 2; if ((Get-Content $log | Select-Object -Skip $before) -match 'landing:') { break } }
Start-Sleep 5
& 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\tools\liveshot.ps1' -Out 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\live-not-landed.png'
while ((Get-Date) -lt $deadline) { Start-Sleep 1; if ((Get-Content $log | Select-Object -Skip $before) -match '\d  --press copy$') { break } }
Start-Sleep -Milliseconds 300
& 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\tools\liveshot.ps1' -Out 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\live-copied.png'
"CLIPBOARD AFTER COPY: [" + (Get-Clipboard -Raw) + "]"
if ($old) { Set-Clipboard -Value $old } else { Set-Clipboard -Value $null }
"clipboard given back"
Get-Content $log | Select-Object -Skip $before
