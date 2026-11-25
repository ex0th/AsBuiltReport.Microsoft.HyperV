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

function Resolve-HvWitnessHost {
    <#
    .SYNOPSIS
        Finds the virtual machine of the cluster that hosts the file share witness.
    .DESCRIPTION
        Pure function without remote calls. Compares the server of the witness share path (\\server\share)
        with the virtual machines of the cluster: VM name, guest host names (Hyper-V data exchange) and IP
        addresses. Names are compared by their first label, so 'fs01' matches 'fs01.example.com'.

        Returns the name of the matching virtual machine, or nothing.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [String] $SharePath,

        # Virtual machines: Name, HostNames, IPAddresses
        [AllowEmptyCollection()]
        [Object[]] $VM = @()
    )

    $Server = ([string]$SharePath).TrimStart('\').Split('\')[0].Trim().TrimEnd('.')
    if ([string]::IsNullOrEmpty($Server)) {
        return
    }
    $Address = $null
    $IsAddress = [System.Net.IPAddress]::TryParse($Server, [ref]$Address)
    $ShortName = $Server.Split('.')[0]

    foreach ($Item in @($VM | Where-Object { $_ })) {
        if ($IsAddress) {
            $Addresses = @($Item.IPAddresses | Where-Object { $_ } | ForEach-Object { ([string]$_).Split('/')[0] })
            if ($Addresses -contains $Address.ToString()) {
                return [string]$Item.Name
            }
            continue
        }
        $Names = @(@($Item.Name) + @($Item.HostNames) | Where-Object { $_ } | ForEach-Object { ([string]$_).Split('.')[0] })
        if ($Names -contains $ShortName) {
            return [string]$Item.Name
        }
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

function Get-HvNodeName {
    <#
    .SYNOPSIS
        Returns the node name for a node FQDN, spelled as in the discovery (cluster node name).
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory)]
        [String] $Fqdn
    )

    $ShortName = $Fqdn.Split('.')[0]
    $NodeFact = @($HvNodeFacts) | Where-Object { $_ -and $_.ComputerName -eq $ShortName } | Select-Object -First 1
    if ($NodeFact) {
        return [string]$NodeFact.ComputerName
    }
    $ShortName
}

function Invoke-HvNodeCommand {
    <#
    .SYNOPSIS
        Runs a read-only script block on every node session of the current target.
    .DESCRIPTION
        Uses the sessions from the discovery ($HvNodeSessions) and adds the property NodeName (node name as
        in the discovery) to every returned object. A node that fails is reported as warning with
        FailureMessage ({0} = node FQDN, {1} = error) and does not stop the section.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,

        [Object[]] $ArgumentList,

        [Parameter(Mandatory)]
        [String] $FailureMessage
    )

    foreach ($Fqdn in @($HvNodeSessions.Keys)) {
        $CommandParams = @{
            Session = $HvNodeSessions[$Fqdn]
            ScriptBlock = $ScriptBlock
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('ArgumentList')) {
            $CommandParams['ArgumentList'] = $ArgumentList
        }
        try {
            $Result = Invoke-Command @CommandParams
            $NodeName = Get-HvNodeName -Fqdn $Fqdn
            foreach ($Item in @($Result | Where-Object { $_ })) {
                $Item | Add-Member -MemberType NoteProperty -Name 'NodeName' -Value $NodeName -Force
                $Item
            }
        } catch {
            Write-PScriboMessage -IsWarning ($FailureMessage -f $Fqdn, $_.Exception.Message)
        }
    }
}

