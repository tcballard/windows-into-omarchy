param(
    [Parameter(Mandatory=$true)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$experienceCommon = Join-Path $PSScriptRoot 'experience\Experience.Common.ps1'
if (-not (Test-Path -LiteralPath $experienceCommon -PathType Leaf)) {
    throw 'The experience state helper is missing.'
}
. $experienceCommon

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-StrictFactoryManifest {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'The embedded factory manifest is missing.' }
    $item = Get-Item -LiteralPath $full
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing a factory manifest that is a reparse point.' }
    $manifest = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.product -ne 'Windows Into Omarchy') {
        throw 'The embedded factory manifest has an unsupported product or schema.'
    }
    if ([string]$manifest.architecture -ne 'x86_64') { throw 'The factory release is not x86-64.' }
    $productVersion = [string]$manifest.productVersion
    $escapedVersion = [regex]::Escape($productVersion)
    $validReleaseTag = [string]$manifest.releaseTag -ceq ('factory-v' + $productVersion) -or
        [string]$manifest.releaseTag -ceq ('v' + $productVersion) -or
        [string]$manifest.releaseTag -cmatch ('^v' + $escapedVersion + '-rc\.[1-9][0-9]*$')
    if (-not $validReleaseTag) {
        throw 'The factory release tag does not match its product version.'
    }
    $buildId = [string]$manifest.buildId
    if ($buildId -notmatch '^[a-z0-9][a-z0-9._-]{7,127}$') { throw 'The factory build identity is unsafe.' }
    $assets = @($manifest.assets)
    if ($assets.Count -ne 2) { throw 'The factory manifest must contain exactly two assets.' }
    foreach ($role in @('runtime','guest')) {
        if (@($assets | Where-Object { [string]$_.role -eq $role }).Count -ne 1) {
            throw "The factory manifest must contain exactly one $role asset."
        }
    }
    $runtimeAsset = @($assets | Where-Object { [string]$_.role -eq 'runtime' })[0]
    $guestAsset = @($assets | Where-Object { [string]$_.role -eq 'guest' })[0]
    if ([string]$runtimeAsset.archive -ne 'zip' -or [string]$runtimeAsset.outputRelativePath -ne 'runtime/qemu' -or
        [string]$runtimeAsset.payload.kind -ne 'tree-manifest' -or
        [string]$runtimeAsset.payload.relativePath -ne 'runtime/qemu/_compliance/payload-manifest.json') {
        throw 'The runtime asset does not match the portable factory layout.'
    }
    if ([string]$guestAsset.archive -ne 'zstd' -or [string]$guestAsset.outputRelativePath -ne 'guest/omarchy-factory.qcow2' -or
        [string]$guestAsset.payload.kind -ne 'file' -or
        [string]$guestAsset.payload.relativePath -ne 'guest/omarchy-factory.qcow2') {
        throw 'The guest asset does not match the factory disk layout.'
    }
    foreach ($asset in $assets) {
        $output = [string]$asset.outputRelativePath
        if ([string]::IsNullOrWhiteSpace($output) -or [IO.Path]::IsPathRooted($output) -or $output -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe factory output path: $output"
        }
        if ([string]$asset.assembledSha256 -notmatch '^[0-9a-f]{64}$' -or [long]$asset.assembledSizeBytes -le 0) {
            throw "Invalid assembled archive contract for $($asset.role)."
        }
        if ([string]$asset.payload.sha256 -notmatch '^[0-9a-f]{64}$' -or [long]$asset.payload.sizeBytes -le 0) {
            throw "Invalid extracted payload contract for $($asset.role)."
        }
        $parts = @($asset.parts)
        if ($parts.Count -eq 0) { throw "Factory asset $($asset.role) has no parts." }
        for ($index = 0; $index -lt $parts.Count; $index++) {
            $part = $parts[$index]
            if ([int]$part.index -ne $index -or [long]$part.sizeBytes -le 0 -or [string]$part.sha256 -notmatch '^[0-9a-f]{64}$') {
                throw "Invalid part contract at $($asset.role)/$index."
            }
            $fileName = [string]$part.fileName
            if ($fileName -ne [IO.Path]::GetFileName($fileName) -or [string]::IsNullOrWhiteSpace($fileName)) {
                throw "Unsafe factory part name: $fileName"
            }
            $uri = [Uri]([string]$part.url)
            $expectedPath = '/tcballard/windows-into-omarchy/releases/download/' + [string]$manifest.releaseTag + '/' + $fileName
            if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or -not $uri.IsDefaultPort -or
                -not [string]::IsNullOrEmpty($uri.Query) -or
                -not [string]::IsNullOrEmpty($uri.Fragment) -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or
                -not $uri.AbsolutePath.Equals($expectedPath, [StringComparison]::Ordinal)) {
                throw "Factory part URL is not an immutable GitHub release asset: $uri"
            }
        }
    }
    return [pscustomobject]@{ Path=$full; Manifest=$manifest; Sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Move-ToFactoryQuarantine {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Reason)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Assert-WindowsIntoOmarchyChildPath -Path $Path | Out-Null
    $paths = Get-OmarchyExperiencePaths
    $leaf = Split-Path -Leaf $Path
    $target = Join-Path $paths.DataRoot ('Quarantine\factory-{0}-{1}-{2}' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $Reason, $leaf)
    Assert-WindowsIntoOmarchyChildPath -Path $target | Out-Null
    Move-Item -LiteralPath $Path -Destination $target
}

