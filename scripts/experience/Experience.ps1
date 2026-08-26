param(
    [ValidateSet('Inspect','PrepareAndLaunch','Launch','Disposable')][string]$Action = 'PrepareAndLaunch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Experience.Common.ps1')

function Invoke-CheckedScript {
    param([Parameter(Mandatory=$true)][string]$Path, [string[]]$Arguments = @())
    $process = Start-OnarchyHiddenPowerShell -Script $Path -Arguments $Arguments -Wait
    if ($process.ExitCode -ne 0) {
        throw "A setup component exited with code $($process.ExitCode). See the experience log for details."
    }
}

function Initialize-OnarchyMachineFromFactory {
    param([Parameter(Mandatory=$true)]$Factory)
    $paths = Get-OnarchyExperiencePaths
    $machineRoot = Join-Path $paths.MachineRoot $Factory.BuildId
    $machineDisk = Join-Path $machineRoot 'omarchy.qcow2'
    $qemuImg = Join-Path $Factory.Runtime 'qemu-img.exe'
    if (Test-Path -LiteralPath $machineDisk -PathType Leaf) {
        $diskInfo = Get-Item -LiteralPath $machineDisk
        if (($diskInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'The private machine disk is a reparse point and will not be opened.' }
        $infoText = (& $qemuImg info --output=json $machineDisk 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'The private machine disk could not be inspected.' }
        $info = $infoText | ConvertFrom-Json
        $backing = [string]$info.'full-backing-filename'
        if ([string]::IsNullOrWhiteSpace($backing)) { $backing = [string]$info.'backing-filename' }
        if ([string]::IsNullOrWhiteSpace($backing) -or
            [IO.Path]::GetFullPath($backing) -ne [IO.Path]::GetFullPath($Factory.Guest)) {
            throw 'The private machine belongs to a different factory build. It will not be opened or modified.'
        }
        & $qemuImg check $machineDisk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'The private machine needs recovery. Use Archive & reset; the existing disk will be preserved.' }
        return $machineDisk
    }

    Write-OnarchyExperienceState -Phase CreatingMachine -Headline 'Creating your private machine' -Detail 'Making an instant writable copy of the verified factory disk.' -Percent 88 -Indeterminate $true | Out-Null
    if (-not (Test-Path -LiteralPath $machineRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $machineRoot -Force | Out-Null
    }
    $machineDisk = Assert-WindowsIntoOmarchyChildPath -Path $machineDisk
    $partial = Assert-WindowsIntoOmarchyChildPath -Path ($machineDisk + '.partial')
    if (Test-Path -LiteralPath $partial -PathType Leaf) { Remove-Item -LiteralPath $partial -Force }
    & $qemuImg create -f qcow2 -F qcow2 -b $Factory.Guest $partial
    if ($LASTEXITCODE -ne 0) { throw 'QEMU could not create the private machine overlay.' }
    & $qemuImg check $partial
    if ($LASTEXITCODE -ne 0) { throw 'The new private machine overlay failed its integrity check.' }
    Move-Item -LiteralPath $partial -Destination $machineDisk
    $receipt = [ordered]@{
        schemaVersion = 1
        buildId = $Factory.BuildId
        backingFile = $Factory.Guest
        disk = $machineDisk
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        isolation = 'qcow2-overlay'
    }
    $receipt | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $machineRoot 'machine.json') -Encoding UTF8
    return $machineDisk
}