function Resolve-HvHostSecurity {
    <#
    .SYNOPSIS
        Evaluates the hypervisor scheduler and the platform security settings of a Hyper-V host.
    .DESCRIPTION
        Pure function without remote calls. Input properties: SchedulerType (event 2 of the hypervisor),
        VbsStatus and SecurityServicesRunning (Win32_DeviceGuard), SecureBoot (UEFISecureBootEnabled, $null
        when the registry value is missing).

        SchedulerKey: ClassicNoSmt (1), Classic (2), Core (3), Root (4), Unknown
        VbsKey: Off (0), Configured (1, enabled but not running), Running (2), Unknown
        ServiceKeys: CredentialGuard, Hvci, SystemGuard, SmmProtection, KernelShadowStack, Hvpt, Service<n>
        SecureBootKey: On, Off, Unknown
        Findings: ClassicScheduler, SecureBootOff

        The classic scheduler is only reported with SMT enabled (type 2). With SMT disabled (type 1) virtual
        processors do not share a core, so the classic scheduler is not a security concern.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [Object] $HostSetting
    )

    $SchedulerKey = switch ([string]$HostSetting.SchedulerType) {
        '1' { 'ClassicNoSmt' }
        '2' { 'Classic' }
        '3' { 'Core' }
        '4' { 'Root' }
        default { 'Unknown' }
    }
    $VbsKey = switch ([string]$HostSetting.VbsStatus) {
        '0' { 'Off' }
        '1' { 'Configured' }
        '2' { 'Running' }
        default { 'Unknown' }
    }
    $ServiceKeys = @(foreach ($Service in @($HostSetting.SecurityServicesRunning | Where-Object { $null -ne $_ })) {
            switch ([string]$Service) {
                '0' { continue }
                '1' { 'CredentialGuard' }
                '2' { 'Hvci' }
                '3' { 'SystemGuard' }
                '4' { 'SmmProtection' }
                '5' { 'KernelShadowStack' }
                '6' { 'Hvpt' }
                default { "Service$Service" }
            }
        })
    $SecureBootKey = switch ([string]$HostSetting.SecureBoot) {
        { $_ -in '1', 'True' } { 'On'; break }
        { $_ -in '0', 'False' } { 'Off'; break }
        default { 'Unknown' }
    }

    $Findings = New-Object -TypeName System.Collections.Generic.List[String]
    if ($SchedulerKey -eq 'Classic') {
        $Findings.Add('ClassicScheduler')
    }
    if ($SecureBootKey -eq 'Off') {
        $Findings.Add('SecureBootOff')
    }

    [PSCustomObject]@{
        SchedulerKey = $SchedulerKey
        VbsKey = $VbsKey
        ServiceKeys = [String[]]$ServiceKeys
        SecureBootKey = $SecureBootKey
        Findings = [String[]]$Findings.ToArray()
    }
}

function Test-HvIpInSubnet {
    <#
    .SYNOPSIS
        Tests whether an IPv4 address is part of a subnet in CIDR notation (for example 192.0.2.0/24).
    .DESCRIPTION
        Pure function. The address may carry a prefix length ('192.0.2.10/24'); it is ignored.
        Returns $false for IPv6 or invalid values.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([Bool])]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [String] $IPAddress,

        [AllowNull()]
        [AllowEmptyString()]
        [String] $Subnet
    )

    $Address = $null
    $Network = $null
    $Parts = ([string]$Subnet).Split('/')
    $Prefix = 0
    if ($Parts.Count -ne 2 -or -not [int]::TryParse($Parts[1], [ref]$Prefix) -or $Prefix -lt 0 -or $Prefix -gt 32) {
        return $false
    }
    if (-not [System.Net.IPAddress]::TryParse(([string]$IPAddress).Split('/')[0], [ref]$Address) -or
        -not [System.Net.IPAddress]::TryParse($Parts[0], [ref]$Network) -or
        $Address.AddressFamily -ne 'InterNetwork' -or $Network.AddressFamily -ne 'InterNetwork') {
        return $false
    }
    $AddressBytes = $Address.GetAddressBytes()
    $NetworkBytes = $Network.GetAddressBytes()
    for ($Index = 0; $Index -lt 4; $Index++) {
        $Bits = [math]::Min([math]::Max($Prefix - (8 * $Index), 0), 8)
        $Mask = [byte]((0xFF -shl (8 - $Bits)) -band 0xFF)
        if (($AddressBytes[$Index] -band $Mask) -ne ($NetworkBytes[$Index] -band $Mask)) {
            return $false
        }
    }
    $true
}

