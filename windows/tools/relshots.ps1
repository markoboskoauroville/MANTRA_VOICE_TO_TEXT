# The released arm64 exe draws its pill faces and its Settings (to look at the name and version).
param([string]$Rid = 'win-arm64')
$exe = "C:\mvt\rel\$Rid\VoiceToTextMantra.exe"
$out = 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build\shots\v2'
New-Item -ItemType Directory -Force $out | Out-Null
Start-Process -Wait $exe -ArgumentList '--pill-shot', $out
Start-Process -Wait $exe -ArgumentList '--settings-shot', "$out\settings.png"
(Get-Item $exe).VersionInfo | Select-Object ProductName, FileDescription, ProductVersion, FileVersion | Format-List
Get-ChildItem $out | Select-Object -ExpandProperty Name
