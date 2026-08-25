Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:LockPath = Join-Path $script:ProjectRoot 'config\runtime.lock.json'

function Get-WindowsIntoOmarchyLock {
    if (-not (Test-Path -LiteralPath $script:LockPath -PathType Leaf)) {
        throw "Runtime lock is missing: $script:LockPath"
    }
    return Get-Content -LiteralPath $script:LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-WindowsIntoOmarchyDataRoot {
    $lock = Get-WindowsIntoOmarchyLock
    $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($local)) { throw 'Windows LocalAppData is unavailable.' }
    return Join-Path $local $lock.product.dataDirectoryName
}

function Initialize-WindowsIntoOmarchyDirectories {
    $root = Get-WindowsIntoOmarchyDataRoot
    foreach ($name in @('Downloads', 'VM', 'Logs', 'Backups', 'Quarantine', 'Temp')) {
        $path = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    return $root
}

function Assert-WindowsIntoOmarchyChildPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $root = [IO.Path]::GetFullPath((Get-WindowsIntoOmarchyDataRoot)).TrimEnd('\') + '\'
    $candidate = [IO.Path]::GetFullPath($Path)
    if (-not $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside Windows Into Omarchy data: $candidate"
    }
    return $candidate
}

function Get-QemuInstallation {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:TRY_OMARCHY_QEMU_DIR)) {
        $candidates.Add($env:TRY_OMARCHY_QEMU_DIR)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles 'qemu'))
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'qemu'))
    }
    $command = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { $candidates.Add((Split-Path -Parent $command.Source)) }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $system = Join-Path $candidate 'qemu-system-x86_64.exe'
        $image = Join-Path $candidate 'qemu-img.exe'
        if ((Test-Path -LiteralPath $system -PathType Leaf) -and
            (Test-Path -LiteralPath $image -PathType Leaf)) {
            return [pscustomobject]@{ Root=$candidate; System=$system; Image=$image }
        }
    }
    return $null
}

function Find-QemuFirmware {
    param([Parameter(Mandatory=$true)]$Qemu)
    $lock = Get-WindowsIntoOmarchyLock
    $code = $null
    $vars = $null
    foreach ($relative in $lock.machine.firmwareCodeCandidates) {
        $candidate = Join-Path $Qemu.Root ([string]$relative).Replace('/', '\')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $code = $candidate; break }
    }
    foreach ($relative in $lock.machine.firmwareVarsCandidates) {
        $candidate = Join-Path $Qemu.Root ([string]$relative).Replace('/', '\')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $vars = $candidate; break }
    }
    return [pscustomobject]@{ Code=$code; Vars=$vars; Ready=($null -ne $code) }
}

function Get-WindowsHypervisorState {
    $featureState = 'Unknown'
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction Stop
        $featureState = [string]$feature.State
    } catch {
        try {
            $output = & dism.exe /English /Online /Get-FeatureInfo /FeatureName:HypervisorPlatform 2>$null
            $line = $output | Where-Object { $_ -match '^State\s*:' } | Select-Object -First 1
            if ($line -match ':\s*(.+)$') { $featureState = $Matches[1].Trim() }
        } catch { $featureState = 'Unknown' }
    }

    $hypervisorPresent = $false
    $firmwareVirtualization = $false
    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $hypervisorPresent = [bool]$computer.HypervisorPresent
    } catch { }
    try {
        $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        $firmwareVirtualization = $processors.Count -gt 0 -and
            @($processors | Where-Object { -not $_.VirtualizationFirmwareEnabled }).Count -eq 0
    } catch { }

    return [pscustomobject]@{
        FeatureState = $featureState
        HypervisorPresent = $hypervisorPresent
        FirmwareVirtualization = $firmwareVirtualization
        Ready = ($featureState -eq 'Enabled' -and ($firmwareVirtualization -or $hypervisorPresent))
    }
}

function Test-PinnedFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('SHA256','SHA512')][string]$Algorithm,
        [Parameter(Mandatory=$true)][string]$ExpectedHash
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
    return $actual -eq $ExpectedHash.ToLowerInvariant()
}

function Test-PinnedFileCached {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('SHA256','SHA512')][string]$Algorithm,
        [Parameter(Mandatory=$true)][string]$ExpectedHash
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    $cachePath = Join-Path (Get-WindowsIntoOmarchyDataRoot) 'verified-downloads.json'
    $record = $null
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        try {
            $records = @(Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json)
            $record = $records | Where-Object {
                $_.path -eq $item.FullName -and
                $_.length -eq $item.Length -and
                $_.lastWriteTimeUtcTicks -eq $item.LastWriteTimeUtc.Ticks -and
                $_.algorithm -eq $Algorithm -and
                $_.expectedHash -eq $ExpectedHash.ToLowerInvariant()
            } | Select-Object -First 1
        } catch { $record = $null }
    }
    if ($null -ne $record) { return [bool]$record.valid }

    $valid = Test-PinnedFile -Path $Path -Algorithm $Algorithm -ExpectedHash $ExpectedHash
    $newRecord = [pscustomobject]@{
        path = $item.FullName
        length = $item.Length
        lastWriteTimeUtcTicks = $item.LastWriteTimeUtc.Ticks
        algorithm = $Algorithm
        expectedHash = $ExpectedHash.ToLowerInvariant()
        valid = $valid
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    @($newRecord) | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $cachePath -Encoding UTF8
    return $valid
}