function Resolve-HvNetworkFinding {
    <#
    .SYNOPSIS
        Evaluates the virtual switch, RDMA and DCB configuration of one Hyper-V host.
    .DESCRIPTION
        Pure function without remote calls. Input properties of NetworkData:
        Switches (Name, EmbeddedTeaming, Members, LoadBalancingAlgorithm),
        HostVnics (Name, SwitchName, RdmaEnabled, MappedAdapter, IPAddresses),
        Adapters (Name, Status, SwitchName, RdmaCapable, RdmaEnabled, RdmaType, DcbEnabled, IPAddresses),
        Qos (Available, PfcPriorities, TrafficClasses (Name, Priority, Algorithm), Policies (Name, Priority,
        Template, NetDirectPort), DcbxWilling).

        RdmaEnabled is empty for adapters without RDMA support. RdmaType uses the values of
        *NetworkDirectTechnology: 1 iWARP, 2 InfiniBand, 3 RoCE, 4 RoCEv2.

        StorageSubnet lists the subnets of the cluster networks that carry cluster and storage traffic
        (role Cluster only or Cluster and client). Only adapters with an address in these subnets are rated
        for RDMA, so management and VM switches without RDMA are not reported. Without subnets, every
        adapter with an address counts.

        Returns one object per finding with Check and Object:
        SetLoadBalancing  SET switch that does not use the Hyper-V port load balancing algorithm
        RdmaDisabled      S2D host: RDMA capable adapter or host vNIC on a storage network with RDMA disabled,
                          or SET member below an RDMA host vNIC with RDMA disabled
        NoStorageRdma     S2D host without any RDMA enabled adapter on a storage network
        RocePfc           RoCE adapter with RDMA enabled but without PFC or with DCB disabled on the adapter
        DcbxWilling       PFC configured and the host accepts DCBX settings from the switch
        DcbTrafficClass   PFC and a QoS policy for SMB or cluster traffic exist, but no ETS traffic class
                          covers its priority (Object: SMB or Cluster)
        VnicTeamMapping   RDMA host vNIC on a SET switch with two or more members without a team mapping
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [Object] $NetworkData,

        # Storage Spaces Direct uses RDMA for the storage traffic between the nodes.
        [Switch] $IsS2D,

        [AllowEmptyCollection()]
        [String[]] $StorageSubnet = @()
    )

    $Subnets = @($StorageSubnet | Where-Object { $_ })
    $OnStorageNetwork = {
        param ($Item)
        $Addresses = @($Item.IPAddresses | Where-Object { $_ })
        if ($Subnets.Count -eq 0) {
            return ($Addresses.Count -gt 0)
        }
        foreach ($Address in $Addresses) {
            foreach ($Subnet in $Subnets) {
                if (Test-HvIpInSubnet -IPAddress $Address -Subnet $Subnet) {
                    return $true
                }
            }
        }
        $false
    }

    $Switches = @($NetworkData.Switches | Where-Object { $_ })
    $Adapters = @($NetworkData.Adapters | Where-Object { $_ })
    $Vnics = @($NetworkData.HostVnics | Where-Object { $_ })

    foreach ($SwitchItem in $Switches) {
        if ([string]$SwitchItem.EmbeddedTeaming -eq 'True' -and
            -not [string]::IsNullOrEmpty([string]$SwitchItem.LoadBalancingAlgorithm) -and
            [string]$SwitchItem.LoadBalancingAlgorithm -ne 'HyperVPort') {
            [PSCustomObject]@{ Check = 'SetLoadBalancing'; Object = [string]$SwitchItem.Name }
        }
    }

    if ($IsS2D) {
        $StorageRdma = 0
        $Reported = New-Object -TypeName System.Collections.Generic.List[String]
        # Adapters and host vNICs that carry a storage network.
        foreach ($Item in @($Adapters | Where-Object { [string]$_.Status -eq 'Up' }) + $Vnics) {
            if (-not (& $OnStorageNetwork $Item)) {
                continue
            }
            if ([string]$Item.RdmaEnabled -eq 'True') {
                $StorageRdma++
            } elseif ([string]$Item.RdmaEnabled -eq 'False') {
                $Reported.Add([string]$Item.Name)
                [PSCustomObject]@{ Check = 'RdmaDisabled'; Object = [string]$Item.Name }
            }
        }
        # Physical members of a SET switch that carries RDMA host vNICs need RDMA as well.
        foreach ($SwitchItem in $Switches) {
            $RdmaVnics = @($Vnics | Where-Object { [string]$_.SwitchName -eq [string]$SwitchItem.Name -and [string]$_.RdmaEnabled -eq 'True' })
            if ($RdmaVnics.Count -eq 0) {
                continue
            }
            foreach ($Member in @($SwitchItem.Members | Where-Object { $_ })) {
                $Adapter = $Adapters | Where-Object { [string]$_.Name -eq [string]$Member } | Select-Object -First 1
                if ($Adapter -and [string]$Adapter.Status -eq 'Up' -and [string]$Adapter.RdmaEnabled -eq 'False' -and
                    -not $Reported.Contains([string]$Adapter.Name)) {
                    $Reported.Add([string]$Adapter.Name)
                    [PSCustomObject]@{ Check = 'RdmaDisabled'; Object = [string]$Adapter.Name }
                }
            }
        }
        if ($StorageRdma -eq 0) {
            [PSCustomObject]@{ Check = 'NoStorageRdma'; Object = '' }
        }
    }

    $PfcPriorities = @($NetworkData.Qos.PfcPriorities | Where-Object { $null -ne $_ -and [string]$_ -ne '' } | ForEach-Object { [string]$_ })
    foreach ($Adapter in $Adapters) {
        if ([string]$Adapter.RdmaEnabled -eq 'True' -and [string]$Adapter.RdmaType -in '3', '4' -and
            ($PfcPriorities.Count -eq 0 -or [string]$Adapter.DcbEnabled -ne 'True')) {
            [PSCustomObject]@{ Check = 'RocePfc'; Object = [string]$Adapter.Name }
        }
    }

    if ($PfcPriorities.Count -gt 0 -and [string]$NetworkData.Qos.DcbxWilling -eq 'True') {
        [PSCustomObject]@{ Check = 'DcbxWilling'; Object = '' }
    }

    if ($PfcPriorities.Count -gt 0) {
        $EtsPriorities = @($NetworkData.Qos.TrafficClasses | Where-Object {
                $_ -and [string]$_.Algorithm -eq 'ETS' -and [string]$_.Name -ne '[Default]'
            } | ForEach-Object { @($_.Priority) } | ForEach-Object { [string]$_ })
        $Policies = @($NetworkData.Qos.Policies | Where-Object { $_ })
        $Traffic = [ordered]@{
            SMB = @($Policies | Where-Object { [string]$_.Template -in 'SMB', 'SMBDirect' -or [string]$_.NetDirectPort -eq '445' })
            Cluster = @($Policies | Where-Object { [string]$_.Template -eq 'Cluster' })
        }
        foreach ($Kind in @($Traffic.Keys)) {
            foreach ($Policy in $Traffic[$Kind]) {
                if ([string]$Policy.Priority -ne '' -and $EtsPriorities -notcontains [string]$Policy.Priority) {
                    [PSCustomObject]@{ Check = 'DcbTrafficClass'; Object = $Kind }
                    break
                }
            }
        }
    }

    foreach ($Vnic in $Vnics) {
        $SwitchItem = $Switches | Where-Object { [string]$_.Name -eq [string]$Vnic.SwitchName } | Select-Object -First 1
        if ([string]$Vnic.RdmaEnabled -eq 'True' -and $SwitchItem -and [string]$SwitchItem.EmbeddedTeaming -eq 'True' -and
            @($SwitchItem.Members | Where-Object { $_ }).Count -ge 2 -and [string]::IsNullOrEmpty([string]$Vnic.MappedAdapter)) {
            [PSCustomObject]@{ Check = 'VnicTeamMapping'; Object = [string]$Vnic.Name }
        }
    }
}

