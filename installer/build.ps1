# Builds dist\installer\VoyagerAccessSetup.exe.
#   1. build\payload: UE4SS plus the mod (installer\build_payload.py)
#   2. dist\VoyagerAccess: VoyagerAccess.exe and its files (PyInstaller)
#   3. the built exe checks its own bundled files and Tolk (--speech-check);
#      a build that would be silent stops here
#   4. dist\installer\VoyagerAccessSetup.exe (Inno Setup)
# Usage: powershell -File installer\build.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

$version = (Select-String voyager\version.py -Pattern '__version__ = "([^"]+)"').Matches[0].Groups[1].Value
$numeric = ($version -split '\.' | Select-Object -First 3) -join '.'
"Building Voyager Access $version"

# A release build (three-part version) needs its entry in docs\WHATS_NEW.md,
# the player-facing changelog (Casey, 2026-10-11: keep it updated). Test
# builds such as 0.2.0.1 never go public and are not checked.
if (($version -split '\.').Count -eq 3) {
    $top = (Select-String docs\WHATS_NEW.md -Pattern '^Version (\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value
    if ($top -ne $version) { throw "docs\WHATS_NEW.md starts with version ${top}, not ${version}: add this release's entry first" }
}

py -3.11 installer\build_payload.py
if ($LASTEXITCODE) { throw "payload failed" }

py -3.11 -m PyInstaller installer\VoyagerAccess.spec --distpath dist --workpath build\pyi --noconfirm --log-level WARN
if ($LASTEXITCODE) { throw "PyInstaller failed" }

# Authenticode (Azure Artifact Signing as Web Friendly Help LLC), before the
# speech check so the check runs the signed exe. Not fatal on a machine that
# cannot sign; check the release with installer\codesign.py --check.
py -3.11 installer\codesign.py --can-sign
$sign = ($LASTEXITCODE -eq 0)
if ($sign) {
    $az = "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin"
    if (Test-Path $az) { $env:PATH = "$az;$env:PATH" }
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

# The mod's scripts alone, for patching a running game, and a checksum file
# beside each release file. The checksums used to be written by hand, and
# 0.1.1's build left the 0.1.0 one in place (caught before upload).
$out = Join-Path $repo 'dist\installer'
$zip = Join-Path $out 'VoyagerAccessMod.zip'
Remove-Item $zip -ErrorAction SilentlyContinue
$stage = Join-Path $repo 'build\modzip'
Remove-Item $stage -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory "$stage\Scripts" | Out-Null
Copy-Item build\payload\ue4ss\Mods\VoyagerAccess\Scripts\*.lua "$stage\Scripts"
Compress-Archive -Path "$stage\Scripts" -DestinationPath $zip
foreach ($name in 'VoyagerAccessSetup.exe', 'VoyagerAccessMod.zip') {
    $hash = (Get-FileHash (Join-Path $out $name) -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText((Join-Path $out "$name.sha256"), "$hash  $name`n")
}
Get-ChildItem $out | Select-Object Name, Length
