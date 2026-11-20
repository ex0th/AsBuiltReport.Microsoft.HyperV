# Unit tests for the environment classification. All facts are synthetic; no data from real environments.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvEnvironmentType.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestNodeFact {
        param (
            [String] $Name,
            [String] $EditionId = 'ServerDatacenter',
            [String] $OSCaption = 'Microsoft Windows Server 2025 Datacenter',
            [Object[]] $DataDisks = @(),
            [Int] $VhdOnSmbCount = 0,
            [Int] $VhdOnCsvCount = 0,
            [String] $DefaultVhdPath = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks',
            [Switch] $Mpio,
            [String[]] $RdmaAdapters = @(),
            [String[]] $SetSwitches = @(),
            [String[]] $SmbShares = @(),
            [Switch] $NoHyperV,
            [Switch] $Unreachable
        )
        if ($Unreachable) {
            return [PSCustomObject]@{ ComputerName = $Name; Reachable = $false }
        }
        [PSCustomObject]@{
            ComputerName = $Name
            Reachable = $true
            OSCaption = $OSCaption
            OSBuild = '26100.1000'
            EditionId = $EditionId
            HyperVInstalled = (-not $NoHyperV)
            MpioInstalled = [bool]$Mpio
            DcbInstalled = ($RdmaAdapters.Count -gt 0)
            DataDisks = $DataDisks
            IscsiSessionCount = @($DataDisks | Where-Object { $_.BusType -eq 'iSCSI' }).Count
            FcInitiatorPortCount = 0
            RdmaAdapters = $RdmaAdapters
            SetSwitches = $SetSwitches
            DefaultVhdPath = $DefaultVhdPath
            VhdOnSmbCount = $VhdOnSmbCount
            VhdOnCsvCount = $VhdOnCsvCount
            VhdLocalCount = 0
            SmbShares = $SmbShares
            Errors = @()
        }
    }

    function New-TestClusterFact {
        param (
            [Switch] $S2D,
            [String[]] $Pools = @(),
            [String] $AzureRegistrationStatus
        )
        [PSCustomObject]@{
            IsCluster = $true
            Name = 'CLU01'
            Domain = 'example.com'
            S2DEnabled = [bool]$S2D
            StoragePools = @($Pools | ForEach-Object { [PSCustomObject]@{ FriendlyName = $_; HealthStatus = 'Healthy' } })
            CsvCount = 2
            ClusterDiskCount = 2
            ScaleOutFileServerCount = 0
            AzureRegistrationStatus = $AzureRegistrationStatus
            AzureConnectionStatus = $(if ($AzureRegistrationStatus) { 'Connected' } else { $null })
            Nodes = @()
            Errors = @()
        }
    }

    # Bus type names as returned by Get-Disk (Storage module enum), e.g. 'FibreChannel' and 'Spaces'.
    function New-TestDisk {
        param ([String] $BusType, [Switch] $Clustered)
        [PSCustomObject]@{ Number = 1; BusType = $BusType; IsClustered = [bool]$Clustered; SizeGB = 1024 }
    }
}

