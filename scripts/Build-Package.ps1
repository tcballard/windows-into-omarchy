Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'tests\Test-Static.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($null -eq $python) { $python = Get-Command python3.exe -ErrorAction SilentlyContinue }
if ($null -eq $python) { throw 'Python 3 is required to build the deterministic ZIP.' }
& $python.Source (Join-Path $PSScriptRoot 'package.py')
exit $LASTEXITCODE