function ConvertTo-HvHealthSeverity {
    <#
    .SYNOPSIS
        Maps a storage health status to a severity.
    .DESCRIPTION
        Pure function. Healthy = Ok, Unhealthy = Critical, every other value (Warning, Unknown) = Warning.
        Integer values of the Storage module (0 Healthy, 1 Warning, 2 Unhealthy) are accepted as well.
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
        [Object] $HealthStatus
    )

    switch ([string]$HealthStatus) {
        { $_ -in 'Healthy', '0' } { return 'Ok' }
        { $_ -in 'Unhealthy', '2' } { return 'Critical' }
        default { return 'Warning' }
    }
}

function ConvertTo-HvFaultSeverity {
    <#
    .SYNOPSIS
        Maps the perceived severity of a health fault (Get-HealthFault) to a severity.
    .DESCRIPTION
        Pure function. Major, critical and fatal faults are Critical, minor faults and degraded or warning
        states are Warning, information is Ok. Accepts the text and the numeric CIM values.
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
        [Object] $PerceivedSeverity
    )

    $Value = [string]$PerceivedSeverity
    if ($Value -match '^(5|6|7)$' -or $Value -match 'Major|Critical|Fatal|Non-recoverable') {
        return 'Critical'
    }
    if ($Value -match '^2$' -or $Value -match '^Information') {
        return 'Ok'
    }
    'Warning'
}

function Resolve-HvResiliency {
    <#
    .SYNOPSIS
        Returns a key for the resiliency of a Storage Spaces virtual disk or storage tier.
    .DESCRIPTION
        Pure function. Keys: Simple, TwoWayMirror, ThreeWayMirror, NestedTwoWayMirror, SingleParity,
        DualParity, NestedParity, or the raw resiliency setting name.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [String] $ResiliencySettingName,

        [AllowNull()]
        [Object] $NumberOfDataCopies,

        [AllowNull()]
        [Object] $PhysicalDiskRedundancy
    )

    $Copies = [string]$NumberOfDataCopies
    $Redundancy = [string]$PhysicalDiskRedundancy
    switch ($ResiliencySettingName) {
        'Simple' { return 'Simple' }
        'Mirror' {
            if ($Copies -eq '4') { return 'NestedTwoWayMirror' }
            if ($Copies -eq '3' -or $Redundancy -eq '2') { return 'ThreeWayMirror' }
            return 'TwoWayMirror'
        }
        'Parity' {
            if ($Copies -eq '2') { return 'NestedParity' }
            if ($Redundancy -eq '2') { return 'DualParity' }
            return 'SingleParity'
        }
        default { return [string]$ResiliencySettingName }
    }
}

