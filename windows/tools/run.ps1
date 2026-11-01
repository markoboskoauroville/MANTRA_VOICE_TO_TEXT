param([int]$Wait = 60, [switch]$NoWait, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$env:DOTNET_ROOT = "C:\dotnet"; Get-Process MantraVoiceToText -ErrorAction SilentlyContinue | Stop-Process -Force
$exe = if ($env:MVT_EXE) { $env:MVT_EXE } else { 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\MantraVoiceToText.exe' }
$log = Join-Path $env:LOCALAPPDATA 'Mantra Voice to Text\log.txt'
$before = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = if ($Rest) { Start-Process -PassThru $exe -ArgumentList $Rest } else { Start-Process -PassThru $exe }
if ($NoWait) { "started pid $($p.Id)"; exit }
if (-not $p.WaitForExit($Wait * 1000)) { "still running after $Wait s: killed"; $p.Kill() } else { "exit $($p.ExitCode) after $([math]::Round($sw.Elapsed.TotalSeconds,1)) s" }
if (Test-Path $log) { Get-Content $log | Select-Object -Skip $before }
