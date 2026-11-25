# Unit tests for the readable live migration deviations. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Format-HvSettingDeviation.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    $script:Hosts = @(
        [PSCustomObject]@{ Name = 'node01'; Authentication = 'CredSSP'; MaxMigrations = '2'; MigrationNetworks = @('10.0.30.0/24', '10.0.31.0/24') }
        [PSCustomObject]@{ Name = 'node02'; Authentication = 'Kerberos'; MaxMigrations = '2'; MigrationNetworks = @('10.0.30.0/24') }
        [PSCustomObject]@{ Name = 'node03'; Authentication = 'Kerberos'; MaxMigrations = ''; MigrationNetworks = @('10.0.30.0/24') }
    )
}

Describe 'Format-HvSettingDeviation' {

    It 'names the value of every host' {
        Format-HvSettingDeviation -InputObject $script:Hosts[0, 1] -Property 'Authentication' |
            Should -Be 'CredSSP (node01), Kerberos (node02)'
    }

    It 'groups hosts with the same value' {
        Format-HvSettingDeviation -InputObject $script:Hosts -Property 'Authentication' |
            Should -Be 'CredSSP (node01), Kerberos (node02, node03)'
    }

    It 'shows empty values as --' {
        Format-HvSettingDeviation -InputObject $script:Hosts -Property 'MaxMigrations' | Should -Be '2 (node01, node02), -- (node03)'
    }

    It 'joins collections' {
        Format-HvSettingDeviation -InputObject $script:Hosts[0, 1] -Property 'MigrationNetworks' |
            Should -Be '10.0.30.0/24, 10.0.31.0/24 (node01), 10.0.30.0/24 (node02)'
    }

    It 'finds the CredSSP deviation together with Resolve-HvSettingDeviation' {
        $Deviations = @(Resolve-HvSettingDeviation -InputObject $script:Hosts[0, 1] -Property 'Authentication')
        $Deviations.Name | Should -Be @('node01', 'node02')
        Format-HvSettingDeviation -InputObject $script:Hosts[0, 1] -Property $Deviations[0].Property |
            Should -Be 'CredSSP (node01), Kerberos (node02)'
    }
}
