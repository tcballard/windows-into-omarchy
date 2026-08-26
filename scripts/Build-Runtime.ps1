param(
    [ValidateSet('Install', 'Bundle')]
    [string]$Mode = 'Install',
    [string]$Destination,
    [string]$InstallerPath,
    [string]$SevenZipPath,
    [string]$ComplianceManifestPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$lock = Get-WindowsIntoOmarchyLock
$dataRoot = Initialize-WindowsIntoOmarchyDirectories
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRelativeDirectory = [string]$lock.qemu.installation.relativeDirectory
if ([string]::IsNullOrWhiteSpace($runtimeRelativeDirectory)) {
    throw 'The runtime lock does not define qemu.installation.relativeDirectory.'
}
$defaultInstallDestination = Join-Path $dataRoot $runtimeRelativeDirectory
$defaultBundleDestination = Join-Path $projectRoot 'runtime\qemu'
$downloads = Join-Path $dataRoot 'Downloads'
$installer = if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Join-Path $downloads $lock.qemu.installerFileName
} else {
    [IO.Path]::GetFullPath($InstallerPath)
}

function Assert-PathBelow {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Parent,
        [Parameter(Mandatory=$true)][string]$Purpose
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath($Path)
    if (-not $candidate.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing $Purpose path outside $parentFull"
    }
    return $candidate
}

function Get-VerifiedQemuInstaller {
    if (Test-PinnedFile -Path $installer -Algorithm SHA512 -ExpectedHash $lock.qemu.sha512) {
        Write-Host "Verified cached QEMU installer: $installer" -ForegroundColor Green
        return $installer
    }

    if (-not [string]::IsNullOrWhiteSpace($InstallerPath)) {
        throw "The supplied QEMU installer does not match the pinned SHA-512: $installer"
    }

    if (Test-Path -LiteralPath $installer) {
        $quarantineName = '{0}-{1}.digest-mismatch' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $lock.qemu.installerFileName
        $quarantine = Join-Path $dataRoot (Join-Path 'Quarantine' $quarantineName)
        Assert-WindowsIntoOmarchyChildPath -Path $quarantine | Out-Null
        Move-Item -LiteralPath $installer -Destination $quarantine
        Write-Warning "Moved an unverified QEMU installer to $quarantine"
    }

    $partial = "$installer.partial"
    Assert-WindowsIntoOmarchyChildPath -Path $partial | Out-Null
    if (Test-Path -LiteralPath $partial) {
        $partialQuarantineName = '{0}-{1}.partial' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $lock.qemu.installerFileName
        $partialQuarantine = Join-Path $dataRoot (Join-Path 'Quarantine' $partialQuarantineName)
        Move-Item -LiteralPath $partial -Destination $partialQuarantine
    }

    Write-Host "Downloading pinned QEMU $($lock.qemu.version)..." -ForegroundColor Cyan
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $lock.qemu.installerUrl -Destination $partial -DisplayName 'Windows Into Omarchy runtime'
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $lock.qemu.installerUrl -OutFile $partial
    }

    if (-not (Test-PinnedFile -Path $partial -Algorithm SHA512 -ExpectedHash $lock.qemu.sha512)) {
        $badName = '{0}-{1}.digest-mismatch' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $lock.qemu.installerFileName
        $bad = Join-Path $dataRoot (Join-Path 'Quarantine' $badName)
        Move-Item -LiteralPath $partial -Destination $bad
        throw "QEMU digest mismatch. The download was quarantined at $bad"
    }

    Move-Item -LiteralPath $partial -Destination $installer
    Write-Host "Verified SHA-512: $installer" -ForegroundColor Green
    return $installer
}

