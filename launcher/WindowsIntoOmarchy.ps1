param([switch]$Resume)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

$native = Join-Path $projectRoot 'WindowsIntoOnarchy.exe'
if (Test-Path -LiteralPath $native -PathType Leaf) {
    $arguments = if ($Resume) { '--resume' } else { '' }
    Start-Process -FilePath $native -ArgumentList $arguments | Out-Null
    exit 0
}

. (Join-Path $projectRoot 'scripts\experience\Experience.Common.ps1')
Add-Type -AssemblyName PresentationFramework

# Compatibility surface only. v0.3 packages launch the native WPF executable.
# The former developer path used Prepare.ps1 -LaunchAfter -NoPause; the native
# experience now calls one lifecycle orchestrator instead.
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Into Onarchy" Width="620" Height="430" WindowStartupLocation="CenterScreen"
        Background="#0B0D0D" Foreground="#F2F1EA" FontFamily="Segoe UI" ResizeMode="NoResize">
  <Window.Resources>
    <Style TargetType="Button"><Setter Property="Padding" Value="18,12"/><Setter Property="Background" Value="#C9FF36"/><Setter Property="Foreground" Value="#0B0D0D"/><Setter Property="BorderBrush" Value="#C9FF36"/><Setter Property="FontWeight" Value="SemiBold"/><Style.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter Property="BorderThickness" Value="2"/></Trigger></Style.Triggers></Style>
  </Window.Resources>
  <Grid Margin="42"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel><TextBlock Text="OM//WIN  COMPATIBILITY" Foreground="#C9FF36" FontFamily="Consolas"/><TextBlock Text="Windows Into Onarchy" FontSize="32" FontWeight="Light" Margin="0,6,0,0"/></StackPanel>
    <StackPanel Grid.Row="1" VerticalAlignment="Center"><TextBlock x:Name="StatusText" Text="One click prepares the verified factory machine and opens Omarchy." FontSize="18" TextWrapping="Wrap" TextAlignment="Center"/><TextBlock Text="The app downloads verified upstream components. Windows drives, folders, and physical devices are never attached." Foreground="#9BA39F" TextWrapping="Wrap" TextAlignment="Center" Margin="20,14,20,0"/></StackPanel>
    <Button x:Name="PrepareButton" Grid.Row="2" Content="Download &amp; enter Omarchy (~6 GB)"/>
    <StackPanel Visibility="Collapsed"><Ellipse x:Name="HostDot"/><Ellipse x:Name="HypervisorDot"/><Ellipse x:Name="RuntimeDot"/><Ellipse x:Name="MediaDot"/><Button x:Name="EnableButton"/><Button x:Name="LaunchButton"/><Button x:Name="DisposableButton"/><Button x:Name="DoctorButton"/><Button x:Name="ResetButton"/></StackPanel>
  </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$prepare = $window.FindName('PrepareButton')
$status = $window.FindName('StatusText')
$prepare.Add_Click({
    $experience = Join-Path $projectRoot 'scripts\experience\Experience.ps1'
    Start-OnarchyHiddenPowerShell -Script $experience -Arguments @('-Action','PrepareAndLaunch') | Out-Null
    $prepare.IsEnabled = $false
    $status.Text = 'Setup is running without a terminal. Omarchy will open when ready.'
})
$window.Add_ContentRendered({ if ($Resume) { $prepare.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) } })
[void]$window.ShowDialog()
