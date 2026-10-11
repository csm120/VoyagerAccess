; Voyager Access Inno Setup script, modeled on KeyQuest's
; (C:\KeyQuest\tools\build\installer\KeyQuest.iss): per-user, no UAC
; prompt, and the welcome, folder and ready pages skipped.
; Build with installer\build.ps1.
;
; Setup installs VoyagerAccess.exe, starts it at every sign-in (it waits
; quietly for the game), and runs it once with --install-mod, which puts the
; mod into the game and says so. Uninstall takes the mod back out of the
; game first, so the game folder is left as it was found.

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
; Start the waiting helper at sign-in. It uses almost nothing until the
; game starts.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue

[Icons]
Name: "{autoprograms}\{#MyAppName}\Add Voyager Access to the game"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-mod"
Name: "{autoprograms}\{#MyAppName}\Read me"; Filename: "{app}\README.txt"

[Run]
; Interactive install: add the mod to the game and say so. A silent
; install (the updater) skips this; the waiting helper reinstalls the mod
; itself when it sees the new version.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-mod"; Flags: skipifsilent
Filename: "{app}\{#MyAppExeName}"; Flags: nowait

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