function Test-QemuRuntimePayload {
    param([Parameter(Mandatory=$true)][string]$Root)

    $system = Join-Path $Root 'qemu-system-x86_64.exe'
    $image = Join-Path $Root 'qemu-img.exe'
    if (-not (Test-Path -LiteralPath $system -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'COPYING') -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'COPYING.LIB') -PathType Leaf)) { return $false }

    try {
        $versionText = (& $system --version 2>&1 | Select-Object -First 1)
        if ($versionText -notmatch 'version\s+(\d+)') { return $false }
        if ([int]$Matches[1] -lt [int]$lock.qemu.minimumMajorVersion) { return $false }

        $accelerators = (& $system -accel help 2>&1) -join "`n"
        $displays = (& $system -display help 2>&1) -join "`n"
        $audio = (& $system -audiodev help 2>&1) -join "`n"
        $devices = (& $system -device help 2>&1) -join "`n"
        if ($accelerators -notmatch '(?im)^\s*whpx(?:\s|$)') { return $false }
        if ($displays -notmatch '(?im)^\s*sdl(?:\s|$)') { return $false }
        if ($audio -notmatch '(?im)^\s*dsound(?:\s|$)') { return $false }
        if ($devices -notmatch 'virtio-vga') { return $false }
        if ($devices -notmatch 'virtio-blk-pci') { return $false }
        if ($devices -notmatch 'hda-duplex') { return $false }

        foreach ($candidate in $lock.machine.firmwareCodeCandidates) {
            $firmware = Join-Path $Root ([string]$candidate).Replace('/', '\')
            if (Test-Path -LiteralPath $firmware -PathType Leaf) { return $true }
        }
    } catch {
        return $false
    }
    return $false
}

function Write-RuntimeReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$AcquisitionMode
    )

    $receipt = [ordered]@{
        schemaVersion = 1
        qemuVersion = [string]$lock.qemu.version
        qemuBuild = [string]$lock.qemu.build
        acquisitionMode = $AcquisitionMode
        upstreamUrl = [string]$lock.qemu.installerUrl
        upstreamInstallerSha512 = [string]$lock.qemu.sha512
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $receiptPath = Join-Path (Split-Path -Parent $Root) 'qemu-runtime.json'
    $receipt | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}

function Install-AppLocalRuntime {
    $target = if ([string]::IsNullOrWhiteSpace($Destination)) { $defaultInstallDestination } else { $Destination }
    $target = Assert-PathBelow -Path $target -Parent $dataRoot -Purpose 'runtime installation'

    if ((-not $Force) -and (Test-QemuRuntimePayload -Root $target)) {
        Write-Host "App-local QEMU runtime is already ready: $target" -ForegroundColor Green
        return
    }

    if (Test-Path -LiteralPath $target) {
        $quarantineName = 'qemu-runtime-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
        $quarantine = Join-Path $dataRoot (Join-Path 'Quarantine' $quarantineName)
        Move-Item -LiteralPath $target -Destination $quarantine
        Write-Warning "Moved the previous runtime to $quarantine"
    }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $verifiedInstaller = Get-VerifiedQemuInstaller
    Write-Host 'Installing the verified runtime silently into the app data directory.' -ForegroundColor Cyan
    Write-Host 'Windows may show one administrator approval prompt.'

    # NSIS requires /D= to be the final argument and treats the rest of the command
    # line as the destination, which permits spaces without fragile nested quoting.
    $argumentLine = "/S /D=$target"
    $process = Start-Process -FilePath $verifiedInstaller -ArgumentList $argumentLine -Verb RunAs -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "The silent QEMU installation exited with code $($process.ExitCode)."
    }
    if (-not (Test-QemuRuntimePayload -Root $target)) {
        throw "QEMU finished installing, but the app-local runtime failed capability or license checks: $target"
    }

    Write-RuntimeReceipt -Root $target -AcquisitionMode 'direct-upstream-silent-install'
    Write-Host "App-local QEMU runtime ready: $target" -ForegroundColor Green
}

