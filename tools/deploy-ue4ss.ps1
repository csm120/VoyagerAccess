# Installs or removes UE4SS in the Voyager demo's Binaries\Win64 folder.
# Install adds exactly two things: dwmapi.dll and the ue4ss\ folder. It refuses
# to run if either already exists, so nothing of the game's is ever replaced.
#
#   .\deploy-ue4ss.ps1 -Zip <UE4SS_*.zip>     install
#   .\deploy-ue4ss.ps1 -Remove                remove both again
#   .\deploy-ue4ss.ps1 -Mod                   copy mod\VoyagerAccess into ue4ss\Mods
param(
    [string]$Zip,
    [switch]$Remove,
    [switch]$Mod,
    [string]$GameBin = "C:\Program Files (x86)\Steam\steamapps\common\Star Trek Voyager - Across the Unknown Demo\STVoyager\Binaries\Win64"
)
$ErrorActionPreference = 'Stop'

if (Get-Process STVoyager-Win64-Shipping -ErrorAction SilentlyContinue) {
    throw "The game is running; close it first."
}

$proxy = Join-Path $GameBin 'dwmapi.dll'
$dir = Join-Path $GameBin 'ue4ss'

if ($Remove) {
    if (Test-Path $proxy) { Remove-Item $proxy }
    if (Test-Path $dir) { Remove-Item $dir -Recurse }
    "Removed UE4SS from $GameBin"
    return
}

if ($Mod) {
    if (-not (Test-Path $dir)) { throw "UE4SS is not installed; run -Zip first." }
    $target = Join-Path $dir 'Mods\VoyagerAccess'
    if (Test-Path $target) { Remove-Item $target -Recurse }
    Copy-Item (Join-Path $PSScriptRoot '..\mod\VoyagerAccess') $target -Recurse
    "Deployed VoyagerAccess mod to $target"
    return
}

if (-not $Zip) { throw "Pass -Zip <UE4SS zip> or -Remove." }
if ((Test-Path $proxy) -or (Test-Path $dir)) {
    throw "dwmapi.dll or ue4ss already exists in $GameBin; run -Remove first."
}

Expand-Archive -Path $Zip -DestinationPath $GameBin
# The ImGui console (unusable with a screen reader) is off by default in
# UE4SS-settings.ini; leave it that way.
"Installed UE4SS into $GameBin"
