using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace WindowsIntoOmarchy;

public partial class MainWindow : Window
{
    private static readonly Brush Green = new SolidColorBrush(Color.FromRgb(0xC9, 0xFF, 0x36));
    private static readonly Brush Amber = new SolidColorBrush(Color.FromRgb(0xFF, 0xB4, 0x54));
    private static readonly Brush Grey = new SolidColorBrush(Color.FromRgb(0x68, 0x70, 0x6C));
    private readonly ExperienceController controller = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(650) };
    private ExperienceState? state;
    private DateTime renderedUpdate;
    private string previousPhase = "";
    private bool resumeClearedForFailure;

    public MainWindow()
    {
        InitializeComponent();
        timer.Tick += (_, _) => RefreshState();
        Loaded += OnLoaded;
        Closing += OnClosing;
        Closed += (_, _) => { timer.Stop(); controller.Dispose(); };
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        timer.Start();
        try
        {
            if (App.IsResume) controller.PrepareAndLaunch();
            else controller.Inspect();
        }
        catch (Exception error) { ShowLocalFailure(error); }
    }

    private void RefreshState()
    {
        var next = controller.ReadState();
        if (next is null || next.UpdatedAtUtc <= renderedUpdate) return;
        if (next.Phase == "Checking" && next.Action == "Continue" && !controller.IsBusy)
        {
            try { controller.PrepareAndLaunch(); } catch (Exception error) { ShowLocalFailure(error); }
            return;
        }
        renderedUpdate = next.UpdatedAtUtc;
        state = next;
        if (next.Phase == "Failed" && next.ErrorCode == "HYPERVISOR_ENABLE_FAILED" && !controller.IsBusy && !resumeClearedForFailure)
        {
            resumeClearedForFailure = true;
            try { controller.ClearResume(); } catch { }
        }
        if (next.Phase != "Failed") resumeClearedForFailure = false;
        Headline.Text = next.Headline;
        Detail.Text = next.Detail;
        Phase.Text = next.Phase.ToUpperInvariant();
        Progress.IsIndeterminate = next.Indeterminate;
        if (!next.Indeterminate) Progress.Value = Math.Clamp(next.Percent, 0, 100);

        Primary.IsEnabled = true;
        Primary.Content = next.Phase switch
        {
            "NeedsAcceleration" => "Enable and continue",
            "AwaitingRestart" => "Restart and continue",
            "Ready" when next.Action == "Prepare" => "Set up and enter Omarchy",
            "Ready" => "Enter Omarchy",
            "Failed" => "Try again",
            "Blocked" => "Open machine files",
            "Running" => "Omarchy is open",
            _ => "Working…"
        };
        if (next.Phase is "Checking" or "EnablingAcceleration" or "Preparing" or "CreatingMachine" or "Launching" or "Running") Primary.IsEnabled = false;
        var busy = next.Phase is "EnablingAcceleration" or "Preparing" or "CreatingMachine" or "Launching" or "Running";
        Disposable.IsEnabled = !busy && next.Phase == "Ready" && next.Action != "Prepare";
        Reset.IsEnabled = !busy;
        Technical.Text = string.IsNullOrWhiteSpace(next.ErrorCode) ? "Resources are selected automatically for this PC." : $"Recovery code: {next.ErrorCode}";

        PcDot.Fill = next.Phase == "Blocked" ? Amber : Green;
        AccelerationDot.Fill = next.Phase is "NeedsAcceleration" or "EnablingAcceleration" or "AwaitingRestart" ? Amber : Green;
        var engineReady = next.Percent >= 60 || next.Phase == "Running" || (next.Phase == "Ready" && next.Action != "Prepare");
        var omarchyReady = next.Percent >= 90 || next.Phase == "Running" || (next.Phase == "Ready" && next.Action != "Prepare");
        EngineDot.Fill = engineReady ? Green : next.Phase == "Preparing" ? Amber : Grey;
        OmarchyDot.Fill = omarchyReady ? Green : next.Phase is "Preparing" or "CreatingMachine" ? Amber : Grey;

        if (next.Phase == "Running" && WindowState != WindowState.Minimized) WindowState = WindowState.Minimized;
        if (previousPhase == "Running" && (next.Phase is "Ready" or "Failed")) { WindowState = WindowState.Normal; Activate(); }
        previousPhase = next.Phase;
    }

    private void Primary_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            switch (state?.Phase)
            {
                case "NeedsAcceleration": controller.EnableAcceleration(); break;
                case "AwaitingRestart":
                    if (MessageBox.Show("Restart Windows now? Setup will reopen and continue automatically after you sign in.", "Continue Windows Into Omarchy", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes) controller.RestartWindows();
                    break;
                case "Ready" when state.Action == "Prepare": controller.PrepareAndLaunch(); break;
                case "Ready": controller.Launch(); break;
                case "Failed": controller.Inspect(); break;
                case "Blocked": controller.OpenFolder(controller.DataRoot); break;
            }
        }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223)
        {
            try { controller.ClearResume(); } catch { }
            ShowLocalFailure(new InvalidOperationException("Approval was cancelled. No changes were made."));
        }
        catch (Exception error) { ShowLocalFailure(error); }
    }

    private void Disposable_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Changes in this session are discarded when Omarchy closes. Continue?", "Disposable session", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            try { controller.Disposable(); } catch (Exception error) { ShowLocalFailure(error); }
    }

    private void Logs_Click(object sender, RoutedEventArgs e) => controller.OpenFolder(controller.LogRoot);
    private void Files_Click(object sender, RoutedEventArgs e) => controller.OpenFolder(controller.DataRoot);
    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Archive the current private machine and start fresh? The archive remains recoverable.", "Archive and reset", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            try { controller.ArchiveAndReset(); } catch (Exception error) { ShowLocalFailure(error); }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!controller.IsBusy) return;
        e.Cancel = true;
        MessageBox.Show("Setup is still working safely. Leave this window open until Omarchy appears.", "Windows Into Omarchy", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void ShowLocalFailure(Exception error)
    {
        state = new ExperienceState { Phase = "Failed", Headline = "Setup paused safely", Detail = error.Message, Action = "Retry", ErrorCode = "WINDOWS_APP_FAILED", UpdatedAtUtc = DateTime.UtcNow };
        renderedUpdate = DateTime.MinValue;
        Headline.Text = state.Headline; Detail.Text = state.Detail; Phase.Text = "FAILED"; Primary.Content = "Try again"; Primary.IsEnabled = true; Technical.Text = $"Recovery code: {state.ErrorCode}";
    }
}
