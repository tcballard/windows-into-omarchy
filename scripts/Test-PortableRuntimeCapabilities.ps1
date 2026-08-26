param(
    [Parameter(Mandatory=$true)][string]$RuntimeRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$MeasuredAtUtc,
    [switch]$RequireRuntimeManifest,
    [switch]$RunDisplaySmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath($RuntimeRoot)
$qemu = Join-Path $root 'qemu-system-x86_64.exe'
if (-not (Test-Path -LiteralPath $qemu -PathType Leaf)) { throw "QEMU is missing: $qemu" }

function Test-DisplayMode {
    param([string]$Device, [string]$Display)
    if (-not $RunDisplaySmoke) { return $false }
    $arguments = @('-machine','q35,accel=tcg','-nodefaults','-device',$Device,'-display',$Display,'-S','-no-reboot')
    $process = $null
    try {
        $process = Start-Process -FilePath $qemu -ArgumentList $arguments -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 3
        if ($process.HasExited) { return $false }
        return $true
    } catch { return $false }
    finally {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
                $process.WaitForExit(5000) | Out-Null
            } catch { }
            $process.Dispose()
        }
    }
}

$version = (& $qemu --version 2>&1) -join "`n"
$accelerators = (& $qemu -accel help 2>&1) -join "`n"
$displays = (& $qemu -display help 2>&1) -join "`n"
$devices = (& $qemu -device help 2>&1) -join "`n"
$audio = (& $qemu -audiodev help 2>&1) -join "`n"
$runtimeManifest = Join-Path $root '_compliance\payload-manifest.json'
if ($RequireRuntimeManifest -and -not (Test-Path -LiteralPath $runtimeManifest -PathType Leaf)) { throw 'The embedded runtime payload manifest is missing.' }
$runtimeManifestHash = if (Test-Path -LiteralPath $runtimeManifest -PathType Leaf) {
    (Get-FileHash -LiteralPath $runtimeManifest -Algorithm SHA256).Hash.ToLowerInvariant()
} else { '' }
$measurementTime = if ([string]::IsNullOrWhiteSpace($MeasuredAtUtc)) { [DateTime]::UtcNow } else {
    [DateTime]::Parse($MeasuredAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
}
$receipt = [ordered]@{
    schemaVersion = 1
    measuredOn = 'current-windows-host'
    qemuVersionOutput = ($version -split "`n" | Select-Object -First 1)
    qemuSystemSha256 = (Get-FileHash -LiteralPath $qemu -Algorithm SHA256).Hash.ToLowerInvariant()
    runtimeManifestSha256 = $runtimeManifestHash
    whpxAdvertised = [bool]($accelerators -match '(?im)^\s*whpx(?:\s|$)')
    sdl2dAdvertised = [bool]($displays -match '(?im)^\s*sdl(?:\s|$)' -and $devices -match 'virtio-vga')
    sdl2dSmokeTested = (Test-DisplayMode -Device 'virtio-vga' -Display 'sdl')
    sdl2dReady = $false
    virglAdvertised = [bool]($devices -match 'virtio-vga-gl' -and $displays -match '(?im)^\s*sdl(?:\s|$)' -and (Test-Path -LiteralPath (Join-Path $root 'libvirglrenderer-1.dll')))
    anglePresent = [bool]((Test-Path -LiteralPath (Join-Path $root 'libEGL.dll')) -and (Test-Path -LiteralPath (Join-Path $root 'libGLESv2.dll')))
    virglDisplaySmokeTested = (Test-DisplayMode -Device 'virtio-vga-gl' -Display 'sdl,gl=on')
    gpuAccelerationReady = $false
    directSoundAdvertised = [bool]($audio -match '(?im)^\s*dsound(?:\s|$)')
    measuredAtUtc = $measurementTime.ToUniversalTime().ToString('o')
    decisionRule = 'gpuAccelerationReady is true only when VirGL is advertised, ANGLE is present, and an SDL OpenGL process survives on this Windows host.'
}
$receipt.sdl2dReady = [bool]($receipt.sdl2dAdvertised -and $receipt.sdl2dSmokeTested)
$receipt.gpuAccelerationReady = [bool]($receipt.virglAdvertised -and $receipt.anglePresent -and $receipt.virglDisplaySmokeTested)
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$json = $receipt | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($json.Replace("`r`n", "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
$receipt
