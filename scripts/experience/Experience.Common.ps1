Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExperienceDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ExperienceScriptsRoot = Split-Path -Parent $script:ExperienceDirectory
$script:ExperienceProjectRoot = Split-Path -Parent $script:ExperienceScriptsRoot
. (Join-Path $script:ExperienceScriptsRoot 'Common.ps1')

function Get-OnarchyExperiencePaths {
    $dataRoot = Initialize-WindowsIntoOmarchyDirectories
    $experienceRoot = Join-Path $dataRoot 'Experience'
    if (-not (Test-Path -LiteralPath $experienceRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $experienceRoot -Force | Out-Null
    }
    return [pscustomobject]@{
        DataRoot = $dataRoot
        ExperienceRoot = $experienceRoot
        State = Join-Path $experienceRoot 'progress.json'
        Resume = Join-Path $experienceRoot 'resume.json'
        Log = Join-Path $dataRoot 'Logs\experience.log'
        FactoryRoot = Join-Path $dataRoot 'Factory'
        MachineRoot = Join-Path $dataRoot 'VM'
    }
}

function Write-OnarchyExperienceLog {
    param([Parameter(Mandatory=$true)][string]$Message)
    $paths = Get-OnarchyExperiencePaths
    $line = '{0:o} {1}' -f [DateTime]::UtcNow, $Message
    Add-Content -LiteralPath $paths.Log -Value $line -Encoding UTF8
}

function Write-OnarchyExperienceState {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Checking','NeedsAcceleration','EnablingAcceleration','AwaitingRestart','Preparing','CreatingMachine','Launching','Running','Ready','Failed','Blocked')][string]$Phase,
        [Parameter(Mandatory=$true)][string]$Headline,
        [Parameter(Mandatory=$true)][string]$Detail,
        [ValidateRange(0,100)][int]$Percent = 0,
        [bool]$Indeterminate = $false,
        [string]$Action = '',
        [string]$ErrorCode = ''
    )
    $paths = Get-OnarchyExperiencePaths
    $state = [ordered]@{
        schemaVersion = 1
        phase = $Phase
        headline = $Headline
        detail = $Detail
        percent = $Percent
        indeterminate = $Indeterminate
        action = $Action
        errorCode = $ErrorCode
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        processId = $PID
    }
    $temporary = Join-Path $paths.ExperienceRoot ('progress-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    Assert-WindowsIntoOmarchyChildPath -Path $temporary | Out-Null
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporary -Encoding UTF8
    if (Test-Path -LiteralPath $paths.State -PathType Leaf) {
        [IO.File]::Replace($temporary, $paths.State, $null, $true)
    } else {
        [IO.File]::Move($temporary, $paths.State)
    }
    Write-OnarchyExperienceLog -Message ("{0}: {1}" -f $Phase, $Detail)
    return [pscustomobject]$state
}

function Read-OnarchyExperienceState {
    $paths = Get-OnarchyExperiencePaths
    if (-not (Test-Path -LiteralPath $paths.State -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $paths.State -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-OnarchyAutomaticResources {
    $lock = Get-WindowsIntoOmarchyLock
    $memoryMiB = [int]$lock.machine.recommendedMemoryMiB
    $logicalProcessors = [Environment]::ProcessorCount
    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $hostMemoryMiB = [math]::Floor([double]$computer.TotalPhysicalMemory / 1MB)
        $halfMemory = [math]::Floor($hostMemoryMiB / 2 / 1024) * 1024
        $memoryMiB = [math]::Max([int]$lock.machine.minimumMemoryMiB, [math]::Min(16384, $halfMemory))
        if ($memoryMiB -gt ($hostMemoryMiB - 3072)) {
            $memoryMiB = [math]::Max([int]$lock.machine.minimumMemoryMiB, $hostMemoryMiB - 3072)
        }
    } catch { }
    $cpuCount = [math]::Floor($logicalProcessors / 2)
    $cpuCount = [math]::Max([int]$lock.machine.minimumCpuCount, $cpuCount)
    $cpuCount = [math]::Min([int]$lock.machine.maximumCpuCount, $cpuCount)
    return [pscustomobject]@{ MemoryMiB=[int]$memoryMiB; CpuCount=[int]$cpuCount }
}

function Get-OnarchyFactoryContract {
    $manifestPath = Join-Path $script:ExperienceProjectRoot 'factory\factory-release.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1) { throw 'The factory release contract has an unsupported schema.' }
    if ([string]$manifest.architecture -ne 'x86_64') { throw 'The factory release is not built for x86-64 Windows PCs.' }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.buildId)) { throw 'The factory release has no build identity.' }
    $guest = @($manifest.assets | Where-Object { [string]$_.role -eq 'guest' })
    $runtime = @($manifest.assets | Where-Object { [string]$_.role -eq 'runtime' })
    if ($guest.Count -ne 1 -or $runtime.Count -ne 1) { throw 'The factory release must contain exactly one guest and one runtime asset.' }
    $sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject]@{ Path=$manifestPath; Sha256=$sha256; Manifest=$manifest; Guest=$guest[0]; Runtime=$runtime[0] }
}

