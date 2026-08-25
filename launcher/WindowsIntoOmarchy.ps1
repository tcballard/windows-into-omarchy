Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'scripts\Common.ps1')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Into Omarchy" Width="1040" Height="720"
        MinWidth="900" MinHeight="640" WindowStartupLocation="CenterScreen"
        Background="#0B0D0D" Foreground="#F2F1EA" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#141717"/>
    <SolidColorBrush x:Key="PanelRaised" Color="#1A1E1D"/>
    <SolidColorBrush x:Key="Line" Color="#343A38"/>
    <SolidColorBrush x:Key="Accent" Color="#C9FF36"/>
    <SolidColorBrush x:Key="Muted" Color="#9BA39F"/>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#202523"/>
      <Setter Property="Foreground" Value="#F2F1EA"/>
      <Setter Property="BorderBrush" Value="#46504C"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
          <Setter Property="Background" Value="#29302D"/>
        </Trigger>
        <Trigger Property="IsKeyboardFocused" Value="True">
          <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
          <Setter Property="BorderThickness" Value="2"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.42"/>
          <Setter Property="Cursor" Value="Arrow"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="#0B0D0D"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#202523"/>
      <Setter Property="Foreground" Value="#F2F1EA"/>
      <Setter Property="BorderBrush" Value="#46504C"/>
      <Setter Property="Padding" Value="9,7"/>
      <Setter Property="MinWidth" Value="110"/>
    </Style>
  </Window.Resources>

  <Grid Margin="34,28,34,26">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="18"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="OM//WIN  01" Foreground="{StaticResource Accent}" FontFamily="Consolas" FontSize="13" FontWeight="Bold"/>
        <TextBlock Text="Windows Into Omarchy" FontSize="38" FontWeight="Light" Margin="0,5,0,0"/>
        <TextBlock Text="One app. One click. Your own contained Omarchy machine." Foreground="{StaticResource Muted}" FontSize="15" Margin="1,4,0,0"/>
      </StackPanel>
      <Button x:Name="RefreshButton" Grid.Column="1" Content="Refresh readiness" VerticalAlignment="Top"/>
    </Grid>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="0.92*"/>
        <ColumnDefinition Width="20"/>
        <ColumnDefinition Width="1.3*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="24">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="18"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <StackPanel>
            <TextBlock Text="BOOT RAIL" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource Muted}"/>
            <TextBlock Text="Four checks. One safe launch." FontSize="20" Margin="0,5,0,0"/>
          </StackPanel>
          <StackPanel Grid.Row="2">
            <Grid Margin="0,2,0,19"><Grid.ColumnDefinitions><ColumnDefinition Width="26"/><ColumnDefinition/></Grid.ColumnDefinitions><Ellipse x:Name="HostDot" Width="10" Height="10" Fill="#68706C" VerticalAlignment="Top" Margin="0,5,0,0"/><StackPanel Grid.Column="1"><TextBlock Text="01  HOST" FontFamily="Consolas" Foreground="{StaticResource Muted}"/><TextBlock x:Name="HostText" Text="Checking Windows..." TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Grid>
            <Border Height="20" Width="1" Background="{StaticResource Line}" HorizontalAlignment="Left" Margin="5,-14,0,4"/>
            <Grid Margin="0,2,0,19"><Grid.ColumnDefinitions><ColumnDefinition Width="26"/><ColumnDefinition/></Grid.ColumnDefinitions><Ellipse x:Name="HypervisorDot" Width="10" Height="10" Fill="#68706C" VerticalAlignment="Top" Margin="0,5,0,0"/><StackPanel Grid.Column="1"><TextBlock Text="02  ACCELERATION" FontFamily="Consolas" Foreground="{StaticResource Muted}"/><TextBlock x:Name="HypervisorText" Text="Checking WHPX..." TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Grid>
            <Border Height="20" Width="1" Background="{StaticResource Line}" HorizontalAlignment="Left" Margin="5,-14,0,4"/>
            <Grid Margin="0,2,0,19"><Grid.ColumnDefinitions><ColumnDefinition Width="26"/><ColumnDefinition/></Grid.ColumnDefinitions><Ellipse x:Name="RuntimeDot" Width="10" Height="10" Fill="#68706C" VerticalAlignment="Top" Margin="0,5,0,0"/><StackPanel Grid.Column="1"><TextBlock Text="03  RUNTIME" FontFamily="Consolas" Foreground="{StaticResource Muted}"/><TextBlock x:Name="RuntimeText" Text="Checking QEMU..." TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Grid>
            <Border Height="20" Width="1" Background="{StaticResource Line}" HorizontalAlignment="Left" Margin="5,-14,0,4"/>
            <Grid Margin="0,2,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="26"/><ColumnDefinition/></Grid.ColumnDefinitions><Ellipse x:Name="MediaDot" Width="10" Height="10" Fill="#68706C" VerticalAlignment="Top" Margin="0,5,0,0"/><StackPanel Grid.Column="1"><TextBlock Text="04  MEDIA" FontFamily="Consolas" Foreground="{StaticResource Muted}"/><TextBlock x:Name="MediaText" Text="Checking Omarchy..." TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Grid>
          </StackPanel>
          <StackPanel Grid.Row="3">
            <Button x:Name="PrepareButton" Style="{StaticResource PrimaryButton}" Content="Download &amp; enter Omarchy (~6 GB)"/>
            <Button x:Name="EnableButton" Style="{StaticResource PrimaryButton}" Content="Enable acceleration &amp; continue"/>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Column="2" Background="{StaticResource PanelRaised}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="26">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <StackPanel>
            <TextBlock Text="MACHINE" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource Muted}"/>
            <TextBlock x:Name="MachineHeadline" Text="Finish preparation to launch" FontSize="24" Margin="0,5,0,0"/>
            <TextBlock x:Name="MachineDetail" Text="Missing components are shown on the boot rail." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,8,0,0"/>
          </StackPanel>

          <Grid Grid.Row="1" Margin="0,28,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="18"/><ColumnDefinition/></Grid.ColumnDefinitions>
            <StackPanel><TextBlock Text="MEMORY" FontFamily="Consolas" FontSize="11" Foreground="{StaticResource Muted}"/><ComboBox x:Name="MemoryCombo" SelectedIndex="0" Margin="0,7,0,0"><ComboBoxItem Content="4096"/><ComboBoxItem Content="8192"/><ComboBoxItem Content="12288"/><ComboBoxItem Content="16384"/></ComboBox></StackPanel>
            <StackPanel Grid.Column="2"><TextBlock Text="PROCESSORS" FontFamily="Consolas" FontSize="11" Foreground="{StaticResource Muted}"/><ComboBox x:Name="CpuCombo" SelectedIndex="0" Margin="0,7,0,0"><ComboBoxItem Content="4"/><ComboBoxItem Content="6"/><ComboBoxItem Content="8"/></ComboBox></StackPanel>
          </Grid>

          <StackPanel Grid.Row="2" VerticalAlignment="Center">
            <Border BorderBrush="#59615E" BorderThickness="1,0,0,0" Padding="16,2,0,2" Margin="0,20,0,25">
              <StackPanel>
                <TextBlock Text="HOST-SAFE BY CONSTRUCTION" Foreground="{StaticResource Accent}" FontFamily="Consolas" FontSize="11"/>
                <TextBlock Text="The guest receives one private virtual disk. Windows drives, folders, and physical devices are never attached." TextWrapping="Wrap" Margin="0,6,0,0"/>
              </StackPanel>
            </Border>
            <Button x:Name="LaunchButton" Style="{StaticResource PrimaryButton}" Content="Enter Omarchy" FontSize="15" Padding="20,14"/>
            <Button x:Name="DisposableButton" Content="Open disposable session" ToolTip="Changes made in this session are discarded when the VM closes."/>
          </StackPanel>

          <WrapPanel Grid.Row="3">
            <Button x:Name="DoctorButton" Content="Diagnostics"/>
            <Button x:Name="OpenDataButton" Content="Open machine data"/>
            <Button x:Name="ResetButton" Content="Archive &amp; reset"/>
          </WrapPanel>
        </Grid>
      </Border>
    </Grid>

    <Grid Grid.Row="3" Margin="0,18,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="StatusText" Text="Checking this PC..." Foreground="{StaticResource Muted}" TextWrapping="Wrap" VerticalAlignment="Center"/>
      <TextBlock Grid.Column="1" Text="LEFT SHIFT + LEFT CTRL + LEFT ALT + G  releases input" Foreground="#707975" FontFamily="Consolas" FontSize="10" VerticalAlignment="Center"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Control([string]$name) { return $window.FindName($name) }
