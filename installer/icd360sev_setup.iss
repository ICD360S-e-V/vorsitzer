; ICD360S e.V - Vorsitzer Portal Installer
; Inno Setup Script

#define MyAppName "ICD360S e.V - Vorsitzer"
#define MyAppVersion "1.0.36"
#define MyAppPublisher "ICD360S e.V"
#define MyAppURL "https://icd360sev.icd360s.de"
#define MyAppExeName "ICD360S_eV.exe"
#define MyAppId "{{8A5E4B2C-9F3D-4E1A-B7C6-D8E9F0A1B2C3}"

[Setup]
; Application info
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/downloads/vorsitzer/windows/

; Installation settings
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=..\build\installer
OutputBaseFilename=icd360sev_vorsitzer_setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; Privileges - admin needed for runtime installs
PrivilegesRequired=admin

; Uninstaller
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Version info
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoCopyright=Copyright (C) 2026 ICD360S e.V.
VersionInfoDescription=ICD360S e.V Vorsitzer Portal
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoOriginalFileName=icd360sev_vorsitzer_setup.exe

; Architecture
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Runtime installers
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

; Main executable
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; DLL files
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\desktop_audio_capture_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_secure_storage_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_webrtc_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\libwebrtc.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\local_notifier_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\system_tray_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\webview_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\windows_single_instance_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\windows_taskbar_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\desktop_multi_window_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; Data folder (Flutter assets)
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Shortcuts point to launcher (with auto-recovery) instead of direct EXE
Name: "{group}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{group}\Vorherige Version wiederherstellen"; Filename: "{app}\backup\Restore_Previous_Version.bat"; IconFilename: "{sys}\shell32.dll"; IconIndex: 238
Name: "{autodesktop}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Install Visual C++ Runtime silently
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Visual C++ Runtime wird installiert..."; Flags: waituntilterminated

; Install WebView2 Runtime silently
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "WebView2 Runtime wird installiert..."; Flags: waituntilterminated

; Launch app via launcher - Interactive install (with checkbox, skip in silent mode)
Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Launch app via launcher - Silent install ONLY (auto-update) - skip if NOT silent
Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; Flags: nowait runhidden skipifnotsilent

[Code]
var
  BackupCreated: Boolean;