function Resolve-HvS2DReserve {
    <#
    .SYNOPSIS
        Calculates the recommended reserve capacity of a Storage Spaces Direct pool.
    .DESCRIPTION
        Pure function. Microsoft recommends keeping the capacity of one capacity drive per node unallocated,
        up to four drives, so that the pool can repair in place after a drive failure. Cache drives (usage
        Journal) do not add capacity and are ignored.

        Returns FreeBytes, ReserveBytes, ReserveMet and the allocated percentage.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [Double] $PoolSize,

        [Parameter(Mandatory)]
        [Double] $AllocatedSize,

        # Pool disks: Size, Usage
        [AllowEmptyCollection()]
        [Object[]] $PhysicalDisk = @(),

        [Int] $NodeCount = 1
    )

    $CapacityDisks = @($PhysicalDisk | Where-Object { $_ -and [string]$_.Usage -ne 'Journal' -and [string]$_.Usage -ne 'Retired' })
    $LargestDisk = 0
    if ($CapacityDisks.Count -gt 0) {
        $LargestDisk = [double](($CapacityDisks | Measure-Object -Property Size -Maximum).Maximum)
    }
    $ReserveBytes = [math]::Min([math]::Max($NodeCount, 1), 4) * $LargestDisk
    $FreeBytes = [math]::Max($PoolSize - $AllocatedSize, 0)

    [PSCustomObject]@{
        FreeBytes = $FreeBytes
        ReserveBytes = $ReserveBytes
        ReserveMet = ($FreeBytes -ge $ReserveBytes)
        AllocatedPercent = $(if ($PoolSize -gt 0) { $AllocatedSize / $PoolSize * 100 } else { $null })
    }
}

function Resolve-HvStoragePath {
    <#
    .SYNOPSIS
        Evaluates the path redundancy and the iSCSI sessions of shared block storage on one host.
    .DESCRIPTION
        Pure function without remote calls. Input properties of StorageData:
        MpioInstalled, Disks (Number, FriendlyName, BusType, Paths), IscsiSessions (TargetNodeAddress,
        IsConnected, IsPersistent).

        Paths is the number of MPIO paths of a disk; an empty value means the disk is not claimed by MPIO
        and has a single path.

        Returns one object per finding with Check, Object and Severity:
        MpioMissing        shared disks exist but the Multipath I/O feature is not installed (Warning)
        SinglePath         shared disk with fewer than two paths (Warning)
        IscsiNotConnected  iSCSI session that is not connected (Critical)
        IscsiNotPersistent iSCSI session that is not restored after a restart (Warning)
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [Object] $StorageData
    )

    $Disks = @($StorageData.Disks | Where-Object { $_ })
    if ($Disks.Count -gt 0 -and [string]$StorageData.MpioInstalled -ne 'True') {
        [PSCustomObject]@{ Check = 'MpioMissing'; Object = ''; Severity = 'Warning' }
    }
    foreach ($Disk in $Disks) {
        $Paths = 1
        if ($null -ne $Disk.Paths -and [string]$Disk.Paths -ne '') {
            $Paths = [int]$Disk.Paths
        }
        if ($Paths -lt 2) {
            $Name = if ($Disk.FriendlyName) { '{0} ({1})' -f $Disk.Number, $Disk.FriendlyName } else { [string]$Disk.Number }
            [PSCustomObject]@{ Check = 'SinglePath'; Object = $Name; Severity = 'Warning' }
        }
    }

    foreach ($Session in @($StorageData.IscsiSessions | Where-Object { $_ })) {
        if ([string]$Session.IsConnected -ne 'True') {
            [PSCustomObject]@{ Check = 'IscsiNotConnected'; Object = [string]$Session.TargetNodeAddress; Severity = 'Critical' }
        } elseif ([string]$Session.IsPersistent -ne 'True') {
            [PSCustomObject]@{ Check = 'IscsiNotPersistent'; Object = [string]$Session.TargetNodeAddress; Severity = 'Warning' }
        }
    }
}

function ConvertTo-HvResourceSeverity {
    <#
    .SYNOPSIS
        Maps the state of a cluster resource to a severity: Online = Ok, Failed = Critical, other = Warning.
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
        [Object] $State
    )

    switch ([string]$State) {
        'Online' { return 'Ok' }
        'Failed' { return 'Critical' }
        default { return 'Warning' }
    }
}

function Resolve-HvVmFinding {
    <#
    .SYNOPSIS
        Evaluates the configuration of one virtual machine.
    .DESCRIPTION
        Pure function without remote calls. Input properties of VM: CheckpointCount, IsClustered, Version,
        Adapters (SwitchName).

        Findings:
        Checkpoints           the VM has checkpoints
        NotClustered          the VM runs on a cluster node but is not a clustered role
        ConfigurationVersion  the configuration version is lower than the default version of the host
        NetworkDisconnected   a network adapter is not connected to a virtual switch
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory)]
        [Object] $VM,

        [Switch] $IsCluster,

        [AllowNull()]
        [AllowEmptyString()]
        [String] $HostDefaultVersion
    )

    if ([int]$VM.CheckpointCount -gt 0) {
        'Checkpoints'
    }
    if ($IsCluster -and [string]$VM.IsClustered -ne 'True') {
        'NotClustered'
    }
    $VmVersion = $null
    $DefaultVersion = $null
    if ([version]::TryParse([string]$VM.Version, [ref]$VmVersion) -and
        [version]::TryParse($HostDefaultVersion, [ref]$DefaultVersion) -and $VmVersion -lt $DefaultVersion) {
        'ConfigurationVersion'
    }
    if (@($VM.Adapters | Where-Object { $_ -and [string]::IsNullOrEmpty([string]$_.SwitchName) }).Count -gt 0) {
        'NetworkDisconnected'
    }
}