function Get-FactoryPart {
    param(
        [Parameter(Mandatory=$true)]$Part,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$SeedRoot,
        [Parameter(Mandatory=$true)][long]$CompletedBytes,
        [Parameter(Mandatory=$true)][long]$TotalBytes
    )
    Assert-WindowsIntoOmarchyChildPath -Path $Destination | Out-Null
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $ready = (Get-Item -LiteralPath $Destination).Length -eq [long]$Part.sizeBytes -and
            (Test-PinnedFile -Path $Destination -Algorithm SHA256 -ExpectedHash ([string]$Part.sha256))
        if ($ready) { return }
        Move-ToFactoryQuarantine -Path $Destination -Reason 'invalid-part'
    }
    $partial = Assert-WindowsIntoOmarchyChildPath -Path ($Destination + '.partial')
    if (Test-Path -LiteralPath $partial) { Move-ToFactoryQuarantine -Path $partial -Reason 'partial' }

    $downloadName = [string]$Part.fileName
    $seed = Join-Path $SeedRoot $downloadName
    if (Test-Path -LiteralPath $seed -PathType Leaf) {
        $seedItem = Get-Item -LiteralPath $seed -Force
        if (($seedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $seedItem.Length -ne [long]$Part.sizeBytes -or
            -not (Test-PinnedFile -Path $seed -Algorithm SHA256 -ExpectedHash ([string]$Part.sha256))) {
            throw "The bundled factory part failed verification: $downloadName"
        }
        Move-Item -LiteralPath $seed -Destination $partial
        if ((Get-Item -LiteralPath $partial).Length -ne [long]$Part.sizeBytes -or
            -not (Test-PinnedFile -Path $partial -Algorithm SHA256 -ExpectedHash ([string]$Part.sha256))) {
            Move-ToFactoryQuarantine -Path $partial -Reason 'bundled-part-digest-mismatch'
            throw "The staged bundled factory part failed verification: $downloadName"
        }
        Move-Item -LiteralPath $partial -Destination $Destination
        return
    }

    $basePercent = 15
    $range = 58
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        $job = Start-BitsTransfer -Source ([string]$Part.url) -Destination $partial -DisplayName ('Windows Into Omarchy ' + $downloadName) -Asynchronous
        try {
            while ($true) {
                $job = Get-BitsTransfer -Id $job.Id
                if ($job.JobState -eq 'Transferred') { Complete-BitsTransfer -BitsJob $job; break }
                if ($job.JobState -in @('Error','TransientError')) {
                    $description = if ($null -ne $job.Error) { [string]$job.Error.Description } else { [string]$job.JobState }
                    throw "Download failed for ${downloadName}: $description"
                }
                $current = [math]::Min([long]$Part.sizeBytes, [long]$job.BytesTransferred)
                $percent = $basePercent + [math]::Floor($range * (($CompletedBytes + $current) / [double]$TotalBytes))
                Write-OmarchyExperienceState -Phase Preparing -Headline 'Getting Omarchy ready' -Detail ("Downloading {0}" -f $downloadName) -Percent $percent | Out-Null
                Start-Sleep -Milliseconds 500
            }
        } catch {
            try { if ($null -ne $job) { Remove-BitsTransfer -BitsJob $job -Confirm:$false -ErrorAction SilentlyContinue } } catch { }
            throw
        }
    } else {
        Write-OmarchyExperienceState -Phase Preparing -Headline 'Getting Omarchy ready' -Detail ("Downloading {0}" -f $downloadName) -Percent $basePercent -Indeterminate $true | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri ([string]$Part.url) -OutFile $partial
    }

    if ((Get-Item -LiteralPath $partial).Length -ne [long]$Part.sizeBytes -or
        -not (Test-PinnedFile -Path $partial -Algorithm SHA256 -ExpectedHash ([string]$Part.sha256))) {
        Move-ToFactoryQuarantine -Path $partial -Reason 'digest-mismatch'
        throw "The downloaded factory part failed verification: $downloadName"
    }
    Move-Item -LiteralPath $partial -Destination $Destination
}

