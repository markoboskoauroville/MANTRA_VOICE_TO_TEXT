# Win+PrtScn inside the VM (Windows' own capture includes layered, topmost windows such as the blob), copied out.
param([string]$Out = 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\live.png')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class K { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra); }
"@
$dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
New-Item -ItemType Directory -Force $dir | Out-Null
$t0 = Get-Date
[K]::keybd_event(0x5B,0,0,[IntPtr]::Zero); [K]::keybd_event(0x2C,0,0,[IntPtr]::Zero); [K]::keybd_event(0x2C,0,2,[IntPtr]::Zero); [K]::keybd_event(0x5B,0,2,[IntPtr]::Zero)
for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 300; $f = Get-ChildItem $dir -Filter *.png | Where-Object { $_.LastWriteTime -ge $t0.AddSeconds(-1) } | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { break } }
if ($f) { Start-Sleep -Milliseconds 300; Copy-Item $f.FullName $Out -Force; "saved $Out"; Remove-Item $f.FullName } else { "no screenshot appeared" }
