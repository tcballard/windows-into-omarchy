param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Experience.Common.ps1')

$mutex = New-Object System.Threading.Mutex($false, 'Local\WindowsIntoOmarchy-VM-v1')
$ownsMutex = $false
try {
    $ownsMutex = $mutex.WaitOne(0, $false)
    if (-not $ownsMutex) { throw 'Close Omarchy before archiving the machine.' }
    $factory = Get-OmarchyActiveFactory
    if ($null -eq $factory) {
        $legacyReset = Join-Path $script:ExperienceScriptsRoot 'Reset.ps1'
        & $legacyReset -Force
        exit 0
    }

    $paths = Get-OmarchyExperiencePaths
    $machineRoot = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.MachineRoot $factory.BuildId)
    $disk = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $machineRoot 'omarchy.qcow2')
    if (-not (Test-Path -LiteralPath $disk -PathType Leaf)) {
        Write-OmarchyExperienceState -Phase Ready -Headline 'Ready for a fresh machine' -Detail 'There was no active private machine to archive.' -Percent 100 -Action 'Prepare' | Out-Null
        exit 0
    }
    $item = Get-Item -LiteralPath $disk
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing to archive a machine disk that is a reparse point.' }

    $backupRoot = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.DataRoot ('Backups\{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'), $factory.BuildId))
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Move-Item -LiteralPath $disk -Destination (Join-Path $backupRoot 'omarchy.qcow2')
    $machineReceipt = Join-Path $machineRoot 'machine.json'
    if (Test-Path -LiteralPath $machineReceipt -PathType Leaf) {
        $receiptInfo = Get-Item -LiteralPath $machineReceipt
        if (($receiptInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            Move-Item -LiteralPath $machineReceipt -Destination (Join-Path $backupRoot 'machine.json')
        }
    }
    Write-OmarchyExperienceState -Phase Ready -Headline 'Ready for a fresh machine' -Detail 'The previous machine was archived safely. Enter Omarchy to create a fresh private overlay.' -Percent 100 -Action 'Prepare' | Out-Null
} catch {
    Write-OmarchyExperienceState -Phase Failed -Headline 'The machine was not changed' -Detail $_.Exception.Message -Action 'Retry' -ErrorCode 'ARCHIVE_FAILED' | Out-Null
    exit 1
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
