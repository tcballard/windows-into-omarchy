param(
    [string]$InnoSetupCompiler,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'config\runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$lock.product.version

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

& $compiler (Join-Path $projectRoot 'installer\WindowsIntoOmarchy.iss')
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