function Resolve-SevenZip {
    if (-not [string]::IsNullOrWhiteSpace($SevenZipPath)) {
        if (-not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
            throw "7-Zip was not found: $SevenZipPath"
        }
        return [IO.Path]::GetFullPath($SevenZipPath)
    }
    foreach ($name in @('7zz.exe', '7z.exe', '7zz', '7z')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Bundle mode requires 7-Zip (7z or 7zz) to extract the verified NSIS installer.'
}

function Build-RedistributableRuntime {
    $compliancePath = if ([string]::IsNullOrWhiteSpace($ComplianceManifestPath)) {
        Join-Path $projectRoot 'runtime\compliance\qemu-bundle-approval.json'
    } else {
        [IO.Path]::GetFullPath($ComplianceManifestPath)
    }
    if (-not (Test-Path -LiteralPath $compliancePath -PathType Leaf)) {
        throw "Bundle mode is disabled until a completed compliance manifest exists: $compliancePath"
    }

    $compliance = Get-Content -LiteralPath $compliancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($compliance.schemaVersion -ne 1 -or -not [bool]$compliance.redistributionApproved) {
        throw 'The QEMU bundle compliance manifest is not approved or has an unsupported schema.'
    }
    if ([string]$compliance.qemuVersion -ne [string]$lock.qemu.version -or
        [string]$compliance.qemuBuild -ne [string]$lock.qemu.build -or
        [string]$compliance.upstreamInstallerSha512 -ne [string]$lock.qemu.sha512) {
        throw 'The QEMU bundle compliance manifest does not match the locked binary.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$compliance.reviewReference)) {
        throw 'The QEMU bundle compliance manifest has no review reference.'
    }

    $requiredRoles = @('corresponding-source', 'sbom', 'license-manifest')
    $approvedArtifacts = @{}
    foreach ($artifact in @($compliance.artifacts)) {
        $role = [string]$artifact.role
        if ($requiredRoles -notcontains $role) { continue }
        $artifactPath = Join-Path (Split-Path -Parent $compliancePath) ([string]$artifact.path)
        $artifactPath = Assert-PathBelow -Path $artifactPath -Parent (Split-Path -Parent $compliancePath) -Purpose 'compliance artifact'
        if (-not (Test-PinnedFile -Path $artifactPath -Algorithm SHA256 -ExpectedHash ([string]$artifact.sha256))) {
            throw "Missing or invalid QEMU bundle compliance artifact: $role"
        }
        $approvedArtifacts[$role] = $artifactPath
    }
    foreach ($role in $requiredRoles) {
        if (-not $approvedArtifacts.ContainsKey($role)) {
            throw "The QEMU bundle compliance manifest is missing: $role"
        }
    }

    $target = if ([string]::IsNullOrWhiteSpace($Destination)) { $defaultBundleDestination } else { $Destination }
    $target = Assert-PathBelow -Path $target -Parent (Join-Path $projectRoot 'runtime') -Purpose 'bundled runtime'
    if (Test-Path -LiteralPath $target) {
        throw "Bundle destination already exists; review and move it before rebuilding: $target"
    }

    $verifiedInstaller = Get-VerifiedQemuInstaller
    $sevenZip = Resolve-SevenZip
    $temporary = Join-Path $dataRoot (Join-Path 'Temp' ('qemu-extract-' + [Guid]::NewGuid().ToString('N')))
    Assert-WindowsIntoOmarchyChildPath -Path $temporary | Out-Null
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        & $sevenZip x $verifiedInstaller "-o$temporary" -y | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction exited with code $LASTEXITCODE." }
        if (-not (Test-QemuRuntimePayload -Root $temporary)) {
            throw 'The extracted QEMU payload failed capability or license checks.'
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Move-Item -LiteralPath $temporary -Destination $target
        $temporary = $null
        $complianceDestination = Join-Path $target '_compliance'
        New-Item -ItemType Directory -Path $complianceDestination -Force | Out-Null
        Copy-Item -LiteralPath $compliancePath -Destination (Join-Path $complianceDestination 'qemu-bundle-approval.json')
        foreach ($role in $requiredRoles) {
            Copy-Item -LiteralPath $approvedArtifacts[$role] -Destination $complianceDestination
        }
        $reviewMarker = [ordered]@{
            reviewed = $true
            reference = [string]$compliance.reviewReference
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
            qemuVersion = [string]$lock.qemu.version
            upstreamInstallerSha512 = [string]$lock.qemu.sha512
        }
        $reviewMarker | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $target '.redistribution-reviewed.json') -Encoding UTF8
        Write-RuntimeReceipt -Root $target -AcquisitionMode 'bundled-redistribution-reviewed'
        Write-Host "Installer-ready QEMU payload built: $target" -ForegroundColor Green
    } finally {
        if ($null -ne $temporary -and (Test-Path -LiteralPath $temporary)) {
            $failedName = 'qemu-extract-failed-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
            $failed = Join-Path $dataRoot (Join-Path 'Quarantine' $failedName)
            Move-Item -LiteralPath $temporary -Destination $failed
            Write-Warning "Preserved failed extraction for inspection: $failed"
        }
    }
}

if ($Mode -eq 'Install') {
    Install-AppLocalRuntime
} else {
    Build-RedistributableRuntime
}
