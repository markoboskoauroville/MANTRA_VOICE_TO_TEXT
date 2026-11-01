# The released zip, unzipped to a fresh folder, runs a take (no .NET installed is needed: self-contained). DOTNET_ROOT is cleared.
param([string]$Rid = 'win-arm64', [string]$Wav = 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\test\en-test.wav', [string]$More = '', [int]$WaitS = 400)
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue
$d = "C:\mvt\rel\$Rid"; if (Test-Path $d) { Remove-Item -Recurse -Force $d }
Expand-Archive "Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\dist\VoiceToTextMantra-v2-$Rid.zip" $d
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
$log = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\log.txt'; $before = (Get-Content $log).Count
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process "$d\VoiceToTextMantra.exe" -ArgumentList (@('--take', $Wav, '--no-type', '--exit') + ($More -split ' ' | Where-Object { $_ })) -PassThru
if (-not $p.WaitForExit($WaitS * 1000)) { "timeout"; $p.Kill() } else { "exit $($p.ExitCode) after $([math]::Round($sw.Elapsed.TotalSeconds,1)) s" }
Get-Content $log | Select-Object -Skip $before
