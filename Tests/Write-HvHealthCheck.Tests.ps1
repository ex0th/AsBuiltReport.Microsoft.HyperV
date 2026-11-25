# Unit tests for the recording of health check findings. PScribo keywords are mocked.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Write-HvHealthCheck.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')
    function Paragraph { param ($Text) "P:$Text" }
    function BlankLine { 'B' }
}

Describe 'Write-HvHealthCheck' {

    BeforeEach {
        $script:HvHealthFindings = New-Object -TypeName System.Collections.Generic.List[Object]
    }

    It 'records the finding and writes finding and recommendation as one paragraph' {
        $Output = @(Write-HvHealthCheck -Area 'Cluster Quorum' -Severity Critical -Finding 'No witness.' -Recommendation 'Configure a witness.')
        $Output | Should -Be @('P:No witness. Configure a witness.', 'B')
        $script:HvHealthFindings.Count | Should -Be 1
        $script:HvHealthFindings[0].Area | Should -Be 'Cluster Quorum'
        $script:HvHealthFindings[0].Severity | Should -Be 'Critical'
        $script:HvHealthFindings[0].Finding | Should -Be 'No witness.'
        $script:HvHealthFindings[0].Recommendation | Should -Be 'Configure a witness.'
    }

    It 'uses Warning as default severity' {
        Write-HvHealthCheck -Area 'Hosts' -Finding 'Secure Boot is off.' | Out-Null
        $script:HvHealthFindings[0].Severity | Should -Be 'Warning'
    }

    It 'writes the paragraph also without a findings list' {
        Remove-Variable -Name 'HvHealthFindings' -Scope Script
        @(Write-HvHealthCheck -Area 'Hosts' -Finding 'Finding.' -Recommendation 'Fix.')[0] | Should -Be 'P:Finding. Fix.'
    }

    It 'rejects unknown severities' {
        { Write-HvHealthCheck -Area 'Hosts' -Severity 'Info' -Finding 'x' } | Should -Throw
    }
}

Describe 'Get-HvMaxSeverity' {

    It 'returns <Expected> for <Severity>' -TestCases @(
        @{ Severity = @('Warning', 'Critical'); Expected = 'Critical' }
        @{ Severity = @('Warning', 'Ok'); Expected = 'Warning' }
        @{ Severity = @(); Expected = 'Warning' }
    ) {
        param ($Severity, $Expected)
        Get-HvMaxSeverity $Severity | Should -Be $Expected
    }
}