$hostDot = Control 'HostDot'; $hostText = Control 'HostText'
$hypervisorDot = Control 'HypervisorDot'; $hypervisorText = Control 'HypervisorText'
$runtimeDot = Control 'RuntimeDot'; $runtimeText = Control 'RuntimeText'
$mediaDot = Control 'MediaDot'; $mediaText = Control 'MediaText'
$headline = Control 'MachineHeadline'; $detail = Control 'MachineDetail'; $statusText = Control 'StatusText'
$launchButton = Control 'LaunchButton'; $disposableButton = Control 'DisposableButton'
$prepareButton = Control 'PrepareButton'; $enableButton = Control 'EnableButton'
$memoryCombo = Control 'MemoryCombo'; $cpuCombo = Control 'CpuCombo'
$refreshButton = Control 'RefreshButton'; $doctorButton = Control 'DoctorButton'
$openDataButton = Control 'OpenDataButton'; $resetButton = Control 'ResetButton'

function Set-Check($dot, $text, $check) {
    $dot.Fill = if ($check.Ready) { '#C9FF36' } else { '#FFB454' }
    $text.Text = $check.Label
}

function Set-Message([string]$message, [bool]$isError = $false) {
    $statusText.Text = $message
    $statusText.Foreground = if ($isError) { '#FFB454' } else { '#9BA39F' }
}

