# Starts the app (after any running copy is stopped) and returns at once.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$env:DOTNET_ROOT = 'C:\dotnet'
Get-Process VoiceToTextMantra -ErrorAction SilentlyContinue | Stop-Process -Force
$exe = if ($env:MVT_EXE) { $env:MVT_EXE } else { 'C:\mvt\src\bin\Release\net8.0-windows10.0.19041.0\VoiceToTextMantra.exe' }
if ($Rest) { Start-Process $exe -ArgumentList $Rest } else { Start-Process $exe }
Start-Sleep 3
"started"
