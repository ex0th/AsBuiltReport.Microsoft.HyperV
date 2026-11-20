function Connect-HvNode {
    <#
    .SYNOPSIS
        Opens a read-only WinRM session to a Hyper-V host or failover cluster name.
    .DESCRIPTION
        Thin wrapper around New-PSSession so every connection in the report uses the same
        authentication, SSL and port settings from the report configuration.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param (
        [Parameter(Mandatory)]
        [String] $ComputerName,

        [PSCredential] $Credential,

        [ValidateSet('Default', 'Kerberos', 'Negotiate')]
        [String] $Authentication = 'Negotiate',

        [Switch] $UseSSL,

        [Int] $Port = 0
    )

    $SessionParams = @{
        ComputerName = $ComputerName
        Authentication = $Authentication
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $SessionParams['Credential'] = $Credential
    }
    if ($UseSSL) {
        $SessionParams['UseSSL'] = $true
    }
    if ($Port -gt 0) {
        $SessionParams['Port'] = $Port
    }
    New-PSSession @SessionParams
}

function Get-HvClusterFact {
    <#
    .SYNOPSIS
        Collects the cluster-level facts used to classify a Hyper-V environment.
    .DESCRIPTION
        Runs read-only queries in the given session. Returns IsCluster = $false when the
        FailoverClusters module is missing or the host is not a cluster member.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )

    Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
        $Fact = [ordered]@{
            IsCluster = $false
            Name = $null
            Domain = $null
            S2DEnabled = $false
            StoragePools = @()
            CsvCount = 0
            ClusterDiskCount = 0
            ScaleOutFileServerCount = 0
            AzureRegistrationStatus = $null
            AzureConnectionStatus = $null
            Nodes = @()
            Errors = @()
        }

        if (-not (Get-Command -Name 'Get-Cluster' -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]$Fact
        }
        try {
            $Cluster = Get-Cluster -ErrorAction Stop
        } catch {
            # Get-Cluster throws on hosts that are not cluster members; that is the standalone case.
            return [PSCustomObject]$Fact
        }

        $Fact.IsCluster = $true
        $Fact.Name = [string]$Cluster.Name
        $Fact.Domain = [string]$Cluster.Domain
        $Fact.S2DEnabled = ($Cluster.S2DEnabled -eq 1)

        try {
            $Fact.Nodes = @(Get-ClusterNode -ErrorAction Stop | ForEach-Object {
                    [PSCustomObject]@{
                        Name = [string]$_.Name
                        State = [string]$_.State
                    }
                })
        } catch {
            $Fact.Errors += "ClusterNode: $($_.Exception.Message)"
        }

        try {
            $Fact.CsvCount = @(Get-ClusterSharedVolume -ErrorAction Stop).Count
        } catch {
            $Fact.Errors += "ClusterSharedVolume: $($_.Exception.Message)"
        }

        try {
            # S2D virtual disks are 'Physical Disk' resources as well, so this count is evidence only.
            $Fact.ClusterDiskCount = @(Get-ClusterResource -ErrorAction Stop | Where-Object { [string]$_.ResourceType.Name -eq 'Physical Disk' }).Count
        } catch {
            $Fact.Errors += "ClusterResource: $($_.Exception.Message)"
        }

        try {
            $Fact.ScaleOutFileServerCount = @(Get-ClusterGroup -ErrorAction Stop | Where-Object { [string]$_.GroupType -eq 'ScaleOutFileServer' }).Count
        } catch {
            $Fact.Errors += "ClusterGroup: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-StorageSubSystem' -ErrorAction SilentlyContinue) {
                # Non-primordial pools on the clustered subsystem exist for S2D and for clustered Storage Spaces on shared SAS JBODs.
                $Fact.StoragePools = @(Get-StorageSubSystem -FriendlyName 'Clustered*' -ErrorAction SilentlyContinue |
                        Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [PSCustomObject]@{
                                FriendlyName = [string]$_.FriendlyName
                                HealthStatus = [string]$_.HealthStatus
                            }
                        })
            }
        } catch {
            $Fact.Errors += "StoragePool: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-AzureStackHCI' -ErrorAction SilentlyContinue) {
                $Registration = Get-AzureStackHCI -ErrorAction Stop
                $Fact.AzureRegistrationStatus = [string]$Registration.RegistrationStatus
                $Fact.AzureConnectionStatus = [string]$Registration.ConnectionStatus
            }
        } catch {
            $Fact.Errors += "AzureStackHCI: $($_.Exception.Message)"
        }

        [PSCustomObject]$Fact
    }
}

