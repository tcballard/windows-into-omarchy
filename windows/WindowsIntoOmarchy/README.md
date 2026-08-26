# Native app build

Build the public Windows entry point on Windows with the .NET 8 SDK:

```powershell
dotnet publish .\windows\WindowsIntoOmarchy\WindowsIntoOmarchy.csproj -c Release -r win-x64 --self-contained true -o .\dist\native-app
```

The project publishes a self-contained, single-file x64 WPF `WinExe` using the
original Windows Into Omarchy icon. Release packaging places the resulting
`WindowsIntoOmarchy.exe` at the application root beside `scripts`, `factory`,
and the documentation. The installed shortcut targets that executable—not
PowerShell, `cmd.exe`, `wscript.exe`, or the compatibility launcher.

Authenticode signing happens after publish and before installer assembly. CI
must compile this project and run the PowerShell 5.1 parser contracts on a
Windows runner; Linux static tests cannot substitute for that gate.
