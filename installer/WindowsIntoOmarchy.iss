#define MyAppName "Windows Into Omarchy"
#ifndef MyAppVersion
#define MyAppVersion "0.3.0"
#endif
#define MyAppPublisher "Windows Into Omarchy contributors"
#define MyAppExeName "WindowsIntoOmarchy.exe"

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
SetupIconFile=..\assets\WindowsIntoOmarchy.ico
UninstallDisplayIcon={app}\assets\WindowsIntoOmarchy.ico

[Files]
Source: "..\dist\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
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
Source: "..\scripts\experience\*.ps1"; DestDir: "{app}\scripts\experience"; Flags: ignoreversion
Source: "..\runtime\README.md"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "..\runtime\portable-runtime.lock.json"; DestDir: "{app}\runtime"; Flags: ignoreversion
Source: "..\runtime\compliance\*"; DestDir: "{app}\runtime\compliance"; Flags: ignoreversion
Source: "..\factory\*.json"; DestDir: "{app}\factory"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\factory\README.md"; DestDir: "{app}\factory"; Flags: ignoreversion
#ifdef FactorySidecars
Source: "{src}\*.part*"; DestDir: "{app}\factory\parts"; Flags: external ignoreversion
#endif
#ifdef BundleQemuRuntime
Source: "..\runtime\qemu\*"; DestDir: "{app}\runtime\qemu"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{autoprograms}\Windows Into Omarchy"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\Windows Into Omarchy"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Windows Into Omarchy"; Flags: nowait postinstall skipifsilent