function Get-HvNodeFact {
    <#
    .SYNOPSIS
        Collects the host-level facts used to classify a Hyper-V environment.
    .DESCRIPTION
        Runs read-only queries in the given session. Each probe is isolated so that a missing
        role or module on one host does not hide the remaining facts.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )

    Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
        # MSFT_Disk.BusType and MSFT_InitiatorPort.ConnectionType can arrive as numbers depending on the type data loaded remotely.
        # The names match the enums of the Storage module (Disk.BusType, InitiatorPort.ConnectionType).
        $BusTypeMap = @{
            '0' = 'Unknown'; '1' = 'SCSI'; '2' = 'ATAPI'; '3' = 'ATA'; '4' = 'IEEE1394'; '5' = 'SSA'
            '6' = 'FibreChannel'; '7' = 'USB'; '8' = 'RAID'; '9' = 'iSCSI'; '10' = 'SAS'; '11' = 'SATA'
            '12' = 'SD'; '13' = 'MMC'; '14' = 'Virtual'; '15' = 'FileBackedVirtual'; '16' = 'Spaces'
            '17' = 'NVMe'; '18' = 'SCM'; '19' = 'UFS'
        }

        $Fact = [ordered]@{
            ComputerName = $env:COMPUTERNAME
            Reachable = $true
            OSCaption = $null
            OSBuild = $null
            EditionId = $null
            HyperVInstalled = $false
            MpioInstalled = $false
            DcbInstalled = $false
            DataDisks = @()
            IscsiSessionCount = 0
            FcInitiatorPortCount = 0
            RdmaAdapters = @()
            SetSwitches = @()
            DefaultVhdPath = $null
            VhdOnSmbCount = 0
            VhdOnCsvCount = 0
            VhdLocalCount = 0
            SmbShares = @()
            Errors = @()
        }

        try {
            $CurrentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $Fact.OSCaption = [string](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
            $Fact.OSBuild = '{0}.{1}' -f $CurrentVersion.CurrentBuildNumber, $CurrentVersion.UBR
            $Fact.EditionId = [string]$CurrentVersion.EditionID
        } catch {
            $Fact.Errors += "OperatingSystem: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-WindowsFeature' -ErrorAction SilentlyContinue) {
                $Features = Get-WindowsFeature -Name 'Hyper-V', 'Multipath-IO', 'Data-Center-Bridging' -ErrorAction Stop
                $Fact.HyperVInstalled = [bool]($Features | Where-Object { $_.Name -eq 'Hyper-V' -and $_.Installed })
                $Fact.MpioInstalled = [bool]($Features | Where-Object { $_.Name -eq 'Multipath-IO' -and $_.Installed })
                $Fact.DcbInstalled = [bool]($Features | Where-Object { $_.Name -eq 'Data-Center-Bridging' -and $_.Installed })
            } else {
                # Images without the ServerManager module: fall back to the services behind the features.
                $Fact.HyperVInstalled = [bool](Get-Service -Name 'vmms' -ErrorAction SilentlyContinue)
                $Fact.MpioInstalled = [bool](Get-Service -Name 'msdsm' -ErrorAction SilentlyContinue)
            }
        } catch {
            $Fact.Errors += "WindowsFeature: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-Disk' -ErrorAction SilentlyContinue) {
                $Fact.DataDisks = @(Get-Disk -ErrorAction Stop | Where-Object { -not $_.IsBoot -and -not $_.IsSystem } | ForEach-Object {
                        $BusType = [string]$_.BusType
                        if ($BusTypeMap.ContainsKey($BusType)) {
                            $BusType = $BusTypeMap[$BusType]
                        }
                        [PSCustomObject]@{
                            Number = $_.Number
                            BusType = $BusType
                            IsClustered = [bool]$_.IsClustered
                            SizeGB = [math]::Round($_.Size / 1GB, 0)
                        }
                    })
            }
        } catch {
            $Fact.Errors += "Disk: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-IscsiSession' -ErrorAction SilentlyContinue) {
                $Fact.IscsiSessionCount = @(Get-IscsiSession -ErrorAction SilentlyContinue).Count
            }
        } catch {
            $Fact.Errors += "IscsiSession: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-InitiatorPort' -ErrorAction SilentlyContinue) {
                $Fact.FcInitiatorPortCount = @(Get-InitiatorPort -ErrorAction SilentlyContinue |
                        Where-Object { @('1', 'FibreChannel') -contains [string]$_.ConnectionType }).Count
            }
        } catch {
            $Fact.Errors += "InitiatorPort: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-NetAdapterRdma' -ErrorAction SilentlyContinue) {
                $Fact.RdmaAdapters = @(Get-NetAdapterRdma -ErrorAction SilentlyContinue | Where-Object { $_.Enabled } | ForEach-Object { [string]$_.Name } | Sort-Object)
            }
        } catch {
            $Fact.Errors += "NetAdapterRdma: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-VMSwitch' -ErrorAction SilentlyContinue) {
                $Fact.SetSwitches = @(Get-VMSwitch -ErrorAction Stop | Where-Object { $_.EmbeddedTeamingEnabled } | ForEach-Object { [string]$_.Name } | Sort-Object)
            }
        } catch {
            $Fact.Errors += "VMSwitch: $($_.Exception.Message)"
        }

        try {
            if (Get-Command -Name 'Get-VMHost' -ErrorAction SilentlyContinue) {
                $Fact.DefaultVhdPath = [string](Get-VMHost -ErrorAction Stop).VirtualHardDiskPath
                # Only the location class of each virtual disk is needed here, not the VM inventory itself.
                $VhdPaths = @(Get-VM -ErrorAction Stop | Get-VMHardDiskDrive -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Path } | Where-Object { $_ })
                $SmbPaths = @($VhdPaths | Where-Object { $_.StartsWith('\\') })
                $Fact.VhdOnSmbCount = $SmbPaths.Count
                $Fact.VhdOnCsvCount = @($VhdPaths | Where-Object { $_ -match '^[A-Za-z]:\\ClusterStorage\\' }).Count
                $Fact.VhdLocalCount = $VhdPaths.Count - $Fact.VhdOnSmbCount - $Fact.VhdOnCsvCount
                $Fact.SmbShares = @($SmbPaths | ForEach-Object {
                        if ($_ -match '^(\\\\[^\\]+\\[^\\]+)') {
                            $Matches[1].ToLowerInvariant()
                        }
                    } | Sort-Object -Unique)
            }
        } catch {
            $Fact.Errors += "VMHost: $($_.Exception.Message)"
        }

        [PSCustomObject]$Fact
    }
}

