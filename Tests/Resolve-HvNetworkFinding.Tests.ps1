# Unit tests for the virtual switch, RDMA and DCB evaluation. All data is synthetic (TEST-NET addresses).
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvNetworkFinding.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    # Converged host: SET switch over two RoCEv2 adapters, two mapped RDMA vNICs on the storage network,
    # PFC on priority 3 and ETS classes for SMB (3) and the cluster heartbeat (7).
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
                [PSCustomObject]@{ Name = 'Management'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = ''; MappedAdapter = ''; IPAddresses = @('192.0.2.11/24') }
                [PSCustomObject]@{ Name = 'SMB1'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = 'True'; MappedAdapter = 'pNIC1'; IPAddresses = @('198.51.100.11/24') }
                [PSCustomObject]@{ Name = 'SMB2'; SwitchName = 'ConvergedSwitch'; RdmaEnabled = 'True'; MappedAdapter = 'pNIC2'; IPAddresses = @('203.0.113.11/24') }
            )
            Adapters = @(
                [PSCustomObject]@{ Name = 'pNIC1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '4'; DcbEnabled = 'True'; IPAddresses = @() }
                [PSCustomObject]@{ Name = 'pNIC2'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '4'; DcbEnabled = 'True'; IPAddresses = @() }
            )
            Qos = [PSCustomObject]@{
                Available = $true
                PfcPriorities = @('3')
                TrafficClasses = @(
                    [PSCustomObject]@{ Name = '[Default]'; Priority = @('0', '1', '2', '4', '5', '6'); Algorithm = 'ETS' }
                    [PSCustomObject]@{ Name = 'SMB'; Priority = @('3'); Algorithm = 'ETS' }
                    [PSCustomObject]@{ Name = 'Cluster'; Priority = @('7'); Algorithm = 'ETS' }
                )
                Policies = @(
                    [PSCustomObject]@{ Name = 'SMB'; Priority = '3'; Template = 'None'; NetDirectPort = '445' }
                    [PSCustomObject]@{ Name = 'Cluster'; Priority = '7'; Template = 'Cluster'; NetDirectPort = '' }
                )
                DcbxWilling = 'False'
            }
        }
    }

    # Cluster networks for storage traffic (role Cluster only).
    $script:StorageSubnets = @('198.51.100.0/24', '203.0.113.0/24')
}

Describe 'Test-HvIpInSubnet' {

    It 'returns <Expected> for <Address> in <Subnet>' -TestCases @(
        @{ Address = '192.0.2.10'; Subnet = '192.0.2.0/24'; Expected = $true }
        @{ Address = '192.0.2.10/24'; Subnet = '192.0.2.0/24'; Expected = $true }
        @{ Address = '192.0.3.10'; Subnet = '192.0.2.0/24'; Expected = $false }
        @{ Address = '192.0.2.130'; Subnet = '192.0.2.128/25'; Expected = $true }
        @{ Address = '192.0.2.10'; Subnet = '192.0.2.128/25'; Expected = $false }
        @{ Address = '10.1.2.3'; Subnet = '10.0.0.0/8'; Expected = $true }
        @{ Address = '2001:db8::1'; Subnet = '192.0.2.0/24'; Expected = $false }
        @{ Address = 'invalid'; Subnet = '192.0.2.0/24'; Expected = $false }
        @{ Address = '192.0.2.10'; Subnet = '192.0.2.0'; Expected = $false }
    ) {
        param ($Address, $Subnet, $Expected)
        Test-HvIpInSubnet -IPAddress $Address -Subnet $Subnet | Should -Be $Expected
    }
}