function Resolve-HvClusterGroup {
    <#
    .SYNOPSIS
        Selects the cluster roles and rates their state.
    .DESCRIPTION
        Pure function without remote calls. Returns the roles as Failover Cluster Manager shows them: core
        groups (cluster core resources, available storage, storage pool, SDDC) are left out.

        PriorityKey: High (3000), Medium (2000), Low (1000), NoAutoStart (0), or the raw value
        StateSeverity: Ok (Online or Offline), Warning (partially online or pending), Critical (Failed)

        A role that is offline is not rated, because virtual machines are often shut down on purpose.
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
        [Object[]] $Group
    )

    $InfrastructureTypes = @('Cluster', 'AvailableStorage', 'ClusterStoragePool', 'CoreSddc', 'ClusterUpdate')
    foreach ($Item in @($Group | Where-Object { $_ })) {
        if ([string]$Item.IsCoreGroup -eq 'True' -or $InfrastructureTypes -contains [string]$Item.GroupType) {
            continue
        }
        $PriorityKey = switch ([string]$Item.Priority) {
            '3000' { 'High' }
            '2000' { 'Medium' }
            '1000' { 'Low' }
            '0' { 'NoAutoStart' }
            default { [string]$Item.Priority }
        }
        $State = [string]$Item.State
        $StateSeverity = switch ($State) {
            { $_ -in 'Online', 'Offline' } { 'Ok'; break }
            'Failed' { 'Critical'; break }
            default { 'Warning' }
        }
        [PSCustomObject]@{
            Name = [string]$Item.Name
            GroupType = [string]$Item.GroupType
            OwnerNode = [string]$Item.OwnerNode
            State = $State
            StateSeverity = $StateSeverity
            PriorityKey = $PriorityKey
        }
    }
}

function Resolve-HvCsvState {
    <#
    .SYNOPSIS
        Rates the state, I/O mode and free space of Cluster Shared Volumes.
    .DESCRIPTION
        Pure function without remote calls.

        StateSeverity: Ok (Online), Warning (maintenance mode or another state), Critical (Failed, Offline)
        IoModeKey: Direct, ReFsRedirected, Redirected, Unknown
        IoSeverity: Ok, Warning (redirected for a reason other than ReFS)
        FreeSeverity: Ok, Warning (below WarningFreePercent), Critical (below CriticalFreePercent)

        ReFS volumes always use file system redirected I/O on every node. That is the expected mode and is
        not rated.
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
        [Object[]] $Volume,

        # One entry per volume and node: Name, Node, StateInfo, FileSystemRedirectedIOReason, BlockRedirectedIOReason
        [AllowEmptyCollection()]
        [Object[]] $NodeState = @(),

        [Double] $WarningFreePercent = 20,

        [Double] $CriticalFreePercent = 10
    )

    foreach ($Item in @($Volume | Where-Object { $_ })) {
        $State = [string]$Item.State
        $StateSeverity = if ($State -in 'Failed', 'Offline') {
            'Critical'
        } elseif ($State -ne 'Online' -or [string]$Item.MaintenanceMode -eq 'True') {
            'Warning'
        } else {
            'Ok'
        }

        $States = @($NodeState | Where-Object { $_ -and [string]$_.Name -eq [string]$Item.Name })
        $Redirected = @($States | Where-Object { [string]$_.StateInfo -ne 'Direct' })
        $Unexpected = @($Redirected | Where-Object {
                -not ([string]$_.StateInfo -eq 'FileSystemRedirected' -and [string]$_.FileSystemRedirectedIOReason -eq 'FileSystemReFs')
            })
        $IoModeKey = if ($States.Count -eq 0) {
            'Unknown'
        } elseif ($Redirected.Count -eq 0) {
            'Direct'
        } elseif ($Unexpected.Count -eq 0) {
            'ReFsRedirected'
        } else {
            'Redirected'
        }

        $FreePercent = $null
        if ($null -ne $Item.FreePercent -and [string]$Item.FreePercent -ne '') {
            $FreePercent = [double]$Item.FreePercent
        }
        $FreeSeverity = if ($null -eq $FreePercent) {
            'Ok'
        } elseif ($FreePercent -lt $CriticalFreePercent) {
            'Critical'
        } elseif ($FreePercent -lt $WarningFreePercent) {
            'Warning'
        } else {
            'Ok'
        }

        [PSCustomObject]@{
            Name = [string]$Item.Name
            State = $State
            StateSeverity = $StateSeverity
            IoModeKey = $IoModeKey
            IoSeverity = $(if ($IoModeKey -eq 'Redirected') { 'Warning' } else { 'Ok' })
            RedirectedNodes = [String[]]@($Unexpected | ForEach-Object { [string]$_.Node } | Sort-Object -Unique)
            FreePercent = $FreePercent
            FreeSeverity = $FreeSeverity
        }
    }
}

