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
; Authenticode, when build.ps1 passes /DSign and the "wfh" sign tool.
#ifdef Sign
SignTool=wfh
SignedUninstaller=yes
#endif
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
; The troubleshooting report; it works with the helper not running (2026-10-29).
Source: "..\tools\collect-report.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; Versions up to 0.2.0 started a waiting helper at sign-in. Remove that
; entry when upgrading: the helper now starts with the game.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#MyAppName}"; Flags: deletevalue

[Icons]
Name: "{autoprograms}\{#MyAppName}\Add Voyager Access to the game"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-mod"
Name: "{autoprograms}\{#MyAppName}\Read me"; Filename: "{app}\README.txt"
Name: "{autoprograms}\{#MyAppName}\Copy a troubleshooting report"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\collect-report.ps1"" -Box"

[Messages]
; One box at the end (Casey, 2026-10-11): the Finish page says it is ready,
; and --install-mod --from-setup shows no box of its own on success.
FinishedLabel=Voyager Access is installed and added to Star Trek: Voyager - Across the Unknown.%n%nStart the game from Steam as usual. Speech starts when the game loads.
FinishedLabelNoIcons=Voyager Access is installed and added to Star Trek: Voyager - Across the Unknown.%n%nStart the game from Steam as usual. Speech starts when the game loads.

[Run]
; Interactive install: adding the mod to the game runs from [Code]
; (CurStepChanged), so its exit code can change the Finish page. A silent
; install (the updater) skips it; the run without arguments that follows
; puts the new mod in, sets the launch options if they are missing (asking
; to restart Steam), and starts the game again after an update.
; Only for silent installs (updates): an interactive install's
; --install-mod has already done this, and a second Steam prompt there
; would be confusing.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait skipifnotsilent

; The Finish page's checkbox, ticked: Finish starts the game through Steam
; (Casey, 2026-10-11). Silent installs never show it.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--start-game"; Description: "Start Star Trek: Voyager - Across the Unknown"; Flags: postinstall nowait skipifsilent

; The mod and the launch options come out in CurUninstallStepChanged
; ([Code]), not [UninstallRun], whose exit code Inno Setup ignores: a failed
; --uninstall-mod then deleted VoyagerAccess.exe while Steam's launch option
; still started it (Fable review, 2026-11-10).

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\VoyagerAccess"
; The updater's downloads (app.py fetch_update; Fable review, 2026-11-10).
Type: filesandordirs; Name: "{%TEMP}\VoyagerAccessUpdater"

[Code]
// Stops the helper, then takes the mod and the launch options out. This
// runs at usUninstall, after the player has answered Yes to Inno Setup's
// own "completely remove" question (InitializeUninstall comes before that
// question, so answering No there left the mod half removed; pre-merge
// review, 2026-11-10). Abort stops the uninstall from here before anything
// is deleted, so the exe the launch option starts and the record of what
// to undo both stay. Exit 1 (the game left running, Steam would not close)
// stops it; exit 3 (app.py UNINSTALL_ERROR: a file that will not go,
// anything unexpected, the same on every try) asks whether to uninstall
// anyway. An exe that will not start at all does not block the uninstall.
// The helper is stopped first: one waiting for a Steam game to close would
// otherwise set the launch options again once Steam closes for the edit.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if not Exec(ExpandConstant('{app}\{#MyAppExeName}'), '--uninstall-mod', '', SW_SHOWNORMAL,
      ewWaitUntilTerminated, ResultCode) then
    Log('--uninstall-mod could not be started; uninstalling anyway')
  else if ResultCode = 3 then
  begin
    Log('--uninstall-mod exited 3 (an error that may repeat); asking');
    if SuppressibleMsgBox('Voyager Access could not take all of its files back out of the game.'
        + #13#10#13#10 + 'Uninstall Voyager Access anyway? Choose Yes to remove it now; Steam''s '
        + '"Verify integrity of game files" puts the game''s own files right afterwards. '
        + 'Choose No to stop, and nothing is uninstalled.', mbError, MB_YESNO, IDNO) <> IDYES then
      Abort;
  end
  else if ResultCode = 4 then
  begin
    // app.py LAUNCH_FILE_ERROR: Steam's settings file could not be changed
    // (read-only, for example). The helper has already named the file and
    // what to do, so no "close the game" box, which could not help here.
    Log('--uninstall-mod exited 4 (a Steam settings file could not be changed); uninstall stopped');
    Abort;
  end
  else if ResultCode <> 0 then
  begin
    Log(Format('--uninstall-mod exited %d; uninstall stopped', [ResultCode]));
    SuppressibleMsgBox('Voyager Access could not take the mod or its Steam launch options back '
      + 'out of the game, so nothing was uninstalled. Close the game, and any other game '
      + 'running in Steam, then uninstall Voyager Access again.', mbError, MB_OK, IDOK);
    Abort;
  end;
  // A helper stopped while it waited for a Steam game to close leaves its
  // one-time sign-in entry (app.py _run_once) pointing at this exe. Kept
  // when the uninstall stops, so that setup still finishes at sign-in.
  RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\RunOnce', 'Voyager Access');
