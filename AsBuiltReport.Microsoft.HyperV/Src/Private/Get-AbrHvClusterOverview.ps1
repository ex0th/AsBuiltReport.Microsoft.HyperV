function Get-AbrHvClusterOverview {
    <#
    .SYNOPSIS
        Used by As Built Report to document the failover cluster configuration and its nodes.
    .DESCRIPTION
        Documents cluster-wide settings and a node summary including the OS build of every node,
        so differing patch levels between nodes are visible at a glance.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterOverview
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $ClusterData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $Cluster = Get-Cluster -ErrorAction Stop
                    [PSCustomObject]@{
                        Name = [string]$Cluster.Name
                        Domain = [string]$Cluster.Domain
                        Description = [string]$Cluster.Description
                        FunctionalLevel = [string]$Cluster.ClusterFunctionalLevel
                        UpgradeVersion = [string]$Cluster.ClusterUpgradeVersion
                        S2DEnabled = ($Cluster.S2DEnabled -eq 1)
                        CsvCount = @(Get-ClusterSharedVolume -ErrorAction SilentlyContinue).Count
                        VMRoleCount = @(Get-ClusterGroup -ErrorAction SilentlyContinue | Where-Object { [string]$_.GroupType -eq 'VirtualMachine' }).Count
                        SameSubnetDelay = $Cluster.SameSubnetDelay
                        SameSubnetThreshold = $Cluster.SameSubnetThreshold
                        CrossSubnetDelay = $Cluster.CrossSubnetDelay
                        CrossSubnetThreshold = $Cluster.CrossSubnetThreshold
                        ResiliencyLevel = [string]$Cluster.ResiliencyLevel
                        ResiliencyDefaultPeriod = $Cluster.ResiliencyDefaultPeriod
                        QuarantineThreshold = $Cluster.QuarantineThreshold
                        QuarantineDuration = $Cluster.QuarantineDuration
                        DrainOnShutdown = ($Cluster.DrainOnShutdown -eq 1)
                        AutoBalancerMode = [string]$Cluster.AutoBalancerMode
                        AutoBalancerLevel = [string]$Cluster.AutoBalancerLevel
                        BlockCacheSize = $Cluster.BlockCacheSize
                        SharedVolumesRoot = [string]$Cluster.SharedVolumesRoot
                        Nodes = @(Get-ClusterNode -ErrorAction Stop | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    Id = [string]$_.Id
                                    State = [string]$_.State
                                    StatusInformation = [string]$_.StatusInformation
                                    DrainStatus = [string]$_.DrainStatus
                                    # Levels without a value ('Rack:', 'Chassis:') carry no information.
                                    FaultDomain = (@($_.FaultDomain | Where-Object { $_ -and $_ -notmatch ':\s*$' }) -join '; ')
                                    Manufacturer = [string]$_.Manufacturer
                                    Model = [string]$_.Model
                                    SerialNumber = [string]$_.SerialNumber
                                }
                            })
                    }
                }

                # The OS build including UBR was collected per node during discovery (Get-HvNodeFact).
                $NodeBuild = @{}
                foreach ($NodeFact in @($HvNodeFacts | Where-Object { $_.Reachable })) {
                    $NodeBuild[[string]$NodeFact.ComputerName] = [PSCustomObject]@{
                        Build = [string]$NodeFact.OSBuild
                        Caption = [string]$NodeFact.OSCaption
                    }
                }
                #endregion Collection

                # The build most nodes run is the reference; any other build is a deviation.
                $ReferenceBuild = $NodeBuild.Values | Where-Object { $_.Build } | Group-Object -Property Build |
                    Sort-Object -Property Count, Name -Descending | Select-Object -First 1 -ExpandProperty Name

                # Numeric cluster properties are shown with their meaning; unknown values stay numeric.
                # Empty values must not resolve to the plain label key (e.g. 'AutoBalancerMode').
                $AutoBalancerModeLabel = if ($ClusterData.AutoBalancerMode) {
                    $LocalizedData["AutoBalancerMode$($ClusterData.AutoBalancerMode)"]
                }
                $AutoBalancerLevelLabel = if ($ClusterData.AutoBalancerLevel) {
                    $LocalizedData["AutoBalancerLevel$($ClusterData.AutoBalancerLevel)"]
                }
                # Azure Local reuses functional level numbers, so the Windows Server names only apply to Windows Server.
                $FunctionalLevelLabel = if ($ClusterData.FunctionalLevel -and $HvEnvironment.Platform -eq 'WindowsServer') {
                    $LocalizedData["FunctionalLevel$($ClusterData.FunctionalLevel)"]
                }

                #region Cluster configuration object
                $ClusterObj = [ordered]@{
                    $LocalizedData.ClusterName = $ClusterData.Name
                    $LocalizedData.Domain = $ClusterData.Domain
                    $LocalizedData.Fqdn = ('{0}.{1}' -f $ClusterData.Name, $ClusterData.Domain).ToLowerInvariant()
                    $LocalizedData.Description = ConvertTo-HvDisplayValue $ClusterData.Description
                    $LocalizedData.NodeCount = @($ClusterData.Nodes).Count
                    $LocalizedData.CsvCount = $ClusterData.CsvCount
                    $LocalizedData.VMRoleCount = $ClusterData.VMRoleCount
                    $LocalizedData.S2DEnabled = ConvertTo-HvDisplayValue $ClusterData.S2DEnabled
                    $LocalizedData.FunctionalLevel = ConvertTo-HvDisplayValue $(if ($FunctionalLevelLabel) {
                            '{0} ({1})' -f $FunctionalLevelLabel, $ClusterData.FunctionalLevel
                        } else {
                            $ClusterData.FunctionalLevel
                        })
                    $LocalizedData.UpgradeVersion = ConvertTo-HvDisplayValue $ClusterData.UpgradeVersion
                }
                if ($InfoLevel.Cluster -ge 2) {
                    $ClusterObj[$LocalizedData.SameSubnetDelay] = ConvertTo-HvDisplayValue $ClusterData.SameSubnetDelay
                    $ClusterObj[$LocalizedData.SameSubnetThreshold] = ConvertTo-HvDisplayValue $ClusterData.SameSubnetThreshold
                    $ClusterObj[$LocalizedData.CrossSubnetDelay] = ConvertTo-HvDisplayValue $ClusterData.CrossSubnetDelay
                    $ClusterObj[$LocalizedData.CrossSubnetThreshold] = ConvertTo-HvDisplayValue $ClusterData.CrossSubnetThreshold
                    $ClusterObj[$LocalizedData.ResiliencyLevel] = ConvertTo-HvDisplayValue $ClusterData.ResiliencyLevel
                    $ClusterObj[$LocalizedData.ResiliencyPeriod] = ConvertTo-HvDisplayValue $ClusterData.ResiliencyDefaultPeriod
                    $ClusterObj[$LocalizedData.QuarantineThreshold] = ConvertTo-HvDisplayValue $ClusterData.QuarantineThreshold
                    $ClusterObj[$LocalizedData.QuarantineDuration] = ConvertTo-HvDisplayValue $ClusterData.QuarantineDuration
                    $ClusterObj[$LocalizedData.DrainOnShutdown] = ConvertTo-HvDisplayValue $ClusterData.DrainOnShutdown
                    $ClusterObj[$LocalizedData.AutoBalancerMode] = ConvertTo-HvDisplayValue $(if ($AutoBalancerModeLabel) {
                            '{0} ({1})' -f $AutoBalancerModeLabel, $ClusterData.AutoBalancerMode
                        } else {
                            $ClusterData.AutoBalancerMode
                        })
                    $ClusterObj[$LocalizedData.AutoBalancerLevel] = ConvertTo-HvDisplayValue $(if ($AutoBalancerLevelLabel) {
                            '{0} ({1})' -f $AutoBalancerLevelLabel, $ClusterData.AutoBalancerLevel
                        } else {
                            $ClusterData.AutoBalancerLevel
                        })
                    $ClusterObj[$LocalizedData.BlockCacheSize] = ConvertTo-HvDisplayValue $ClusterData.BlockCacheSize
                    $ClusterObj[$LocalizedData.SharedVolumesRoot] = ConvertTo-HvDisplayValue $ClusterData.SharedVolumesRoot
                }
                $ClusterObj = [PSCustomObject]$ClusterObj
                #endregion Cluster configuration object

                #region Node objects
                $NodeObj = @()
                foreach ($Node in @($ClusterData.Nodes)) {
                    try {
                        $Build = $NodeBuild[$Node.Name]
                        $Model = ('{0} {1}' -f $Node.Manufacturer, $Node.Model).Trim()
                        $InObj = [ordered]@{
                            $LocalizedData.NodeName = $Node.Name
                            $LocalizedData.State = $Node.State
                            $LocalizedData.DrainStatus = ConvertTo-HvDisplayValue $Node.DrainStatus
                            $LocalizedData.OSBuild = ConvertTo-HvDisplayValue $Build.Build
                            $LocalizedData.Model = ConvertTo-HvDisplayValue $Model
                        }
                        if ($InfoLevel.Cluster -ge 2) {
                            $InObj[$LocalizedData.NodeId] = ConvertTo-HvDisplayValue $Node.Id
                            $InObj[$LocalizedData.StatusInformation] = ConvertTo-HvDisplayValue $Node.StatusInformation
                            $InObj[$LocalizedData.FaultDomain] = ConvertTo-HvDisplayValue $Node.FaultDomain
                            $InObj[$LocalizedData.OSVersion] = ConvertTo-HvDisplayValue $Build.Caption
                            $InObj[$LocalizedData.SerialNumber] = ConvertTo-HvDisplayValue $Node.SerialNumber
                        }
                        $NodeObj += [PSCustomObject]$InObj
                    } catch {
                        Write-PScriboMessage -IsWarning $_.Exception.Message
                    }
                }
                #endregion Node objects

                #region Health checks
                $NodesNotUp = @($NodeObj | Where-Object { $_.$($LocalizedData.State) -ne 'Up' })
                $NodesOtherBuild = @($NodeObj | Where-Object { $ReferenceBuild -and $_.$($LocalizedData.OSBuild) -ne '--' -and $_.$($LocalizedData.OSBuild) -ne $ReferenceBuild })
                if ($Healthcheck.Cluster.NodeState) {
                    $NodeObj | Where-Object { $_.$($LocalizedData.State) -eq 'Down' } | Set-Style -Style Critical -Property $LocalizedData.State
                    $NodeObj | Where-Object { @('Paused', 'Joining', 'Unknown') -contains $_.$($LocalizedData.State) } | Set-Style -Style Warning -Property $LocalizedData.State
                }
                if ($Healthcheck.Cluster.NodeOSBuildConsistency) {
                    $NodesOtherBuild | Set-Style -Style Warning -Property $LocalizedData.OSBuild
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    Section -Style Heading3 $LocalizedData.HeadingConfiguration {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableConfiguration) - $HvObjectName"
                            List = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $ClusterObj | Table @TableParams
                    }

                    Section -Style Heading3 $LocalizedData.HeadingNodes {
                        Paragraph ($LocalizedData.ParagraphNodes -f $HvObjectName)
                        BlankLine
                        if ($InfoLevel.Cluster -ge 2) {
                            # One single-row list table per node: PScribo drops captions from multi-row list tables.
                            foreach ($Node in ($NodeObj | Sort-Object -Property $LocalizedData.NodeName)) {
                                Section -Style Heading4 $Node.$($LocalizedData.NodeName) {
                                    $TableParams = @{
                                        Name = "$($LocalizedData.TableNode) - $($Node.$($LocalizedData.NodeName))"
                                        List = $true
                                        ColumnWidths = 40, 60
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $Node | Table @TableParams
                                }
                            }
                        } else {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableNodes) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 13, 15, 18, 32
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $NodeObj | Sort-Object -Property $LocalizedData.NodeName | Table @TableParams
                        }

                        $ShowNodeStateCheck = ($Healthcheck.Cluster.NodeState -and $NodesNotUp.Count -gt 0)
                        $ShowBuildCheck = ($Healthcheck.Cluster.NodeOSBuildConsistency -and $NodesOtherBuild.Count -gt 0)
                        if ($ShowNodeStateCheck -or $ShowBuildCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowNodeStateCheck) {
                                Paragraph ($LocalizedData.NodeStateBP -f (($NodesNotUp | ForEach-Object { $_.$($LocalizedData.NodeName) }) -join ', '))
                                BlankLine
                            }
                            if ($ShowBuildCheck) {
                                Paragraph ($LocalizedData.NodeBuildBP -f (($NodesOtherBuild | ForEach-Object { $_.$($LocalizedData.NodeName) }) -join ', '), $ReferenceBuild)
                                BlankLine
                            }
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
