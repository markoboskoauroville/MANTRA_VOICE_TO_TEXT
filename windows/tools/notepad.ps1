# Opens a fresh Notepad, brings it to the front, runs a --take into it, then reads Notepad's text back (UI Automation).
param([string]$Wav = 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\test\en-test.wav', [string]$Extra = '', [string]$Shot = '')
$env:DOTNET_ROOT = 'C:\dotnet'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra); }
"@
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
$f = "C:\mvt\note-$(Get-Random).txt"; Set-Content $f '' -NoNewline
$np = Start-Process notepad.exe -ArgumentList $f -PassThru
Start-Sleep 3
$h = (Get-Process -Id $np.Id -ErrorAction SilentlyContinue).MainWindowHandle
if (-not $h -or $h -eq 0) { $h = (Get-Process notepad | Where-Object { $_.MainWindowTitle -like "*note-*" } | Select-Object -First 1).MainWindowHandle }
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep 1
"foreground is notepad: $([W]::GetForegroundWindow() -eq $h)"
$exe = if ($env:MVT_EXE) { $env:MVT_EXE } else { 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\VoiceToTextMantra.exe' }
$log = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\log.txt'; $before = (Get-Content $log).Count
$args2 = @('--take', $Wav) + ($Extra -split ' ' | Where-Object { $_ })
$p = Start-Process $exe -ArgumentList $args2 -PassThru
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline) { Start-Sleep 2; if ((Get-Content $log | Select-Object -Skip $before) -match 'landing:|dropped:|failed after') { break } }
Start-Sleep 2
if ($Shot) { & 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\tools\shot.ps1' -Out $Shot }
Get-Content $log | Select-Object -Skip $before
$el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
$doc = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
if (-not $doc) { $doc = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit))) }
$tp = $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
$t = $tp.DocumentRange.GetText(-1); "NOTEPAD TEXT: [" + $t + "]"; "codes: " + (($t.ToCharArray() | Select-Object -First 20 | % { [int]$_ }) -join " ")
"notepad pid $($np.Id) hwnd $h"
