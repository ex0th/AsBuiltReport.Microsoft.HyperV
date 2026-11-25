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

        It 'flags the storage vNICs with RDMA disabled when no storage path uses RDMA' {
            $Data = New-TestNetworkData
            $Data.HostVnics[1].RdmaEnabled = 'False'
            $Data.HostVnics[2].RdmaEnabled = 'False'
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabledVnic' }).Object | Should -Be @('SMB1', 'SMB2')
            $Result.Check | Should -Contain 'NoStorageRdma'
            $Result.Check | Should -Not -Contain 'RdmaDisabledAdapter'
        }

        It 'reports nothing as long as one storage path of the host uses RDMA' {
            $Data = New-TestNetworkData
            $Data.HostVnics[2].RdmaEnabled = 'False'
            $Data.Adapters[1].RdmaEnabled = 'False'
            @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets).Check |
                Should -Not -Match '^(RdmaDisabled|NoStorageRdma)'
        }

        It 'flags a physical storage adapter with RDMA disabled under the adapter check' {
            $Data = [PSCustomObject]@{
                Switches = @()
                HostVnics = @()
                Adapters = @(
                    [PSCustomObject]@{ Name = 'Storage1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @('198.51.100.11/24') }
                )
                Qos = [PSCustomObject]@{ Available = $false; PfcPriorities = @(); TrafficClasses = @(); Policies = @(); DcbxWilling = '' }
            }
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabledAdapter' }).Object | Should -Be 'Storage1'
        }

        It 'does not rate an adapter that is down' {
            $Data = New-TestNetworkData
            foreach ($Vnic in $Data.HostVnics) {
                $Vnic.RdmaEnabled = ''
            }
            $Data.Adapters[1].RdmaEnabled = 'False'
            $Data.Adapters[1].Status = 'Disconnected'
            $Data.Adapters[1].IPAddresses = @('198.51.100.21/24')
            @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets).Check |
                Should -Not -Contain 'RdmaDisabledAdapter'
        }

        It 'treats the interfaces of SMB multichannel constraints as storage paths' {
            $Data = [PSCustomObject]@{
                Switches = @()
                HostVnics = @()
                Adapters = @(
                    [PSCustomObject]@{ Name = 'SAN1'; Status = 'Up'; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @('10.10.10.11/24') }
                )
                Qos = [PSCustomObject]@{ Available = $false; PfcPriorities = @(); TrafficClasses = @(); Policies = @(); DcbxWilling = '' }
                SmbConstraintInterfaces = @('SAN1')
            }
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -StorageSubnet $script:StorageSubnets)
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabledAdapter' }).Object | Should -Be 'SAN1'
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
                Should -Not -Match '^(RdmaDisabled|NoStorageRdma)'
        }

        It 'counts every adapter with an address when the storage subnets are unknown' {
            $Data = New-TestNetworkData
            Resolve-HvNetworkFinding -NetworkData $Data -IsS2D | Should -BeNullOrEmpty
        }

        It 'never rates adapters on excluded (management) subnets when the storage subnets are unknown' {
            $Data = New-TestNetworkData
            foreach ($Vnic in $Data.HostVnics) {
                $Vnic.RdmaEnabled = 'False'
            }
            $Data.HostVnics = @($Data.HostVnics[0])
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Data -IsS2D -ExcludeSubnet @('192.0.2.0/24'))
            $Result.Check | Should -Not -Contain 'RdmaDisabledVnic'
        }
    }

    Context 'Dedicated RDMA ports with management and live migration vNICs without RDMA' {

        BeforeAll {
            # Two nodes: storage over dedicated physical ports in two Cluster only networks (RDMA on),
            # management vNIC on a Cluster and client network and live migration vNIC on a Cluster only
            # network, both without RDMA. No host vNIC uses RDMA.
            function New-DedicatedNode {
                param ($Octet)
                [PSCustomObject]@{
                    Switches = @(
                        [PSCustomObject]@{ Name = 'vSwitch-MGMT'; EmbeddedTeaming = 'True'; Members = @('MGMT-A', 'MGMT-B'); LoadBalancingAlgorithm = 'HyperVPort' }
                    )
                    HostVnics = @(
                        [PSCustomObject]@{ Name = 'vSwitch-MGMT'; SwitchName = 'vSwitch-MGMT'; RdmaEnabled = 'False'; MappedAdapter = ''; IPAddresses = @("192.0.2.$Octet/24") }
                        [PSCustomObject]@{ Name = 'LiveMigration'; SwitchName = 'vSwitch-MGMT'; RdmaEnabled = 'False'; MappedAdapter = ''; IPAddresses = @("10.0.30.$Octet/24") }
                    )
                    Adapters = @(
                        [PSCustomObject]@{ Name = 'MGMT-A'; Status = 'Up'; LinkSpeed = '25 Gbps'; Speed = 25000000000; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                        [PSCustomObject]@{ Name = 'MGMT-B'; Status = 'Up'; LinkSpeed = '25 Gbps'; Speed = 25000000000; RdmaCapable = 'True'; RdmaEnabled = 'False'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @() }
                        [PSCustomObject]@{ Name = 'vNet-RDMA-0'; Status = 'Up'; LinkSpeed = '25 Gbps'; Speed = 25000000000; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @("198.51.100.$Octet/24") }
                        [PSCustomObject]@{ Name = 'vNet-RDMA-1'; Status = 'Up'; LinkSpeed = '25 Gbps'; Speed = 25000000000; RdmaCapable = 'True'; RdmaEnabled = 'True'; RdmaType = '1'; DcbEnabled = ''; IPAddresses = @("203.0.113.$Octet/24") }
                    )
                    Qos = [PSCustomObject]@{ Available = $true; PfcPriorities = @(); TrafficClasses = @(); Policies = @(); DcbxWilling = '' }
                    SmbConstraintInterfaces = @()
                    MigrationPerformance = 'SMB'
                }
            }
            $script:Nodes = @((New-DedicatedNode 11), (New-DedicatedNode 12))
            $script:ClusterNetworks = @(
                [PSCustomObject]@{ Name = 'Management'; Role = 3; Subnets = @('192.0.2.0/24'); AllowedForMigration = $false }
                [PSCustomObject]@{ Name = 'LiveMigration'; Role = 1; Subnets = @('10.0.30.0/24'); AllowedForMigration = $true }
                [PSCustomObject]@{ Name = 'Storage-0'; Role = 1; Subnets = @('198.51.100.0/24'); AllowedForMigration = $false }
                [PSCustomObject]@{ Name = 'Storage-1'; Role = 1; Subnets = @('203.0.113.0/24'); AllowedForMigration = $false }
            )
            $script:Class = Resolve-HvStorageNetwork -ClusterNetwork $script:ClusterNetworks -NetworkData $script:Nodes
        }

        It 'classifies only the Cluster only networks with RDMA as storage networks' {
            $script:Class.StorageSubnets | Should -Be @('198.51.100.0/24', '203.0.113.0/24')
            $script:Class.ExcludedSubnets | Should -Be @('192.0.2.0/24')
            $script:Class.MigrationSubnets | Should -Be @('10.0.30.0/24')
        }

        It 'produces no RDMA warning for <_>' -ForEach @(0, 1) {
            $Result = @(Resolve-HvNetworkFinding -NetworkData $script:Nodes[$_] -IsS2D -StorageSubnet $script:Class.StorageSubnets `
                    -ExcludeSubnet $script:Class.ExcludedSubnets -MigrationSubnet $script:Class.MigrationSubnets)
            $Result.Check | Should -Not -Match '^(RdmaDisabled|NoStorageRdma)'
        }

        It 'only notes live migration over SMB without RDMA' {
            $Result = @(Resolve-HvNetworkFinding -NetworkData $script:Nodes[0] -IsS2D -StorageSubnet $script:Class.StorageSubnets `
                    -ExcludeSubnet $script:Class.ExcludedSubnets -MigrationSubnet $script:Class.MigrationSubnets)
            $Result.Check | Should -Be @('MigrationNoRdma')
        }

        It 'does not note live migration with compression' {
            $Node = New-DedicatedNode 13
            $Node.MigrationPerformance = 'Compression'
            Resolve-HvNetworkFinding -NetworkData $Node -IsS2D -StorageSubnet $script:Class.StorageSubnets `
                -ExcludeSubnet $script:Class.ExcludedSubnets -MigrationSubnet $script:Class.MigrationSubnets | Should -BeNullOrEmpty
        }

        It 'falls back to every Cluster only network when no network uses RDMA' {
            $Nodes = @((New-DedicatedNode 11), (New-DedicatedNode 12))
            foreach ($Adapter in @($Nodes | ForEach-Object { $_.Adapters })) {
                $Adapter.RdmaEnabled = 'False'
            }
            $Class = Resolve-HvStorageNetwork -ClusterNetwork $script:ClusterNetworks -NetworkData $Nodes
            $Class.StorageSubnets | Should -Be @('10.0.30.0/24', '198.51.100.0/24', '203.0.113.0/24')
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Nodes[0] -IsS2D -StorageSubnet $Class.StorageSubnets -ExcludeSubnet $Class.ExcludedSubnets)
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabledAdapter' }).Object | Should -Be @('vNet-RDMA-0', 'vNet-RDMA-1')
            ($Result | Where-Object { $_.Check -eq 'RdmaDisabledVnic' }).Object | Should -Be @('LiveMigration')
            $Result.Check | Should -Contain 'NoStorageRdma'
        }

        It 'reports a SET member that is disconnected' {
            $Node = New-DedicatedNode 11
            $Node.Adapters[1].Status = 'Disconnected'
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Node -IsS2D -StorageSubnet $script:Class.StorageSubnets `
                    -ExcludeSubnet $script:Class.ExcludedSubnets)
            $Result.Check | Should -Be @('SetMemberState')
            $Result[0].Object | Should -Be 'MGMT-B'
        }

        It 'reports SET members with 10 and 25 Gbit/s' {
            $Node = New-DedicatedNode 11
            $Node.Adapters[0].Speed = 10000000000
            $Node.Adapters[0].LinkSpeed = '10 Gbps'
            $Result = @(Resolve-HvNetworkFinding -NetworkData $Node)
            $Result.Check | Should -Be @('SetMemberLinkSpeed')
            $Result[0].Object | Should -Be 'vSwitch-MGMT'
            $Result[0].Members | Should -Be @('MGMT-A', 'MGMT-B')
        }

        It 'compares the link speed text when the speed is missing' {
            $Node = New-DedicatedNode 11
            foreach ($Adapter in $Node.Adapters) {
                $Adapter.Speed = 0
            }
            Resolve-HvNetworkFinding -NetworkData $Node | Should -BeNullOrEmpty
            $Node.Adapters[1].LinkSpeed = '10 Gbps'
            @(Resolve-HvNetworkFinding -NetworkData $Node).Check | Should -Be @('SetMemberLinkSpeed')
        }

        It 'does not compare the speed of a member that is down' {
            $Node = New-DedicatedNode 11
            $Node.Adapters[1].Status = 'Disconnected'
            $Node.Adapters[1].Speed = 0
            @(Resolve-HvNetworkFinding -NetworkData $Node).Check | Should -Not -Contain 'SetMemberLinkSpeed'
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