function Resolve-HvEnvironmentType {
    <#
    .SYNOPSIS
        Classifies a Hyper-V environment from the facts collected by Get-HvClusterFact and Get-HvNodeFact.
    .DESCRIPTION
        Pure function without remote calls, so the classification can be unit tested with synthetic facts.
        Returns language-independent keys; report sections translate them for display.

        EnvironmentType: Standalone, S2D, AzureLocal, ThreeTier, SMB, Mixed, NoSharedStorage
        StorageTopology: S2D, iSCSI, FibreChannel, SharedSAS, SMB, Local
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSObject] $ClusterFact,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Object[]] $NodeFact,

        [ValidateSet('Auto', 'S2D', 'iSCSI', 'FibreChannel', 'SharedSAS', 'SMB', 'Local')]
        [String[]] $StorageTopology = @('Auto')
    )

    $Evidence = New-Object -TypeName System.Collections.Generic.List[PSObject]
    $Detected = New-Object -TypeName System.Collections.Generic.List[String]

    $IsCluster = [bool]($ClusterFact -and $ClusterFact.IsCluster)
    $ClusterScope = if ($IsCluster) { [string]$ClusterFact.Name } else { $null }
    $NodeList = @($NodeFact | Where-Object { $_ })
    $ReachableNodes = @($NodeList | Where-Object { $_.Reachable })
    $TargetScope = if ($IsCluster) { $ClusterScope } else { [string]($NodeList | Select-Object -First 1).ComputerName }

    # Evidence values are language-independent. ValueKey/ValueArgs let the report section translate fixed wording.
    $Membership = if ($IsCluster) { 'Cluster' } else { 'None' }
    $Evidence.Add([PSCustomObject]@{ Check = 'ClusterMembership'; Scope = $TargetScope; Value = $Membership; ValueKey = $Membership; Indicates = $(if ($IsCluster) { 'Cluster' } else { 'Standalone' }) })
    $Evidence.Add([PSCustomObject]@{ Check = 'NodeReachability'; Scope = $TargetScope; Value = ('{0}/{1}' -f $ReachableNodes.Count, $NodeList.Count); Indicates = '' })

    # Every documented host is expected to run the Hyper-V role.
    $NodesWithoutHyperV = @($ReachableNodes | Where-Object { -not $_.HyperVInstalled } | ForEach-Object { [string]$_.ComputerName })
    foreach ($Node in $ReachableNodes) {
        $RoleState = if ($Node.HyperVInstalled) { 'Installed' } else { 'NotInstalled' }
        $Evidence.Add([PSCustomObject]@{ Check = 'HyperVRole'; Scope = [string]$Node.ComputerName; Value = $RoleState; ValueKey = $RoleState; Indicates = '' })
    }

    # Platform: Azure Local (formerly Azure Stack HCI) reports its own edition on every node.
    $AzureLocalNodes = @($ReachableNodes | Where-Object { $_.EditionId -match 'AzureStackHCI' -or $_.OSCaption -match 'Azure Stack HCI|Azure Local' })
    $IsAzureLocal = ($AzureLocalNodes.Count -gt 0)
    foreach ($Node in $ReachableNodes) {
        $Evidence.Add([PSCustomObject]@{ Check = 'OSEdition'; Scope = [string]$Node.ComputerName; Value = ('{0} ({1})' -f $Node.OSCaption, $Node.OSBuild); Indicates = $(if ($AzureLocalNodes -contains $Node) { 'AzureLocal' } else { '' }) })
    }
    if ($IsCluster -and $ClusterFact.AzureRegistrationStatus) {
        $Evidence.Add([PSCustomObject]@{ Check = 'AzureRegistration'; Scope = $ClusterScope; Value = ('{0} / {1}' -f $ClusterFact.AzureRegistrationStatus, $ClusterFact.AzureConnectionStatus); Indicates = 'AzureLocal' })
    }

    # Storage Spaces Direct, or clustered Storage Spaces on shared SAS enclosures (pool present, S2D disabled).
    $PoolNames = @($ClusterFact.StoragePools | Where-Object { $_ } | ForEach-Object { $_.FriendlyName })
    if ($IsCluster -and $ClusterFact.S2DEnabled) {
        $Detected.Add('S2D')
        $Evidence.Add([PSCustomObject]@{ Check = 'S2DEnabled'; Scope = $ClusterScope; Value = $(if ($PoolNames) { $PoolNames -join ', ' } else { '-' }); Indicates = 'S2D' })
    } elseif ($IsCluster -and $PoolNames.Count -gt 0) {
        $Detected.Add('SharedSAS')
        $Evidence.Add([PSCustomObject]@{ Check = 'StoragePool'; Scope = $ClusterScope; Value = ($PoolNames -join ', '); Indicates = 'SharedSAS' })
    }

    # Cluster storage objects, for context only: S2D volumes are 'Physical Disk' resources and CSVs as well.
    if ($IsCluster) {
        $Evidence.Add([PSCustomObject]@{ Check = 'ClusterDiskResource'; Scope = $ClusterScope; Value = [string][int]$ClusterFact.ClusterDiskCount; Indicates = '' })
        $Evidence.Add([PSCustomObject]@{ Check = 'ClusterSharedVolume'; Scope = $ClusterScope; Value = [string][int]$ClusterFact.CsvCount; Indicates = '' })
        if ($ClusterFact.ScaleOutFileServerCount -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'ScaleOutFileServer'; Scope = $ClusterScope; Value = [string]$ClusterFact.ScaleOutFileServerCount; Indicates = '' })
        }
    }

    # Shared block storage. In a cluster only clustered disks count; local SAS on a standalone host is direct-attached, not shared.
    # Bus type names follow the Storage module enum (e.g. 'FibreChannel', 'Spaces').
    foreach ($Node in $ReachableNodes) {
        $RelevantDisks = @($Node.DataDisks | Where-Object { $_ -and ((-not $IsCluster) -or $_.IsClustered) })
        foreach ($Group in @($RelevantDisks | Group-Object -Property BusType | Sort-Object -Property Name)) {
            $Topology = switch ($Group.Name) {
                'iSCSI' { 'iSCSI' }
                'FibreChannel' { 'FibreChannel' }
                'SAS' { if ($IsCluster) { 'SharedSAS' } else { '' } }
                # Clustered Storage Spaces volumes: S2D when enabled, otherwise a pool on shared SAS enclosures.
                'Spaces' {
                    if (-not $IsCluster) { '' } elseif ($ClusterFact.S2DEnabled) { 'S2D' } else { 'SharedSAS' }
                }
                default { '' }
            }
            if ($Topology -and -not $Detected.Contains($Topology)) {
                $Detected.Add($Topology)
            }
            $Evidence.Add([PSCustomObject]@{ Check = $(if ($IsCluster) { 'ClusteredDisk' } else { 'DataDisk' }); Scope = [string]$Node.ComputerName; Value = ('{0} x{1}' -f $Group.Name, $Group.Count); Indicates = $Topology })
        }
        if ($Node.IscsiSessionCount -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'IscsiSession'; Scope = [string]$Node.ComputerName; Value = [string]$Node.IscsiSessionCount; Indicates = '' })
        }
        if ($Node.FcInitiatorPortCount -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'FcInitiatorPort'; Scope = [string]$Node.ComputerName; Value = [string]$Node.FcInitiatorPortCount; Indicates = '' })
        }
    }

    # SMB 3 storage: virtual disks or the default virtual disk path on a UNC share.
    foreach ($Node in $ReachableNodes) {
        $DefaultOnSmb = ([string]$Node.DefaultVhdPath).StartsWith('\\')
        if ($Node.VhdOnSmbCount -gt 0 -or $DefaultOnSmb) {
            if (-not $Detected.Contains('SMB')) {
                $Detected.Add('SMB')
            }
        }
        $VhdCounts = @([int]$Node.VhdOnSmbCount, [int]$Node.VhdOnCsvCount, [int]$Node.VhdLocalCount)
        $Evidence.Add([PSCustomObject]@{ Check = 'VhdLocation'; Scope = [string]$Node.ComputerName; Value = ('SMB {0}, CSV {1}, Local {2}' -f $VhdCounts); ValueKey = 'VhdLocation'; ValueArgs = $VhdCounts; Indicates = $(if ($Node.VhdOnSmbCount -gt 0) { 'SMB' } else { '' }) })
        if ($DefaultOnSmb) {
            $Evidence.Add([PSCustomObject]@{ Check = 'DefaultVhdPath'; Scope = [string]$Node.ComputerName; Value = [string]$Node.DefaultVhdPath; Indicates = 'SMB' })
        }
        if (@($Node.SmbShares | Where-Object { $_ }).Count -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'SmbShare'; Scope = [string]$Node.ComputerName; Value = (@($Node.SmbShares | Where-Object { $_ }) -join ', '); Indicates = 'SMB' })
        }
    }

    if ($Detected.Count -eq 0) {
        $Detected.Add('Local')
    }

    # Manual override from the report configuration wins, but the automatic result stays visible in the evidence.
    $Requested = @($StorageTopology | Where-Object { $_ -and $_ -ne 'Auto' } | Select-Object -Unique)
    if ($Requested.Count -gt 0) {
        $Topologies = $Requested
        $DetectionMode = 'Override'
        $OverrideArgs = @(($Requested -join ', '), ($Detected -join ', '))
        $Evidence.Add([PSCustomObject]@{ Check = 'Override'; Scope = $TargetScope; Value = ('{0} (auto: {1})' -f $OverrideArgs); ValueKey = 'Override'; ValueArgs = $OverrideArgs; Indicates = '' })
    } else {
        $Topologies = @($Detected)
        $DetectionMode = 'Automatic'
    }

    $IsS2D = $Topologies -contains 'S2D'
    $HasSharedBlock = [bool]($Topologies | Where-Object { @('iSCSI', 'FibreChannel', 'SharedSAS') -contains $_ })
    $HasSmb = $Topologies -contains 'SMB'
    $StorageClassCount = @($IsS2D, $HasSharedBlock, $HasSmb | Where-Object { $_ }).Count

    $EnvironmentType = if (-not $IsCluster) {
        'Standalone'
    } elseif ($StorageClassCount -gt 1) {
        'Mixed'
    } elseif ($IsS2D -and $IsAzureLocal) {
        'AzureLocal'
    } elseif ($IsS2D) {
        'S2D'
    } elseif ($HasSharedBlock) {
        'ThreeTier'
    } elseif ($HasSmb) {
        'SMB'
    } else {
        'NoSharedStorage'
    }

    # Feature flags drive which host networking and storage sections are relevant.
    foreach ($Node in $ReachableNodes) {
        if ($Node.MpioInstalled) {
            $Evidence.Add([PSCustomObject]@{ Check = 'MpioFeature'; Scope = [string]$Node.ComputerName; Value = 'Installed'; ValueKey = 'Installed'; Indicates = '' })
        }
        if (@($Node.RdmaAdapters).Count -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'RdmaAdapter'; Scope = [string]$Node.ComputerName; Value = (@($Node.RdmaAdapters) -join ', '); Indicates = '' })
        }
        if ($Node.DcbInstalled) {
            $Evidence.Add([PSCustomObject]@{ Check = 'DcbFeature'; Scope = [string]$Node.ComputerName; Value = 'Installed'; ValueKey = 'Installed'; Indicates = '' })
        }
        if (@($Node.SetSwitches).Count -gt 0) {
            $Evidence.Add([PSCustomObject]@{ Check = 'SetSwitch'; Scope = [string]$Node.ComputerName; Value = (@($Node.SetSwitches) -join ', '); Indicates = '' })
        }
    }

    [PSCustomObject]@{
        EnvironmentType = $EnvironmentType
        Platform = $(if ($IsAzureLocal) { 'AzureLocal' } else { 'WindowsServer' })
        IsCluster = $IsCluster
        IsAzureLocal = $IsAzureLocal
        StorageTopology = [String[]]$Topologies
        IsS2D = $IsS2D
        HasSharedBlock = $HasSharedBlock
        HasSmb = $HasSmb
        UsesMpio = [bool]($ReachableNodes | Where-Object { $_.MpioInstalled })
        UsesRdma = [bool]($ReachableNodes | Where-Object { @($_.RdmaAdapters).Count -gt 0 })
        UsesDcb = [bool]($ReachableNodes | Where-Object { $_.DcbInstalled })
        UsesSet = [bool]($ReachableNodes | Where-Object { @($_.SetSwitches).Count -gt 0 })
        DetectionMode = $DetectionMode
        NodeCount = $NodeList.Count
        ReachableNodeCount = $ReachableNodes.Count
        NodesWithoutHyperV = [String[]]$NodesWithoutHyperV
        Evidence = $Evidence.ToArray()
    }
}

