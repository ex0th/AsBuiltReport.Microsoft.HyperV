<#
.SYNOPSIS
    Invoke Pester tests for AsBuiltReport.Microsoft.HyperV module

.DESCRIPTION
    This script runs Pester tests with optional code coverage analysis.
    It's designed to work with CI/CD pipelines and local development.

.PARAMETER CodeCoverage
    Enable code coverage analysis

.PARAMETER OutputFormat
    Specify the output format for test results (Console, NUnitXml, JUnitXml)

.EXAMPLE
    .\Invoke-Tests.ps1

.EXAMPLE
    .\Invoke-Tests.ps1 -CodeCoverage -OutputFormat NUnitXml
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$CodeCoverage,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'NUnitXml', 'JUnitXml')]
    [string]$OutputFormat = 'Console'
)

# Ensure we're in the Tests directory
$TestsPath = $PSScriptRoot
if (-not (Test-Path $TestsPath)) {
    Write-Error "Tests directory not found at: $TestsPath"
    exit 1
}

# Get the module root directory
$ModuleRoot = Split-Path -Path $TestsPath -Parent
$ModuleName = 'AsBuiltReport.Microsoft.HyperV'
$ModulePath = Join-Path -Path $ModuleRoot -ChildPath $ModuleName

Write-Host "Module Root: $ModuleRoot" -ForegroundColor Cyan
Write-Host "Module Path: $ModulePath" -ForegroundColor Cyan
Write-Host "Tests Path: $TestsPath" -ForegroundColor Cyan

# Check PowerShell version
$PSVersion = $PSVersionTable.PSVersion
Write-Host "PowerShell Version: $PSVersion" -ForegroundColor Cyan

# The module supports Windows PowerShell 5.1 and PowerShell 7; run the tests in both before a release.
if ($PSVersion.Major -lt 5 -or ($PSVersion.Major -eq 5 -and $PSVersion.Minor -lt 1)) {
    Write-Warning "Windows PowerShell 5.1 or PowerShell 7 is required"
}

# Install required modules
Write-Host "`nInstalling required modules..." -ForegroundColor Yellow

# The tests are written for Pester 5; Pester 6 changes defaults (e.g. empty -TestCases fail discovery).
$RequiredModules = @(
    @{ Name = 'Pester'; MinimumVersion = '5.0.0'; MaximumVersion = '5.99.99' }
    @{ Name = 'PScribo'; MinimumVersion = '0.11.1'; MaximumVersion = $null }
    @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.0.0'; MaximumVersion = $null }
)

foreach ($Module in $RequiredModules) {
    $InstalledModule = Get-Module -Name $Module.Name -ListAvailable |
        Where-Object { $_.Version -ge [Version]$Module.MinimumVersion -and (-not $Module.MaximumVersion -or $_.Version -le [Version]$Module.MaximumVersion) } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if (-not $InstalledModule) {
        Write-Host "Installing $($Module.Name) (minimum version $($Module.MinimumVersion))..." -ForegroundColor Yellow
        $InstallParams = @{
            Name = $Module.Name
            MinimumVersion = $Module.MinimumVersion
            Repository = 'PSGallery'
            Force = $true
            AllowClobber = $true
            Scope = 'CurrentUser'
        }
        if ($Module.MaximumVersion) {
            $InstallParams['MaximumVersion'] = $Module.MaximumVersion
        }
        if ($Module.Name -eq 'Pester') {
            # Windows ships Pester 3.4 signed by a different publisher.
            $InstallParams['SkipPublisherCheck'] = $true
        }
        Install-Module @InstallParams
    } else {
        Write-Host "$($Module.Name) version $($InstalledModule.Version) is already installed" -ForegroundColor Green
    }
}

# Import Pester 5
Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force

# Configure Pester
$PesterConfiguration = New-PesterConfiguration

# Run settings
$PesterConfiguration.Run.Path = $TestsPath
$PesterConfiguration.Run.Exit = $false
$PesterConfiguration.Run.PassThru = $true

# Output settings
$PesterConfiguration.Output.Verbosity = 'Detailed'

# TestResult settings
if ($OutputFormat -ne 'Console') {
    $PesterConfiguration.TestResult.Enabled = $true
    $ResultFile = Join-Path -Path $TestsPath -ChildPath 'testResults.xml'
    $PesterConfiguration.TestResult.OutputPath = $ResultFile

    if ($OutputFormat -eq 'NUnitXml') {
        $PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
    } elseif ($OutputFormat -eq 'JUnitXml') {
        $PesterConfiguration.TestResult.OutputFormat = 'JUnitXml'
    }

    Write-Host "Test results will be saved to: $ResultFile" -ForegroundColor Cyan
}

