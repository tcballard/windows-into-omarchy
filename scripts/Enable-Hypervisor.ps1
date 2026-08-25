#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Enabling Windows Hypervisor Platform...' -ForegroundColor Cyan
$result = Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart
Write-Host "Feature state: $($result.State)" -ForegroundColor Green
if ($result.RestartNeeded) {
    Write-Host 'Restart Windows before launching Omarchy.' -ForegroundColor Yellow
} else {
    Write-Host 'Windows Hypervisor Platform is ready.' -ForegroundColor Green
}
Read-Host 'Press Enter to close'