function Resolve-HvQuorumState {
    <#
    .SYNOPSIS
        Evaluates the quorum configuration collected from a failover cluster.
    .DESCRIPTION
        Pure function without remote calls, so the evaluation can be unit tested with synthetic data.
        Returns language-independent keys; the report section translates them for display.

        QuorumModel: NodeMajority, NodeAndWitnessMajority, DiskOnly
        WitnessType: None, Disk, FileShare, Cloud, Other
        Findings:    NoWitnessTwoNodes, NoWitness, WitnessNotOnline, DynamicQuorumDisabled
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [PSObject] $QuorumData
    )

    $ResourceType = [string]$QuorumData.WitnessResourceType
    $HasWitness = -not [string]::IsNullOrWhiteSpace([string]$QuorumData.WitnessName)
    $WitnessType = if (-not $HasWitness) {
        'None'
    } else {
        switch ($ResourceType) {
            'Physical Disk' { 'Disk' }
            'File Share Witness' { 'FileShare' }
            'Cloud Witness' { 'Cloud' }
            default { 'Other' }
        }
    }

    # Windows Server 2012 R2 and later report 'Majority' (with or without witness) or 'DiskOnly';
    # older clusters report the legacy names.
    $QuorumType = [string]$QuorumData.QuorumType
    $QuorumModel = if ($QuorumType -eq 'DiskOnly') {
        'DiskOnly'
    } elseif ($HasWitness) {
        'NodeAndWitnessMajority'
    } else {
        'NodeMajority'
    }

    $Nodes = @($QuorumData.Nodes | Where-Object { $_ })
    $VotingNodes = @($Nodes | Where-Object { [int]$_.NodeWeight -eq 1 })
    $WitnessState = if ($HasWitness) { [string]$QuorumData.WitnessState } else { $null }
    $DynamicQuorum = ([int]$QuorumData.DynamicQuorum -eq 1)

    $LowerPriorityNodeName = $null
    if ([int]$QuorumData.LowerQuorumPriorityNodeId -ne 0) {
        $LowerPriorityNode = $Nodes | Where-Object { [string]$_.Id -eq [string]$QuorumData.LowerQuorumPriorityNodeId } |
            Select-Object -First 1
        $LowerPriorityNodeName = if ($LowerPriorityNode) {
            [string]$LowerPriorityNode.Name
        } else {
            [string]$QuorumData.LowerQuorumPriorityNodeId
        }
    }

    $Findings = New-Object -TypeName System.Collections.Generic.List[String]
    if ($QuorumModel -ne 'DiskOnly' -and -not $HasWitness) {
        # With two votes, dynamic quorum takes the vote from one node; losing the other node stops the cluster.
        if ($VotingNodes.Count -eq 2) {
            $Findings.Add('NoWitnessTwoNodes')
        } else {
            $Findings.Add('NoWitness')
        }
    }
    if ($HasWitness -and $WitnessState -ne 'Online') {
        $Findings.Add('WitnessNotOnline')
    }
    if (-not $DynamicQuorum) {
        $Findings.Add('DynamicQuorumDisabled')
    }

    [PSCustomObject]@{
        QuorumModel = $QuorumModel
        WitnessType = $WitnessType
        HasWitness = $HasWitness
        WitnessState = $WitnessState
        DynamicQuorum = $DynamicQuorum
        WitnessHasVote = ($HasWitness -and [int]$QuorumData.WitnessDynamicWeight -eq 1)
        VotingNodeCount = $VotingNodes.Count
        LowerPriorityNodeName = $LowerPriorityNodeName
        Findings = [String[]]$Findings.ToArray()
    }
}

