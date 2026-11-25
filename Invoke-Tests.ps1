<#
 .Synopsis
  Runs the Pester tests in ./tests.

 .Description
  Needs Pester 5 or later (Install-Module Pester -Scope CurrentUser -SkipPublisherCheck).
  Works in Windows PowerShell 5.1 and PowerShell 7+ on Windows, macOS and Linux.
  Exits with a non-zero code when a test fails.

 .Parameter Path
  Test files or folders to run. Defaults to ./tests.

 .Parameter ExcludeTag
  Skip tests with these tags. 'Integration' runs the real handle.exe, which scans every handle on
  the machine (about 30 seconds).

 .Example
  ./Invoke-Tests.ps1

 .Example
  ./Invoke-Tests.ps1 -ExcludeTag Integration

 .Example
  ./Invoke-Tests.ps1 -Path ./tests/Rename-GitBranch.Tests.ps1
#>
param(
    [string[]] $Path = @(Join-Path $PSScriptRoot 'tests'),
    [string[]] $ExcludeTag = @()
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    Import-Module Pester -MinimumVersion 5.0.0
}

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Filter.ExcludeTag = $ExcludeTag
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