function Get-SelectionNumber($combo) {
    return [int]$combo.SelectedItem.Content
}

function Start-ProjectPowerShell {
    param([string]$Script, [string]$Arguments = '', [switch]$Elevated)
    $scriptPath = Join-Path $projectRoot $Script
    $argumentLine = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $Arguments"
    $parameters = @{ FilePath='powershell.exe'; ArgumentList=$argumentLine; PassThru=$true }
    if ($Elevated) { $parameters.Verb = 'RunAs' }
    return Start-Process @parameters
}

function Refresh-Status {
    try {
        Set-Message 'Checking the host, runtime, and pinned media...'
        $status = Get-WindowsIntoOmarchyStatus
        Set-Check $hostDot $hostText $status.Host
        Set-Check $hypervisorDot $hypervisorText $status.Hypervisor
        Set-Check $runtimeDot $runtimeText $status.Runtime
        Set-Check $mediaDot $mediaText $status.Media
        $launchButton.IsEnabled = $status.Ready
        $disposableButton.IsEnabled = $status.Ready
        $enableButton.IsEnabled = -not $status.Hypervisor.Ready
        $prepareButton.IsEnabled = $status.Host.Ready -and $status.Hypervisor.Ready -and -not ($status.Runtime.Ready -and $status.Media.Ready)
        $launchButton.Visibility = if ($status.Ready) { 'Visible' } else { 'Collapsed' }
        $disposableButton.Visibility = if ($status.Ready) { 'Visible' } else { 'Collapsed' }
        $prepareButton.Visibility = if ($status.Hypervisor.Ready -and -not ($status.Runtime.Ready -and $status.Media.Ready)) { 'Visible' } else { 'Collapsed' }
        $enableButton.Visibility = if (-not $status.Hypervisor.Ready) { 'Visible' } else { 'Collapsed' }
        if ($status.Ready) {
            $headline.Text = 'Ready to enter Omarchy'
            $detail.Text = 'Your private Omarchy machine is ready. On a new machine, installation and owner setup continue automatically.'
            Set-Message 'All four contracts are ready.'
        } else {
            $headline.Text = if ($status.Hypervisor.Ready) { 'Download once, then enter Omarchy' } else { 'One Windows feature is needed' }
            $detail.Text = if ($status.Hypervisor.Ready) {
                'The app downloads verified upstream components, installs Omarchy unattended, then hands the machine to its first owner.'
            } else {
                'Enable Windows Hypervisor Platform once. Windows may ask to restart; the app keeps everything else contained.'
            }
            Set-Message 'Nothing launches until every pinned contract passes.'
        }
    } catch {
        $launchButton.IsEnabled = $false
        $disposableButton.IsEnabled = $false
        Set-Message $_.Exception.Message $true
    }
}