function Resolve-HvClusterNetwork {
    <#
    .SYNOPSIS
        Evaluates the cluster networks and their use for live migration.
    .DESCRIPTION
        Pure function without remote calls, so the evaluation can be unit tested with synthetic data.
        Returns language-independent keys; report sections translate them for display.

        RoleKey: None (0), ClusterOnly (1), ClientOnly (2), ClusterAndClient (3), or the raw value
        StateSeverity: Ok, Warning, Critical
        Findings: NoMigrationNetwork, SingleClusterNetwork

        A network is allowed for live migration unless it is listed in MigrationExcludeNetworks of the
        'Virtual Machine' resource type. MigrationNetworkOrder sets the preference of the allowed networks.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Object[]] $Network,

        # Semicolon separated network IDs, as stored in the cluster parameter.
        [AllowNull()]
        [AllowEmptyString()]
        [String] $MigrationExcludeNetworks,

        [AllowNull()]
        [AllowEmptyString()]
        [String] $MigrationNetworkOrder
    )

    $Excluded = @(([string]$MigrationExcludeNetworks).Split(';') | ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ })
    $Order = @(([string]$MigrationNetworkOrder).Split(';') | ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ })

    $Networks = foreach ($Item in @($Network | Where-Object { $_ })) {
        $Id = ([string]$Item.Id).ToLowerInvariant()
        $RoleKey = switch ([string]$Item.Role) {
            { $_ -in '0', 'None' } { 'None'; break }
            { $_ -in '1', 'Cluster' } { 'ClusterOnly'; break }
            { $_ -in '2', 'Client' } { 'ClientOnly'; break }
            { $_ -in '3', 'ClusterAndClient' } { 'ClusterAndClient'; break }
            default { [string]$Item.Role }
        }
        $State = [string]$Item.State
        $StateSeverity = switch ($State) {
            'Up' { 'Ok' }
            'Down' { 'Critical' }
            default { 'Warning' }
        }
        $AllowedForMigration = ($Excluded -notcontains $Id)
        $OrderIndex = [array]::IndexOf($Order, $Id)
        [PSCustomObject]@{
            Name = [string]$Item.Name
            Id = $Id
            RoleKey = $RoleKey
            State = $State
            StateSeverity = $StateSeverity
            AllowedForMigration = $AllowedForMigration
            MigrationOrder = $(if ($AllowedForMigration -and $OrderIndex -ge 0) { $OrderIndex + 1 } else { $null })
        }
    }
    $Networks = @($Networks)

    # Cluster traffic (heartbeat) uses networks with the role 'Cluster only' or 'Cluster and client'.
    $ClusterNetworks = @($Networks | Where-Object { $_.RoleKey -in 'ClusterOnly', 'ClusterAndClient' -and $_.State -eq 'Up' })
    $MigrationNetworks = @($Networks | Where-Object { $_.AllowedForMigration })

    $Findings = New-Object -TypeName System.Collections.Generic.List[String]
    if ($Networks.Count -gt 0 -and $MigrationNetworks.Count -eq 0) {
        $Findings.Add('NoMigrationNetwork')
    }
    if ($ClusterNetworks.Count -lt 2) {
        $Findings.Add('SingleClusterNetwork')
    }

    [PSCustomObject]@{
        Networks = $Networks
        ClusterNetworkCount = $ClusterNetworks.Count
        MigrationNetworks = [String[]]@($MigrationNetworks | Sort-Object -Property @{ Expression = {
                    if ($null -ne $_.MigrationOrder) { $_.MigrationOrder } else { [int]::MaxValue } }
            }, Name | ForEach-Object { $_.Name })
        Findings = [String[]]$Findings.ToArray()
    }
}

