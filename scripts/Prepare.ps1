param(
    [switch]$Qemu,
    [switch]$Iso,
    [switch]$All
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
            $installer = Join-Path $downloads $lock.qemu.installerFileName
            Get-VerifiedDownload -Url $lock.qemu.installerUrl -Destination $installer -Algorithm SHA512 -ExpectedHash $lock.qemu.sha512
            Write-Host ''
            Write-Host 'Opening the verified QEMU installer.' -ForegroundColor Cyan
            Write-Host 'Accept the defaults. Windows may request administrator approval.'
            $process = Start-Process -FilePath $installer -Verb RunAs -PassThru -Wait
            if ($process.ExitCode -ne 0) { throw "QEMU installer exited with code $($process.ExitCode)." }
            if ($null -eq (Get-QemuInstallation)) {
                throw 'QEMU installation completed, but qemu-system-x86_64.exe was not found. Re-run after installing QEMU to C:\Program Files\qemu.'
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
    Write-Host 'Component preparation complete. Return to the launcher and choose Refresh.' -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message
    Write-WindowsIntoOmarchyLog -Message "Preparation failed: $($_.Exception.Message)"
    exit 1
} finally {
    Write-Host ''
    Read-Host 'Press Enter to close'
}