function Resolve-HvCauState {
    <#
    .SYNOPSIS
        Evaluates the Cluster-Aware Updating configuration.
    .DESCRIPTION
        Pure function without remote calls. RoleParameter is the list of name/value pairs returned by
        Get-CauClusterRole (or a hashtable); LastRunResult is the result of the most recent updating run.

        Findings: NoSelfUpdatingRole, SelfUpdatingRoleOffline, LastRunNotSucceeded
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [AllowNull()]
        [Object] $RoleParameter,

        [AllowNull()]
        [AllowEmptyString()]
        [String] $LastRunResult
    )

    $Settings = [ordered]@{}
    if ($RoleParameter -is [System.Collections.IDictionary]) {
        foreach ($Key in $RoleParameter.Keys) {
            $Settings[[string]$Key] = $RoleParameter[$Key]
        }
    } else {
        foreach ($Item in @($RoleParameter | Where-Object { $_ })) {
            if ($Item.PSObject.Properties['Name']) {
                $Settings[[string]$Item.Name] = $Item.Value
            }
        }
    }

    $HasRole = ($Settings.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Settings['ResourceGroupName']))
    $RoleOnline = ($HasRole -and [string]$Settings['Status'] -eq 'Online')

    $Findings = New-Object -TypeName System.Collections.Generic.List[String]
    if (-not $HasRole) {
        $Findings.Add('NoSelfUpdatingRole')
    } elseif (-not $RoleOnline) {
        $Findings.Add('SelfUpdatingRoleOffline')
    }
    if (-not [string]::IsNullOrWhiteSpace($LastRunResult) -and $LastRunResult -ne 'Succeeded') {
        $Findings.Add('LastRunNotSucceeded')
    }

    [PSCustomObject]@{
        HasSelfUpdatingRole = $HasRole
        SelfUpdatingRoleOnline = $RoleOnline
        Settings = $Settings
        Findings = [String[]]$Findings.ToArray()
    }
}

function Get-HvReportCulture {
    <#
    .SYNOPSIS
        Returns the culture of the report language.
    .DESCRIPTION
        Numbers and dates follow the report language (Report.Language), not the culture of the machine that
        generates the report. Falls back to the current culture.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([System.Globalization.CultureInfo])]
    param ()

    $ReportConfig = Get-Variable -Name 'Report' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($ReportConfig -and $ReportConfig.Language) {
        try {
            return [System.Globalization.CultureInfo]::GetCultureInfo([string]$ReportConfig.Language)
        } catch {
            Write-Verbose "Unknown report language '$($ReportConfig.Language)', using the current culture."
        }
    }
    Get-Culture
}