function Join-FactoryParts {
    param([Parameter(Mandatory=$true)]$Asset, [Parameter(Mandatory=$true)][string]$DownloadRoot)
    $archive = Join-Path $DownloadRoot (([string]$Asset.role) + '.' + [string]$Asset.archive)
    Assert-WindowsIntoOmarchyChildPath -Path $archive | Out-Null
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        if ((Get-Item -LiteralPath $archive).Length -eq [long]$Asset.assembledSizeBytes -and
            (Test-PinnedFile -Path $archive -Algorithm SHA256 -ExpectedHash ([string]$Asset.assembledSha256))) {
            return $archive
        }
        Move-ToFactoryQuarantine -Path $archive -Reason 'invalid-archive'
    }
    $partial = Assert-WindowsIntoOmarchyChildPath -Path ($archive + '.partial')
    if (Test-Path -LiteralPath $partial) { Move-ToFactoryQuarantine -Path $partial -Reason 'partial-archive' }
    $output = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        foreach ($part in @($Asset.parts)) {
            $sourcePath = Join-Path $DownloadRoot ([string]$part.fileName)
            $source = [IO.File]::OpenRead($sourcePath)
            try { $source.CopyTo($output) } finally { $source.Dispose() }
        }
    } finally { $output.Dispose() }
    if ((Get-Item -LiteralPath $partial).Length -ne [long]$Asset.assembledSizeBytes -or
        -not (Test-PinnedFile -Path $partial -Algorithm SHA256 -ExpectedHash ([string]$Asset.assembledSha256))) {
        Move-ToFactoryQuarantine -Path $partial -Reason 'assembled-digest-mismatch'
        throw "The assembled $($Asset.role) archive failed verification."
    }
    Move-Item -LiteralPath $partial -Destination $archive
    return $archive
}

