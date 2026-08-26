param([Parameter(Mandatory=$true)][ValidateSet('Register','Clear')][string]$Mode)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Experience.Common.ps1')

if ($Mode -eq 'Register') { Register-OnarchyPostRestartResume }
else { Clear-OnarchyPostRestartResume }
