# Unit tests for the keyed node-to-node comparison. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvKeyedDeviation.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestNode {
        param ([String] $Name, [Hashtable] $Values)
        [PSCustomObject]@{
            Name = $Name
            Items = @($Values.Keys | Sort-Object | ForEach-Object { [PSCustomObject]@{ Key = $_; Value = $Values[$_] } })
        }
    }
}

Describe 'Resolve-HvKeyedDeviation' {

    It 'returns nothing when all nodes match' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ Build = '26100.1'; Model = 'Server' }
            New-TestNode -Name 'hv02' -Values @{ Build = '26100.1'; Model = 'Server' }
        )
        Resolve-HvKeyedDeviation -InputObject $Nodes | Should -BeNullOrEmpty
    }

    It 'returns nothing for a single node' {
        Resolve-HvKeyedDeviation -InputObject @(New-TestNode -Name 'hv01' -Values @{ Build = '1' }) | Should -BeNullOrEmpty
    }

    It 'reports the node that differs from the majority' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ Build = '26100.2' }
            New-TestNode -Name 'hv02' -Values @{ Build = '26100.1' }
            New-TestNode -Name 'hv03' -Values @{ Build = '26100.2' }
        )
        $Result = @(Resolve-HvKeyedDeviation -InputObject $Nodes)
        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'hv02'
        $Result[0].Value | Should -Be '26100.1'
        $Result[0].Reference | Should -Be '26100.2'
        $Result[0].HasReference | Should -BeTrue
    }

    It 'reports every node of a tie without reference' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ Build = '26100.2' }
            New-TestNode -Name 'hv02' -Values @{ Build = '26100.1' }
        )
        $Result = @(Resolve-HvKeyedDeviation -InputObject $Nodes)
        $Result.Name | Should -Be @('hv01', 'hv02')
        $Result[0].HasReference | Should -BeFalse
    }

    It 'reports a missing hotfix in a two-node cluster with PreferPresent' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ KB0000001 = 'Installed' }
            New-TestNode -Name 'hv02' -Values @{ KB0000001 = 'Installed'; KB0000002 = 'Installed' }
        )
        $Result = @(Resolve-HvKeyedDeviation -InputObject $Nodes -PreferPresent)
        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'hv01'
        $Result[0].Key | Should -Be 'KB0000002'
        $Result[0].Missing | Should -BeTrue
        $Result[0].Reference | Should -Be 'Installed'
    }

    It 'reports both nodes of a two-node tie on a missing key without PreferPresent' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{}
            New-TestNode -Name 'hv02' -Values @{ KB0000002 = 'Installed' }
        )
        @(Resolve-HvKeyedDeviation -InputObject $Nodes).Count | Should -Be 2
    }

    It 'treats a key that most nodes do not have as extra on the other node' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ 'Switch|Test' = 'External' }
            New-TestNode -Name 'hv02' -Values @{}
            New-TestNode -Name 'hv03' -Values @{}
        )
        $Result = @(Resolve-HvKeyedDeviation -InputObject $Nodes)
        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'hv01'
        $Result[0].ReferenceIsMissing | Should -BeTrue
    }

    It 'compares the values of present keys with PreferPresent' {
        $Nodes = @(
            New-TestNode -Name 'hv01' -Values @{ 'Driver|NIC' = '1.0' }
            New-TestNode -Name 'hv02' -Values @{ 'Driver|NIC' = '2.0' }
            New-TestNode -Name 'hv03' -Values @{ 'Driver|NIC' = '2.0' }
        )
        $Result = @(Resolve-HvKeyedDeviation -InputObject $Nodes -PreferPresent)
        $Result.Name | Should -Be @('hv01')
        $Result[0].Reference | Should -Be '2.0'
    }

    It 'keeps the order in which keys first appear' {
        $Nodes = @(
            [PSCustomObject]@{ Name = 'hv01'; Items = @(
                    [PSCustomObject]@{ Key = 'B'; Value = '1' }
                    [PSCustomObject]@{ Key = 'A'; Value = '1' }
                ) }
            [PSCustomObject]@{ Name = 'hv02'; Items = @(
                    [PSCustomObject]@{ Key = 'B'; Value = '2' }
                    [PSCustomObject]@{ Key = 'A'; Value = '2' }
                ) }
        )
        (@(Resolve-HvKeyedDeviation -InputObject $Nodes).Key | Select-Object -Unique) | Should -Be @('B', 'A')
    }
}
