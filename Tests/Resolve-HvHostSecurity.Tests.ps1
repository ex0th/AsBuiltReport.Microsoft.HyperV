# Unit tests for the host scheduler and platform security evaluation. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvHostSecurity.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestHostSetting {
        param (
            [Object] $SchedulerType = '3',
            [Object] $VbsStatus = '2',
            [Object[]] $SecurityServicesRunning = @('1', '2'),
            [Object] $SecureBoot = '1'
        )
        [PSCustomObject]@{
            SchedulerType = $SchedulerType
            VbsStatus = $VbsStatus
            SecurityServicesRunning = $SecurityServicesRunning
            SecureBoot = $SecureBoot
        }
    }
}

Describe 'Resolve-HvHostSecurity' {

    It 'maps the scheduler type <Type> to <Expected>' -TestCases @(
        @{ Type = '1'; Expected = 'ClassicNoSmt' }
        @{ Type = '2'; Expected = 'Classic' }
        @{ Type = 3; Expected = 'Core' }
        @{ Type = '4'; Expected = 'Root' }
        @{ Type = $null; Expected = 'Unknown' }
    ) {
        param ($Type, $Expected)
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SchedulerType $Type)).SchedulerKey | Should -Be $Expected
    }

    It 'flags only the classic scheduler with SMT' {
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SchedulerType '2')).Findings | Should -Contain 'ClassicScheduler'
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SchedulerType '1')).Findings | Should -Not -Contain 'ClassicScheduler'
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SchedulerType $null)).Findings | Should -Not -Contain 'ClassicScheduler'
    }

    It 'maps the VBS status <Status> to <Expected>' -TestCases @(
        @{ Status = '0'; Expected = 'Off' }
        @{ Status = '1'; Expected = 'Configured' }
        @{ Status = '2'; Expected = 'Running' }
        @{ Status = $null; Expected = 'Unknown' }
    ) {
        param ($Status, $Expected)
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -VbsStatus $Status)).VbsKey | Should -Be $Expected
    }

    It 'maps the running security services and ignores 0' {
        $Result = Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SecurityServicesRunning @('0', '1', '2', '9'))
        $Result.ServiceKeys | Should -Be @('CredentialGuard', 'Hvci', 'Service9')
    }

    It 'returns no services when none are running' {
        (Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SecurityServicesRunning @())).ServiceKeys | Should -BeNullOrEmpty
    }

    It 'maps Secure Boot <Value> to <Expected>' -TestCases @(
        @{ Value = '1'; Expected = 'On'; Finding = $false }
        @{ Value = '0'; Expected = 'Off'; Finding = $true }
        @{ Value = $null; Expected = 'Unknown'; Finding = $false }
    ) {
        param ($Value, $Expected, $Finding)
        $Result = Resolve-HvHostSecurity -HostSetting (New-TestHostSetting -SecureBoot $Value)
        $Result.SecureBootKey | Should -Be $Expected
        ($Result.Findings -contains 'SecureBootOff') | Should -Be $Finding
    }
}
