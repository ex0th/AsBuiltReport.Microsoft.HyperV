function Get-AbrHvNetworking {
    <#
    .SYNOPSIS
        Used by As Built Report to document the virtual switches, host networking, RDMA and DCB of every host.
    .DESCRIPTION
        Documents the virtual switches including Switch Embedded Teaming (SET), the host virtual network
        adapters with VLAN, RDMA and team mapping, the physical adapters with RDMA and jumbo frames, and the
        Data Center Bridging (DCB) configuration (PFC, traffic classes, QoS policies).
        Health checks highlight SET switches without Hyper-V port load balancing, disabled RDMA on S2D hosts,
        RoCE without PFC, DCBX willing mode and RDMA host vNICs without team mapping.
    .NOTES
        Version:        0.1.0
        Author:         Silas Süßmilch
        Twitter:        @AsBuiltReport
        Github:         ex0th
        Credits:        Iain Brighton (@iainbrighton) - PScribo module

    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV
    #>
    [CmdletBinding()]
    param (
    )

    begin {
        $LocalizedData = $reportTranslate.GetAbrHvNetworking
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Networking)
    }

    process {
        try {
            if ($InfoLevel.Networking -ge 1 -and $HvNodeSessions.Count -gt 0) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $NetworkData = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.HostFailed -ScriptBlock {
                        $NetAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
                        $RdmaAdapters = @(Get-NetAdapterRdma -ErrorAction SilentlyContinue)
                        $HasTeamMapping = [bool](Get-Command -Name 'Get-VMNetworkAdapterTeamMapping' -ErrorAction SilentlyContinue)

                        $Switches = @(Get-VMSwitch -ErrorAction SilentlyContinue | ForEach-Object {
                                $VSwitch = $_
                                $Team = $null
                                if ($VSwitch.EmbeddedTeamingEnabled) {
                                    $Team = Get-VMSwitchTeam -Name $VSwitch.Name -ErrorAction SilentlyContinue
                                }
                                [PSCustomObject]@{
                                    Name = [string]$VSwitch.Name
                                    SwitchType = [string]$VSwitch.SwitchType
                                    EmbeddedTeaming = [string][bool]$VSwitch.EmbeddedTeamingEnabled
                                    AllowManagementOS = [string][bool]$VSwitch.AllowManagementOS
                                    BandwidthReservationMode = [string]$VSwitch.BandwidthReservationMode
                                    IovEnabled = [string][bool]$VSwitch.IovEnabled
                                    Members = [string[]]@($VSwitch.NetAdapterInterfaceDescriptions | Where-Object { $_ } | ForEach-Object {
                                            $Description = $_
                                            $Match = $NetAdapters | Where-Object { $_.InterfaceDescription -eq $Description } | Select-Object -First 1
                                            if ($Match) { [string]$Match.Name } else { [string]$Description }
                                        })
                                    TeamingMode = [string]$Team.TeamingMode
                                    LoadBalancingAlgorithm = [string]$Team.LoadBalancingAlgorithm
                                }
                            })

                        $HostVnics = @(Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | ForEach-Object {
                                $Vnic = $_
                                $Alias = 'vEthernet ({0})' -f $Vnic.Name
                                $Vlan = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $Vnic.Name -ErrorAction SilentlyContinue |
                                    Select-Object -First 1
                                $Mapping = $null
                                if ($HasTeamMapping) {
                                    $Mapping = Get-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $Vnic.Name -ErrorAction SilentlyContinue |
                                        Select-Object -First 1
                                }
                                $Rdma = $RdmaAdapters | Where-Object { $_.Name -eq $Alias } | Select-Object -First 1
                                [PSCustomObject]@{
                                    Name = [string]$Vnic.Name
                                    SwitchName = [string]$Vnic.SwitchName
                                    VlanMode = [string]$Vlan.OperationMode
                                    VlanId = [string]$Vlan.AccessVlanId
                                    MappedAdapter = [string]$Mapping.NetAdapterName
                                    MinimumBandwidthWeight = $Vnic.BandwidthSetting.MinimumBandwidthWeight
                                    RdmaEnabled = $(if ($Rdma) { [string][bool]$Rdma.Enabled } else { '' })
                                    IPAddresses = [string[]]@(Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                                            ForEach-Object { '{0}/{1}' -f $_.IPAddress, $_.PrefixLength })
                                }
                            })

                        $Adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
                                $Adapter = $_
                                $Rdma = $RdmaAdapters | Where-Object { $_.Name -eq $Adapter.Name } | Select-Object -First 1
                                $RdmaType = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword '*NetworkDirectTechnology' -ErrorAction SilentlyContinue |
                                    Select-Object -First 1
                                $Jumbo = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword '*JumboPacket' -ErrorAction SilentlyContinue |
                                    Select-Object -First 1
                                $Dcb = $null
                                if (Get-Command -Name 'Get-NetAdapterQos' -ErrorAction SilentlyContinue) {
                                    $Dcb = Get-NetAdapterQos -Name $Adapter.Name -ErrorAction SilentlyContinue
                                }
                                $SwitchName = ($Switches | Where-Object { $_.Members -contains [string]$Adapter.Name } | Select-Object -First 1).Name
                                [PSCustomObject]@{
                                    Name = [string]$Adapter.Name
                                    InterfaceDescription = [string]$Adapter.InterfaceDescription
                                    Status = [string]$Adapter.Status
                                    LinkSpeed = [string]$Adapter.LinkSpeed
                                    SwitchName = [string]$SwitchName
                                    RdmaCapable = [string][bool]$Rdma
                                    RdmaEnabled = $(if ($Rdma) { [string][bool]$Rdma.Enabled } else { '' })
                                    RdmaType = $(if ($RdmaType) { [string](@($RdmaType.RegistryValue) | Select-Object -First 1) } else { '' })
                                    JumboPacket = $(if ($Jumbo) { [string](@($Jumbo.RegistryValue) | Select-Object -First 1) } else { '' })
                                    DcbEnabled = $(if ($Dcb) { [string][bool]$Dcb.Enabled } else { '' })
                                    IPAddresses = [string[]]@(Get-NetIPAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                                            ForEach-Object { '{0}/{1}' -f $_.IPAddress, $_.PrefixLength })
                                }
                            })

                        $Qos = [PSCustomObject]@{
                            Available = [bool](Get-Command -Name 'Get-NetQosFlowControl' -ErrorAction SilentlyContinue)
                            PfcPriorities = [string[]]@()
                            TrafficClasses = @()
                            Policies = @()
                            DcbxWilling = ''
                        }
                        if ($Qos.Available) {
                            $Qos.PfcPriorities = [string[]]@(Get-NetQosFlowControl -ErrorAction SilentlyContinue | Where-Object { $_.Enabled } |
                                    ForEach-Object { [string]$_.Priority })
                            $Qos.TrafficClasses = @(Get-NetQosTrafficClass -ErrorAction SilentlyContinue | ForEach-Object {
                                    [PSCustomObject]@{
                                        Name = [string]$_.Name
                                        Priority = [string[]]@($_.Priority | ForEach-Object { [string]$_ })
                                        BandwidthPercentage = [string]$_.BandwidthPercentage
                                        Algorithm = [string]$_.Algorithm
                                    }
                                })
                            $Qos.Policies = @(Get-NetQosPolicy -ErrorAction SilentlyContinue | ForEach-Object {
                                    [PSCustomObject]@{
                                        Name = [string]$_.Name
                                        Priority = [string]$_.PriorityValue8021Action
                                        Template = [string]$_.Template
                                        NetDirectPort = [string]$_.NetDirectPortMatchCondition
                                    }
                                })
                            $Qos.DcbxWilling = [string](Get-NetQosDcbxSetting -ErrorAction SilentlyContinue | Select-Object -First 1).Willing
                        }

                        [PSCustomObject]@{
                            Switches = $Switches
                            HostVnics = $HostVnics
                            Adapters = $Adapters
                            Qos = $Qos
                        }
                    } | Sort-Object -Property NodeName)
                $IsS2D = (@($HvEnvironment.StorageTopology) -contains 'S2D')
                # Storage traffic between S2D nodes uses the cluster networks with the role Cluster or Cluster and client.
                $StorageSubnets = @()
                if ($HvClusterSession) {
                    $StorageSubnets = @(Invoke-Command -Session $HvClusterSession -ErrorAction SilentlyContinue -ScriptBlock {
                            Get-ClusterNetwork -ErrorAction SilentlyContinue | Where-Object { [int]$_.Role -in 1, 3 } | ForEach-Object {
                                $Network = $_
                                for ($Index = 0; $Index -lt @($Network.Ipv4Addresses).Count; $Index++) {
                                    '{0}/{1}' -f @($Network.Ipv4Addresses)[$Index], @($Network.Ipv4PrefixLengths)[$Index]
                                }
                            }
                        } | ForEach-Object { [string]$_ })
                }
                $Findings = @(foreach ($HostItem in $NetworkData) {
                        Resolve-HvNetworkFinding -NetworkData $HostItem -IsS2D:$IsS2D -StorageSubnet $StorageSubnets | ForEach-Object {
                            $_ | Add-Member -MemberType NoteProperty -Name 'NodeName' -Value $HostItem.NodeName -PassThru
                        }
                    })
                #endregion Collection

                #region Objects
                $FormatRdma = {
                    param ($Item)
                    if ([string]$Item.RdmaEnabled -eq '') {
                        $LocalizedData.ValueNotSupported
                    } else {
                        ConvertTo-HvDisplayValue ([string]$Item.RdmaEnabled -eq 'True')
                    }
                }

                $SwitchObj = @(foreach ($HostItem in $NetworkData) {
                        foreach ($SwitchItem in @($HostItem.Switches | Sort-Object -Property Name)) {
                            $LbLabel = if ($SwitchItem.LoadBalancingAlgorithm) { $LocalizedData["Algorithm$($SwitchItem.LoadBalancingAlgorithm)"] }
                            $InObj = [ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.SwitchName = $SwitchItem.Name
                                $LocalizedData.SwitchType = ConvertTo-HvDisplayValue $SwitchItem.SwitchType
                                $LocalizedData.Set = ConvertTo-HvDisplayValue ($SwitchItem.EmbeddedTeaming -eq 'True')
                                $LocalizedData.LoadBalancing = $(if ($LbLabel) { $LbLabel } else { ConvertTo-HvDisplayValue $SwitchItem.LoadBalancingAlgorithm })
                                $LocalizedData.Members = ConvertTo-HvDisplayValue $SwitchItem.Members
                                $LocalizedData.ManagementOS = ConvertTo-HvDisplayValue ($SwitchItem.AllowManagementOS -eq 'True')
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $InObj[$LocalizedData.BandwidthMode] = ConvertTo-HvDisplayValue $SwitchItem.BandwidthReservationMode
                                $InObj[$LocalizedData.Iov] = ConvertTo-HvDisplayValue ($SwitchItem.IovEnabled -eq 'True')
                            }
                            [PSCustomObject]$InObj
                        }
                    })

                $VnicObj = @(foreach ($HostItem in $NetworkData) {
                        foreach ($Vnic in @($HostItem.HostVnics | Sort-Object -Property Name)) {
                            $InObj = [ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.VnicName = $Vnic.Name
                                $LocalizedData.SwitchName = ConvertTo-HvDisplayValue $Vnic.SwitchName
                                $LocalizedData.Vlan = $(switch ($Vnic.VlanMode) {
                                        'Access' { $Vnic.VlanId }
                                        'Untagged' { $LocalizedData.ValueUntagged }
                                        default { ConvertTo-HvDisplayValue $Vnic.VlanMode }
                                    })
                                $LocalizedData.IPAddress = ConvertTo-HvDisplayValue $Vnic.IPAddresses
                                $LocalizedData.Rdma = & $FormatRdma $Vnic
                                $LocalizedData.MappedAdapter = ConvertTo-HvDisplayValue $Vnic.MappedAdapter
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $InObj[$LocalizedData.BandwidthWeight] = ConvertTo-HvDisplayValue $Vnic.MinimumBandwidthWeight
                            }
                            [PSCustomObject]$InObj
                        }
                    })

                $AdapterObj = @(foreach ($HostItem in $NetworkData) {
                        foreach ($Adapter in @($HostItem.Adapters | Sort-Object -Property Name)) {
                            $TypeLabel = if ($Adapter.RdmaType) { $LocalizedData["RdmaTechnology$($Adapter.RdmaType)"] }
                            $InObj = [ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.AdapterName = $Adapter.Name
                                $LocalizedData.SwitchName = ConvertTo-HvDisplayValue $Adapter.SwitchName
                                $LocalizedData.LinkSpeed = ConvertTo-HvDisplayValue $Adapter.LinkSpeed
                                $LocalizedData.Status = ConvertTo-HvDisplayValue $Adapter.Status
                                $LocalizedData.Rdma = & $FormatRdma $Adapter
                                $LocalizedData.RdmaType = $(if ($TypeLabel) { $TypeLabel } else { ConvertTo-HvDisplayValue $Adapter.RdmaType })
                                $LocalizedData.JumboPacket = ConvertTo-HvDisplayValue $Adapter.JumboPacket
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $InObj[$LocalizedData.Description] = ConvertTo-HvDisplayValue $Adapter.InterfaceDescription
                                $InObj[$LocalizedData.Dcb] = $(if ($Adapter.DcbEnabled -eq '') {
                                        '--'
                                    } else {
                                        ConvertTo-HvDisplayValue ($Adapter.DcbEnabled -eq 'True')
                                    })
                            }
                            [PSCustomObject]$InObj
                        }
                    })

                $DcbObj = @(foreach ($HostItem in $NetworkData) {
                        $Qos = $HostItem.Qos
                        $Configured = (@($Qos.PfcPriorities).Count -gt 0 -or @($Qos.Policies).Count -gt 0 -or
                            @($Qos.TrafficClasses | Where-Object { $_.Name -ne '[Default]' }).Count -gt 0)
                        if (-not $Configured) {
                            continue
                        }
                        [PSCustomObject][ordered]@{
                            $LocalizedData.HostName = $HostItem.NodeName
                            $LocalizedData.PfcPriorities = ConvertTo-HvDisplayValue $Qos.PfcPriorities
                            # ETS classes have a bandwidth share; strict priority classes have none.
                            $LocalizedData.TrafficClasses = ConvertTo-HvDisplayValue @($Qos.TrafficClasses | ForEach-Object {
                                    if ($_.Algorithm -eq 'ETS') {
                                        $LocalizedData.ValueTrafficClassEts -f $_.Name, (@($_.Priority) -join ','), $_.BandwidthPercentage
                                    } else {
                                        $LocalizedData.ValueTrafficClassStrict -f $_.Name, (@($_.Priority) -join ',')
                                    }
                                })
                            $LocalizedData.QosPolicies = ConvertTo-HvDisplayValue @($Qos.Policies | ForEach-Object {
                                    $LocalizedData.ValuePolicy -f $_.Name, $_.Priority
                                })
                            $LocalizedData.DcbxWilling = ConvertTo-HvDisplayValue ([string]$Qos.DcbxWilling -eq 'True')
                        }
                    })
                #endregion Objects

                #region Health checks
                # Every check names the cells it highlights: table, key column (empty = every row of the host)
                # and the highlighted column. Checks without targets are only reported as text.
                $Checks = [ordered]@{
                    SetLoadBalancing = @{
                        Enabled = $Healthcheck.Networking.SetLoadBalancing
                        Targets = @(@{ Table = $SwitchObj; KeyColumn = $LocalizedData.SwitchName; Column = $LocalizedData.LoadBalancing })
                        Finding = $LocalizedData.SetLoadBalancingFinding
                        Recommendation = $LocalizedData.SetLoadBalancingBP
                    }
                    RdmaDisabled = @{
                        Enabled = $Healthcheck.Networking.RdmaState
                        Targets = @(
                            @{ Table = $AdapterObj; KeyColumn = $LocalizedData.AdapterName; Column = $LocalizedData.Rdma }
                            @{ Table = $VnicObj; KeyColumn = $LocalizedData.VnicName; Column = $LocalizedData.Rdma }
                        )
                        Finding = $LocalizedData.RdmaStateFinding
                        Recommendation = $LocalizedData.RdmaStateBP
                    }
                    NoStorageRdma = @{
                        Enabled = $Healthcheck.Networking.RdmaState
                        Targets = @()
                        Finding = $LocalizedData.NoStorageRdmaFinding
                        Recommendation = $LocalizedData.NoStorageRdmaBP
                    }
                    RocePfc = @{
                        Enabled = $Healthcheck.Networking.RocePfc
                        Targets = @(@{ Table = $AdapterObj; KeyColumn = $LocalizedData.AdapterName; Column = $LocalizedData.RdmaType })
                        Finding = $LocalizedData.RocePfcFinding
                        Recommendation = $LocalizedData.RocePfcBP
                    }
                    DcbxWilling = @{
                        Enabled = $Healthcheck.Networking.DcbxWilling
                        Targets = @(@{ Table = $DcbObj; KeyColumn = ''; Column = $LocalizedData.DcbxWilling })
                        Finding = $LocalizedData.DcbxWillingFinding
                        Recommendation = $LocalizedData.DcbxWillingBP
                    }
                    DcbTrafficClass = @{
                        Enabled = $Healthcheck.Networking.DcbTrafficClass
                        Targets = @(@{ Table = $DcbObj; KeyColumn = ''; Column = $LocalizedData.TrafficClasses })
                        Finding = $LocalizedData.DcbTrafficClassFinding
                        Recommendation = $LocalizedData.DcbTrafficClassBP
                    }
                    VnicTeamMapping = @{
                        Enabled = $Healthcheck.Networking.VnicTeamMapping
                        Targets = @(@{ Table = $VnicObj; KeyColumn = $LocalizedData.VnicName; Column = $LocalizedData.MappedAdapter })
                        Finding = $LocalizedData.VnicTeamMappingFinding
                        Recommendation = $LocalizedData.VnicTeamMappingBP
                    }
                }
                $ShownChecks = New-Object -TypeName System.Collections.Generic.List[String]
                foreach ($CheckName in @($Checks.Keys)) {
                    $Check = $Checks[$CheckName]
                    $CheckFindings = @($Findings | Where-Object { $_.Check -eq $CheckName })
                    if (-not $Check.Enabled -or $CheckFindings.Count -eq 0) {
                        continue
                    }
                    $ShownChecks.Add($CheckName)
                    foreach ($Finding in $CheckFindings) {
                        foreach ($Target in @($Check.Targets)) {
                            @($Target.Table) | Where-Object {
                                $_.$($LocalizedData.HostName) -eq $Finding.NodeName -and
                                ($Target.KeyColumn -eq '' -or $_.$($Target.KeyColumn) -eq $Finding.Object)
                            } | Set-Style -Style Warning -Property $Target.Column
                        }
                    }
                }
                # Writes the health check text of the given checks below the table they highlight.
                $WriteChecks = {
                    param ([String[]] $CheckNames)
                    $Shown = @($CheckNames | Where-Object { $ShownChecks.Contains($_) })
                    if ($Shown.Count -gt 0) {
                        Paragraph $LocalizedData.HealthCheck -Bold -Underline
                        BlankLine
                        foreach ($CheckName in $Shown) {
                            $Objects = @($Findings | Where-Object { $_.Check -eq $CheckName } | ForEach-Object {
                                    if ($_.Object) { '{0} ({1})' -f $_.Object, $_.NodeName } else { $_.NodeName }
                                })
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($Checks[$CheckName].Finding -f ($Objects -join ', ')) `
                                -Recommendation $Checks[$CheckName].Recommendation
                        }
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    Section -Style Heading3 $LocalizedData.HeadingSwitches {
                        if ($SwitchObj.Count -eq 0) {
                            Paragraph $LocalizedData.NoSwitches
                        } else {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableSwitches) - $HvObjectName"
                                List = $false
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $TableParams['ColumnWidths'] = 13, 13, 9, 7, 12, 16, 9, 12, 9
                            } else {
                                $TableParams['ColumnWidths'] = 15, 15, 11, 8, 15, 24, 12
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $SwitchObj | Table @TableParams
                            & $WriteChecks 'SetLoadBalancing'
                        }
                    }

                    if ($VnicObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingVnics {
                            Paragraph $LocalizedData.ParagraphVnics
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableVnics) - $HvObjectName"
                                List = $false
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $TableParams['ColumnWidths'] = 13, 14, 13, 8, 17, 9, 14, 12
                            } else {
                                $TableParams['ColumnWidths'] = 14, 15, 14, 9, 20, 10, 18
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $VnicObj | Table @TableParams
                            & $WriteChecks 'VnicTeamMapping'
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingAdapters {
                        Paragraph $LocalizedData.ParagraphAdapters
                        BlankLine
                        if ($AdapterObj.Count -gt 0) {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableAdapters) - $HvObjectName"
                                List = $false
                            }
                            if ($InfoLevel.Networking -ge 2) {
                                $TableParams['ColumnWidths'] = 11, 11, 10, 9, 8, 9, 9, 9, 16, 8
                            } else {
                                $TableParams['ColumnWidths'] = 14, 14, 12, 11, 10, 11, 14, 14
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $AdapterObj | Table @TableParams
                            & $WriteChecks 'RdmaDisabled', 'NoStorageRdma', 'RocePfc'
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingDcb {
                        if ($DcbObj.Count -eq 0) {
                            Paragraph $LocalizedData.NoDcb
                        } else {
                            Paragraph $LocalizedData.ParagraphDcb
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableDcb) - $HvObjectName"
                                List = $false
                                ColumnWidths = 16, 14, 32, 26, 12
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $DcbObj | Table @TableParams
                            & $WriteChecks 'DcbxWilling', 'DcbTrafficClass'
                        }
                    }
                }
            }
        } catch {
            Write-PScriboMessage -IsWarning $_.Exception.Message
        }
    }

    end {}
}
