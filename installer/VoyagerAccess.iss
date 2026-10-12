; Voyager Access Inno Setup script, modeled on KeyQuest's
; (C:\KeyQuest\tools\build\installer\KeyQuest.iss): per-user, no UAC
; prompt, and the welcome, folder and ready pages skipped.
; Build with installer\build.ps1.
;
; Setup installs VoyagerAccess.exe and runs it once with --install-mod,
; which puts the mod into the game, points the game's Steam launch options
; at the helper (Steam then starts the helper, and the helper starts the
; game), and says so. Nothing runs at Windows sign-in (Casey, 2026-10-11).
; Uninstall takes the mod and the launch options back out first, so the
; game folder and Steam are left as they were found.

#define MyAppName "Voyager Access"
#define MyAppPublisher "Web Friendly Help"
#define MyAppURL "https://webfriendlyhelp.com"
#define MyAppExeName "VoyagerAccess.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#ifndef MyAppVersionNumeric
  #define MyAppVersionNumeric "0.1.0.0"
#endif

[Setup]
AppId={{A83B765A-5617-4654-BFF1-B0018DDE03EE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName}
VersionInfoVersion={#MyAppVersionNumeric}
VersionInfoProductVersion={#MyAppVersionNumeric}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\VoyagerAccess
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
ShowLanguageDialog=no
DisableWelcomePage=yes
DisableDirPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist\installer
OutputBaseFilename=VoyagerAccessSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\dist\VoyagerAccess\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Registry]
; Versions up to 0.2.0 started a waiting helper at sign-in. Remove that
; entry when upgrading: the helper now starts with the game.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#MyAppName}"; Flags: deletevalue

[Icons]
Name: "{autoprograms}\{#MyAppName}\Add Voyager Access to the game"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-mod"
Name: "{autoprograms}\{#MyAppName}\Read me"; Filename: "{app}\README.txt"

[Messages]
; One box at the end (Casey, 2026-10-11): the Finish page says it is ready,
; and --install-mod --from-setup shows no box of its own on success.
FinishedLabel=Voyager Access is installed and added to Star Trek: Voyager - Across the Unknown.%n%nStart the game from Steam as usual. Speech starts when the game loads.
FinishedLabelNoIcons=Voyager Access is installed and added to Star Trek: Voyager - Across the Unknown.%n%nStart the game from Steam as usual. Speech starts when the game loads.

[Run]
; Interactive install: add the mod to the game and say so. A silent
; install (the updater) skips this; the run without arguments that follows
; puts the new mod in, sets the launch options if they are missing (asking
; to restart Steam), and starts the game again after an update.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-mod --from-setup"; Flags: skipifsilent
; Only for silent installs (updates): an interactive install's
; --install-mod has already done this, and a second Steam prompt there
; would be confusing.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent

; The Finish page's checkbox, ticked: Finish starts the game through Steam
; (Casey, 2026-10-11). Silent installs never show it.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--start-game"; Description: "Start Star Trek: Voyager - Across the Unknown"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden; RunOnceId: "StopHelper"
Filename: "{app}\{#MyAppExeName}"; Parameters: "--uninstall-mod"; RunOnceId: "RemoveMod"

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\VoyagerAccess"

[Code]
// The waiting helper keeps VoyagerAccess.exe open; stop it so the files
// can be replaced. The new copy is started again by [Run].
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
