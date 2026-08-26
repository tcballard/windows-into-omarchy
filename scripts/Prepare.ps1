param(
    [switch]$Qemu,
    [switch]$Iso,
    [switch]$All,
    [switch]$LaunchAfter,
    [switch]$NoPause,
    [int]$MemoryMiB = 8192,
    [int]$CpuCount = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not ($Qemu -or $Iso -or $All)) { $All = $true }
$lock = Get-WindowsIntoOmarchyLock
$root = Initialize-WindowsIntoOmarchyDirectories
$downloads = Join-Path $root 'Downloads'

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][ValidateSet('SHA256','SHA512')][string]$Algorithm,
        [Parameter(Mandatory=$true)][string]$ExpectedHash
    )
    Assert-WindowsIntoOmarchyChildPath -Path $Destination | Out-Null
    if (Test-PinnedFile -Path $Destination -Algorithm $Algorithm -ExpectedHash $ExpectedHash) {
        Write-Host "Verified: $Destination" -ForegroundColor Green
        return
    }
    if (Test-Path -LiteralPath $Destination) {
        $quarantine = Join-Path $root ('Quarantine\{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), (Split-Path -Leaf $Destination))
        Move-Item -LiteralPath $Destination -Destination $quarantine
        Write-Warning "Moved an unverified existing file to $quarantine"
    }
    $partial = "$Destination.partial"
    Assert-WindowsIntoOmarchyChildPath -Path $partial | Out-Null
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }

    Write-Host "Downloading $Url" -ForegroundColor Cyan
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $partial -DisplayName 'Windows Into Omarchy prerequisite'
    } else {
        $progressPreference = 'Continue'
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $partial
    }

    Write-Host "Verifying $Algorithm..." -ForegroundColor Cyan
    if (-not (Test-PinnedFile -Path $partial -Algorithm $Algorithm -ExpectedHash $ExpectedHash)) {
        $bad = Join-Path $root ('Quarantine\{0}-{1}.digest-mismatch' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), (Split-Path -Leaf $Destination))
        Move-Item -LiteralPath $partial -Destination $bad
        throw "Digest mismatch. The download was quarantined at $bad"
    }
    Move-Item -LiteralPath $partial -Destination $Destination
    Write-Host "Verified: $Destination" -ForegroundColor Green
}

try {
    if ($All -or $Qemu) {
        $existing = Get-QemuInstallation
        if ($null -eq $existing) {
            & (Join-Path $PSScriptRoot 'Build-Runtime.ps1') -Mode Install
            if ($null -eq (Get-QemuInstallation)) {
                throw 'QEMU preparation completed, but the app-local runtime was not found.'
            }
        } else {
            Write-Host "QEMU already installed: $($existing.Root)" -ForegroundColor Green
        }
    }

    if ($All -or $Iso) {
        $isoPath = Join-Path $downloads $lock.omarchy.fileName
        Get-VerifiedDownload -Url $lock.omarchy.downloadUrl -Destination $isoPath -Algorithm SHA256 -ExpectedHash $lock.omarchy.sha256
    }

    Write-Host ''
    & (Join-Path $PSScriptRoot 'Doctor.ps1') -NoExit
    Write-Host 'Component preparation complete.' -ForegroundColor Green
    if ($LaunchAfter) {
        Write-Host 'Entering Omarchy...' -ForegroundColor Green
        & (Join-Path $PSScriptRoot 'Run-VM.ps1') -Mode Persistent -MemoryMiB $MemoryMiB -CpuCount $CpuCount
    }
} catch {
    Write-Error $_.Exception.Message
    Write-WindowsIntoOmarchyLog -Message "Preparation failed: $($_.Exception.Message)"
    exit 1
} finally {
    if (-not $NoPause) {
        Write-Host ''
        Read-Host 'Press Enter to close'
    }
}