try {
    $status = Get-WindowsIntoOmarchyStatus
    if (-not $status.Host.Ready) {
        Write-OnarchyExperienceState -Phase Blocked -Headline 'This PC is not supported yet' -Detail $status.Host.Label -Percent 0 -Action 'Diagnostics' -ErrorCode 'HOST_UNSUPPORTED' | Out-Null
        exit 2
    }
    $hypervisorState = Get-WindowsHypervisorState
    if ($hypervisorState.FeatureState -eq 'Enabled' -and -not $hypervisorState.Ready) {
        Write-OnarchyExperienceState -Phase Blocked -Headline 'Turn on virtualisation in your PC firmware' -Detail 'Windows acceleration is installed, but CPU virtualisation is disabled in UEFI/BIOS. Enable Intel VT-x or AMD-V, then reopen the app.' -Percent 5 -Action 'Diagnostics' -ErrorCode 'FIRMWARE_VIRTUALIZATION_DISABLED' | Out-Null
        exit 4
    }
    if (-not $status.Hypervisor.Ready) {
        Write-OnarchyExperienceState -Phase NeedsAcceleration -Headline 'One Windows feature is needed' -Detail 'Enable hardware acceleration once. If Windows needs a restart, setup resumes by itself.' -Percent 5 -Action 'Enable' | Out-Null
        exit 3
    }
    if ($Action -eq 'Inspect') {
        $factory = Get-OnarchyActiveFactory
        if ($status.Ready -or $null -ne $factory) {
            Write-OnarchyExperienceState -Phase Ready -Headline 'Ready when you are' -Detail 'Open your private Omarchy machine.' -Percent 100 -Action 'Launch' | Out-Null
        } else {
            $factoryContract = Get-OnarchyFactoryContract
            $detail = if ($null -ne $factoryContract) {
                'One click gets the verified factory package, creates your private machine, and opens Omarchy.'
            } else {
                'This source build has no factory package; one click uses the verified installer fallback.'
            }
            Write-OnarchyExperienceState -Phase Ready -Headline 'One click, then Omarchy' -Detail $detail -Percent 10 -Action 'Prepare' | Out-Null
        }
        exit 0
    }
    Clear-OnarchyPostRestartResume

    $factoryContract = Get-OnarchyFactoryContract
    $factory = Get-OnarchyActiveFactory
    if ($null -eq $factory -and $null -ne $factoryContract) {
        $materializer = Join-Path $script:ExperienceScriptsRoot 'Materialize-Factory.ps1'
        if (-not (Test-Path -LiteralPath $materializer -PathType Leaf)) {
            throw 'Factory media is declared but the verified factory materializer is unavailable.'
        }
        Write-OnarchyExperienceState -Phase Preparing -Headline 'Getting Omarchy ready' -Detail 'Downloading and verifying the one-time factory package. You can keep using Windows.' -Percent 15 -Indeterminate $true | Out-Null
        Invoke-CheckedScript -Path $materializer -Arguments @('-ManifestPath', $factoryContract.Path)
        $factory = Get-OnarchyActiveFactory
        if ($null -eq $factory) { throw 'Factory preparation completed without a valid active factory receipt.' }
    }

    if ($null -eq $factory) {
        if ($null -ne $factoryContract) { throw 'The factory release could not be activated.' }
        Write-OnarchyExperienceState -Phase Preparing -Headline 'Getting Omarchy ready' -Detail 'This source build has no factory bundle, so it is using the verified unattended installer fallback.' -Percent 15 -Indeterminate $true | Out-Null
        $prepare = Join-Path $script:ExperienceScriptsRoot 'Prepare.ps1'
        Invoke-CheckedScript -Path $prepare -Arguments @('-All','-NoPause')
    } else {
        Initialize-OnarchyMachineFromFactory -Factory $factory | Out-Null
    }

    $resources = Get-OnarchyAutomaticResources
    $run = Join-Path $script:ExperienceScriptsRoot 'Run-VM.ps1'
    $mode = if ($Action -eq 'Disposable') { 'Disposable' } else { 'Persistent' }
    Write-OnarchyExperienceState -Phase Launching -Headline 'Opening Omarchy' -Detail 'Your private machine is ready.' -Percent 96 -Indeterminate $true | Out-Null
    Write-OnarchyExperienceState -Phase Running -Headline 'You are in Omarchy' -Detail 'Close the Omarchy window to return here.' -Percent 100 | Out-Null
    Invoke-CheckedScript -Path $run -Arguments @('-Mode',$mode,'-MemoryMiB',[string]$resources.MemoryMiB,'-CpuCount',[string]$resources.CpuCount)
    Write-OnarchyExperienceState -Phase Ready -Headline 'Ready when you are' -Detail 'Your private Omarchy machine is saved and ready to reopen.' -Percent 100 -Action 'Launch' | Out-Null
} catch {
    Write-OnarchyExperienceState -Phase Failed -Headline 'Setup paused safely' -Detail $_.Exception.Message -Percent 0 -Action 'Retry' -ErrorCode 'EXPERIENCE_FAILED' | Out-Null
    exit 1
}
