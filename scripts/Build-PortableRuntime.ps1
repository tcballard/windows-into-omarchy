param(
    [string]$OutputDirectory,
    [string]$CacheDirectory,
    [string]$SevenZipPath,
    [switch]$RunDisplaySmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$projectRoot = Split-Path -Parent $PSScriptRoot
$lockPath = Join-Path $projectRoot 'runtime\portable-runtime.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$output = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { Join-Path $projectRoot 'dist\runtime' } else { [IO.Path]::GetFullPath($OutputDirectory) }
$cache = if ([string]::IsNullOrWhiteSpace($CacheDirectory)) { Join-Path ([IO.Path]::GetTempPath()) 'windows-into-onarchy-runtime-cache' } else { [IO.Path]::GetFullPath($CacheDirectory) }

function Resolve-SevenZip {
    if (-not [string]::IsNullOrWhiteSpace($SevenZipPath)) {
        if (-not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) { throw "7-Zip not found: $SevenZipPath" }
        return [IO.Path]::GetFullPath($SevenZipPath)
    }
    foreach ($name in @('7zz.exe', '7z.exe', '7zz', '7z')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw 'A pinned release input and 7-Zip are required to construct the portable runtime.'
}

function Get-LockedFile {
    param([Parameter(Mandatory=$true)]$Artifact, [Parameter(Mandatory=$true)][ValidateSet('SHA256','SHA512')][string]$Algorithm)
    $path = Join-Path $cache ([string]$Artifact.fileName)
    $hashProperty = $Algorithm.ToLowerInvariant()
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm $Algorithm).Hash.ToLowerInvariant()
        $expected = ([string]$Artifact.$hashProperty).ToLowerInvariant()
        if ($actual -eq $expected) { return $path }
        $quarantine = "$path.digest-mismatch-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
        Move-Item -LiteralPath $path -Destination $quarantine
    }
    $partial = "$path.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    Invoke-WebRequest -UseBasicParsing -Uri ([string]$Artifact.url) -OutFile $partial
    $actual = (Get-FileHash -LiteralPath $partial -Algorithm $Algorithm).Hash.ToLowerInvariant()
    $expected = ([string]$Artifact.$hashProperty).ToLowerInvariant()
    if ($actual -ne $expected) { throw "Digest mismatch for $($Artifact.fileName): expected $expected, got $actual" }
    Move-Item -LiteralPath $partial -Destination $path
    return $path
}

function Invoke-SevenZip {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    & $script:sevenZip @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "7-Zip exited with code $LASTEXITCODE." }
}

