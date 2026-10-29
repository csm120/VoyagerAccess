# Gathers what is needed to look into a Voyager Access problem on someone
# else's computer and copies it to their clipboard, ready to paste into a
# message. Collects: the helper's log, the mod's lines from the game's
# UE4SS log, the installed version, and the game's Steam launch options.
# Their Windows user name appears in file paths; nothing else personal.
param([switch]$Box)
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
$out.Add("Voyager Access report, $(Get-Date -Format 'yyyy-MM-dd HH:mm')")

$exe = "$env:LOCALAPPDATA\Programs\VoyagerAccess\VoyagerAccess.exe"
$ver = Select-String -Path "$env:LOCALAPPDATA\VoyagerAccess\helper.log" -Pattern 'Voyager Access (\S+) (installed|waiting)|updated to (\S+)' |
    Select-Object -Last 1 | ForEach-Object { $g = $_.Matches[0].Groups; if ($g[1].Value) { $g[1].Value } else { $g[3].Value } }
$out.Add("Installed: " + $(if (Test-Path $exe) { "yes, version $ver" } else { 'not found' }))
# The full game's exe and the demo's (2026-10-29: only the demo's was checked).
$out.Add("Game running: " + [bool](Get-Process STVoyagerSteam-Win64-Shipping, STVoyager-Win64-Shipping))
$out.Add("Helper running: " + [bool](Get-Process VoyagerAccess))

$steam = (Get-ItemProperty HKCU:\Software\Valve\Steam).SteamPath
$out.Add("")
$out.Add("== Launch options ==")
Get-ChildItem "$steam\userdata\*\config\localconfig.vdf" | ForEach-Object {
    Select-String -Path $_.FullName -Pattern 'LaunchOptions' | Where-Object { $_.Line -match 'VoyagerAccess|dx11' } |
        ForEach-Object { $out.Add($_.Line.Trim()) }
}

$out.Add("")
$out.Add("== Helper log ==")
Get-Content "$env:LOCALAPPDATA\VoyagerAccess\helper.log" -Tail 40 | ForEach-Object { $out.Add($_) }

# What the mod last said: with the helper's log it shows whether speech
# stopped at the mod or at the helper. Works with the helper not running,
# which the in-game backtick report cannot.
$speech = "$env:LOCALAPPDATA\VoyagerAccess\speech.txt"
if (Test-Path $speech) {
    $out.Add("")
    $out.Add("== Last speech ==")
    Get-Content $speech -Tail 30 | ForEach-Object { $out.Add($_) }
}

$setupLog = "$env:LOCALAPPDATA\VoyagerAccess\setup.log"
if (Test-Path $setupLog) {
    $out.Add("")
    $out.Add("== Last update's setup log (end) ==")
    Get-Content $setupLog -Tail 25 | ForEach-Object { $out.Add($_) }
}

$libs = @("$steam\steamapps")
Select-String -Path "$steam\steamapps\libraryfolders.vdf" -Pattern '"path"\s+"([^"]+)"' | ForEach-Object {
    $libs += ($_.Matches[0].Groups[1].Value -replace '\\\\', '\') + '\steamapps'
}
foreach ($lib in ($libs | Select-Object -Unique)) {
    Get-ChildItem "$lib\common" -Directory -Filter 'Star Trek Voyager - Across the Unknown*' | ForEach-Object {
        $log = Join-Path $_.FullName 'STVoyager\Binaries\Win64\ue4ss\UE4SS.log'
        if (Test-Path $log) {
            $out.Add("")
            $out.Add("== Game log: $($_.Name) ==")
            Select-String -Path $log -Pattern 'VoyagerAccess|error' | Select-Object -Last 80 |
                ForEach-Object { $out.Add($_.Line) }
        }
    }
}

$out -join "`r`n" | Set-Clipboard
Write-Host "The Voyager Access report is on your clipboard. Paste it into a message."
# From the Start menu shortcut the console closes at once, so a standard
# message box says it (screen readers read it in full).
if ($Box) {
    (New-Object -ComObject WScript.Shell).Popup("The Voyager Access report is on your clipboard. Paste it into a message.", 0, "Voyager Access", 64) | Out-Null
}