function Get-WindowsIntoOmarchyStatus {
    $lock = Get-WindowsIntoOmarchyLock
    $root = Initialize-WindowsIntoOmarchyDirectories
    $downloads = Join-Path $root 'Downloads'
    $iso = Join-Path $downloads $lock.omarchy.fileName

    $osReady = $false
    $osLabel = 'Windows 11 x64 required'
    if ($env:OS -eq 'Windows_NT') {
        try {
            $build = [Environment]::OSVersion.Version.Build
            $is64 = [Environment]::Is64BitOperatingSystem
            $memoryMiB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
            $osReady = $is64 -and $build -ge [int]$lock.host.minimumBuild -and
                $memoryMiB -ge [int]$lock.host.minimumHostMemoryMiB
            $osLabel = if ($osReady) { "Windows build $build / $memoryMiB MiB RAM" } else { "Windows build $build / $memoryMiB MiB RAM does not meet the host contract" }
        } catch { $osLabel = 'Could not read Windows version' }
    }

    $hypervisor = if ($env:OS -eq 'Windows_NT') { Get-WindowsHypervisorState } else {
        [pscustomobject]@{ FeatureState='Unavailable'; HypervisorPresent=$false; FirmwareVirtualization=$false; Ready=$false }
    }
    $qemu = Get-QemuInstallation
    $qemuReady = $false
    $qemuLabel = 'QEMU 11.1.0 is not installed'
    $firmware = $null
    if ($null -ne $qemu) {
        try {
            $versionText = (& $qemu.System --version 2>&1 | Select-Object -First 1)
            $qemuReady = $versionText -match 'version\s+(\d+)' -and [int]$Matches[1] -ge [int]$lock.qemu.minimumMajorVersion
            $qemuLabel = [string]$versionText
            if ($qemuReady) {
                $accelerators = (& $qemu.System -accel help 2>&1) -join "`n"
                $displays = (& $qemu.System -display help 2>&1) -join "`n"
                $audio = (& $qemu.System -audiodev help 2>&1) -join "`n"
                $devices = (& $qemu.System -device help 2>&1) -join "`n"
                $requiredCapabilities = @(
                    @{ Name='WHPX'; Present=($accelerators -match '(?im)^\s*whpx(?:\s|$)') },
                    @{ Name='SDL display'; Present=($displays -match '(?im)^\s*sdl(?:\s|$)') },
                    @{ Name='DirectSound'; Present=($audio -match '(?im)^\s*dsound(?:\s|$)') },
                    @{ Name='VirtIO display'; Present=($devices -match 'virtio-vga') },
                    @{ Name='VirtIO storage'; Present=($devices -match 'virtio-blk-pci') },
                    @{ Name='HDA duplex audio'; Present=($devices -match 'hda-duplex') }
                )
                $missing = @($requiredCapabilities | Where-Object { -not $_.Present } | ForEach-Object { $_.Name })
                if ($missing.Count -gt 0) {
                    $qemuReady = $false
                    $qemuLabel = 'QEMU is missing: ' + ($missing -join ', ')
                }
            }
        } catch { $qemuLabel = 'QEMU was found but could not be executed' }
        $firmware = Find-QemuFirmware -Qemu $qemu
        if (-not $firmware.Ready) {
            $qemuReady = $false
            $qemuLabel = 'QEMU firmware was not found'
        }
    }

    $isoReady = $false
    $isoLabel = "Omarchy $($lock.omarchy.version) ISO is not downloaded"
    if (Test-Path -LiteralPath $iso -PathType Leaf) {
        try {
            $isoReady = Test-PinnedFileCached -Path $iso -Algorithm SHA256 -ExpectedHash $lock.omarchy.sha256
            $isoLabel = if ($isoReady) { "Omarchy $($lock.omarchy.version) verified" } else { 'Omarchy ISO digest mismatch' }
        } catch { $isoLabel = 'Omarchy ISO could not be verified' }
    }

    return [pscustomobject]@{
        Ready = ($osReady -and $hypervisor.Ready -and $qemuReady -and $isoReady)
        DataRoot = $root
        IsoPath = $iso
        Qemu = $qemu
        Firmware = $firmware
        Host = [pscustomobject]@{ Ready=$osReady; Label=$osLabel }
        Hypervisor = [pscustomobject]@{ Ready=$hypervisor.Ready; Label="Windows hypervisor: $($hypervisor.FeatureState); firmware virtualization: $($hypervisor.FirmwareVirtualization -or $hypervisor.HypervisorPresent)" }
        Runtime = [pscustomobject]@{ Ready=$qemuReady; Label=$qemuLabel }
        Media = [pscustomobject]@{ Ready=$isoReady; Label=$isoLabel }
    }
}

function Write-WindowsIntoOmarchyLog {
    param([Parameter(Mandatory=$true)][string]$Message)
    $root = Initialize-WindowsIntoOmarchyDirectories
    $path = Join-Path $root 'Logs\launcher.log'
    $line = '{0:o} {1}' -f [DateTime]::UtcNow, $Message
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
}