function Get-OnarchyActiveFactory {
    $paths = Get-OnarchyExperiencePaths
    $pointerPath = Join-Path $paths.FactoryRoot 'active.json'
    if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { return $null }
    try {
        $pointerInfo = Get-Item -LiteralPath $pointerPath
        if (($pointerInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        $pointer = Get-Content -LiteralPath $pointerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $buildId = [string]$pointer.buildId
        if ([string]::IsNullOrWhiteSpace($buildId) -or $buildId -match '[\\/:*?"<>|]') { return $null }
        $contract = Get-OnarchyFactoryContract
        if ($null -ne $contract -and [string]$contract.Manifest.buildId -ne $buildId) { return $null }
        if ($null -eq $contract -or [int]$pointer.schemaVersion -ne 1 -or [string]$pointer.factoryManifestSha256 -ne [string]$contract.Sha256) { return $null }
        $buildRoot = Join-Path $paths.FactoryRoot $buildId
        $receipt = Join-Path $buildRoot 'receipt.json'
        $runtime = Join-Path $buildRoot 'runtime\qemu'
        $runtimeManifest = Join-Path $buildRoot 'runtime\qemu\_compliance\payload-manifest.json'
        $guest = Join-Path $buildRoot 'guest\omarchy-factory.qcow2'
        $zstd = Join-Path $buildRoot 'tools\zstd.exe'
        $capabilities = Join-Path $buildRoot 'host-capabilities.json'
        if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath $guest -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath $zstd -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath $capabilities -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath (Join-Path $runtime 'qemu-system-x86_64.exe') -PathType Leaf)) { return $null }
        if (-not (Test-Path -LiteralPath (Join-Path $runtime 'qemu-img.exe') -PathType Leaf)) { return $null }
        $receiptRecord = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$receiptRecord.schemaVersion -ne 1 -or -not [bool]$receiptRecord.complete -or
            [string]$receiptRecord.buildId -ne $buildId -or
            [string]$receiptRecord.factoryManifestSha256 -ne [string]$contract.Sha256 -or
            [string]$receiptRecord.runtimePayloadSha256 -ne [string]$contract.Runtime.payload.sha256 -or
            [string]$receiptRecord.guestPayloadSha256 -ne [string]$contract.Guest.payload.sha256) { return $null }
        $capabilityRecord = Get-Content -LiteralPath $capabilities -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$capabilityRecord.schemaVersion -ne 1 -or -not [bool]$capabilityRecord.sdl2dReady) { return $null }
        foreach ($criticalPath in @($receipt, $runtimeManifest, $guest, $zstd, $capabilities, (Join-Path $runtime 'qemu-system-x86_64.exe'), (Join-Path $runtime 'qemu-img.exe'))) {
            $critical = Get-Item -LiteralPath $criticalPath
            if (($critical.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        }
        if (-not (Get-Item -LiteralPath $guest).IsReadOnly) { return $null }
        $payloadRecord = Get-Content -LiteralPath $runtimeManifest -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$payloadRecord.schemaVersion -ne 1 -or [string]$payloadRecord.target -ne 'windows-x86_64') { return $null }
        $criticalRuntimeFiles = [ordered]@{
            'runtime/qemu/qemu-system-x86_64.exe' = (Join-Path $runtime 'qemu-system-x86_64.exe')
            'runtime/qemu/qemu-img.exe' = (Join-Path $runtime 'qemu-img.exe')
            'tools/zstd.exe' = $zstd
        }
        foreach ($entry in $criticalRuntimeFiles.GetEnumerator()) {
            $fileRecord = @($payloadRecord.files | Where-Object { [string]$_.path -eq [string]$entry.Key })
            if ($fileRecord.Count -ne 1) { return $null }
            $actualFile = Get-Item -LiteralPath ([string]$entry.Value)
            if ([long]$actualFile.Length -ne [long]$fileRecord[0].size -or
                (Get-FileHash -LiteralPath $actualFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$fileRecord[0].sha256) { return $null }
        }
        $qemuSystemHash = (Get-FileHash -LiteralPath (Join-Path $runtime 'qemu-system-x86_64.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
        $runtimeManifestHash = (Get-FileHash -LiteralPath $runtimeManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($runtimeManifestHash -ne [string]$contract.Runtime.payload.sha256 -or
            [string]$capabilityRecord.qemuSystemSha256 -ne $qemuSystemHash -or
            [string]$capabilityRecord.runtimeManifestSha256 -ne $runtimeManifestHash) { return $null }
        if ([bool]$capabilityRecord.gpuAccelerationReady -and
            (-not [bool]$capabilityRecord.virglAdvertised -or -not [bool]$capabilityRecord.anglePresent -or -not [bool]$capabilityRecord.virglDisplaySmokeTested)) { return $null }
        return [pscustomobject]@{ BuildId=$buildId; Root=$buildRoot; Receipt=$receipt; Runtime=$runtime; Guest=$guest; Capabilities=$capabilityRecord }
    } catch {
        return $null
    }
}

function Register-OnarchyPostRestartResume {
    $paths = Get-OnarchyExperiencePaths
    $launcher = Join-Path $script:ExperienceProjectRoot 'launcher\WindowsIntoOmarchy.ps1'
    $resume = [ordered]@{ schemaVersion=1; requestedAtUtc=[DateTime]::UtcNow.ToString('o'); action='PrepareAndLaunch' }
    $resume | ConvertTo-Json | Set-Content -LiteralPath $paths.Resume -Encoding UTF8
    $nativeCandidates = @(
        (Join-Path $script:ExperienceProjectRoot 'WindowsIntoOnarchy.exe'),
        (Join-Path $script:ExperienceProjectRoot 'windows\WindowsIntoOnarchy\bin\Release\net8.0-windows\win-x64\publish\WindowsIntoOnarchy.exe')
    )
    $native = $nativeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $command = if ($null -ne $native) {
        '"{0}" --resume' -f $native
    } else {
        'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{0}" -Resume' -f $launcher
    }
    $runOnce = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\RunOnce')
    try { $runOnce.SetValue('WindowsIntoOnarchyResume', $command, [Microsoft.Win32.RegistryValueKind]::String) }
    finally { $runOnce.Dispose() }
}

function Clear-OnarchyPostRestartResume {
    $paths = Get-OnarchyExperiencePaths
    if (Test-Path -LiteralPath $paths.Resume -PathType Leaf) {
        Assert-WindowsIntoOmarchyChildPath -Path $paths.Resume | Out-Null
        Remove-Item -LiteralPath $paths.Resume -Force
    }
    $runOnce = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\RunOnce', $true)
    if ($null -ne $runOnce) {
        try { $runOnce.DeleteValue('WindowsIntoOnarchyResume', $false) }
        finally { $runOnce.Dispose() }
    }
}

function Test-OnarchyPostRestartResume {
    $paths = Get-OnarchyExperiencePaths
    return Test-Path -LiteralPath $paths.Resume -PathType Leaf
}

function Start-OnarchyHiddenPowerShell {
    param(
        [Parameter(Mandatory=$true)][string]$Script,
        [string[]]$Arguments = @(),
        [switch]$Elevated,
        [switch]$Wait
    )
    $argumentList = New-Object System.Collections.Generic.List[string]
    foreach ($item in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$Script)) {
        $argumentList.Add([string]$item)
    }
    foreach ($item in $Arguments) { $argumentList.Add([string]$item) }
    $quoted = $argumentList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
    }
    $parameters = @{
        FilePath = 'powershell.exe'
        ArgumentList = ($quoted -join ' ')
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    if ($Elevated) { $parameters.Verb = 'RunAs' }
    if ($Wait) { $parameters.Wait = $true }
    return Start-Process @parameters
}
