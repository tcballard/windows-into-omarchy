param(
    [Parameter(Mandatory=$true)][string]$RuntimeDirectory,
    [Parameter(Mandatory=$true)][string]$GuestDirectory,
    [string]$OutputDirectory,
    [string]$InnoSetupCompiler
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtime = [IO.Path]::GetFullPath($RuntimeDirectory)
$guest = [IO.Path]::GetFullPath($GuestDirectory)
$output = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectRoot 'dist\factory-release'
} else {
    [IO.Path]::GetFullPath($OutputDirectory)
}
foreach ($pair in @(@($runtime,'runtime'), @($guest,'guest'))) {
    if (-not (Test-Path -LiteralPath $pair[0] -PathType Container)) {
        throw "The $($pair[1]) artifact directory is missing: $($pair[0])"
    }
    $item = Get-Item -LiteralPath $pair[0] -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The $($pair[1]) artifact directory must not be a reparse point."
    }
}
if (Test-Path -LiteralPath $output) { throw "Release staging already exists: $output" }

$work = Join-Path ([IO.Path]::GetTempPath()) ('onarchy-factory-assembly-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $work) { throw "Unexpected existing assembly work directory: $work" }
$manifest = Join-Path $projectRoot 'factory\factory-release.json'
$assembly = Join-Path $projectRoot 'factory\assemble_release.py'
$builder = Join-Path $projectRoot 'scripts\Build-Installer.ps1'
$productLock = Get-Content -LiteralPath (Join-Path $projectRoot 'config\runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$productLock.product.version
if ($version -ne '0.3.0') { throw "This assembly gate is locked to 0.3.0, got $version." }

try {
    & python $assembly `
        --root $projectRoot `
        --runtime $runtime `
        --guest $guest `
        --work $work `
        --staging $output `
        --manifest-output $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Independent runtime/guest assembly verification failed.' }

    & $builder -InnoSetupCompiler $InnoSetupCompiler -RequireFactory -SkipTests
    if (-not $?) { throw 'The native factory installer build failed.' }
    $installer = Join-Path $projectRoot "dist\Windows-Into-Onarchy-v$version-setup-unsigned.exe"
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "The expected native installer is missing: $installer"
    }
    $stagedInstaller = Join-Path $output (Split-Path -Leaf $installer)
    if (Test-Path -LiteralPath $stagedInstaller) { throw 'The installer staging destination already exists.' }
    Copy-Item -LiteralPath $installer -Destination $stagedInstaller

    $stagedManifest = Join-Path $output 'factory-release.json'
    if (-not (Test-Path -LiteralPath $stagedManifest -PathType Leaf)) { throw 'The staged factory manifest is missing.' }
    $embeddedManifest = Join-Path $projectRoot 'factory\factory-release.json'
    $stagedHash = (Get-FileHash -LiteralPath $stagedManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    $embeddedHash = (Get-FileHash -LiteralPath $embeddedManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stagedHash -ne $embeddedHash) { throw 'The staged and installer-embedded factory manifests differ.' }

    $sums = Join-Path $output 'SHA256SUMS'
    if (Test-Path -LiteralPath $sums) { throw 'Release checksum destination already exists.' }
    $lines = foreach ($file in Get-ChildItem -LiteralPath $output -File | Sort-Object Name) {
        $name = $file.Name
        if ($name -ne [IO.Path]::GetFileName($name) -or $name.Contains("`n") -or $name.Contains("`r")) {
            throw "Unsafe release asset name: $name"
        }
        '{0}  {1}' -f ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()), $name
    }
    [IO.File]::WriteAllLines($sums, $lines, (New-Object Text.UTF8Encoding($false)))

    foreach ($line in Get-Content -LiteralPath $sums) {
        $fields = $line -split '  ', 2
        if ($fields.Count -ne 2) { throw "Malformed staged checksum line: $line" }
        $path = Join-Path $output $fields[1]
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $fields[0]) { throw "Final staged checksum mismatch: $($fields[1])" }
    }
    Write-Host "Factory release candidate staged at $output" -ForegroundColor Green
} catch {
    if (Test-Path -LiteralPath $output) {
        $failed = "$output.failed-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
        if (-not (Test-Path -LiteralPath $failed)) { Move-Item -LiteralPath $output -Destination $failed }
    }
    throw
} finally {
    if (Test-Path -LiteralPath $work) {
        $workItem = Get-Item -LiteralPath $work -Force
        if (($workItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
            $work.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $work -Recurse -Force
        }
    }
}
