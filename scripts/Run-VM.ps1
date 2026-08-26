param(
    [ValidateSet('Persistent','Disposable')][string]$Mode = 'Persistent',
    [int]$MemoryMiB = 8192,
    [int]$CpuCount = 4,
    [switch]$FullScreen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'experience\Experience.Common.ps1')

$lock = Get-WindowsIntoOmarchyLock
if ($MemoryMiB -lt [int]$lock.machine.minimumMemoryMiB -or $MemoryMiB -gt 32768) {
    throw "Memory must be between $($lock.machine.minimumMemoryMiB) and 32768 MiB."
}
if ($CpuCount -lt [int]$lock.machine.minimumCpuCount -or $CpuCount -gt [int]$lock.machine.maximumCpuCount) {
    throw "CPU count must be between $($lock.machine.minimumCpuCount) and $($lock.machine.maximumCpuCount)."
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\WindowsIntoOmarchy-VM-v1')
$ownsMutex = $false
$ephemeralDisk = $null
try {
    $ownsMutex = $mutex.WaitOne(0, $false)
    if (-not $ownsMutex) { throw 'Windows Into Onarchy is already running for this Windows user.' }

    $status = Get-WindowsIntoOmarchyStatus
    $factory = Get-OnarchyActiveFactory
    if ($null -eq $factory -and -not $status.Ready) {
        throw 'The machine is not ready. Open the launcher and let setup finish.'
    }
    if (-not $status.Host.Ready -or -not $status.Hypervisor.Ready) {
        throw 'The Windows host or hypervisor is not ready.'
    }
    $hostMemoryMiB = [math]::Floor((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB)
    if ($MemoryMiB -gt ($hostMemoryMiB - 2048)) {
        throw "The selected memory would leave Windows less than 2048 MiB. Select a smaller VM memory size."
    }
    if ($status.DataRoot.Contains(',')) {
        throw 'The Windows profile path contains a comma, which this QEMU command contract cannot safely encode.'
    }

    $root = $status.DataRoot
    $vm = if ($null -ne $factory) { Join-Path $root ('VM\' + [string]$factory.BuildId) } else { Join-Path $root 'VM' }
    $temp = Join-Path $root 'Temp'
    $logs = Join-Path $root 'Logs'
    $persistentDisk = Join-Path $vm 'omarchy.qcow2'
    $diskSize = "$($lock.machine.diskSizeGiB)G"

    if ($null -ne $factory -and -not (Test-Path -LiteralPath $persistentDisk -PathType Leaf)) {
        throw 'The version-bound private machine overlay is missing. Reopen setup to recreate it safely.'
    }
    if ($null -eq $factory -and -not (Test-Path -LiteralPath $persistentDisk -PathType Leaf)) {
        Write-Host "Creating private $diskSize virtual disk..." -ForegroundColor Cyan
        & $status.Qemu.Image create -f qcow2 $persistentDisk $diskSize
        if ($LASTEXITCODE -ne 0) { throw 'qemu-img could not create the persistent disk.' }
    }
    $diskInfo = Get-Item -LiteralPath $persistentDisk
    if (($diskInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Refusing a persistent disk that is a reparse point.'
    }

    $qemu = if ($null -ne $factory) {
        [pscustomobject]@{
            Root = [string]$factory.Runtime
            System = (Join-Path $factory.Runtime 'qemu-system-x86_64.exe')
            Image = (Join-Path $factory.Runtime 'qemu-img.exe')
        }
    } else { $status.Qemu }
    $firmware = if ($null -ne $factory) { Find-QemuFirmware -Qemu $qemu } else { $status.Firmware }
    if (-not $firmware.Ready) { throw 'The version-bound QEMU firmware is missing.' }

    if ($null -ne $factory) {
        $machineReceiptPath = Join-Path $vm 'machine.json'
        if (-not (Test-Path -LiteralPath $machineReceiptPath -PathType Leaf)) { throw 'The private machine receipt is missing.' }
        $machineReceipt = Get-Content -LiteralPath $machineReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$machineReceipt.buildId -ne [string]$factory.BuildId -or
            [IO.Path]::GetFullPath([string]$machineReceipt.backingFile) -ne [IO.Path]::GetFullPath([string]$factory.Guest)) {
            throw 'The private machine does not belong to the active factory build.'
        }
        $chainText = (& $qemu.Image info --backing-chain --output=json $persistentDisk 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'QEMU could not inspect the private machine backing chain.' }
        $chain = @($chainText | ConvertFrom-Json)
        if ($chain.Count -lt 2 -or [IO.Path]::GetFullPath([string]$chain[1].filename) -ne [IO.Path]::GetFullPath([string]$factory.Guest)) {
            throw 'The private machine backing chain does not match the verified factory disk.'
        }
    }

    $runDisk = $persistentDisk
    if ($Mode -eq 'Disposable') {
        $ephemeralDisk = Join-Path $temp ("disposable-{0}-{1}.qcow2" -f $PID, [Guid]::NewGuid().ToString('N'))
        Assert-WindowsIntoOmarchyChildPath -Path $ephemeralDisk | Out-Null
        & $qemu.Image create -f qcow2 -F qcow2 -b $persistentDisk $ephemeralDisk
        if ($LASTEXITCODE -ne 0) { throw 'qemu-img could not create the disposable overlay.' }
        $runDisk = $ephemeralDisk
    }

    $args = New-Object System.Collections.Generic.List[string]
    foreach ($value in @(
        '-name', 'Windows Into Onarchy',
        '-machine', 'q35',
        '-accel', 'whpx',
        '-smp', "$CpuCount,sockets=1,cores=$CpuCount,threads=1",
        '-m', [string]$MemoryMiB
    )) { $args.Add([string]$value) }

    $qemuShare = Join-Path $qemu.Root 'share'
    if (Test-Path -LiteralPath $qemuShare -PathType Container) {
        foreach ($value in @('-L', $qemuShare)) { $args.Add([string]$value) }
    }

    $firmwareVars = Join-Path $vm 'firmware-vars.fd'
    if ($null -ne $firmware.Vars) {
        if (-not (Test-Path -LiteralPath $firmwareVars -PathType Leaf)) {
            Copy-Item -LiteralPath $firmware.Vars -Destination $firmwareVars
        }
        foreach ($value in @(
            '-drive', "if=pflash,format=raw,readonly=on,file=$($firmware.Code)",
            '-drive', "if=pflash,format=raw,file=$firmwareVars"
        )) { $args.Add($value) }
    } else {
        foreach ($value in @('-bios', $firmware.Code)) { $args.Add($value) }
    }

    foreach ($value in @(
        '-drive', "file=$runDisk,if=none,format=qcow2,id=drive0,cache=writeback,discard=unmap",
        '-device', 'virtio-blk-pci,drive=drive0,bootindex=1',
        '-device', 'qemu-xhci',
        '-device', 'usb-tablet',
        '-device', 'usb-kbd',
        '-netdev', 'user,id=net0',
        '-device', 'virtio-net-pci,netdev=net0',
        '-device', 'virtio-rng-pci',
        '-audiodev', 'dsound,id=audio0',
        '-device', 'ich9-intel-hda',
        '-device', 'hda-duplex,audiodev=audio0'
    )) { $args.Add([string]$value) }
    if ($null -ne $factory) {
        foreach ($value in @('-boot', 'menu=off,order=c')) { $args.Add([string]$value) }
    } else {
        foreach ($value in @(
            '-drive', "file=$($status.IsoPath),media=cdrom,if=none,format=raw,readonly=on,id=cdrom0",
            '-device', 'ide-cd,drive=cdrom0,bootindex=2',
            '-boot', 'menu=on,order=cd',
            '-drive', "file=$($status.CidataPath),format=raw,if=none,readonly=on,id=cidata",
            '-device', 'usb-storage,drive=cidata'
        )) { $args.Add([string]$value) }
    }
    $gpuReady = $false
    if ($null -ne $factory) {
        $gpuReady = [bool]$factory.Capabilities.gpuAccelerationReady -and
            [bool]$factory.Capabilities.virglAdvertised -and
            [bool]$factory.Capabilities.anglePresent -and
            [bool]$factory.Capabilities.virglDisplaySmokeTested
    }
    if ($gpuReady) {
        foreach ($value in @('-device','virtio-vga-gl','-display','sdl,gl=on,grab-mod=lshift-lctrl-lalt,window-close=on')) { $args.Add([string]$value) }
    } else {
        foreach ($value in @('-device','virtio-vga','-display','sdl,gl=off,grab-mod=lshift-lctrl-lalt,window-close=on')) { $args.Add([string]$value) }
    }
    if ($FullScreen) { $args.Add('-full-screen') }

    $logPath = Join-Path $logs ("qemu-{0}.log" -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $quoted = $args | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }
    Write-WindowsIntoOmarchyLog -Message "Starting $Mode VM with $MemoryMiB MiB and $CpuCount CPUs"
    Write-Host 'Starting Omarchy. Release keyboard capture with Left Shift + Left Ctrl + Left Alt + G.' -ForegroundColor Green

    $process = Start-Process -FilePath $qemu.System -ArgumentList ($quoted -join ' ') -PassThru -Wait -RedirectStandardError $logPath
    if ($process.ExitCode -ne 0) {
        throw "QEMU exited with code $($process.ExitCode). Diagnostic log: $logPath"
    }
} catch {
    Write-WindowsIntoOmarchyLog -Message "VM failed: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
} finally {
    if ($null -ne $ephemeralDisk -and (Test-Path -LiteralPath $ephemeralDisk -PathType Leaf)) {
        Assert-WindowsIntoOmarchyChildPath -Path $ephemeralDisk | Out-Null
        Remove-Item -LiteralPath $ephemeralDisk -Force
    }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
