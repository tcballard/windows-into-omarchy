#define MyAppName "Windows Into Omarchy"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Windows Into Omarchy contributors"
#define MyAppExeName "Start-WindowsIntoOmarchy.cmd"

[Setup]
AppId={{68E9DE88-C58C-4F57-A5B6-0BD014E96E95}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Windows Into Omarchy
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
OutputDir=..\dist
OutputBaseFilename=Windows-Into-Omarchy-v{#MyAppVersion}-setup-unsigned
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
SetupLogging=yes
LicenseFile=..\LICENSE

[Files]
Source: "..\Start-WindowsIntoOmarchy.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\launcher\*"; DestDir: "{app}\launcher"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\scripts\*.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Windows Into Omarchy"; Filename: "{app}\Start-WindowsIntoOmarchy.cmd"; WorkingDir: "{app}"
Name: "{userdesktop}\Windows Into Omarchy"; Filename: "{app}\Start-WindowsIntoOmarchy.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\Start-WindowsIntoOmarchy.cmd"; Description: "Launch Windows Into Omarchy"; Flags: nowait postinstall skipifsilent