function Get-RelativePath {
    param([string]$Base, [string]$Path)
    $baseUri = New-Object Uri(([IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'))
    $pathUri = New-Object Uri([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Write-CanonicalJson {
    param([Parameter(Mandatory=$true)]$Value, [Parameter(Mandatory=$true)][string]$Path, [int]$Depth = 12)
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, ($json.Replace("`r`n", "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
}

$script:sevenZip = Resolve-SevenZip
New-Item -ItemType Directory -Path $cache -Force | Out-Null
New-Item -ItemType Directory -Path $output -Force | Out-Null
$work = Join-Path ([IO.Path]::GetTempPath()) ('windows-into-onarchy-runtime-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    $qemuInstaller = Get-LockedFile -Artifact $lock.qemu.installer -Algorithm SHA512
    $qemuSource = Get-LockedFile -Artifact $lock.qemu.source -Algorithm SHA256
    $zstdBinary = Get-LockedFile -Artifact $lock.zstd.binary -Algorithm SHA256
    $zstdSource = Get-LockedFile -Artifact $lock.zstd.source -Algorithm SHA256

    $qemuExtract = Join-Path $work 'qemu-extracted'
    $zstdExtract = Join-Path $work 'zstd-extracted'
    $payload = Join-Path $work 'payload'
    $qemuPayload = Join-Path $payload 'runtime\qemu'
    $toolsPayload = Join-Path $payload 'tools'
    $licensesPayload = Join-Path $payload 'licenses'
    foreach ($directory in @($qemuExtract, $zstdExtract, $qemuPayload, $toolsPayload, $licensesPayload)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Invoke-SevenZip @('x', $qemuInstaller, "-o$qemuExtract", '-y')
    Invoke-SevenZip @('x', $zstdBinary, "-o$zstdExtract", '-y')

    # Keep the complete dependency/data set but omit installer-only plugins and
    # emulators for unrelated guest architectures. This is an extraction, not
    # an installation, and therefore needs no elevation on the end-user PC.
    $allowedExecutables = @('qemu-system-x86_64.exe','qemu-system-x86_64w.exe','qemu-img.exe')
    foreach ($item in Get-ChildItem -LiteralPath $qemuExtract -Force) {
        if ($item.Name -eq '$PLUGINSDIR') { continue }
        if (-not $item.PSIsContainer -and $item.Extension -ieq '.exe' -and $allowedExecutables -notcontains $item.Name) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $qemuPayload -Recurse -Force
    }
    $zstdExe = Get-ChildItem -LiteralPath $zstdExtract -Filter 'zstd.exe' -File -Recurse | Select-Object -First 1
    if ($null -eq $zstdExe) { throw 'The locked Zstandard archive contains no zstd.exe.' }
    Copy-Item -LiteralPath $zstdExe.FullName -Destination (Join-Path $toolsPayload 'zstd.exe')

    foreach ($required in @('qemu-system-x86_64.exe','qemu-img.exe','COPYING','COPYING.LIB','share\edk2-licenses.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $qemuPayload $required) -PathType Leaf)) { throw "Portable runtime is missing $required" }
    }
    New-Item -ItemType Directory -Path (Join-Path $licensesPayload 'qemu') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $licensesPayload 'zstd') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $qemuPayload 'COPYING') -Destination (Join-Path $licensesPayload 'qemu\COPYING')
    Copy-Item -LiteralPath (Join-Path $qemuPayload 'COPYING.LIB') -Destination (Join-Path $licensesPayload 'qemu\COPYING.LIB')

    $zstdSourceExtract = Join-Path $work 'zstd-source'
    New-Item -ItemType Directory -Path $zstdSourceExtract | Out-Null
    Invoke-SevenZip @('x', $zstdSource, "-o$zstdSourceExtract", '-y')
    $zstdTar = Get-ChildItem -LiteralPath $zstdSourceExtract -Filter '*.tar' -File | Select-Object -First 1
    if ($null -eq $zstdTar) { throw 'Zstandard source archive did not expand to a tar archive.' }
    Invoke-SevenZip @('x', $zstdTar.FullName, "-o$zstdSourceExtract\tree", '-y')
    $zstdLicense = Get-ChildItem -LiteralPath (Join-Path $zstdSourceExtract 'tree') -Filter 'LICENSE' -File -Recurse | Select-Object -First 1
    if ($null -eq $zstdLicense) { throw 'Zstandard source contains no LICENSE.' }
    Copy-Item -LiteralPath $zstdLicense.FullName -Destination (Join-Path $licensesPayload 'zstd\LICENSE')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\SOURCE-OFFER.txt') -Destination $licensesPayload
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\license-manifest.json') -Destination $licensesPayload
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\corresponding-source-manifest.json') -Destination $licensesPayload

    $capabilityScript = Join-Path $projectRoot 'scripts\Test-PortableRuntimeCapabilities.ps1'
    $capabilityPath = Join-Path $payload 'capability-receipt.json'
    & $capabilityScript -RuntimeRoot $qemuPayload -OutputPath $capabilityPath -MeasuredAtUtc '2026-08-11T00:00:00Z' -RunDisplaySmoke:$RunDisplaySmoke | Out-Null
    $capabilities = Get-Content -LiteralPath $capabilityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$capabilities.qemuVersionOutput -notmatch [regex]::Escape([string]$lock.qemu.version)) {
        throw "Unexpected QEMU version: $($capabilities.qemuVersionOutput)"
    }

    $fileRecords = @()
    foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
        $relative = (Get-RelativePath -Base $payload -Path $file.FullName).Replace('\','/')
        $fileRecords += [ordered]@{ path=$relative; size=[long]$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $payloadManifest = [ordered]@{
        schemaVersion = 1
        target = [string]$lock.target
        qemuVersion = [string]$lock.qemu.version
        qemuBuild = [string]$lock.qemu.build
        zstdVersion = [string]$lock.zstd.version
        fileCount = $fileRecords.Count
        files = $fileRecords
    }
    $manifestPath = Join-Path $output 'payload-manifest.json'
    Write-CanonicalJson -Value $payloadManifest -Path $manifestPath -Depth 8
    $embeddedCompliance = Join-Path $qemuPayload '_compliance'
    New-Item -ItemType Directory -Path $embeddedCompliance -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $embeddedCompliance 'payload-manifest.json')

    $spdxFiles = @()
    $relationships = @([ordered]@{ spdxElementId='SPDXRef-DOCUMENT'; relationshipType='DESCRIBES'; relatedSpdxElement='SPDXRef-Package-PortableRuntime' })
    $index = 0
    foreach ($record in $fileRecords) {
        $index += 1
        $id = "SPDXRef-File-$index"
        $spdxFiles += [ordered]@{ fileName="./$($record.path)"; SPDXID=$id; checksums=@([ordered]@{ algorithm='SHA256'; checksumValue=$record.sha256 }); licenseConcluded='NOASSERTION'; copyrightText='NOASSERTION' }
        $relationships += [ordered]@{ spdxElementId='SPDXRef-Package-PortableRuntime'; relationshipType='CONTAINS'; relatedSpdxElement=$id }
    }
    $sbom = [ordered]@{
        spdxVersion='SPDX-2.3'; dataLicense='CC0-1.0'; SPDXID='SPDXRef-DOCUMENT'; name='Windows-Into-Onarchy-Portable-Runtime'
        documentNamespace=[string]$lock.payload.sbomNamespace
        creationInfo=[ordered]@{ created='2026-08-26T00:00:00Z'; creators=@('Tool: scripts/Build-PortableRuntime.ps1') }
        packages=@([ordered]@{ name='Windows Into Onarchy portable runtime'; SPDXID='SPDXRef-Package-PortableRuntime'; versionInfo=[string]$lock.qemu.build; downloadLocation='NOASSERTION'; filesAnalyzed=$true; licenseConcluded='NOASSERTION'; licenseDeclared='NOASSERTION'; copyrightText='NOASSERTION' })
        files=$spdxFiles; relationships=$relationships
    }
    Write-CanonicalJson -Value $sbom -Path (Join-Path $output 'runtime.spdx.json') -Depth 12

    $provenance = [ordered]@{
        schemaVersion=1; builder='scripts/Build-PortableRuntime.ps1'; target=[string]$lock.target
        inputs=@(
            [ordered]@{ uri=[string]$lock.qemu.installer.url; digest=[ordered]@{ sha512=[string]$lock.qemu.installer.sha512 } },
            [ordered]@{ uri=[string]$lock.qemu.source.url; digest=[ordered]@{ sha256=[string]$lock.qemu.source.sha256 } },
            [ordered]@{ uri=[string]$lock.zstd.binary.url; digest=[ordered]@{ sha256=[string]$lock.zstd.binary.sha256 } },
            [ordered]@{ uri=[string]$lock.zstd.source.url; digest=[ordered]@{ sha256=[string]$lock.zstd.source.sha256 } }
        )
        transformations=@('verify locked inputs','extract QEMU NSIS without executing it','retain x86_64 executables and complete dependency/data set','add pinned zstd CLI','hash every payload file','create deterministic archives')
    }
    Write-CanonicalJson -Value $provenance -Path (Join-Path $output 'provenance.json')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\license-manifest.json') -Destination $output -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\corresponding-source-manifest.json') -Destination $output -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime\compliance\SOURCE-OFFER.txt') -Destination $output -Force
    Copy-Item -LiteralPath (Join-Path $payload 'capability-receipt.json') -Destination $output -Force

    $fixedTime = [DateTime]::SpecifyKind([DateTime]'2026-08-11T00:00:00', [DateTimeKind]::Utc)
    Get-ChildItem -LiteralPath $payload -Recurse -Force | ForEach-Object { $_.LastWriteTimeUtc = $fixedTime }
    $runtimeArchive = Join-Path $output ([string]$lock.payload.archiveName)
    if (Test-Path -LiteralPath $runtimeArchive) { Remove-Item -LiteralPath $runtimeArchive -Force }
    Push-Location $payload
    try { Invoke-SevenZip @('a','-tzip','-mx=9','-mmt=off','-mtc=off','-mta=off',$runtimeArchive,'.\*') } finally { Pop-Location }

    $sourceStage = Join-Path $work 'source-stage'
    New-Item -ItemType Directory -Path $sourceStage | Out-Null
    Copy-Item -LiteralPath $qemuSource -Destination $sourceStage
    Copy-Item -LiteralPath $zstdSource -Destination $sourceStage
    Copy-Item -Path (Join-Path $projectRoot 'runtime\compliance\*') -Destination $sourceStage -Force
    Get-ChildItem -LiteralPath $sourceStage -Recurse -Force | ForEach-Object { $_.LastWriteTimeUtc = $fixedTime }
    $sourceArchive = Join-Path $output ([string]$lock.payload.sourceArchiveName)
    if (Test-Path -LiteralPath $sourceArchive) { Remove-Item -LiteralPath $sourceArchive -Force }
    Push-Location $sourceStage
    try { Invoke-SevenZip @('a','-tzip','-mx=9','-mmt=off','-mtc=off','-mta=off',$sourceArchive,'.\*') } finally { Pop-Location }

    $partSize = [long]$lock.payload.splitPartBytes
    $inputStream = [IO.File]::OpenRead($runtimeArchive)
    try {
        $part = 1
        $buffer = New-Object byte[] (4MB)
        while ($inputStream.Position -lt $inputStream.Length) {
            $partPath = '{0}.part{1:d3}' -f $runtimeArchive, $part
            $outStream = [IO.File]::Create($partPath)
            try {
                $written = 0L
                while ($written -lt $partSize -and $inputStream.Position -lt $inputStream.Length) {
                    $wanted = [int][Math]::Min($buffer.Length, $partSize - $written)
                    $read = $inputStream.Read($buffer, 0, $wanted)
                    if ($read -le 0) { break }
                    $outStream.Write($buffer, 0, $read)
                    $written += $read
                }
            } finally { $outStream.Dispose() }
            $part += 1
        }
    } finally { $inputStream.Dispose() }

    $checksumTargets = Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object Name
    $lines = foreach ($file in $checksumTargets) { '{0}  {1}' -f ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()), $file.Name }
    [IO.File]::WriteAllLines((Join-Path $output 'SHA256SUMS'), $lines, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Portable runtime release built at $output" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
