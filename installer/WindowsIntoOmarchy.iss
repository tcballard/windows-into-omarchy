#define MyAppName "Windows Into Omarchy"
#define MyAppVersion "0.2.0"
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
#ifdef BundleQemuRuntime
OutputBaseFilename=Windows-Into-Omarchy-v{#MyAppVersion}-setup-with-qemu-unsigned
#else
OutputBaseFilename=Windows-Into-Omarchy-v{#MyAppVersion}-setup-unsigned
#endif
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
SetupLogging=yes
LicenseFile=..\LICENSE

[Files]
Source: "..\Start-WindowsIntoOmarchy.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\WindowsIntoOmarchy.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\*"; DestDir: "{app}\assets"; Excludes: "cidata.img"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\image\cidata\*"; DestDir: "{app}\image\cidata"; Flags: ignoreversion
Source: "..\launcher\*"; DestDir: "{app}\launcher"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\scripts\*.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\runtime\README.md"; DestDir: "{app}\runtime"; Flags: ignoreversion
#ifdef BundleQemuRuntime
Source: "..\runtime\qemu\*"; DestDir: "{app}\runtime\qemu"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{autoprograms}\Windows Into Omarchy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\WindowsIntoOmarchy.vbs"""; WorkingDir: "{app}"
Name: "{userdesktop}\Windows Into Omarchy"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\WindowsIntoOmarchy.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\WindowsIntoOmarchy.vbs"""; Description: "Launch Windows Into Omarchy"; Flags: nowait postinstall skipifsilent
