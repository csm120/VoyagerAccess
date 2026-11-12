# Writes the release files beside VoyagerAccessSetup.exe in -Out: its .sha256,
# and, only with -LivePatching, VoyagerAccessMod.zip (the mod's scripts, for
# patching a running game) and that zip's .sha256.
#
# Live patching is OFF (Casey, 2026-11-11): old helpers 0.1.2 to 0.1.9 patch a
# running game whenever a release has VoyagerAccessMod.zip, and that reload can
# freeze the game. The rule "upload only the setup and its .sha256" was written
# down, yet 0.3.91 to 0.4.2 uploaded the zip because a stale note said "all four
# files". So without -LivePatching the zip is not built at all, and any left by
# an older build is removed (build.ps1 runs -CleanOnly first, and a zip that
# cannot be removed fails the build): the usual hand-typed upload from
# dist\installer then fails on a missing file. This does not stop a build run
# with -LivePatching, a zip made by hand, or an upload from another folder.
# Pass -LivePatching only after the reload freeze is understood and the flag
# reload passes repeated tests.
# Called by installer\build.ps1; tests\test_release_files.py runs it directly.
param(
    [Parameter(Mandatory)][string]$Out,
    [Parameter(Mandatory)][string]$Scripts,
    [Parameter(Mandatory)][string]$Stage,
    [switch]$LivePatching,
    # Only remove an old zip and its .sha256, and write nothing: build.ps1
    # runs this first, so a build that fails part way leaves no zip behind.
    [switch]$CleanOnly
)
$ErrorActionPreference = 'Stop'

$zip = Join-Path $Out 'VoyagerAccessMod.zip'
foreach ($old in $zip, "$zip.sha256") {
    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    # A file held open (or otherwise locked) survives Remove-Item; say so
    # rather than report "not built" with the old zip still there to upload.
    if (Test-Path -LiteralPath $old) {
        throw "Could not remove $old (is it open in another program?). Close it and build again; it must not be uploaded."
    }
}
if ($CleanOnly) { return }
$names = @('VoyagerAccessSetup.exe')
if ($LivePatching) {
    Remove-Item $Stage -Recurse -ErrorAction SilentlyContinue
    New-Item -ItemType Directory (Join-Path $Stage 'Scripts') | Out-Null
    Copy-Item (Join-Path $Scripts '*.lua') (Join-Path $Stage 'Scripts')
    Compress-Archive -Path (Join-Path $Stage 'Scripts') -DestinationPath $zip
    $names += 'VoyagerAccessMod.zip'
} else {
    Write-Host 'Live patching is off: VoyagerAccessMod.zip is not built. Upload only VoyagerAccessSetup.exe and its .sha256.'
}
# A checksum file beside each release file. They used to be written by hand,
# and 0.1.1's build left the 0.1.0 one in place (caught before upload).
foreach ($name in $names) {
    $hash = (Get-FileHash (Join-Path $Out $name) -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText((Join-Path $Out "$name.sha256"), "$hash  $name`n")
}