Describe 'Resolve-HvNetworkFinding' {

    Context 'Recommended configuration' {

        It 'returns nothing for a host that follows the recommendations' {
            Resolve-HvNetworkFinding -NetworkData (New-TestNetworkData) -IsS2D -StorageSubnet $script:StorageSubnets | Should -BeNullOrEmpty
        }

        It 'returns nothing for a host without switches and RDMA that is not an S2D host' {
            $Data = [PSCustomObject]@{
                Switches = @()
                HostVnics = @()
                Adapters = @([PSCustomObject]@{ Name = 'Ethernet'; Status = 'Up'; RdmaCapable = 'False'; RdmaEnabled = ''; RdmaType = ''; DcbEnabled = ''; IPAddresses = @('192.0.2.11/24') })
                Qos = [PSCustomObject]@{ Available = $false; PfcPriorities = @(); TrafficClasses = @(); Policies = @(); DcbxWilling = '' }
            }
            Resolve-HvNetworkFinding -NetworkData $Data | Should -BeNullOrEmpty
        }
    }

    Context 'Switch Embedded Teaming' {

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

    Context 'RDMA for storage traffic' {

        It 'ignores SET members of management and VM switches when dedicated RDMA adapters carry the storage traffic' {
            $Data = [PSCustomObject]@{
                Switches = @(
                    [PSCustomObject]@{ Name = 'vSwitch-Mgmt'; EmbeddedTeaming = 'True'; Members = @('pNIC1', 'pNIC2'); LoadBalancingAlgorithm = 'HyperVPort' }
                    [PSCustomObject]@{ Name = 'vSwitch-VM'; EmbeddedTeaming = 'True'; Members = @('pNIC3', 'pNIC4'); LoadBalancingAlgorithm = 'HyperVPort' }
                )
                HostVnics = @(
                    [PSCustomObject]@{ Name = 'Management'; SwitchName = 'vSwitch-Mgmt'; RdmaEnabled = 'False'; MappedAdapter = ''; IPAddresses = @('192.0.2.11/24') }
                )
                Adapters = @(
                    [PSCustomObject]@{ Name = 'pNIC1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                    [PSCustomObject]@{ Name = 'pNIC2'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                    [PSCustomObject]@{ Name = 'pNIC3'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                    [PSCustomObject]@{ Name = 'pNIC4'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                    [PSCustomObject]@{ Name = 'Storage1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @('198.51.100.11/24') }
                    [PSCustomObject]@{ Name = 'Storage2'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @('203.0.113.11/24') }
                )
                Qos = [PSCustomObject]@{ Available = $true; PfcPriorities = @(); TrafficClasses = @(); Policies = @(); DcbxWilling = '' }
            }
            Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets | Should -BeNullOrEmpty
        }

        It 'flags a storage adapter with RDMA disabled' {
            $Data = New-TestNetworkData
            $Data.HostVnics[2].RdmaEnabled = 'False'
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            $Result.Check | Should -Be @('RdmaDisabled')
            $Result[0].Object | Should -Be 'SMB2'
        }

        It 'flags a SET member with RDMA disabled below RDMA host vNICs' {
            $Data = New-TestNetworkData
            $Data.Adapters[1].RdmaEnabled = 'False'
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabled' }).Object | Should -Be 'pNIC2'
        }

        It 'ignores a SET member that is down' {
            $Data = New-TestNetworkData
            $Data.Adapters[1].RdmaEnabled = 'False'
            $Data.Adapters[1].Status = 'Disconnected'
            @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets).Check |
                Should -Not -Contain 'RdmaDisabled'
        }

        It 'reports an S2D host without RDMA on the storage networks' {
            $Data = New-TestNetworkData
            foreach ($Vnic in $Data.HostVnics) {
                $Vnic.RdmaEnabled = ''
            }
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            $Result.Check | Should -Contain 'NoStorageRdma'
        }

        It 'does not rate RDMA on hosts without S2D' {
            $Data = New-TestNetworkData
            $Data.HostVnics[2].RdmaEnabled = 'False'
            $Data.Adapters[1].RdmaEnabled = 'False'
            @(Resolve-HvNetworkFinding -NetworkData $Data -StorageSubnet $script:StorageSubnets).Check |
                Should -Not -Contain 'RdmaDisabled'
        }

        It 'counts every adapter with an address when the storage subnets are unknown' {
            $Data = New-TestNetworkData
            Resolve-HvNetworkFinding -NetworkData $Data -IsS2D | Should -BeNullOrEmpty
        }
    }

    Context 'Data Center Bridging' {

        It 'flags RoCE without PFC' {
            $Data = New-TestNetworkData
            $Data.Qos.PfcPriorities = @()
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'RocePfc' })
            $Result.Object | Should -Be @('pNIC1', 'pNIC2')
        }

        It 'flags RoCE with DCB disabled on the adapter' {
            $Data = New-TestNetworkData
            $Data.Adapters[0].DcbEnabled = 'False'
            @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'RocePfc' }).Object | Should -Be @('pNIC1')
        }

        It 'does not require PFC for iWARP' {
            $Data = New-TestNetworkData
            $Data.Qos.PfcPriorities = @()
            foreach ($Adapter in $Data.Adapters) {
                $Adapter.RdmaType = '1'
            }
            Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets | Should -BeNullOrEmpty
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

        It 'flags an SMB policy without ETS traffic class' {
            $Data = New-TestNetworkData
            $Data.Qos.TrafficClasses = @($Data.Qos.TrafficClasses | Where-Object { $_.Name -ne 'SMB' })
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'DcbTrafficClass' })
            $Result.Object | Should -Be @('SMB')
        }

        It 'flags a cluster heartbeat policy without ETS traffic class' {
            $Data = New-TestNetworkData
            $Data.Qos.TrafficClasses = @($Data.Qos.TrafficClasses | Where-Object { $_.Name -ne 'Cluster' })
            @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'DcbTrafficClass' }).Object | Should -Be @('Cluster')
        }

        It 'does not count the default class or strict priority classes as ETS class' {
            $Data = New-TestNetworkData
            $Data.Qos.TrafficClasses = @(
                [PSCustomObject]@{ Name = '[Default]'; Priority = @('0', '1', '2', '3', '4', '5', '6', '7'); Algorithm = 'ETS' }
                [PSCustomObject]@{ Name = 'Cluster'; Priority = @('7'); Algorithm = 'Strict' }
            )
            @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'DcbTrafficClass' }).Object | Should -Be @('SMB', 'Cluster')
        }

        It 'recognises an SMB policy by its template' {
            $Data = New-TestNetworkData
            $Data.Qos.Policies[0].NetDirectPort = ''
            $Data.Qos.Policies[0].Template = 'SMB'
            $Data.Qos.TrafficClasses = @($Data.Qos.TrafficClasses | Where-Object { $_.Name -ne 'SMB' })
            @(Resolve-HvNetworkFinding -NetworkData $Data | Where-Object { $_.Check -eq 'DcbTrafficClass' }).Object | Should -Be @('SMB')
        }

        It 'does not check traffic classes without PFC' {
            $Data = New-TestNetworkData
            $Data.Qos.PfcPriorities = @()
            $Data.Qos.TrafficClasses = @()
            foreach ($Adapter in $Data.Adapters) {
                $Adapter.RdmaType = '1'
            }
            @(Resolve-HvNetworkFinding -NetworkData $Data).Check | Should -Not -Contain 'DcbTrafficClass'
        }
    }
}
