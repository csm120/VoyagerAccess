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

py -3.11 installer\build_payload.py
if ($LASTEXITCODE) { throw "payload failed" }

py -3.11 -m PyInstaller installer\VoyagerAccess.spec --distpath dist --workpath build\pyi --noconfirm --log-level WARN
if ($LASTEXITCODE) { throw "PyInstaller failed" }

$report = Join-Path $repo 'build\speech-check.txt'
Remove-Item $report -ErrorAction SilentlyContinue
$p = Start-Process dist\VoyagerAccess\VoyagerAccess.exe -ArgumentList '--speech-check', "`"$report`"" -Wait -PassThru
Get-Content $report
if ($p.ExitCode -ne 0) { throw "speech check failed: the build would be silent" }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 (ISCC.exe) not found" }
& $iscc /Q "/DMyAppVersion=$version" "/DMyAppVersionNumeric=$numeric.0" installer\VoyagerAccess.iss
if ($LASTEXITCODE) { throw "Inno Setup failed" }

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
