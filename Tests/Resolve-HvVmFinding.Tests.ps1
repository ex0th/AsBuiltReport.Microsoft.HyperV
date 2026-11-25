# Unit tests for the virtual machine evaluation. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvVmFinding.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestVM {
        param (
            [Int] $CheckpointCount = 0,
            [String] $IsClustered = 'True',
            [String] $Version = '12.0',
            [String[]] $SwitchName = @('ConvergedSwitch')
        )
        [PSCustomObject]@{
            CheckpointCount = $CheckpointCount
            IsClustered = $IsClustered
            Version = $Version
            Adapters = @($SwitchName | ForEach-Object { [PSCustomObject]@{ SwitchName = $_ } })
        }
    }
}

Describe 'Resolve-HvVmFinding' {

    It 'returns nothing for a clustered, current and connected virtual machine' {
        Resolve-HvVmFinding -VM (New-TestVM) -IsCluster -HostDefaultVersion '12.0' | Should -BeNullOrEmpty
    }

    It 'flags checkpoints' {
        Resolve-HvVmFinding -VM (New-TestVM -CheckpointCount 2) -HostDefaultVersion '12.0' | Should -Be @('Checkpoints')
    }

    It 'flags a virtual machine that is not clustered only on a cluster' {
        Resolve-HvVmFinding -VM (New-TestVM -IsClustered 'False') -IsCluster -HostDefaultVersion '12.0' | Should -Be @('NotClustered')
        Resolve-HvVmFinding -VM (New-TestVM -IsClustered 'False') -HostDefaultVersion '12.0' | Should -BeNullOrEmpty
    }

    It 'compares configuration versions as versions, not as text' {
        Resolve-HvVmFinding -VM (New-TestVM -Version '9.0') -HostDefaultVersion '12.0' | Should -Be @('ConfigurationVersion')
        Resolve-HvVmFinding -VM (New-TestVM -Version '10.0') -HostDefaultVersion '9.0' | Should -BeNullOrEmpty
    }

    It 'ignores a missing default version' {
        Resolve-HvVmFinding -VM (New-TestVM -Version '9.0') -HostDefaultVersion '' | Should -BeNullOrEmpty
    }

    It 'flags a network adapter without switch' {
        Resolve-HvVmFinding -VM (New-TestVM -SwitchName 'ConvergedSwitch', '') -HostDefaultVersion '12.0' | Should -Be @('NetworkDisconnected')
    }

    It 'accepts a virtual machine without network adapters' {
        Resolve-HvVmFinding -VM (New-TestVM -SwitchName @()) -HostDefaultVersion '12.0' | Should -BeNullOrEmpty
    }
}
