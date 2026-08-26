param(
    [Parameter(Mandatory=$true)][string]$PayloadRoot,
    [Parameter(Mandatory=$true)][string]$FactoryRoot,
    [Parameter(Mandatory=$true)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd('\')
$destination = [IO.Path]::GetFullPath($FactoryRoot).TrimEnd('\')
$manifestFile = [IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) { throw "Payload manifest not found: $manifestFile" }
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or [string]$manifest.target -ne 'windows-x86_64') { throw 'Unsupported portable runtime manifest.' }

function Assert-SafeRelativePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe payload path: $Path" }
    if ($Path -notmatch '^(runtime/qemu/|tools/zstd\.exe$|licenses/|capability-receipt\.json$)') { throw "Unexpected payload path: $Path" }
}

function Assert-FileRecord {
    param([Parameter(Mandatory=$true)]$Record, [Parameter(Mandatory=$true)][string]$Root)
    $relative = [string]$Record.path
    Assert-SafeRelativePath $relative
    $path = Join-Path $Root $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Payload file is missing: $relative" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Payload file is a reparse point: $relative" }
    if ([long]$item.Length -ne [long]$Record.size) { throw "Payload length mismatch: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$Record.sha256).ToLowerInvariant()) { throw "Payload digest mismatch: $relative" }
}

foreach ($record in @($manifest.files)) { Assert-FileRecord -Record $record -Root $source }
$embeddedManifest = Join-Path $source 'runtime\qemu\_compliance\payload-manifest.json'
if (-not (Test-Path -LiteralPath $embeddedManifest -PathType Leaf)) { throw 'Embedded payload manifest is absent.' }
$externalManifestHash = (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash.ToLowerInvariant()
$embeddedManifestHash = (Get-FileHash -LiteralPath $embeddedManifest -Algorithm SHA256).Hash.ToLowerInvariant()
if ($embeddedManifestHash -ne $externalManifestHash) { throw 'Embedded payload manifest does not match the release manifest.' }
if (-not (Test-Path -LiteralPath (Join-Path $source 'runtime\qemu\qemu-system-x86_64.exe'))) { throw 'QEMU system executable is absent.' }
if (-not (Test-Path -LiteralPath (Join-Path $source 'runtime\qemu\qemu-img.exe'))) { throw 'QEMU image executable is absent.' }
if (-not (Test-Path -LiteralPath (Join-Path $source 'tools\zstd.exe'))) { throw 'Pinned zstd tool is absent.' }

# Factory materializers normally extract directly into their private staging
# root. In that case only verification is needed. The copy path is retained for
# installers that unpack the runtime into a separate temporary directory.
if (-not $source.Equals($destination, [StringComparison]::OrdinalIgnoreCase)) {
    $stage = "$destination.runtime-stage-$([Guid]::NewGuid().ToString('N'))"
    if (Test-Path -LiteralPath $stage) { throw "Unexpected existing runtime stage: $stage" }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        foreach ($name in @('runtime','tools','licenses')) {
            $from = Join-Path $source $name
            if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $stage -Recurse -Force }
        }
        Copy-Item -LiteralPath (Join-Path $source 'capability-receipt.json') -Destination $stage -Force
        foreach ($record in @($manifest.files)) { Assert-FileRecord -Record $record -Root $stage }
        if (-not (Test-Path -LiteralPath $destination)) { New-Item -ItemType Directory -Path $destination -Force | Out-Null }
        foreach ($name in @('runtime','tools','licenses','capability-receipt.json')) {
            $from = Join-Path $stage $name
            if (-not (Test-Path -LiteralPath $from)) { continue }
            $to = Join-Path $destination $name
            if (Test-Path -LiteralPath $to) { throw "Refusing to overwrite an existing factory component: $to" }
            Move-Item -LiteralPath $from -Destination $to
        }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}

$receipt = [ordered]@{
    schemaVersion = 1
    target = [string]$manifest.target
    qemuVersion = [string]$manifest.qemuVersion
    qemuBuild = [string]$manifest.qemuBuild
    zstdVersion = [string]$manifest.zstdVersion
    runtimeRoot = (Join-Path $destination 'runtime\qemu')
    qemuSystem = (Join-Path $destination 'runtime\qemu\qemu-system-x86_64.exe')
    qemuImage = (Join-Path $destination 'runtime\qemu\qemu-img.exe')
    zstd = (Join-Path $destination 'tools\zstd.exe')
    manifestSha256 = $externalManifestHash
    verifiedFileCount = @($manifest.files).Count
}
$receipt | ConvertTo-Json -Depth 4