Describe 'Resolve-HvEnvironmentType' {

    It 'classifies a standalone host with local disks' {
        $Result = Resolve-HvEnvironmentType -ClusterFact $null -NodeFact @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'NVMe'))
        $Result.EnvironmentType | Should -Be 'Standalone'
        $Result.IsCluster | Should -BeFalse
        ($Result.StorageTopology -join ',') | Should -Be 'Local'
    }

    It 'does not treat direct-attached SAS on a standalone host as shared storage' {
        $Result = Resolve-HvEnvironmentType -ClusterFact $null -NodeFact @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'SAS'))
        ($Result.StorageTopology -join ',') | Should -Be 'Local'
    }

    It 'detects SMB storage on a standalone host' {
        $Result = Resolve-HvEnvironmentType -ClusterFact $null -NodeFact @(New-TestNodeFact -Name 'HV01' -VhdOnSmbCount 3)
        $Result.EnvironmentType | Should -Be 'Standalone'
        $Result.StorageTopology | Should -Contain 'SMB'
        $Result.HasSmb | Should -BeTrue
    }

    It 'classifies a 3-tier cluster with iSCSI and MPIO' {
        $Disks = @(New-TestDisk -BusType 'iSCSI' -Clustered; New-TestDisk -BusType 'iSCSI' -Clustered)
        $Nodes = @(
            New-TestNodeFact -Name 'HV01' -DataDisks $Disks -Mpio -VhdOnCsvCount 4
            New-TestNodeFact -Name 'HV02' -DataDisks $Disks -Mpio -VhdOnCsvCount 3
        )
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'ThreeTier'
        ($Result.StorageTopology -join ',') | Should -Be 'iSCSI'
        $Result.HasSharedBlock | Should -BeTrue
        $Result.UsesMpio | Should -BeTrue
    }

    It 'ignores non-clustered iSCSI disks in a cluster' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'iSCSI'))
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'NoSharedStorage'
    }

    It 'classifies a Fibre Channel cluster' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'FibreChannel' -Clustered) -Mpio)
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'ThreeTier'
        ($Result.StorageTopology -join ',') | Should -Be 'FibreChannel'
    }

    It 'classifies a Windows Server S2D cluster with RDMA and SET' {
        $Nodes = @(
            New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'Spaces' -Clustered) -RdmaAdapters @('SMB1', 'SMB2') -SetSwitches @('ConvergedSwitch')
            New-TestNodeFact -Name 'HV02' -DataDisks @(New-TestDisk -BusType 'Spaces' -Clustered) -RdmaAdapters @('SMB1', 'SMB2') -SetSwitches @('ConvergedSwitch')
        )
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact -S2D -Pools 'S2D Pool') -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'S2D'
        $Result.Platform | Should -Be 'WindowsServer'
        ($Result.StorageTopology -join ',') | Should -Be 'S2D'
        $Result.UsesRdma | Should -BeTrue
        $Result.UsesSet | Should -BeTrue
    }

    It 'marks clustered Storage Spaces volumes as S2D evidence when S2D is enabled' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'Spaces' -Clustered))
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact -S2D -Pools 'S2D Pool') -NodeFact $Nodes
        ($Result.Evidence | Where-Object { $_.Check -eq 'ClusteredDisk' }).Indicates | Should -Be 'S2D'
    }

    It 'treats clustered Storage Spaces volumes without S2D as shared SAS' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'Spaces' -Clustered))
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'ThreeTier'
        ($Result.StorageTopology -join ',') | Should -Be 'SharedSAS'
    }

    It 'does not treat Storage Spaces on a standalone host as shared storage' {
        $Result = Resolve-HvEnvironmentType -ClusterFact $null -NodeFact @(New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'Spaces'))
        ($Result.StorageTopology -join ',') | Should -Be 'Local'
    }

    It 'lists cluster storage objects as evidence' {
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact @(New-TestNodeFact -Name 'HV01')
        $Result.Evidence.Check | Should -Contain 'ClusterDiskResource'
        $Result.Evidence.Check | Should -Contain 'ClusterSharedVolume'
    }

    It 'lists SMB shares that hold virtual hard disks as evidence' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -VhdOnSmbCount 2 -SmbShares @('\\sofs.example.com\vms'))
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        ($Result.Evidence | Where-Object { $_.Check -eq 'SmbShare' }).Value | Should -Be '\\sofs.example.com\vms'
    }

    It 'reports hosts without the Hyper-V role' {
        $Nodes = @(
            New-TestNodeFact -Name 'HV01'
            New-TestNodeFact -Name 'HV02' -NoHyperV
            New-TestNodeFact -Name 'HV03' -Unreachable
        )
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        ($Result.NodesWithoutHyperV -join ',') | Should -Be 'HV02'
        ($Result.Evidence | Where-Object { $_.Check -eq 'HyperVRole' }).Count | Should -Be 2
    }

    It 'classifies an Azure Local cluster' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -EditionId 'ServerAzureStackHCICor' -OSCaption 'Microsoft Azure Stack HCI')
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact -S2D -Pools 'SU1_Pool' -AzureRegistrationStatus 'Registered') -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'AzureLocal'
        $Result.Platform | Should -Be 'AzureLocal'
        $Result.Evidence.Check | Should -Contain 'AzureRegistration'
    }

    It 'treats a clustered pool without S2D as shared SAS (clustered Storage Spaces)' {
        $Nodes = @(New-TestNodeFact -Name 'HV01')
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact -Pools 'JBOD Pool') -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'ThreeTier'
        ($Result.StorageTopology -join ',') | Should -Be 'SharedSAS'
    }

    It 'classifies a cluster with SMB storage' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -VhdOnSmbCount 5)
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'SMB'
    }

    It 'classifies S2D plus SMB as mixed' {
        $Nodes = @(New-TestNodeFact -Name 'HV01' -VhdOnSmbCount 1)
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact -S2D -Pools 'S2D Pool') -NodeFact $Nodes
        $Result.EnvironmentType | Should -Be 'Mixed'
        $Result.StorageTopology | Should -Contain 'S2D'
        $Result.StorageTopology | Should -Contain 'SMB'
    }

    It 'counts unreachable nodes' {
        $Nodes = @(
            New-TestNodeFact -Name 'HV01' -DataDisks @(New-TestDisk -BusType 'iSCSI' -Clustered)
            New-TestNodeFact -Name 'HV02' -Unreachable
        )
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes
        $Result.NodeCount | Should -Be 2
        $Result.ReachableNodeCount | Should -Be 1
        $Result.EnvironmentType | Should -Be 'ThreeTier'
    }

    It 'applies a manual storage topology override and keeps the automatic result as evidence' {
        $Nodes = @(New-TestNodeFact -Name 'HV01')
        $Result = Resolve-HvEnvironmentType -ClusterFact (New-TestClusterFact) -NodeFact $Nodes -StorageTopology 'FibreChannel'
        $Result.DetectionMode | Should -Be 'Override'
        $Result.EnvironmentType | Should -Be 'ThreeTier'
        ($Result.Evidence | Where-Object { $_.Check -eq 'Override' }).Value | Should -Match 'auto: Local'
    }

    It 'rejects unknown storage topology values' {
        { Resolve-HvEnvironmentType -ClusterFact $null -NodeFact @(New-TestNodeFact -Name 'HV01') -StorageTopology 'NFS' } | Should -Throw
    }
}
