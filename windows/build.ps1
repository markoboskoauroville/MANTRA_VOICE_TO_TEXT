# Build Voice to Text (Mantra) (Windows) inside the VM: the sources are copied from the shared Mac folder to C:\mvt, built
# there (fast, local disk), and the release zips copied back to windows\dist.
#   powershell -ExecutionPolicy Bypass -File build.ps1 [-Publish] [-Rids win-x64,win-arm64]
param([switch]$Publish, [string[]]$Rids = @('win-x64','win-arm64'))
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotnet = if (Test-Path C:\dotnet\dotnet.exe) { 'C:\dotnet\dotnet.exe' } else { 'dotnet' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
if (-not $env:NUGET_PACKAGES -and (Test-Path "$here\build\nuget")) { $env:NUGET_PACKAGES = "$here\build\nuget" }
Get-Process VoiceToTextMantra, MantraVoiceToText -ErrorAction SilentlyContinue | Stop-Process -Force
$work = 'C:\mvt'
New-Item -ItemType Directory -Force "$work\src" | Out-Null
robocopy "$here\src" "$work\src" /MIR /XD bin obj /NFL /NDL /NJH /NJS /NP | Out-Null
Push-Location "$work\src"
& $dotnet build -c Release -nologo -v q
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "build failed" }
if ($Publish) {
  New-Item -ItemType Directory -Force "$here\dist" | Out-Null
  foreach ($rid in $Rids) {
    $out = "$work\publish\$rid"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    & $dotnet publish -c Release -r $rid -p:PublishSingleFile=true -o $out -nologo -v q
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "publish $rid failed" }
    $zip = "$here\dist\VoiceToTextMantra-v2-$rid.zip"
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path "$out\*" -DestinationPath $zip
    Write-Output "zip: $zip $([math]::Round((Get-Item $zip).Length/1MB,1)) MB"
  }
}
Pop-Location
