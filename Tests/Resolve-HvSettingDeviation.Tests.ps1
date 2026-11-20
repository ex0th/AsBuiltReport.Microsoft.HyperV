# Unit tests for the node-to-node comparison. All data is synthetic; no data from real environments.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvSettingDeviation.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestHostSetting {
        param (
            [String] $Name,
            [Int] $MaxMigrations = 2,
            [String] $Authentication = 'Kerberos',
            [String[]] $MigrationNetworks = @('192.0.2.0/24')
        )
        [PSCustomObject]@{
            Name = $Name
            MaxMigrations = $MaxMigrations
            Authentication = $Authentication
            MigrationNetworks = $MigrationNetworks
        }
    }
}

Describe 'Resolve-HvSettingDeviation' {

    It 'returns nothing when all hosts use the same settings' {
        $Hosts = @(
            New-TestHostSetting -Name 'hv01'
            New-TestHostSetting -Name 'hv02'
            New-TestHostSetting -Name 'hv03'
        )
        Resolve-HvSettingDeviation -InputObject $Hosts -Property 'MaxMigrations', 'Authentication', 'MigrationNetworks' |
            Should -BeNullOrEmpty
    }

    It 'returns nothing for a single host' {
        Resolve-HvSettingDeviation -InputObject @(New-TestHostSetting -Name 'hv01') -Property 'MaxMigrations' |
            Should -BeNullOrEmpty
    }

    It 'reports the host that differs from the majority' {
        $Hosts = @(
            New-TestHostSetting -Name 'hv01'
            New-TestHostSetting -Name 'hv02' -Authentication 'CredSSP'
            New-TestHostSetting -Name 'hv03'
        )
        $Result = @(Resolve-HvSettingDeviation -InputObject $Hosts -Property 'MaxMigrations', 'Authentication')
        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'hv02'
        $Result[0].Property | Should -Be 'Authentication'
        $Result[0].Value | Should -Be 'CredSSP'
        $Result[0].Reference | Should -Be 'Kerberos'
    }

    It 'reports every host when no value is the most common' {
        $Hosts = @(
            New-TestHostSetting -Name 'hv01' -MaxMigrations 1
            New-TestHostSetting -Name 'hv02' -MaxMigrations 2
        )
        $Result = @(Resolve-HvSettingDeviation -InputObject $Hosts -Property 'MaxMigrations')
        $Result.Name | Should -Be @('hv01', 'hv02')
        $Result[0].Reference | Should -BeNullOrEmpty
    }

    It 'compares collections including their order' {
        $Hosts = @(
            New-TestHostSetting -Name 'hv01' -MigrationNetworks '192.0.2.0/24', '198.51.100.0/24'
            New-TestHostSetting -Name 'hv02' -MigrationNetworks '192.0.2.0/24', '198.51.100.0/24'
            New-TestHostSetting -Name 'hv03' -MigrationNetworks '198.51.100.0/24', '192.0.2.0/24'
        )
        $Result = @(Resolve-HvSettingDeviation -InputObject $Hosts -Property 'MigrationNetworks')
        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'hv03'
        $Result[0].Value | Should -Be '198.51.100.0/24;192.0.2.0/24'
    }

    It 'treats a missing value as a value of its own' {
        $Hosts = @(
            New-TestHostSetting -Name 'hv01'
            New-TestHostSetting -Name 'hv02'
            [PSCustomObject]@{ Name = 'hv03'; MaxMigrations = $null }
        )
        $Result = @(Resolve-HvSettingDeviation -InputObject $Hosts -Property 'MaxMigrations')
        $Result.Name | Should -Be 'hv03'
        $Result[0].Value | Should -Be ''
    }

}
