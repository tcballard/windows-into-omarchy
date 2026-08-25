param(
    [ValidateSet('Persistent','Disposable')][string]$Mode = 'Persistent',
    [int]$MemoryMiB = 8192,
    [int]$CpuCount = 4,
    [switch]$FullScreen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

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
    if (-not $status.Ready) {
        throw 'The machine is not ready. Open the launcher, prepare missing components, then refresh diagnostics.'
    }
    $hostMemoryMiB = [math]::Floor((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB)
    if ($MemoryMiB -gt ($hostMemoryMiB - 2048)) {
        throw "The selected memory would leave Windows less than 2048 MiB. Select a smaller VM memory size."
    }
    if ($status.DataRoot.Contains(',')) {
        throw 'The Windows profile path contains a comma, which this QEMU command contract cannot safely encode.'
    }

    $root = $status.DataRoot
    $vm = Join-Path $root 'VM'
    $temp = Join-Path $root 'Temp'
    $logs = Join-Path $root 'Logs'
    $persistentDisk = Join-Path $vm 'omarchy.qcow2'
    $diskSize = "$($lock.machine.diskSizeGiB)G"

    if (-not (Test-Path -LiteralPath $persistentDisk -PathType Leaf)) {
        Write-Host "Creating private $diskSize virtual disk..." -ForegroundColor Cyan
        & $status.Qemu.Image create -f qcow2 $persistentDisk $diskSize
        if ($LASTEXITCODE -ne 0) { throw 'qemu-img could not create the persistent disk.' }
    }
    $diskInfo = Get-Item -LiteralPath $persistentDisk
    if (($diskInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Refusing a persistent disk that is a reparse point.'
    }

    $runDisk = $persistentDisk
    if ($Mode -eq 'Disposable') {
        $ephemeralDisk = Join-Path $temp ("disposable-{0}-{1}.qcow2" -f $PID, [Guid]::NewGuid().ToString('N'))
        Assert-WindowsIntoOmarchyChildPath -Path $ephemeralDisk | Out-Null
        & $status.Qemu.Image create -f qcow2 -F qcow2 -b $persistentDisk $ephemeralDisk
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

    $qemuShare = Join-Path $status.Qemu.Root 'share'
    if (Test-Path -LiteralPath $qemuShare -PathType Container) {
        foreach ($value in @('-L', $qemuShare)) { $args.Add([string]$value) }
    }

    $firmwareVars = Join-Path $vm 'firmware-vars.fd'
    if ($null -ne $status.Firmware.Vars) {
        if (-not (Test-Path -LiteralPath $firmwareVars -PathType Leaf)) {
            Copy-Item -LiteralPath $status.Firmware.Vars -Destination $firmwareVars
        }
        foreach ($value in @(
            '-drive', "if=pflash,format=raw,readonly=on,file=$($status.Firmware.Code)",
            '-drive', "if=pflash,format=raw,file=$firmwareVars"
        )) { $args.Add($value) }
    } else {
        foreach ($value in @('-bios', $status.Firmware.Code)) { $args.Add($value) }
    }

    foreach ($value in @(
        '-drive', "file=$runDisk,if=none,format=qcow2,id=drive0,cache=writeback,discard=unmap",
        '-device', 'virtio-blk-pci,drive=drive0,bootindex=1',
        '-drive', "file=$($status.IsoPath),media=cdrom,if=none,format=raw,readonly=on,id=cdrom0",
        '-device', 'ide-cd,drive=cdrom0,bootindex=2',
        '-boot', 'menu=on,order=cd',
        '-device', 'virtio-vga',
        '-display', 'sdl,gl=off,grab-mod=lshift-lctrl-lalt,window-close=on',
        '-device', 'qemu-xhci',
        '-drive', "file=$($status.CidataPath),format=raw,if=none,readonly=on,id=cidata",
        '-device', 'usb-storage,drive=cidata',
        '-device', 'usb-tablet',
        '-device', 'usb-kbd',
        '-netdev', 'user,id=net0',
        '-device', 'virtio-net-pci,netdev=net0',
        '-device', 'virtio-rng-pci',
        '-audiodev', 'dsound,id=audio0',
        '-device', 'ich9-intel-hda',
        '-device', 'hda-duplex,audiodev=audio0'
    )) { $args.Add([string]$value) }
    if ($FullScreen) { $args.Add('-full-screen') }

    $logPath = Join-Path $logs ("qemu-{0}.log" -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $quoted = $args | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }
    Write-WindowsIntoOmarchyLog -Message "Starting $Mode VM with $MemoryMiB MiB and $CpuCount CPUs"
    Write-Host 'Starting Omarchy. Release keyboard capture with Left Shift + Left Ctrl + Left Alt + G.' -ForegroundColor Green

    $process = Start-Process -FilePath $status.Qemu.System -ArgumentList ($quoted -join ' ') -PassThru -Wait -RedirectStandardError $logPath
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