function Resolve-HvSettingDeviation {
    <#
    .SYNOPSIS
        Finds settings that differ between hosts.
    .DESCRIPTION
        Pure function for node-to-node consistency checks. For every property, the value most hosts use is
        the reference and every other value is a deviation. If no single value is the most common (for
        example two hosts with different values), every host is reported, because the correct value
        cannot be determined. Values are compared as text; collections are joined in their given order.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Object[]] $InputObject,

        [Parameter(Mandatory)]
        [String[]] $Property,

        [String] $NameProperty = 'Name'
    )

    $Items = @($InputObject | Where-Object { $_ })
    if ($Items.Count -lt 2) {
        return
    }
    foreach ($Name in $Property) {
        $Values = foreach ($Item in $Items) {
            $Value = $Item.$Name
            $Text = if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                (@($Value) | ForEach-Object { [string]$_ }) -join ';'
            } else {
                [string]$Value
            }
            [PSCustomObject]@{ Host = [string]$Item.$NameProperty; Value = $Text }
        }
        $Groups = @($Values | Group-Object -Property Value | Sort-Object -Property Count -Descending)
        if ($Groups.Count -lt 2) {
            continue
        }
        $Reference = if ($Groups[0].Count -gt $Groups[1].Count) { $Groups[0].Name } else { $null }
        foreach ($Entry in @($Values | Where-Object { $null -eq $Reference -or $_.Value -ne $Reference })) {
            [PSCustomObject]@{
                Name = $Entry.Host
                Property = $Name
                Value = $Entry.Value
                Reference = $Reference
            }
        }
    }
}

function ConvertTo-HvDisplayValue {
    <#
    .SYNOPSIS
        Formats a single value for a report table cell.
    .DESCRIPTION
        Booleans become the localized Yes/No, arrays are joined, empty values become '--'.
        Only formats values; the columns of every table stay visible in the section function.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        [Object] $Value
    )

    $Common = $reportTranslate.HvCommon
    if ($null -eq $Value) {
        return '--'
    }
    if ($Value -is [bool]) {
        if ($Value) {
            return $(if ($Common.Yes) { $Common.Yes } else { 'Yes' })
        }
        return $(if ($Common.No) { $Common.No } else { 'No' })
    }
    # Arrays arrive as ArrayList after remoting deserialization, so test for any non-string collection.
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($Items.Count -eq 0) {
            return '--'
        }
        return ($Items -join ', ')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return '--'
    }
    [string]$Value
}