end;

// The waiting helper keeps VoyagerAccess.exe open; stop it so the files
// can be replaced. The new copy is started again by [Run].
// Whether the game is running (both exes in voyager\steam.py GAME_EXES).
function GameRunning(): Boolean;
var
  Locator, Service, Procs: Variant;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Procs := Service.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE '
      + 'Name = ''STVoyagerSteam-Win64-Shipping.exe'' OR Name = ''STVoyager-Win64-Shipping.exe''');
    Result := Procs.Count > 0;
  except
    Log('Could not check whether the game is running: ' + GetExceptionMessage);
  end;
end;

// A silent run is an update the helper started when the game closed. If
// the game is running again by now, its helper is serving it: refuse
// instead of killing that helper, and leave update-deferred.txt so the
// helper does not count this as a failed update; it installs at the next
// close (Fable review and Casey, 2026-11-10).
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  if WizardSilent and GameRunning() then
  begin
    ForceDirectories(ExpandConstant('{localappdata}\VoyagerAccess'));
    SaveStringToFile(ExpandConstant('{localappdata}\VoyagerAccess\update-deferred.txt'), 'game running', False);
    Result := 'The game is running. The Voyager Access update installs when the game closes.';
    exit;
  end;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// Adding the mod to the game (interactive installs only). The Finish page
// said "installed and added to the game" even after the box saying the game
// is not installed (JAWS in the VM, 2026-10-15). --install-mod exits 0 when
// added, 2 (NO_GAME in app.py) when the game is missing, 1 when it failed.
var
  ModResult: Integer;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and not WizardSilent then
  begin
    if not Exec(ExpandConstant('{app}\{#MyAppExeName}'), '--install-mod --from-setup', '',
        SW_SHOWNORMAL, ewWaitUntilTerminated, ModResult) then
      ModResult := 1;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and (ModResult <> 0) then
  begin
    if ModResult = 2 then
      WizardForm.FinishedLabel.Caption :=
        'Voyager Access is installed, but Star Trek: Voyager - Across the Unknown is not installed in Steam yet.' + #13#10#13#10 +
        'After installing the game, open the Start menu and choose "Add Voyager Access to the game", or run this installer again.'
    else
      WizardForm.FinishedLabel.Caption :=
        'Voyager Access is installed, but it could not be added to the game.' + #13#10#13#10 +
        'Open the Start menu and choose "Add Voyager Access to the game" to try again.';
    // No "Start the game" box when there is no game to start.
    WizardForm.RunList.Visible := False;
    if WizardForm.RunList.Items.Count > 0 then
      WizardForm.RunList.Checked[0] := False;
    // Focus is left where the hidden box was: JAWS then reads the message
    // above, and Enter still presses Finish (the default button). With
    // focus moved to Finish it said only "Finish button" and skipped the
    // message (VM, 2026-10-15).
  end;
end;
