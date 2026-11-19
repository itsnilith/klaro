; klaro. Windows Installer (Inno Setup 6)
; Per-user installation under %LOCALAPPDATA%\Programs\Klaro — no admin required.

#define MyAppName "klaro."
#define MyAppVersion "1.0.0"
#define MyAppPublisher "itsnilith"
#define MyAppURL "https://github.com/itsnilith/klaro"
#define MyAppExeName "klaro.exe"

[Setup]
AppId={{8F9E4A2D-5B1E-4C7A-9F3D-2A6E1C8B4D09}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Klaro
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\LICENSE
OutputDir=..
OutputBaseFilename=Klaro-Windows-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\Klaro-Portable\klaro.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Klaro-Portable\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Klaro-Portable\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Klaro-Portable\NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Klaro-Portable\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Klaro-Portable\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Klaro-Portable\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\Klaro-Portable\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
Name: "{app}\userdata"
Name: "{app}\config"
Name: "{app}\models"
Name: "{app}\cache"
Name: "{app}\logs"
Name: "{app}\backups"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
