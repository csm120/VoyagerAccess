# Builds dist\installer\VoyagerAccessSetup.exe.
#   1. build\payload: UE4SS plus the mod (installer\build_payload.py)
#   2. dist\VoyagerAccess: VoyagerAccess.exe and its files (PyInstaller)
#   3. the built exe checks its own bundled files and Tolk (--speech-check);
#      a build that would be silent stops here
#   4. dist\installer\VoyagerAccessSetup.exe (Inno Setup)
# Usage: powershell -File installer\build.ps1
#   -LivePatching also builds VoyagerAccessMod.zip; leave it off while live
#   patching is off (installer\release-files.ps1 says why).
param([switch]$LivePatching)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

# An old VoyagerAccessMod.zip goes first, so a build that fails part way
# cannot leave one in dist\installer to be uploaded (Fable re-review, 2026-11-11).
& (Join-Path $repo 'installer\release-files.ps1') -Out (Join-Path $repo 'dist\installer') `
    -Scripts (Join-Path $repo 'build\payload\ue4ss\Mods\VoyagerAccess\Scripts') `
    -Stage (Join-Path $repo 'build\modzip') -CleanOnly

$version = (Select-String voyager\version.py -Pattern '__version__ = "([^"]+)"').Matches[0].Groups[1].Value
$numeric = ($version -split '\.' | Select-Object -First 3) -join '.'
"Building Voyager Access $version"

# A release build (three-part version) needs its entry in docs\WHATS_NEW.md,
# the player-facing changelog (Casey, 2026-10-11: keep it updated). Test
# builds such as 0.2.0.1 never go public and are not checked.
if (($version -split '\.').Count -eq 3) {
    $top = (Select-String docs\WHATS_NEW.md -Pattern '^Version (\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value
    if ($top -ne $version) { throw "docs\WHATS_NEW.md starts with version ${top}, not ${version}: add this release's entry first" }
    # And the tests and the translation tables pass, before anything is
    # built or signed (Fable review and Casey, 2026-11-10). Without lupa
    # every Lua test skips and the suite still passes, so it is required.
    py -3.11 -c "import lupa"
    if ($LASTEXITCODE) { throw "lupa is not installed, so the Lua tests would be skipped: no release build" }
    py -3.11 -m unittest discover -s tests
    if ($LASTEXITCODE) { throw "the tests failed: no release build" }
    py -3.11 tools\check_translations.py
    if ($LASTEXITCODE) { throw "check_translations.py found problems: no release build" }
}

# Authenticode (Azure Artifact Signing as Web Friendly Help LLC), before the
# speech check so the check runs the signed exe. Not fatal on a machine that
# cannot sign; check the release with installer\codesign.py --check.
py -3.11 installer\codesign.py --can-sign
$sign = ($LASTEXITCODE -eq 0)
if ($sign) {
    $az = "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin"
    if (Test-Path $az) { $env:PATH = "$az;$env:PATH" }
}

# voystart.dll, which the mod uses to start the helper with no window
# (helperstart.lua, 2026-10-29); signed before the payload copies it.
pwsh -NoProfile -File installer\build_native.ps1
if ($LASTEXITCODE) { throw "voystart.dll failed" }
if ($sign) {
    py -3.11 installer\codesign.py build\native\voystart.dll
    if ($LASTEXITCODE) { throw "signing voystart.dll failed" }
}

py -3.11 installer\build_payload.py
if ($LASTEXITCODE) { throw "payload failed" }

py -3.11 -m PyInstaller installer\VoyagerAccess.spec --distpath dist --workpath build\pyi --noconfirm --log-level WARN
if ($LASTEXITCODE) { throw "PyInstaller failed" }

if ($sign) {
    py -3.11 installer\codesign.py dist\VoyagerAccess\VoyagerAccess.exe
    if ($LASTEXITCODE) { throw "signing VoyagerAccess.exe failed" }
} else {
    Write-Warning "NOT SIGNED: this build's exe and installer are unsigned"
}

$report = Join-Path $repo 'build\speech-check.txt'
Remove-Item $report -ErrorAction SilentlyContinue
$p = Start-Process dist\VoyagerAccess\VoyagerAccess.exe -ArgumentList '--speech-check', "`"$report`"" -Wait -PassThru
Get-Content $report
if ($p.ExitCode -ne 0) { throw "speech check failed: the build would be silent" }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 (ISCC.exe) not found" }
$isccArgs = @('/Q', "/DMyAppVersion=$version", "/DMyAppVersionNumeric=$numeric.0")
if ($sign) {
    # Inno signs the setup and the uninstaller it generates.
    $signTool = py -3.11 installer\codesign.py --inno-sign-tool (Join-Path $repo 'build\artifact-signing.json')
    $isccArgs += @('/DSign', "/Swfh=$signTool")
}
& $iscc @isccArgs installer\VoyagerAccess.iss
if ($LASTEXITCODE) { throw "Inno Setup failed" }
if ($sign) {
    py -3.11 installer\codesign.py --check dist\installer\VoyagerAccessSetup.exe
    if ($LASTEXITCODE) { throw "VoyagerAccessSetup.exe came out of Inno Setup unsigned" }
}

# The setup's checksum file, and the live-patch zip only with -LivePatching.
$out = Join-Path $repo 'dist\installer'
& (Join-Path $repo 'installer\release-files.ps1') -Out $out `
    -Scripts (Join-Path $repo 'build\payload\ue4ss\Mods\VoyagerAccess\Scripts') `
    -Stage (Join-Path $repo 'build\modzip') -LivePatching:$LivePatching
Get-ChildItem $out | Select-Object Name, Length
