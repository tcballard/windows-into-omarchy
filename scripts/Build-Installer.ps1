param(
    [string]$InnoSetupCompiler,
    [switch]$RequireFactory,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'config\runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$lock.product.version

$requiredPackageInputs = @(
    'scripts\Materialize-Factory.ps1',
    'scripts\Install-PortableRuntime.ps1',
    'scripts\Test-PortableRuntimeCapabilities.ps1',
    'scripts\Run-VM.ps1',
    'runtime\portable-runtime.lock.json',
    'runtime\compliance\SOURCE-OFFER.txt',
    'factory\release-manifest.schema.json'
)
foreach ($relative in $requiredPackageInputs) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
        throw "Required installer input is missing: $relative"
    }
}
$factoryManifest = Join-Path $projectRoot 'factory\factory-release.json'
if ($RequireFactory -and -not (Test-Path -LiteralPath $factoryManifest -PathType Leaf)) {
    throw 'A frictionless release installer requires factory\factory-release.json.'
}
if (Test-Path -LiteralPath $factoryManifest -PathType Leaf) {
    $factory = Get-Content -LiteralPath $factoryManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$factory.schemaVersion -ne 1 -or [string]$factory.product -ne 'Windows Into Omarchy' -or
        [string]$factory.productVersion -ne $version -or [string]$factory.releaseTag -ne ('factory-v' + $version) -or
        [string]$factory.architecture -ne 'x86_64' -or [string]$factory.buildId -notmatch '^[a-z0-9][a-z0-9._-]{7,127}$' -or
        @($factory.assets).Count -ne 2) {
        throw 'The factory release manifest does not match this installer version.'
    }
    $factoryRuntime = @($factory.assets | Where-Object { [string]$_.role -eq 'runtime' })
    $factoryGuest = @($factory.assets | Where-Object { [string]$_.role -eq 'guest' })
    if ($factoryRuntime.Count -ne 1 -or [string]$factoryRuntime[0].archive -ne 'zip' -or
        [string]$factoryRuntime[0].outputRelativePath -ne 'runtime/qemu' -or
        [string]$factoryRuntime[0].payload.relativePath -ne 'runtime/qemu/_compliance/payload-manifest.json' -or
        $factoryGuest.Count -ne 1 -or [string]$factoryGuest[0].archive -ne 'zstd' -or
        [string]$factoryGuest[0].outputRelativePath -ne 'guest/omarchy-factory.qcow2' -or
        [string]$factoryGuest[0].payload.relativePath -ne 'guest/omarchy-factory.qcow2') {
        throw 'The factory release manifest has an incompatible runtime or guest layout.'
    }
}

$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if ($null -eq $dotnet) { throw 'The .NET 8 SDK is required to build the native Windows application.' }
$nativeProject = Join-Path $projectRoot 'windows\WindowsIntoOmarchy\WindowsIntoOmarchy.csproj'
$nativeOutput = Join-Path $projectRoot 'dist\app'
$nativeStage = Join-Path $projectRoot ('dist\app-stage-' + [Guid]::NewGuid().ToString('N'))
& $dotnet.Source publish $nativeProject -c Release -r win-x64 --self-contained true -o $nativeStage -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw 'The native Windows application did not publish successfully.' }
$nativeExe = Join-Path $nativeStage 'WindowsIntoOmarchy.exe'
if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) { throw 'The native Windows executable was not produced.' }
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist')).TrimEnd('\') + '\'
if (-not [IO.Path]::GetFullPath($nativeOutput).StartsWith($distRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to replace a native output directory outside dist.'
}
if (Test-Path -LiteralPath $nativeOutput) { Remove-Item -LiteralPath $nativeOutput -Recurse -Force }
Move-Item -LiteralPath $nativeStage -Destination $nativeOutput

if (-not $SkipTests) {
    & python (Join-Path $projectRoot 'image\make_cidata.py')
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the deterministic cidata image.' }
    & (Join-Path $projectRoot 'tests\Test-Static.ps1')
    if (-not $?) { throw 'Windows PowerShell static checks failed.' }
    & python -m unittest discover -s (Join-Path $projectRoot 'tests') -v
    if ($LASTEXITCODE -ne 0) { throw 'Python contract checks failed.' }
}

if ($SkipTests) {
    & python (Join-Path $projectRoot 'image\make_cidata.py')
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate the deterministic cidata image.' }
}

$cidata = Join-Path $projectRoot ([string]$lock.machine.unattended.imageRelativePath)
$cidataHash = (Get-FileHash -LiteralPath $cidata -Algorithm SHA256).Hash.ToLowerInvariant()
if ($cidataHash -ne [string]$lock.machine.unattended.sha256) {
    throw 'Refusing to package an unattended drive that does not match the runtime lock.'
}

$compiler = $InnoSetupCompiler
if ([string]::IsNullOrWhiteSpace($compiler)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $compiler = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($compiler) -or -not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'Inno Setup 6 compiler was not found. Install Inno Setup or pass -InnoSetupCompiler.'
}

$compilerArguments = @("/DMyAppVersion=$version")
if ($RequireFactory) { $compilerArguments += '/DFactorySidecars' }
$compilerArguments += (Join-Path $projectRoot 'installer\WindowsIntoOmarchy.iss')
& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0) { throw "Inno Setup exited with code $LASTEXITCODE." }

$artifact = Join-Path $projectRoot "dist\Windows-Into-Omarchy-v$version-setup-unsigned.exe"
if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
    throw "Expected installer was not produced: $artifact"
}
$digest = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
$sumPath = Join-Path $projectRoot 'dist\SHA256SUMS'
$existing = if (Test-Path -LiteralPath $sumPath) { Get-Content -LiteralPath $sumPath } else { @() }
$lines = @($existing | Where-Object { $_ -notmatch [regex]::Escape((Split-Path -Leaf $artifact)) })
$lines += "$digest  $(Split-Path -Leaf $artifact)"
$lines | Set-Content -LiteralPath $sumPath -Encoding Ascii

Write-Host "Built $artifact" -ForegroundColor Green
Write-Host "SHA-256 $digest"
