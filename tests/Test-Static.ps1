Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$failed = $false
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed = $true
        Write-Host "not ok - $($_.FullName)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $($_.Message) at $($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber)" }
    } else {
        Write-Host "ok - $($_.FullName)" -ForegroundColor Green
    }
}

try {
    $lock = Get-Content -LiteralPath (Join-Path $root 'config\runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($lock.schemaVersion -ne 2) { throw 'unsupported runtime lock schema' }
    $cidata = Join-Path $root $lock.machine.unattended.imageRelativePath
    if (-not (Test-Path -LiteralPath $cidata -PathType Leaf)) { throw 'cidata image is missing' }
    $cidataHash = (Get-FileHash -LiteralPath $cidata -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($cidataHash -ne $lock.machine.unattended.sha256) { throw 'cidata image digest mismatch' }
    Write-Host 'ok - runtime lock parses' -ForegroundColor Green
} catch {
    $failed = $true
    Write-Host "not ok - runtime lock: $($_.Exception.Message)" -ForegroundColor Red
}

if ($failed) { exit 1 }
