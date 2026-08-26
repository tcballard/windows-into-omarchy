Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Experience.Common.ps1')

try {
    Write-OmarchyExperienceState -Phase EnablingAcceleration -Headline 'Preparing Windows' -Detail 'Enabling hardware acceleration. Approve the Windows request once.' -Percent 8 -Indeterminate $true | Out-Null
    $result = Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart -ErrorAction Stop
    if ([bool]$result.RestartNeeded) {
        Write-OmarchyExperienceState -Phase AwaitingRestart -Headline 'Restart once, then we carry on' -Detail 'Windows enabled hardware acceleration. Restart now; setup will resume automatically after sign-in.' -Percent 10 -Action 'Restart' | Out-Null
    } else {
        Write-OmarchyExperienceState -Phase Checking -Headline 'Acceleration is ready' -Detail 'Continuing setup automatically.' -Percent 12 -Action 'Continue' | Out-Null
    }
} catch {
    Write-OmarchyExperienceState -Phase Failed -Headline 'Windows could not enable acceleration' -Detail $_.Exception.Message -Percent 0 -Action 'Retry' -ErrorCode 'HYPERVISOR_ENABLE_FAILED' | Out-Null
    exit 1
}
