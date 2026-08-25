param([switch]$Force, [switch]$Pause)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$root = Initialize-WindowsIntoOmarchyDirectories
$vm = Join-Path $root 'VM'
$disk = Join-Path $vm 'omarchy.qcow2'
$vars = Join-Path $vm 'firmware-vars.fd'
$mutex = New-Object System.Threading.Mutex($false, 'Local\WindowsIntoOmarchy-VM-v1')
$ownsMutex = $false

try {
    $ownsMutex = $mutex.WaitOne(0, $false)
    if (-not $ownsMutex) { throw 'The machine is running. Shut it down before reset.' }

    if (-not (Test-Path -LiteralPath $disk -PathType Leaf)) {
        Write-Host 'There is no persistent Omarchy disk to reset.' -ForegroundColor Yellow
        exit 0
    }
    if (-not $Force) {
        $answer = Read-Host 'Type RESET to archive the current VM and start fresh'
        if ($answer -cne 'RESET') { Write-Host 'Reset cancelled.'; exit 1 }
    }

    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $backup = Join-Path $root "Backups\$stamp"
    Assert-WindowsIntoOmarchyChildPath -Path $backup | Out-Null
    New-Item -ItemType Directory -Path $backup | Out-Null
    Move-Item -LiteralPath $disk -Destination (Join-Path $backup 'omarchy.qcow2')
    if (Test-Path -LiteralPath $vars -PathType Leaf) {
        Move-Item -LiteralPath $vars -Destination (Join-Path $backup 'firmware-vars.fd')
    }
    Write-Host "The previous machine was archived at $backup" -ForegroundColor Green
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    if ($Pause) { Read-Host 'Press Enter to close' }
}
