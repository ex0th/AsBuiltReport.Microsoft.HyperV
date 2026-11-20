function Invoke-AsBuiltReport.Microsoft.HyperV {
    <#
    .SYNOPSIS
        PowerShell script to document the configuration of Microsoft Hyper-V hosts and failover clusters in Word/HTML/Text formats
    .DESCRIPTION
        Documents the configuration of Microsoft Hyper-V hosts and failover clusters in Word/HTML/Text formats using PScribo.
        A target can be a failover cluster name, any cluster node or a standalone Hyper-V host (FQDN).
        Cluster nodes are discovered automatically and every cluster is documented once.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Twitter:        @AsBuiltReport
        Github:         AsBuiltReport
        Credits:        Iain Brighton (@iainbrighton) - PScribo module

    .EXAMPLE
        PS C:\> New-AsBuiltReport -Report Microsoft.HyperV -Target 'cluster01.example.com' -Credential $Credential -Format Html,Word -OutputFolderPath 'C:\Reports'

    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV
    #>

    # Do not remove or add to these parameters
    [CmdletBinding()]
    param (
        [String[]] $Target,
        [PSCredential] $Credential
    )

    # Display report module information using Core function
    Write-ReportModuleInfo -ModuleName 'Microsoft.HyperV'

    # Import Report Configuration
    $script:Report = $ReportConfig.Report
    $script:InfoLevel = $ReportConfig.InfoLevel
    $script:Options = $ReportConfig.Options
    $LocalizedData = $reportTranslate.InvokeAsBuiltReportMicrosoftHyperV

    # Used to set values to TitleCase where required
    $script:TextInfo = (Get-Culture).TextInfo

    # Same connection settings for the target and for every discovered node
    $ConnectParams = @{
        Authentication = $(if ($Options.WinRMAuthentication) { [string]$Options.WinRMAuthentication } else { 'Negotiate' })
        UseSSL = [bool]$Options.WinRMUseSSL
        Port = [int]$Options.WinRMPort
    }
    if ($Credential) {
        $ConnectParams['Credential'] = $Credential
    }
    $StorageTopology = @($Options.StorageTopology | Where-Object { $_ })
    if ($StorageTopology.Count -eq 0) {
        $StorageTopology = @('Auto')
    }

    # Several nodes of one cluster may be passed as targets; the cluster is documented once.
    $DocumentedClusters = New-Object -TypeName System.Collections.Generic.List[String]

    #region foreach loop
    foreach ($System in $Target) {

        # Kerberos needs a DNS name, and node FQDNs are derived from the cluster DNS domain.
        if ($System -match '^\d{1,3}(\.\d{1,3}){3}$' -or $System -notmatch '\.') {
            throw ($LocalizedData.FqdnRequired -f $System)
        }

        $TargetSession = $null
        $script:HvClusterSession = $null
        $script:HvNodeSessions = [ordered]@{}
        $script:HvNodeFacts = @()
        $script:HvEnvironment = $null
        $script:HvObjectName = $null

        try {
            Write-PScriboMessage ($LocalizedData.Connecting -f $System)
            $TargetSession = Connect-HvNode -ComputerName $System @ConnectParams

            #region Discovery
            $ClusterFact = Get-HvClusterFact -Session $TargetSession
            if ($ClusterFact.IsCluster) {
                $ClusterFqdn = ('{0}.{1}' -f $ClusterFact.Name, $ClusterFact.Domain).ToLowerInvariant()
                if ($DocumentedClusters.Contains($ClusterFqdn)) {
                    Write-PScriboMessage ($LocalizedData.ClusterAlreadyDocumented -f $System, $ClusterFqdn)
                    continue
                }
                $DocumentedClusters.Add($ClusterFqdn)
                $SectionName = $ClusterFqdn
                $script:HvObjectName = [string]$ClusterFact.Name
                $script:HvClusterSession = $TargetSession
                # Node names are taken from the cluster, so every section spells them the same way.
                $NodeTargets = @($ClusterFact.Nodes | ForEach-Object {
                        [PSCustomObject]@{
                            Name = [string]$_.Name
                            Fqdn = ('{0}.{1}' -f $_.Name, $ClusterFact.Domain).ToLowerInvariant()
                        }
                    })
                Write-PScriboMessage ($LocalizedData.ClusterFound -f $ClusterFqdn, $NodeTargets.Count)
            } else {
                $SectionName = $System.ToLowerInvariant()
                $script:HvObjectName = $System.Split('.')[0].ToUpperInvariant()
                $NodeTargets = @([PSCustomObject]@{ Name = $HvObjectName; Fqdn = $SectionName })
                Write-PScriboMessage ($LocalizedData.StandaloneFound -f $System)
            }

            # One session per host. Connecting to each node directly avoids the Kerberos double hop.
            $NodeFacts = foreach ($NodeTarget in $NodeTargets) {
                try {
                    if ($ClusterFact.IsCluster) {
                        $NodeSession = Connect-HvNode -ComputerName $NodeTarget.Fqdn @ConnectParams
                    } else {
                        $NodeSession = $TargetSession
                    }
                    $script:HvNodeSessions[$NodeTarget.Fqdn] = $NodeSession
                    $NodeFact = Get-HvNodeFact -Session $NodeSession
                    $NodeFact.ComputerName = $NodeTarget.Name
                    $NodeFact
                } catch {
                    Write-PScriboMessage -IsWarning ($LocalizedData.NodeUnreachable -f $NodeTarget.Fqdn, $_.Exception.Message)
                    [PSCustomObject]@{
                        ComputerName = $NodeTarget.Name
                        Reachable = $false
                    }
                }
            }
            # Sections reuse the node facts instead of querying the hosts again.
            $script:HvNodeFacts = @($NodeFacts | Where-Object { $_ })
            # Individual probes that failed are reported, but do not stop the report.
            foreach ($ProbeError in @($ClusterFact.Errors | Where-Object { $_ })) {
                Write-PScriboMessage -IsWarning ($LocalizedData.ProbeFailed -f $SectionName, $ProbeError)
            }
            foreach ($NodeFact in @($NodeFacts | Where-Object { $_.Errors })) {
                foreach ($ProbeError in @($NodeFact.Errors)) {
                    Write-PScriboMessage -IsWarning ($LocalizedData.ProbeFailed -f $NodeFact.ComputerName, $ProbeError)
                }
            }

            $script:HvEnvironment = Resolve-HvEnvironmentType -ClusterFact $ClusterFact -NodeFact $HvNodeFacts -StorageTopology $StorageTopology
            Write-PScriboMessage ($LocalizedData.EnvironmentDetected -f $SectionName, $HvEnvironment.EnvironmentType, ($HvEnvironment.StorageTopology -join ', '), $HvEnvironment.DetectionMode)
            #endregion Discovery

            #region Report Sections
            Section -Style Heading1 $SectionName {
                Paragraph ($LocalizedData.ParagraphTarget -f $SectionName)
                BlankLine

                # Detected environment type, storage topology and the evidence behind it
                Get-AbrHvEnvironmentType

                if ($HvEnvironment.IsCluster) {
                    # Cluster configuration and node summary
                    Get-AbrHvClusterOverview
                    # Quorum model, witness and node votes
                    Get-AbrHvClusterQuorum
                    # Cluster networks, their use for live migration and the node interfaces
                    Get-AbrHvClusterNetwork
                }

                # Live migration settings of the cluster and of every host (also for standalone hosts)
                Get-AbrHvLiveMigration

                # Planned sections (see README roadmap):
                # Cluster: Cluster-Aware Updating
                # Host: Hardware, OS build, Hyper-V settings, NICs, SET switches, RDMA/DCB
                # Storage by topology: S2D pool/virtual disks/cache/fault domains, iSCSI/FC/MPIO, SMB shares
                # Consistency: node-to-node comparison as health checks
                # Virtual machines (optional)
            }
            #endregion Report Sections
        } catch {
            Write-PScriboMessage -IsWarning ($LocalizedData.TargetFailed -f $System, $_.Exception.Message)
        } finally {
            $OpenSessions = @(@($TargetSession) + @($script:HvNodeSessions.Values) | Where-Object { $_ } | Sort-Object -Property Id -Unique)
            foreach ($OpenSession in $OpenSessions) {
                Remove-PSSession -Session $OpenSession -ErrorAction SilentlyContinue
            }
        }
    }
    #endregion foreach loop
}
