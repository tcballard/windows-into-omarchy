using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace WindowsIntoOnarchy;

public sealed class ExperienceController : IDisposable
{
    private readonly string projectRoot;
    private readonly string progressPath;
    private readonly JsonSerializerOptions json = new() { PropertyNameCaseInsensitive = true };
    private Process? worker;

    public ExperienceController()
    {
        projectRoot = FindProjectRoot();
        var dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Windows Into Onarchy");
        progressPath = Path.Combine(dataRoot, "Experience", "progress.json");
    }

    public bool IsBusy => worker is { HasExited: false };
    public string DataRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Windows Into Onarchy");
    public string LogRoot => Path.Combine(DataRoot, "Logs");

    public ExperienceState? ReadState()
    {
        try
        {
            if (!File.Exists(progressPath)) return null;
            using var stream = new FileStream(progressPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return JsonSerializer.Deserialize<ExperienceState>(stream, json);
        }
        catch (IOException) { return null; }
        catch (JsonException) { return null; }
    }

    public void Inspect() => StartExperience("Inspect");
    public void PrepareAndLaunch() => StartExperience("PrepareAndLaunch");
    public void Launch() => StartExperience("Launch");
    public void Disposable() => StartExperience("Disposable");

    public void EnableAcceleration()
    {
        EnsureIdle();
        using (var registration = StartPowerShell(Path.Combine(projectRoot, "scripts", "experience", "Resume-Registration.ps1"), ["-Mode", "Register"], elevated: false))
        {
            registration.WaitForExit();
            if (registration.ExitCode != 0) throw new InvalidOperationException("Windows could not register the one-time post-restart continuation.");
        }
        var script = Path.Combine(projectRoot, "scripts", "experience", "Enable-Acceleration.ps1");
        worker = StartPowerShell(script, [], elevated: true);
    }

    public void ClearResume()
    {
        using var clearing = StartPowerShell(Path.Combine(projectRoot, "scripts", "experience", "Resume-Registration.ps1"), ["-Mode", "Clear"], elevated: false);
        clearing.WaitForExit();
    }

    public void RestartWindows()
    {
        Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5 /c \"Windows Into Onarchy setup will resume after sign-in.\"")
        { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden });
    }

    public void ArchiveAndReset()
    {
        EnsureIdle();
        worker = StartPowerShell(Path.Combine(projectRoot, "scripts", "experience", "Archive-ActiveMachine.ps1"), ["-Force"], elevated: false);
    }

    public void OpenFolder(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }

    private void StartExperience(string action)
    {
        EnsureIdle();
        var script = Path.Combine(projectRoot, "scripts", "experience", "Experience.ps1");
        worker = StartPowerShell(script, ["-Action", action], elevated: false);
    }

    private static Process StartPowerShell(string script, IReadOnlyList<string> arguments, bool elevated)
    {
        if (!File.Exists(script)) throw new FileNotFoundException("The signed experience helper is missing.", script);
        var command = $"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{script}\"";
        foreach (var argument in arguments) command += $" \"{argument.Replace("\"", "\\\"")}\"";
        var start = new ProcessStartInfo("powershell.exe", command)
        {
            UseShellExecute = elevated,
            CreateNoWindow = !elevated,
            WindowStyle = ProcessWindowStyle.Hidden,
            Verb = elevated ? "runas" : ""
        };
        return Process.Start(start) ?? throw new InvalidOperationException("Windows could not start the experience helper.");
    }

    private void EnsureIdle()
    {
        if (IsBusy) throw new InvalidOperationException("Setup is already working.");
        worker?.Dispose();
        worker = null;
    }

    private static string FindProjectRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (Directory.Exists(Path.Combine(current.FullName, "scripts", "experience"))) return current.FullName;
            current = current.Parent;
        }
        throw new DirectoryNotFoundException("Windows Into Onarchy helpers were not found beside the app.");
    }

    public void Dispose() => worker?.Dispose();
}
