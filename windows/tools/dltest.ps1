# The model download resumes: start it, kill the app after ~2 MB, start the app again (no switch): it must go on by
# itself from the .part's size (the log names the start offset). Only a few MB are downloaded (SIM data); the real model
# is put back afterwards.
param([int]$StepMB = 2)
$env:DOTNET_ROOT = 'C:\dotnet'
$exe = if ($env:MVT_EXE) { $env:MVT_EXE } else { 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\VoiceToTextMantra.exe' }
$m = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\models'
$bin = "$m\ggml-large-v3-turbo-q5_0.bin"; $part = "$bin.part"; $keep = "$bin.keep"
$log = Join-Path $env:LOCALAPPDATA 'Voice to Text (Mantra)\log.txt'; $before = (Get-Content $log).Count
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
if (Test-Path $bin) { Move-Item $bin $keep -Force }
Remove-Item $part -ErrorAction SilentlyContinue
function Size { if (Test-Path $part) { (Get-Item $part).Length } else { 0 } }
function WaitGrow($from, $mb) { $t = (Get-Date).AddSeconds(180); while ((Get-Date) -lt $t -and (Size) -lt $from + $mb * 1MB) { Start-Sleep -Milliseconds 300 } }
try {
  Start-Process $exe -ArgumentList '--download-model'
  WaitGrow 0 $StepMB
  Get-Process VoiceToTextMantra | Stop-Process -Force; Start-Sleep 1
  $s1 = Size; "1. killed with the .part at $s1 bytes"
  Start-Process $exe
  WaitGrow $s1 $StepMB
  Get-Process VoiceToTextMantra | Stop-Process -Force; Start-Sleep 1
  $s2 = Size; "2. started again without a switch, killed at $s2 bytes (+$($s2 - $s1))"
  Start-Process $exe -ArgumentList '--settings-shot','Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\settings-downloading.png'
  Start-Sleep 6
  Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1
  $s3 = Size; "3. third start (settings drawn while it downloads), ended at $s3 bytes"
  # the bytes are the model's: compare the first $s3 bytes with the real file
  $a = [IO.File]::OpenRead($part); $b = [IO.File]::OpenRead($keep)
  $n = [Math]::Min($s3, 64MB); $ba = New-Object byte[] $n; $bb = New-Object byte[] $n
  [void]$a.Read($ba, 0, $n); [void]$b.Read($bb, 0, $n); $a.Close(); $b.Close()
  "the .part's $n bytes equal the model's first $n bytes: $([Linq.Enumerable]::SequenceEqual($ba, $bb))"
} finally {
  Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
  Remove-Item $part -ErrorAction SilentlyContinue
  if (Test-Path $keep) { Move-Item $keep $bin -Force }
  "model back: $((Get-Item $bin).Length) bytes"
}
Get-Content $log | Select-Object -Skip $before | Where-Object { $_ -match 'model download|start v|data folder' }