# Code Coverage settings
if ($CodeCoverage) {
    Write-Host "`nEnabling code coverage analysis..." -ForegroundColor Yellow

    $PesterConfiguration.CodeCoverage.Enabled = $true
    $PesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
    $CoverageFile = Join-Path -Path $TestsPath -ChildPath 'coverage.xml'
    $PesterConfiguration.CodeCoverage.OutputPath = $CoverageFile

    # Include all PowerShell files in the module
    $CoverageFiles = @(
        "$ModulePath\*.psm1"
        "$ModulePath\Src\Public\*.ps1"
        "$ModulePath\Src\Private\*.ps1"
    )

    $PesterConfiguration.CodeCoverage.Path = $CoverageFiles

    Write-Host "Code coverage will be saved to: $CoverageFile" -ForegroundColor Cyan
    Write-Host "Coverage files included:" -ForegroundColor Cyan
    foreach ($File in $CoverageFiles) {
        Write-Host "  - $File" -ForegroundColor Gray
    }
}

# Run Pester tests
Write-Host "`nRunning Pester tests..." -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Cyan

$TestResults = Invoke-Pester -Configuration $PesterConfiguration

# Display results
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "Test Results Summary" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($TestResults.TotalCount)" -ForegroundColor White
Write-Host "Passed: $($TestResults.PassedCount)" -ForegroundColor Green
Write-Host "Failed: $($TestResults.FailedCount)" -ForegroundColor $(if ($TestResults.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped: $($TestResults.SkippedCount)" -ForegroundColor Yellow
Write-Host "Failed Containers: $($TestResults.FailedContainersCount)" -ForegroundColor $(if ($TestResults.FailedContainersCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Duration: $($TestResults.Duration)" -ForegroundColor White

# Display failed tests
if ($TestResults.FailedCount -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    foreach ($FailedTest in $TestResults.Failed) {
        Write-Host "  - $($FailedTest.Name)" -ForegroundColor Red
        Write-Host "    $($FailedTest.ErrorRecord)" -ForegroundColor Gray
    }
}

# A test file that fails during discovery or setup counts as a failed container, not as a failed test.
if ($TestResults.FailedContainersCount -gt 0) {
    Write-Host "`nFailed Containers:" -ForegroundColor Red
    foreach ($FailedContainer in $TestResults.FailedContainers) {
        Write-Host "  - $($FailedContainer.Item)" -ForegroundColor Red
        foreach ($ContainerError in @($FailedContainer.ErrorRecord)) {
            Write-Host "    $ContainerError" -ForegroundColor Gray
        }
    }
}

# Display code coverage summary
if ($CodeCoverage -and $TestResults.CodeCoverage) {
    Write-Host "`n======================================" -ForegroundColor Cyan
    Write-Host "Code Coverage Summary" -ForegroundColor Yellow
    Write-Host "======================================" -ForegroundColor Cyan

    # Pester 5 property names (Pester 4 used NumberOfCommandsAnalyzed etc.).
    $Coverage = $TestResults.CodeCoverage
    $Analyzed = [int]$Coverage.CommandsAnalyzedCount
    $Executed = [int]$Coverage.CommandsExecutedCount
    $CoveragePercent = if ($Analyzed -gt 0) { [math]::Round($Executed / $Analyzed * 100, 2) } else { 0 }

    Write-Host "Commands Analyzed: $Analyzed" -ForegroundColor White
    Write-Host "Commands Executed: $Executed" -ForegroundColor White
    Write-Host "Commands Missed: $($Coverage.CommandsMissedCount)" -ForegroundColor White
    Write-Host "Coverage: $CoveragePercent%" -ForegroundColor $(if ($CoveragePercent -ge 80) { 'Green' } elseif ($CoveragePercent -ge 60) { 'Yellow' } else { 'Red' })
}

Write-Host "`n======================================" -ForegroundColor Cyan

# Exit with appropriate code; Result also covers failed containers and failed blocks.
if ($TestResults.Result -ne 'Passed' -or $TestResults.FailedCount -gt 0 -or $TestResults.FailedContainersCount -gt 0) {
    Write-Host "Tests FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
