param([switch]$Json, [switch]$Pause, [switch]$NoExit)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$exitCode = 0
try {
    $status = Get-WindowsIntoOmarchyStatus
    $report = [ordered]@{
        product = (Get-WindowsIntoOmarchyLock).product.name
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
        ready = $status.Ready
        dataRoot = $status.DataRoot
        checks = @(
            [ordered]@{ id='host'; ready=$status.Host.Ready; detail=$status.Host.Label }
            [ordered]@{ id='hypervisor'; ready=$status.Hypervisor.Ready; detail=$status.Hypervisor.Label }
            [ordered]@{ id='runtime'; ready=$status.Runtime.Ready; detail=$status.Runtime.Label }
            [ordered]@{ id='media'; ready=$status.Media.Ready; detail=$status.Media.Label }
        )
    }
    if ($Json) {
        $report | ConvertTo-Json -Depth 5
    } else {
        Write-Host ''
        Write-Host 'WINDOWS INTO OMARCHY / DIAGNOSTICS' -ForegroundColor Green
        foreach ($check in $report.checks) {
            $mark = if ($check.ready) { '[ready]' } else { '[needs attention]' }
            $color = if ($check.ready) { 'Green' } else { 'Yellow' }
            Write-Host ("{0,-18} {1}" -f $mark, $check.detail) -ForegroundColor $color
        }
        Write-Host ''
        Write-Host "Data: $($report.dataRoot)"
    }
    if (-not $status.Ready) { $exitCode = 2 }
} catch {
    if ($Json) {
        [ordered]@{ ready=$false; error=$_.Exception.Message } | ConvertTo-Json
    } else {
        Write-Error $_.Exception.Message
    }
    $exitCode = 1
} finally {
    if ($Pause -and -not $Json) { Read-Host 'Press Enter to close' }
}
if (-not $NoExit -and $exitCode -ne 0) { exit $exitCode }