$refreshButton.Add_Click({ Refresh-Status })
$prepareButton.Add_Click({
    $memory = Get-SelectionNumber $memoryCombo; $cpu = Get-SelectionNumber $cpuCombo
    Start-ProjectPowerShell -Script 'scripts\Prepare.ps1' -Arguments "-All -LaunchAfter -NoPause -MemoryMiB $memory -CpuCount $cpu" | Out-Null
    Set-Message 'Preparing verified components. Omarchy will open automatically when they are ready.'
    $prepareButton.IsEnabled = $false
})
$enableButton.Add_Click({
    try {
        Start-ProjectPowerShell -Script 'scripts\Enable-Hypervisor.ps1' -Elevated | Out-Null
        Set-Message 'Windows will request approval. A restart may be required.'
    } catch { Set-Message $_.Exception.Message $true }
})
$launchButton.Add_Click({
    $memory = Get-SelectionNumber $memoryCombo; $cpu = Get-SelectionNumber $cpuCombo
    Start-ProjectPowerShell -Script 'scripts\Run-VM.ps1' -Arguments "-Mode Persistent -MemoryMiB $memory -CpuCount $cpu" | Out-Null
    Set-Message 'Persistent machine launched. Closing its QEMU window returns here.'
})
$disposableButton.Add_Click({
    $answer = [Windows.MessageBox]::Show(
        'This session starts from your persistent machine but discards every change when its window closes. Continue?',
        'Disposable session', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') {
        $memory = Get-SelectionNumber $memoryCombo; $cpu = Get-SelectionNumber $cpuCombo
        Start-ProjectPowerShell -Script 'scripts\Run-VM.ps1' -Arguments "-Mode Disposable -MemoryMiB $memory -CpuCount $cpu" | Out-Null
        Set-Message 'Disposable session launched. Its overlay will be removed after shutdown.'
    }
})
$doctorButton.Add_Click({ Start-ProjectPowerShell -Script 'scripts\Doctor.ps1' -Arguments '-Pause' | Out-Null })
$openDataButton.Add_Click({
    $data = Initialize-WindowsIntoOmarchyDirectories
    Start-Process explorer.exe -ArgumentList ('"' + $data + '"') | Out-Null
})
$resetButton.Add_Click({
    $answer = [Windows.MessageBox]::Show(
        'Archive the current machine and return to a fresh 64 GB disk? The archive remains recoverable in Backups.',
        'Archive and reset', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') {
        Start-ProjectPowerShell -Script 'scripts\Reset.ps1' -Arguments '-Force -Pause' | Out-Null
        Set-Message 'Reset opened in a separate window. Your previous machine will be archived, not deleted.'
    }
})

$window.Add_ContentRendered({ Refresh-Status })
[void]$window.ShowDialog()
