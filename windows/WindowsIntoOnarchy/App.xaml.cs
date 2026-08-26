using System.Windows;

namespace WindowsIntoOnarchy;

public partial class App : Application
{
    public static bool IsResume { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        IsResume = e.Args.Any(a => string.Equals(a, "--resume", StringComparison.OrdinalIgnoreCase));
        base.OnStartup(e);
    }
}
