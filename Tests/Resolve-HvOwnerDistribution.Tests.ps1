# Unit tests for the role and Cluster Shared Volume distribution check. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvOwnerDistribution.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-NodeState {
        param ([String] $Node01 = 'Up', [String] $Node02 = 'Up', [String] $Node03)
        @(
            [PSCustomObject]@{ Name = 'node01'; State = $Node01 }
            [PSCustomObject]@{ Name = 'node02'; State = $Node02 }
            if ($Node03) { [PSCustomObject]@{ Name = 'node03'; State = $Node03 } }
        )
    }
}

Describe 'Resolve-HvOwnerDistribution' {

    It 'reports the idle node when all roles run on one node' {
        Resolve-HvOwnerDistribution -OwnerNode @('node01', 'node01', 'node01') -NodeState (New-NodeState) | Should -Be 'node02'
    }

    It 'reports nothing when the roles are distributed' {
        Resolve-HvOwnerDistribution -OwnerNode @('node01', 'node02') -NodeState (New-NodeState) | Should -BeNullOrEmpty
    }

    It 'does not report a paused node' {
        Resolve-HvOwnerDistribution -OwnerNode @('node01', 'node01') -NodeState (New-NodeState -Node02 'Paused') | Should -BeNullOrEmpty
    }

    It 'does not report a node that is down' {
        Resolve-HvOwnerDistribution -OwnerNode @('node01') -NodeState (New-NodeState -Node02 'Down') | Should -BeNullOrEmpty
    }

    It 'reports only the idle node that is up in a three-node cluster with a paused node' {
        Resolve-HvOwnerDistribution -OwnerNode @('node01', 'node01') -NodeState (New-NodeState -Node03 'Paused') | Should -Be 'node02'
    }

    It 'reports nothing when no node owns roles' {
        Resolve-HvOwnerDistribution -OwnerNode @() -NodeState (New-NodeState) | Should -BeNullOrEmpty
    }

    It 'reports nothing when the roles run on a node that is not up' {
        Resolve-HvOwnerDistribution -OwnerNode @('node03') -NodeState (New-NodeState -Node03 'Paused') | Should -BeNullOrEmpty
    }

    It 'compares the node names case-insensitively' {
        Resolve-HvOwnerDistribution -OwnerNode @('NODE01') -NodeState (New-NodeState) | Should -Be 'node02'
    }
}