// Close running application before install/uninstall
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  BackupCreated := False;
  // Try to close running instance
  if Exec('taskkill', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Sleep(500); // Wait for process to close
  end;
end;

// Backup current installation before updating
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  AppDir, BackupDir: String;
  FindRec: TFindRec;
begin
  Result := '';
  AppDir := ExpandConstant('{autopf}\{#MyAppName}');
  BackupDir := AppDir + '\backup';

  // Check if app is already installed
  if FileExists(AppDir + '\{#MyAppExeName}') then
  begin
    // Create backup directory
    if not DirExists(BackupDir) then
      CreateDir(BackupDir);

    // Backup EXE
    if FileCopy(AppDir + '\{#MyAppExeName}', BackupDir + '\{#MyAppExeName}', False) then
      BackupCreated := True;

    // Backup all DLL files
    if FindFirst(AppDir + '\*.dll', FindRec) then
    begin
      try
        repeat
          FileCopy(AppDir + '\' + FindRec.Name, BackupDir + '\' + FindRec.Name, False);
        until not FindNext(FindRec);
      finally
        FindClose(FindRec);
      end;
    end;

    // Backup data folder
    if DirExists(AppDir + '\data') then
    begin
      if not DirExists(BackupDir + '\data') then
        CreateDir(BackupDir + '\data');
      // Note: Full recursive copy would need more code, but main files are covered
    end;

    // Create restore batch script
    SaveStringToFile(BackupDir + '\Restore_Previous_Version.bat',
      '@echo off' + #13#10 +
      'echo ========================================' + #13#10 +
      'echo  ICD360S e.V - Vorherige Version wiederherstellen' + #13#10 +
      'echo ========================================' + #13#10 +
      'echo.' + #13#10 +
      'echo Dieses Script stellt die vorherige Version wieder her.' + #13#10 +
      'echo.' + #13#10 +
      'pause' + #13#10 +
      'echo.' + #13#10 +
      'echo Beende laufende Anwendung...' + #13#10 +
      'taskkill /F /IM {#MyAppExeName} 2>nul' + #13#10 +
      'timeout /t 2 >nul' + #13#10 +
      'echo.' + #13#10 +
      'echo Stelle vorherige Version wieder her...' + #13#10 +
      'copy /Y "%~dp0*.exe" "%~dp0.."' + #13#10 +
      'copy /Y "%~dp0*.dll" "%~dp0.."' + #13#10 +
      'echo.' + #13#10 +
      'echo Fertig! Die vorherige Version wurde wiederhergestellt.' + #13#10 +
      'echo.' + #13#10 +
      'echo Starte Anwendung...' + #13#10 +
      'start "" "%~dp0..\{#MyAppExeName}"' + #13#10 +
      'echo.' + #13#10 +
      'pause' + #13#10,
      False);

    // Create a simple info file
    SaveStringToFile(BackupDir + '\info.txt',
      'Backup erstellt am: ' + GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':') + #13#10 +
      'Von Version: vorherige Installation' + #13#10 +
      'Neue Version: {#MyAppVersion}' + #13#10 + #13#10 +
      'Um die vorherige Version wiederherzustellen:' + #13#10 +
      '1. Fuehren Sie "Restore_Previous_Version.bat" aus' + #13#10 +
      '   ODER' + #13#10 +
      '2. Start Menu -> ICD360S e.V -> Vorherige Version wiederherstellen' + #13#10,
      False);
  end;
end;

// Create the launcher script with auto-recovery functionality
procedure CreateLauncherScript();
var
  AppDir: String;
  LauncherScript: String;
  CRLF: String;
  Q: String;
begin
  AppDir := ExpandConstant('{app}');
  CRLF := Chr(13) + Chr(10);
  Q := Chr(39);

  LauncherScript :=
    Q + ' ICD360S e.V - Launcher with Auto-Recovery' + CRLF +
    'Option Explicit' + CRLF + CRLF +
    'Dim WshShell, fso, appPath, backupPath, exeName, proc' + CRLF +
    'Dim startTime, exitCode, crashTimeout' + CRLF + CRLF +
    'Set WshShell = CreateObject("WScript.Shell")' + CRLF +
    'Set fso = CreateObject("Scripting.FileSystemObject")' + CRLF + CRLF +
    'exeName = "{#MyAppExeName}"' + CRLF +
    'appPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\" & exeName' + CRLF +
    'backupPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\backup"' + CRLF +
    'crashTimeout = 5' + CRLF + CRLF +
    'If Not fso.FileExists(appPath) Then' + CRLF +
    '    MsgBox "Die Anwendung wurde nicht gefunden:" & vbCrLf & appPath, vbCritical, "ICD360S e.V - Fehler"' + CRLF +
    '    WScript.Quit 1' + CRLF +
    'End If' + CRLF + CRLF +
    'On Error Resume Next' + CRLF +
    'Set proc = WshShell.Exec("""" & appPath & """")' + CRLF + CRLF +
    'If Err.Number <> 0 Then' + CRLF +
    '    Call HandleCrash()' + CRLF +
    '    WScript.Quit 1' + CRLF +
    'End If' + CRLF +
    'On Error GoTo 0' + CRLF + CRLF +
    'startTime = Timer' + CRLF +
    'Do While proc.Status = 0' + CRLF +
    '    WScript.Sleep 200' + CRLF +
    '    If Timer - startTime > crashTimeout Then' + CRLF +
    '        WScript.Quit 0' + CRLF +
    '    End If' + CRLF +
    'Loop' + CRLF + CRLF +
    'exitCode = proc.ExitCode' + CRLF +
    'If exitCode <> 0 Then' + CRLF +
    '    Call HandleCrash()' + CRLF +
    'End If' + CRLF +
    'WScript.Quit exitCode' + CRLF + CRLF +
    'Sub HandleCrash()' + CRLF +
    '    Dim response' + CRLF +
    '    If fso.FileExists(backupPath & "\" & exeName) Then' + CRLF +
    '        response = MsgBox("Die Anwendung konnte nicht gestartet werden." & vbCrLf & vbCrLf & "Moechten Sie zur vorherigen Version zurueckkehren?", vbYesNo + vbQuestion, "ICD360S e.V - Startfehler")' + CRLF +
    '        If response = vbYes Then' + CRLF +
    '            Call RestorePreviousVersion()' + CRLF +
    '        End If' + CRLF +
    '    Else' + CRLF +
    '        MsgBox "Die Anwendung konnte nicht gestartet werden." & vbCrLf & vbCrLf & "Kein Backup verfuegbar. Bitte laden Sie die Anwendung erneut herunter: https://icd360sev.icd360s.de/downloads/windows/", vbCritical, "ICD360S e.V - Startfehler"' + CRLF +
    '    End If' + CRLF +
    'End Sub' + CRLF + CRLF +
    'Sub RestorePreviousVersion()' + CRLF +
    '    Dim parentDir, file' + CRLF +
    '    parentDir = fso.GetParentFolderName(backupPath)' + CRLF +
    '    On Error Resume Next' + CRLF +
    '    fso.CopyFile backupPath & "\" & exeName, parentDir & "\" & exeName, True' + CRLF +
    '    For Each file In fso.GetFolder(backupPath).Files' + CRLF +
    '        If LCase(fso.GetExtensionName(file.Name)) = "dll" Then' + CRLF +
    '            fso.CopyFile file.Path, parentDir & "\" & file.Name, True' + CRLF +
    '        End If' + CRLF +
    '    Next' + CRLF +
    '    On Error GoTo 0' + CRLF +
    '    MsgBox "Die vorherige Version wurde wiederhergestellt." & vbCrLf & vbCrLf & "Die Anwendung wird jetzt gestartet.", vbInformation, "ICD360S e.V - Wiederherstellung"' + CRLF +
    '    WshShell.Run """" & parentDir & "\" & exeName & """", 1, False' + CRLF +
    'End Sub' + CRLF;

  SaveStringToFile(AppDir + '\Launcher.vbs', LauncherScript, False);
end;

// Called after installation is complete
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    CreateLauncherScript();
  end;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Close running instance before uninstall
  if Exec('taskkill', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Sleep(500);
  end;
end;
