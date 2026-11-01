# F1 starts a take (the microphone), Esc throws it away (nothing is written down); then ⚙ opens its menu (--press);
# the foreground app (Notepad) must keep the focus all the time.
$env:DOTNET_ROOT = 'C:\dotnet'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K3 { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
Get-Process MantraVoiceToText -ErrorAction SilentlyContinue | Stop-Process -Force
$f = "C:\mvt\k-$(Get-Random).txt"; Set-Content $f 'keys test' -NoNewline
Start-Process notepad.exe -ArgumentList $f; Start-Sleep 3
$h = (Get-Process notepad | Where-Object { $_.MainWindowTitle -like "*k-*" } | Select-Object -First 1).MainWindowHandle
[K3]::SetForegroundWindow($h) | Out-Null; Start-Sleep 1
$log = Join-Path $env:LOCALAPPDATA 'Mantra Voice to Text\log.txt'; $before = (Get-Content $log).Count
Start-Process 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\MantraVoiceToText.exe' -ArgumentList '--press','settings','10'
Start-Sleep 4
"input devices: " + ((Get-CimInstance Win32_PnPEntity -Filter "PNPClass='AudioEndpoint'" | Select-Object -ExpandProperty Name) -join '; ')
[K3]::keybd_event(0x70,0,0,[IntPtr]::Zero); [K3]::keybd_event(0x70,0,2,[IntPtr]::Zero)     # F1
Start-Sleep 3
& 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\tools\liveshot.ps1' -Out 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\live-recording.png'
[K3]::SetForegroundWindow($h) | Out-Null
"foreground while recording is notepad: $([K3]::GetForegroundWindow() -eq $h)"
[K3]::keybd_event(0x1B,0,0,[IntPtr]::Zero); [K3]::keybd_event(0x1B,0,2,[IntPtr]::Zero)     # Esc
Start-Sleep 9
& 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\tools\liveshot.ps1' -Out 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\live-gear-menu.png'
"foreground with the menu open is notepad: $([K3]::GetForegroundWindow() -eq $h)"
Get-Content $log | Select-Object -Skip $before
Get-Process MantraVoiceToText -ErrorAction SilentlyContinue | Stop-Process -Force
