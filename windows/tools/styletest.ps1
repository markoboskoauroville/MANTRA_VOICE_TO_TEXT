# STYLE on Notepad's box with --test-style-fake (capitals, no Claude): proves reading and writing back the focused box.
param([switch]$Select)
$env:DOTNET_ROOT = 'C:\dotnet'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W2 { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra); }
"@
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
$f = "C:\mvt\s-$(Get-Random).txt"; Set-Content $f 'first line stays. this second part gets styled' -NoNewline
$np = Start-Process notepad.exe -ArgumentList $f -PassThru; Start-Sleep 3
$h = (Get-Process notepad | Where-Object { $_.MainWindowTitle -like "*s-*" } | Select-Object -First 1).MainWindowHandle
[W2]::SetForegroundWindow($h) | Out-Null; Start-Sleep 1
if ($Select) { # End, then Shift+Home…: select the last 4 words with Ctrl+Shift+Left x4
  [W2]::keybd_event(0x23,0,0,[IntPtr]::Zero); [W2]::keybd_event(0x23,0,2,[IntPtr]::Zero)
  [W2]::keybd_event(0x11,0,0,[IntPtr]::Zero); [W2]::keybd_event(0x10,0,0,[IntPtr]::Zero)
  1..5 | % { [W2]::keybd_event(0x25,0,1,[IntPtr]::Zero); [W2]::keybd_event(0x25,0,3,[IntPtr]::Zero) }
  [W2]::keybd_event(0x10,0,2,[IntPtr]::Zero); [W2]::keybd_event(0x11,0,2,[IntPtr]::Zero)
}
$log = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\log.txt'; $before = (Get-Content $log).Count
$exe = 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\VoiceToTextMantra.exe'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W3 { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }
"@
"foreground before start is notepad: $([W3]::GetForegroundWindow() -eq $h)"
Start-Process $exe -ArgumentList '--test-style-fake','--press','style','5'; Start-Sleep 3
"foreground after start is notepad: $([W3]::GetForegroundWindow() -eq $h)"
[W2]::SetForegroundWindow($h) | Out-Null; Start-Sleep 1
"foreground before STYLE is notepad: $([W3]::GetForegroundWindow() -eq $h)"
Start-Sleep 4
"foreground after STYLE is notepad: $([W3]::GetForegroundWindow() -eq $h)"
Get-Content $log | Select-Object -Skip $before
$el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$doc = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
"NOTEPAD TEXT: [" + $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1) + "]"
