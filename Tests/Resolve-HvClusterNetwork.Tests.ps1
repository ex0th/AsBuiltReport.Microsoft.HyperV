# Unit tests for the cluster network evaluation. All data is synthetic; no data from real environments.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvClusterNetwork.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestNetwork {
        param (
            [String] $Name,
            [String] $Id,
            [Object] $Role = 3,
            [String] $State = 'Up'
        )
        [PSCustomObject]@{
            Name = $Name
            Id = $Id
            Role = $Role
            State = $State
        }
    }

    $script:IdMgmt = '11111111-1111-1111-1111-111111111111'
    $script:IdLm = '22222222-2222-2222-2222-222222222222'
    $script:IdStorage = '33333333-3333-3333-3333-333333333333'
}

Describe 'Resolve-HvClusterNetwork' {

    Context 'Roles and states' {

        It 'maps the role <Role> to <Expected>' -TestCases @(
            @{ Role = 0; Expected = 'None' }
            @{ Role = 1; Expected = 'ClusterOnly' }
            @{ Role = 2; Expected = 'ClientOnly' }
            @{ Role = 3; Expected = 'ClusterAndClient' }
            @{ Role = 'ClusterAndClient'; Expected = 'ClusterAndClient' }
            @{ Role = 7; Expected = '7' }
        ) {
            param ($Role, $Expected)
            $Result = Resolve-HvClusterNetwork -Network @(New-TestNetwork -Name 'net' -Id $script:IdMgmt -Role $Role)
            $Result.Networks[0].RoleKey | Should -Be $Expected
        }

        It 'rates the state <State> as <Expected>' -TestCases @(
            @{ State = 'Up'; Expected = 'Ok' }
            @{ State = 'Down'; Expected = 'Critical' }
            @{ State = 'Partitioned'; Expected = 'Warning' }
            @{ State = 'Unavailable'; Expected = 'Warning' }
        ) {
            param ($State, $Expected)
            $Result = Resolve-HvClusterNetwork -Network @(New-TestNetwork -Name 'net' -Id $script:IdMgmt -State $State)
            $Result.Networks[0].StateSeverity | Should -Be $Expected
        }

    }

    Context 'Live migration' {

        It 'allows every network when nothing is excluded' {
            $Result = Resolve-HvClusterNetwork -Network @(
                New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt
                New-TestNetwork -Name 'lm' -Id $script:IdLm -Role 1
            )
            @($Result.Networks | Where-Object { $_.AllowedForMigration }).Count | Should -Be 2
            $Result.Findings | Should -Not -Contain 'NoMigrationNetwork'
        }

        It 'flags a cluster whose only network is excluded' {
            $Result = Resolve-HvClusterNetwork -Network @(New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt) `
                -MigrationExcludeNetworks $script:IdMgmt.ToUpperInvariant()
            $Result.Networks[0].AllowedForMigration | Should -BeFalse
            $Result.MigrationNetworks | Should -BeNullOrEmpty
            $Result.Findings | Should -Contain 'NoMigrationNetwork'
        }

        It 'applies the exclude list and the preference order' {
            $Result = Resolve-HvClusterNetwork -Network @(
                New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt
                New-TestNetwork -Name 'lm' -Id $script:IdLm -Role 1
                New-TestNetwork -Name 'storage' -Id $script:IdStorage -Role 1
            ) -MigrationExcludeNetworks "$($script:IdMgmt);" -MigrationNetworkOrder "$($script:IdStorage);$($script:IdLm);$($script:IdMgmt)"
            $Result.MigrationNetworks | Should -Be @('storage', 'lm')
            ($Result.Networks | Where-Object { $_.Name -eq 'storage' }).MigrationOrder | Should -Be 1
            ($Result.Networks | Where-Object { $_.Name -eq 'lm' }).MigrationOrder | Should -Be 2
            ($Result.Networks | Where-Object { $_.Name -eq 'mgmt' }).MigrationOrder | Should -BeNullOrEmpty
        }

        It 'lists allowed networks without a preference after the ordered ones' {
            $Result = Resolve-HvClusterNetwork -Network @(
                New-TestNetwork -Name 'a-unordered' -Id $script:IdMgmt
                New-TestNetwork -Name 'lm' -Id $script:IdLm
            ) -MigrationNetworkOrder $script:IdLm
            $Result.MigrationNetworks | Should -Be @('lm', 'a-unordered')
        }

        It 'does not flag a cluster without networks' {
            $Result = Resolve-HvClusterNetwork -Network @()
            $Result.Findings | Should -Not -Contain 'NoMigrationNetwork'
        }

    }

    Context 'Redundancy' {

        It 'flags a single network for cluster communication' {
            $Result = Resolve-HvClusterNetwork -Network @(New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt)
            $Result.ClusterNetworkCount | Should -Be 1
            $Result.Findings | Should -Contain 'SingleClusterNetwork'
        }

        It 'ignores networks without cluster role or not up' {
            $Result = Resolve-HvClusterNetwork -Network @(
                New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt
                New-TestNetwork -Name 'iscsi' -Id $script:IdStorage -Role 0
                New-TestNetwork -Name 'lm' -Id $script:IdLm -Role 1 -State 'Down'
            )
            $Result.ClusterNetworkCount | Should -Be 1
            $Result.Findings | Should -Contain 'SingleClusterNetwork'
        }

        It 'accepts two networks for cluster communication' {
            $Result = Resolve-HvClusterNetwork -Network @(
                New-TestNetwork -Name 'mgmt' -Id $script:IdMgmt
                New-TestNetwork -Name 'lm' -Id $script:IdLm -Role 1
            )
            $Result.ClusterNetworkCount | Should -Be 2
            $Result.Findings | Should -BeNullOrEmpty
        }

    }

}
