# Unit tests for the virtual switch, RDMA and DCB evaluation. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvNetworkFinding.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    # A host with a SET switch over two RoCEv2 adapters, two mapped RDMA vNICs and PFC on priority 3.
    function New-TestNetworkData {
        [PSCustomObject]@{
            Switches = @(
                [PSCustomObject]@{
                    Name = 'ConvergedSwitch'
                    EmbeddedTeaming = 'True'
                    Members = @('pNIC1', 'pNIC2')
                    LoadBalancingAlgorithm = 'HyperVPort'
                }
            )
            HostVnics = @(
                [PSCustomObject]@{ Name = 'Management'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = ''; MappedAdapter = '' }
                [PSCustomObject]@{ Name = 'SMB1'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = 'True'; MappedAdapter = 'pNIC1' }
                [PSCustomObject]@{ Name = 'SMB2'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = 'True'; MappedAdapter = 'pNIC2' }
            )
            Adapters = @(
                [PSCustomObject]@{ Name = 'pNIC1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '4'; DcbEnabled = 'True' }
                [PSCustomObject]@{ Name = 'pNIC2'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '4'; DcbEnabled = 'True' }
            )
            Qos = [PSCustomObject]@{ Available = $true; PfcPriorities = @('3'); DcbxWilling = 'False' }
        }
    }
}

Describe 'Resolve-HvNetworkFinding' {

    It 'returns nothing for a host that follows the recommendations' {
        Resolve-HvNetworkFinding -NetworkData (New-TestNetworkData) -IsS2D | Should -BeNullOrEmpty
    }

    It 'returns nothing for a host without switches and RDMA' {
        $Data = [PSCustomObject]@{
            Switches = @()
            HostVnics = @()
            Adapters = @([PSCustomObject]@{ Name = 'Ethernet'; Status = 'Up'; RdmaCapable = 'False'; RdmaEnabled = ''; RdmaType = ''; DcbEnabled = '' })
            Qos = [PSCustomObject]@{ Available = $false; PfcPriorities = @(); DcbxWilling = '' }
        }
        Resolve-HvNetworkFinding -NetworkData $Data -IsS2D | Should -BeNullOrEmpty
    }

    It 'flags a SET switch with dynamic load balancing' {
        $Data = New-TestNetworkData
        $Data.Switches[0].LoadBalancingAlgorithm = 'Dynamic'
        $Result = @(Resolve-HvNetworkFinding -NetworkData $Data)
        $Result.Check | Should -Be @('SetLoadBalancing')
        $Result[0].Object | Should -Be 'ConvergedSwitch'
    }

    It 'does not rate the load balancing of a switch without SET' {
        $Data = New-TestNetworkData
        $Data.Switches[0].EmbeddedTeaming = 'False'
        $Data.Switches[0].LoadBalancingAlgorithm = ''
        @(Resolve-HvNetworkFinding -NetworkData $Data).Check | Should -Not -Contain 'SetLoadBalancing'
    }

    It 'flags disabled RDMA on an S2D host only' {
        $Data = New-TestNetworkData
        $Data.Adapters[1].RdmaEnabled = 'False'
        $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D)
        ($Result | Where-Object { $_.Check -eq 'RdmaDisabled' }).Object | Should -Be 'pNIC2'
        @(Resolve-HvNetworkFinding -NetworkData $Data).Check | Should -Not -Contain 'RdmaDisabled'
    }

    It 'ignores disabled RDMA on an adapter that is down' {
        $Data = New-TestNetworkData
        $Data.Adapters[1].RdmaEnabled = 'False'
        $Data.Adapters[1].Status = 'Disconnected'
        @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D).Check | Should -Not -Contain 'RdmaDisabled'
    }

    It 'flags RoCE without PFC' {
        $Data = New-TestNetworkData
        $Data.Qos.PfcPriorities = @()
        $Result = @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'RocePfc' })
        $Result.Object | Should -Be @('pNIC1', 'pNIC2')
    }

    It 'flags RoCE with DCB disabled on the adapter' {
        $Data = New-TestNetworkData
        $Data.Adapters[0].DcbEnabled = 'False'
        ($Resolve = @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'RocePfc' })).Object | Should -Be @('pNIC1')
    }

    It 'does not require PFC for iWARP' {
        $Data = New-TestNetworkData
        $Data.Qos.PfcPriorities = @()
        foreach ($Adapter in $Data.Adapters) {
            $Adapter.RdmaType = '1'
        }
        Resolve-HvNetworkFinding -NetworkData $Data -IsS2D | Should -BeNullOrEmpty
    }

    It 'flags DCBX willing mode only when PFC is configured' {
        $Data = New-TestNetworkData
        $Data.Qos.DcbxWilling = 'True'
        @(Resolve-HvNetworkFinding -NetworkData $Data).Check | Should -Be @('DcbxWilling')
        foreach ($Adapter in $Data.Adapters) {
            $Adapter.RdmaType = '1'
        }
        $Data.Qos.PfcPriorities = @()
        Resolve-HvNetworkFinding -NetworkData $Data | Should -BeNullOrEmpty
    }

    It 'flags an RDMA vNIC without team mapping' {
        $Data = New-TestNetworkData
        $Data.HostVnics[2].MappedAdapter = ''
        $Result = @(Resolve-HvNetworkFinding -NetworkData $Data)
        $Result.Check | Should -Be @('VnicTeamMapping')
        $Result[0].Object | Should -Be 'SMB2'
    }

    It 'does not require a team mapping on a SET switch with one member' {
        $Data = New-TestNetworkData
        $Data.Switches[0].Members = @('pNIC1')
        $Data.HostVnics[2].MappedAdapter = ''
        @(Resolve-HvNetworkFinding -NetworkData $Data).Check | Should -Not -Contain 'VnicTeamMapping'
    }
}