function Expand-FactoryZipSafely {
    param([Parameter(Mandatory=$true)][string]$Archive, [Parameter(Mandatory=$true)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $total = [long]0
    try {
        foreach ($entry in $zip.Entries) {
            $total += [long]$entry.Length
            if ($total -gt 8GB) { throw 'The runtime archive exceeds its extraction limit.' }
            $unixType = (([int64]$entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or (([int64]$entry.ExternalAttributes -band 0x400) -ne 0)) {
                throw "The runtime archive contains a link or reparse entry: $($entry.FullName)"
            }
            $relative = $entry.FullName.Replace('/', '\')
            if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) {
                throw "The runtime archive contains an unsafe Windows path: $($entry.FullName)"
            }
            foreach ($segment in @($relative -split '\\')) {
                if ($segment.EndsWith(' ') -or $segment.EndsWith('.') -or
                    $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
                    throw "The runtime archive contains a reserved Windows path: $($entry.FullName)"
                }
            }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $relative))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "The runtime archive tries to escape its destination: $($entry.FullName)"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $input = $entry.Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Test-FactoryPayload {
    param([Parameter(Mandatory=$true)]$Asset, [Parameter(Mandatory=$true)][string]$BuildRoot)
    $payloadPath = Join-Path $BuildRoot ([string]$Asset.payload.relativePath).Replace('/', '\')
    $payloadPath = Assert-WindowsIntoOmarchyChildPath -Path $payloadPath
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $payloadPath).Length -ne [long]$Asset.payload.sizeBytes) { return $false }
    return Test-PinnedFile -Path $payloadPath -Algorithm SHA256 -ExpectedHash ([string]$Asset.payload.sha256)
}

$contract = Get-StrictFactoryManifest -Path $ManifestPath
$manifest = $contract.Manifest
$paths = Get-OmarchyExperiencePaths
$seedRoot = Join-Path (Split-Path -Parent $contract.Path) 'parts'
$buildRoot = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.FactoryRoot ([string]$manifest.buildId))
$downloadRoot = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.DataRoot ('Downloads\' + [string]$manifest.buildId))
$temporaryRoot = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.DataRoot ('Temp\factory-' + [Guid]::NewGuid().ToString('N')))

try {
    $active = Get-OmarchyActiveFactory
    if ($null -ne $active -and [string]$active.BuildId -eq [string]$manifest.buildId) { exit 0 }
    if (Test-Path -LiteralPath $buildRoot) { Move-ToFactoryQuarantine -Path $buildRoot -Reason 'incomplete-build' }
    New-Item -ItemType Directory -Path $buildRoot,$downloadRoot,$temporaryRoot -Force | Out-Null

    $allParts = @($manifest.assets | ForEach-Object { @($_.parts) })
    $totalBytes = [long](($allParts | Measure-Object -Property sizeBytes -Sum).Sum)
    $completedBytes = [long]0
    foreach ($asset in @($manifest.assets | Sort-Object { if ([string]$_.role -eq 'runtime') { 0 } else { 1 } })) {
        foreach ($part in @($asset.parts)) {
            $partPath = Join-Path $downloadRoot ([string]$part.fileName)
            Get-FactoryPart -Part $part -Destination $partPath -SeedRoot $seedRoot -CompletedBytes $completedBytes -TotalBytes $totalBytes
            $completedBytes += [long]$part.sizeBytes
        }
    }

    $runtime = @($manifest.assets | Where-Object { [string]$_.role -eq 'runtime' })[0]
    $guest = @($manifest.assets | Where-Object { [string]$_.role -eq 'guest' })[0]

    Write-OmarchyExperienceState -Phase Preparing -Headline 'Preparing the Windows engine' -Detail 'Verifying and unpacking the portable virtualisation engine.' -Percent 76 -Indeterminate $true | Out-Null
    $runtimeArchive = Join-FactoryParts -Asset $runtime -DownloadRoot $downloadRoot
    $runtimeExtract = Join-Path $temporaryRoot 'runtime'
    Expand-FactoryZipSafely -Archive $runtimeArchive -Destination $runtimeExtract
    $runtimePayloadManifest = Join-Path $runtimeExtract 'runtime\qemu\_compliance\payload-manifest.json'
    if (-not (Test-Path -LiteralPath $runtimePayloadManifest -PathType Leaf)) { throw 'The runtime payload manifest is missing at its contracted path after extraction.' }
    if ((Get-Item -LiteralPath $runtimePayloadManifest).Length -ne [long]$runtime.payload.sizeBytes -or
        -not (Test-PinnedFile -Path $runtimePayloadManifest -Algorithm SHA256 -ExpectedHash ([string]$runtime.payload.sha256))) {
        throw 'The extracted runtime payload manifest does not match the embedded factory trust root.'
    }
    $runtimeInstaller = Join-Path $PSScriptRoot 'Install-PortableRuntime.ps1'
    if (-not (Test-Path -LiteralPath $runtimeInstaller -PathType Leaf)) { throw 'The portable runtime installer is missing.' }
    & $runtimeInstaller -PayloadRoot $runtimeExtract -FactoryRoot $buildRoot -ManifestPath $runtimePayloadManifest | Out-Null
    $capabilityTest = Join-Path $PSScriptRoot 'Test-PortableRuntimeCapabilities.ps1'
    if (-not (Test-Path -LiteralPath $capabilityTest -PathType Leaf)) { throw 'The host runtime capability test is missing.' }
    $hostCapabilitiesPath = Join-Path $buildRoot 'host-capabilities.json'
    & $capabilityTest -RuntimeRoot (Join-Path $buildRoot 'runtime\qemu') -OutputPath $hostCapabilitiesPath -RequireRuntimeManifest -RunDisplaySmoke | Out-Null
    $hostCapabilities = Get-Content -LiteralPath $hostCapabilitiesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$hostCapabilities.sdl2dReady) {
        throw 'The portable runtime could not open its safe SDL display on this Windows session.'
    }

    Write-OmarchyExperienceState -Phase Preparing -Headline 'Preparing Omarchy' -Detail 'Expanding the verified factory machine.' -Percent 84 -Indeterminate $true | Out-Null
    $guestArchive = Join-FactoryParts -Asset $guest -DownloadRoot $downloadRoot
    $guestOutput = Join-Path $buildRoot ([string]$guest.outputRelativePath).Replace('/', '\')
    $guestOutput = Assert-WindowsIntoOmarchyChildPath -Path $guestOutput
    $guestParent = Split-Path -Parent $guestOutput
    if (-not (Test-Path -LiteralPath $guestParent -PathType Container)) { New-Item -ItemType Directory -Path $guestParent -Force | Out-Null }
    $guestPartial = Assert-WindowsIntoOmarchyChildPath -Path ($guestOutput + '.partial')
    $zstd = Join-Path $buildRoot 'tools\zstd.exe'
    if (-not (Test-Path -LiteralPath $zstd -PathType Leaf)) { throw 'The verified runtime does not contain its pinned zstd decompressor.' }
    & $zstd -q -d -f --sparse $guestArchive -o $guestPartial
    if ($LASTEXITCODE -ne 0) { throw 'The factory machine could not be expanded.' }
    if ((Get-Item -LiteralPath $guestPartial).Length -ne [long]$guest.payload.sizeBytes -or
        -not (Test-PinnedFile -Path $guestPartial -Algorithm SHA256 -ExpectedHash ([string]$guest.payload.sha256))) {
        Move-ToFactoryQuarantine -Path $guestPartial -Reason 'guest-payload-digest-mismatch'
        throw 'The expanded factory machine failed verification.'
    }
    Move-Item -LiteralPath $guestPartial -Destination $guestOutput
    (Get-Item -LiteralPath $guestOutput).IsReadOnly = $true
    if (-not (Test-FactoryPayload -Asset $runtime -BuildRoot $buildRoot) -or -not (Test-FactoryPayload -Asset $guest -BuildRoot $buildRoot)) {
        throw 'A materialised factory payload does not match the embedded release contract.'
    }

    $receipt = [ordered]@{
        schemaVersion = 1
        complete = $true
        buildId = [string]$manifest.buildId
        productVersion = [string]$manifest.productVersion
        factoryManifestSha256 = $contract.Sha256
        runtimePayloadSha256 = [string]$runtime.payload.sha256
        guestPayloadSha256 = [string]$guest.payload.sha256
        activatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $receiptPath = Join-Path $buildRoot 'receipt.json'
    $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $active = [ordered]@{ schemaVersion=1; buildId=[string]$manifest.buildId; factoryManifestSha256=$contract.Sha256 }
    if (-not (Test-Path -LiteralPath $paths.FactoryRoot -PathType Container)) { New-Item -ItemType Directory -Path $paths.FactoryRoot -Force | Out-Null }
    $activePartial = Assert-WindowsIntoOmarchyChildPath -Path (Join-Path $paths.FactoryRoot 'active.json.partial')
    $active | ConvertTo-Json | Set-Content -LiteralPath $activePartial -Encoding UTF8
    Move-Item -LiteralPath $activePartial -Destination (Join-Path $paths.FactoryRoot 'active.json') -Force
    Write-OmarchyExperienceState -Phase CreatingMachine -Headline 'Creating your private machine' -Detail 'The verified factory is ready.' -Percent 90 -Indeterminate $true | Out-Null
} catch {
    Write-OmarchyExperienceLog -Message ('Factory materialisation failed: ' + $_.Exception.Message)
    if (Test-Path -LiteralPath $buildRoot) { Move-ToFactoryQuarantine -Path $buildRoot -Reason 'failed-build' }
    throw
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Assert-WindowsIntoOmarchyChildPath -Path $temporaryRoot | Out-Null
        $temporaryInfo = Get-Item -LiteralPath $temporaryRoot
        if (($temporaryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}
