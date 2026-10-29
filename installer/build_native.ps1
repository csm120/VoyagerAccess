# Builds build\native\voystart.dll from installer\native\voystart.c with the
# Visual Studio Build Tools (x64). helperstart.lua loads it with
# package.loadlib to start the helper with no window (2026-10-29).
#   pwsh -File installer\build_native.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$out = Join-Path $repo 'build\native'
New-Item -ItemType Directory -Force $out | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "Visual Studio Build Tools with the C++ x64 compiler not found" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$src = Join-Path $repo 'installer\native\voystart.c'
$cmd = "`"$vcvars`" >nul && cl /nologo /O2 /W4 /LD /MT `"$src`" /Fe:`"$out\voystart.dll`" /Fo:`"$out\\`" /link /NOLOGO kernel32.lib"
cmd /c $cmd
if ($LASTEXITCODE) { throw "voystart.dll did not build" }
"built $out\voystart.dll"