function Resolve-HvKeyedDeviation {
    <#
    .SYNOPSIS
        Compares keyed values between hosts, for example hotfixes, features or settings.
    .DESCRIPTION
        Pure function for node-to-node consistency checks. Every input object has a Name (host) and Items, a
        list of Key/Value pairs. A key that a host does not have counts as missing.

        For every key, the value most hosts share is the reference; hosts with another value or without the
        key are deviations. If no single value is the most common, every host is reported with an empty
        reference. With PreferPresent, the reference is taken from the hosts that have the key, so a hotfix
        or feature that is missing on some hosts is reported for those hosts, even in a two-node cluster.

        Returns Name, Key, Value, Missing and Reference for every deviation. Keys keep the order in which
        they first appear.
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

        [Switch] $PreferPresent
    )

    $Hosts = @($InputObject | Where-Object { $_ })
    if ($Hosts.Count -lt 2) {
        return
    }

    $Keys = New-Object -TypeName System.Collections.Generic.List[String]
    $Lookup = @{}
    foreach ($HostItem in $Hosts) {
        $Values = @{}
        foreach ($Item in @($HostItem.Items | Where-Object { $_ })) {
            $Key = [string]$Item.Key
            if (-not $Keys.Contains($Key)) {
                $Keys.Add($Key)
            }
            $Values[$Key] = [string]$Item.Value
        }
        $Lookup[[string]$HostItem.Name] = $Values
    }

    foreach ($Key in $Keys) {
        $Entries = foreach ($HostItem in $Hosts) {
            $Values = $Lookup[[string]$HostItem.Name]
            $Present = $Values.ContainsKey($Key)
            [PSCustomObject]@{
                Name = [string]$HostItem.Name
                Missing = (-not $Present)
                Value = $(if ($Present) { $Values[$Key] } else { $null })
            }
        }
        $Entries = @($Entries)
        $Distinct = @($Entries | ForEach-Object { if ($_.Missing) { 'm' } else { "v:$($_.Value)" } } | Select-Object -Unique)
        if ($Distinct.Count -lt 2) {
            continue
        }

        $Candidates = if ($PreferPresent) { @($Entries | Where-Object { -not $_.Missing }) } else { $Entries }
        $Groups = @($Candidates | Group-Object -Property { if ($_.Missing) { 'm' } else { "v:$($_.Value)" } } |
                Sort-Object -Property Count -Descending)
        $Reference = $null
        $ReferenceIsMissing = $false
        if ($Groups.Count -eq 1 -or ($Groups.Count -gt 1 -and $Groups[0].Count -gt $Groups[1].Count)) {
            $Winner = $Groups[0].Group[0]
            $ReferenceIsMissing = $Winner.Missing
            $Reference = $Winner.Value
        }
        $HasReference = ($Groups.Count -eq 1 -or ($Groups.Count -gt 1 -and $Groups[0].Count -gt $Groups[1].Count))

        foreach ($Entry in $Entries) {
            $IsDeviation = if (-not $HasReference) {
                $true
            } elseif ($ReferenceIsMissing) {
                -not $Entry.Missing
            } else {
                $Entry.Missing -or $Entry.Value -ne $Reference
            }
            if ($IsDeviation) {
                [PSCustomObject]@{
                    Name = $Entry.Name
                    Key = $Key
                    Value = $Entry.Value
                    Missing = $Entry.Missing
                    Reference = $Reference
                    ReferenceIsMissing = ($HasReference -and $ReferenceIsMissing)
                    HasReference = $HasReference
                }
            }
        }
    }
}

function ConvertTo-HvSize {
    <#
    .SYNOPSIS
        Formats a size in bytes as GB or TB for a report table cell.
    .DESCRIPTION
        Sizes from 1 TB are shown in TB with two decimals, smaller sizes in GB with up to one decimal.
        Uses binary units (1 GB = 1024^3 bytes), like the Windows storage tools. Empty values become '--'.
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
        [Object] $Bytes,

        [System.Globalization.CultureInfo] $Culture = (Get-HvReportCulture)
    )

    if ($null -eq $Bytes -or [string]$Bytes -eq '') {
        return '--'
    }
    $Value = [double]$Bytes
    if ($Value -ge 1TB) {
        return [string]::Format($Culture, '{0} TB', [math]::Round($Value / 1TB, 2))
    }
    [string]::Format($Culture, '{0} GB', [math]::Round($Value / 1GB, 1))
}

function ConvertTo-HvPercent {
    <#
    .SYNOPSIS
        Formats a percentage for a report table cell, for example '97.4 %'. Empty values become '--'.
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
        [Object] $Value,

        [Int] $Decimals = 1,

        [System.Globalization.CultureInfo] $Culture = (Get-HvReportCulture)
    )

    if ($null -eq $Value -or [string]$Value -eq '') {
        return '--'
    }
    [string]::Format($Culture, '{0} %', [math]::Round([double]$Value, $Decimals))
}

function Get-HvMaxSeverity {
    <#
    .SYNOPSIS
        Returns Critical if any of the given severities is Critical, otherwise Warning.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [Parameter(Position = 0)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [String[]] $Severity
    )

    if (@($Severity) -contains 'Critical') {
        return 'Critical'
    }
    'Warning'
}

function Write-HvHealthCheck {
    <#
    .SYNOPSIS
        Writes the text of a health check finding and records it for the Health Check Summary.
    .DESCRIPTION
        Outputs a paragraph with finding and recommendation (and a blank line) for the section, and adds the
        finding to $HvHealthFindings, which the Health Check Summary at the end of the report lists.
        Area is the heading of the section that reports the finding.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Github:         ex0th
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String] $Area,

        [ValidateSet('Critical', 'Warning')]
        [String] $Severity = 'Warning',

        [Parameter(Mandatory)]
        [String] $Finding,

        [AllowEmptyString()]
        [String] $Recommendation = ''
    )

    $Findings = Get-Variable -Name 'HvHealthFindings' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $Findings) {
        $Findings.Add([PSCustomObject]@{
                Area = $Area
                Severity = $Severity
                Finding = $Finding
                Recommendation = $Recommendation
            })
    }
    Paragraph ((@($Finding, $Recommendation) | Where-Object { $_ }) -join ' ')
    BlankLine
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
