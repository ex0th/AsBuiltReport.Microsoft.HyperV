function Get-AbrHvClusterSharedVolume {
    <#
    .SYNOPSIS
        Used by As Built Report to document the Cluster Shared Volumes of a failover cluster.
    .DESCRIPTION
        Documents every Cluster Shared Volume with path, owner node, state, I/O mode, capacity and free space.
        InfoLevel 2 adds the file system, the I/O mode of every node and the CSV block cache size.
        Health checks highlight volumes that are not online, use redirected I/O for a reason other than ReFS
        or run out of free space.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterSharedVolume
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $CsvData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $Volumes = @(Get-Volume -ErrorAction SilentlyContinue)
                    [PSCustomObject]@{
                        BlockCacheSize = (Get-Cluster -ErrorAction Stop).BlockCacheSize
                        Nodes = @(Get-ClusterNode -ErrorAction SilentlyContinue | ForEach-Object {
                                [PSCustomObject]@{ Name = [string]$_.Name; State = [string]$_.State }
                            })
                        Volumes = @(foreach ($Csv in @(Get-ClusterSharedVolume -ErrorAction Stop)) {
                                foreach ($Info in @($Csv.SharedVolumeInfo)) {
                                    $Partition = $Info.Partition
                                    $Volume = $Volumes | Where-Object { $Partition -and $_.Path -eq $Partition.Name } |
                                        Select-Object -First 1
                                    [PSCustomObject]@{
                                        Name = [string]$Csv.Name
                                        OwnerNode = [string]$Csv.OwnerNode
                                        State = [string]$Csv.State
                                        Path = [string]$Info.FriendlyVolumeName
                                        MaintenanceMode = [string]$Info.MaintenanceMode
                                        FileSystem = $(if ($Volume -and $Volume.FileSystemType) {
                                                [string]$Volume.FileSystemType
                                            } else {
                                                [string]$Partition.FileSystem
                                            })
                                        Size = $Partition.Size
                                        FreeSpace = $Partition.FreeSpace
                                        FreePercent = $Partition.PercentFree
                                    }
                                }
                            })
                        NodeState = @(Get-ClusterSharedVolumeState -ErrorAction SilentlyContinue | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    Node = [string]$_.Node
                                    StateInfo = [string]$_.StateInfo
                                    FileSystemRedirectedIOReason = [string]$_.FileSystemRedirectedIOReason
                                    BlockRedirectedIOReason = [string]$_.BlockRedirectedIOReason
                                }
                            })
                    }
                }
                $Volumes = @($CsvData.Volumes | Where-Object { $_ } | Sort-Object -Property Name)
                $NodeStates = @($CsvData.NodeState | Where-Object { $_ })
                $CsvStates = @(Resolve-HvCsvState -Volume $Volumes -NodeState $NodeStates)
                #endregion Collection

                #region Objects
                $CsvObj = @(foreach ($Volume in $Volumes) {
                        $CsvState = $CsvStates | Where-Object { $_.Name -eq $Volume.Name } | Select-Object -First 1
                        $IoLabel = $LocalizedData["IoMode$($CsvState.IoModeKey)"]
                        $InObj = [ordered]@{
                            $LocalizedData.VolumeName = $Volume.Name
                            $LocalizedData.Path = ConvertTo-HvDisplayValue $Volume.Path
                            $LocalizedData.OwnerNode = ConvertTo-HvDisplayValue $Volume.OwnerNode
                            $LocalizedData.State = ConvertTo-HvDisplayValue $Volume.State
                            $LocalizedData.IoMode = $(if ($CsvState.IoModeKey -eq 'Redirected') {
                                    $IoLabel -f ($CsvState.RedirectedNodes -join ', ')
                                } else {
                                    $IoLabel
                                })
                            $LocalizedData.Capacity = ConvertTo-HvSize $Volume.Size
                            $LocalizedData.FreePercent = $(if ($null -ne $Volume.FreeSpace) {
                                    '{0} ({1})' -f (ConvertTo-HvSize $Volume.FreeSpace), (ConvertTo-HvPercent $CsvState.FreePercent)
                                } else {
                                    ConvertTo-HvPercent $CsvState.FreePercent
                                })
                        }
                        if ($InfoLevel.Cluster -ge 2) {
                            $InObj[$LocalizedData.FileSystem] = ConvertTo-HvDisplayValue $Volume.FileSystem
                        }
                        [PSCustomObject]$InObj
                    })

                $NodeStateObj = @()
                if ($InfoLevel.Cluster -ge 2) {
                    $NodeStateObj = @(foreach ($State in ($NodeStates | Sort-Object -Property Name, Node)) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.VolumeName = $State.Name
                                $LocalizedData.Node = $State.Node
                                $LocalizedData.StateInfo = ConvertTo-HvDisplayValue $State.StateInfo
                                $LocalizedData.FileSystemReason = ConvertTo-HvDisplayValue $State.FileSystemRedirectedIOReason
                                $LocalizedData.BlockReason = ConvertTo-HvDisplayValue $State.BlockRedirectedIOReason
                            }
                        })
                }
                #endregion Objects

                #region Health checks
                $StateIssues = @($CsvStates | Where-Object { $_.StateSeverity -ne 'Ok' })
                $ShowStateCheck = ($Healthcheck.Cluster.CsvState -and $StateIssues.Count -gt 0)
                if ($ShowStateCheck) {
                    foreach ($Issue in $StateIssues) {
                        $CsvObj | Where-Object { $_.$($LocalizedData.VolumeName) -eq $Issue.Name } |
                            Set-Style -Style $Issue.StateSeverity -Property $LocalizedData.State
                    }
                }
                $IoIssues = @($CsvStates | Where-Object { $_.IoSeverity -ne 'Ok' })
                $ShowIoCheck = ($Healthcheck.Cluster.CsvRedirectedAccess -and $IoIssues.Count -gt 0)
                if ($ShowIoCheck) {
                    foreach ($Issue in $IoIssues) {
                        $CsvObj | Where-Object { $_.$($LocalizedData.VolumeName) -eq $Issue.Name } |
                            Set-Style -Style $Issue.IoSeverity -Property $LocalizedData.IoMode
                    }
                }
                $FreeIssues = @($CsvStates | Where-Object { $_.FreeSeverity -ne 'Ok' })
                $ShowFreeCheck = ($Healthcheck.Cluster.CsvFreeSpace -and $FreeIssues.Count -gt 0)
                if ($ShowFreeCheck) {
                    foreach ($Issue in $FreeIssues) {
                        $CsvObj | Where-Object { $_.$($LocalizedData.VolumeName) -eq $Issue.Name } |
                            Set-Style -Style $Issue.FreeSeverity -Property $LocalizedData.FreePercent
                    }
                }
                # All volumes on one node is only a note: the owner node coordinates metadata, the I/O is direct.
                $CsvOwners = @($Volumes | ForEach-Object { $_.OwnerNode } | Where-Object { $_ })
                $ShowOwnerNote = ($Healthcheck.Cluster.RoleDistribution -and @($Volumes | Select-Object -ExpandProperty Name -Unique).Count -ge 2 -and
                    @($CsvOwners | Sort-Object -Unique).Count -eq 1 -and
                    @(Resolve-HvOwnerDistribution -OwnerNode $CsvOwners -NodeState @($CsvData.Nodes)).Count -gt 0)
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine
                    if ($CsvObj.Count -eq 0) {
                        Paragraph $LocalizedData.NoVolumes
                    } else {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableVolumes) - $HvObjectName"
                            List = $false
                        }
                        if ($InfoLevel.Cluster -ge 2) {
                            $TableParams['ColumnWidths'] = 16, 16, 12, 8, 14, 10, 14, 10
                        } else {
                            $TableParams['ColumnWidths'] = 17, 17, 12, 9, 17, 12, 16
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $CsvObj | Table @TableParams
                        if ($ShowOwnerNote) {
                            Paragraph ($LocalizedData.CsvOwnerNote -f @($CsvOwners)[0])
                            BlankLine
                        }

                        if ($ShowStateCheck -or $ShowIoCheck -or $ShowFreeCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowStateCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Severity (Get-HvMaxSeverity @($StateIssues | ForEach-Object { $_.StateSeverity })) -Finding ($LocalizedData.CsvStateFinding -f (($StateIssues | ForEach-Object { $_.Name }) -join ', ')) -Recommendation $LocalizedData.CsvStateBP
                            }
                            if ($ShowIoCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.CsvRedirectedAccessFinding -f (($IoIssues | ForEach-Object { $_.Name }) -join ', ')) -Recommendation $LocalizedData.CsvRedirectedAccessBP
                            }
                            if ($ShowFreeCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Severity (Get-HvMaxSeverity @($FreeIssues | ForEach-Object { $_.FreeSeverity })) -Finding ($LocalizedData.CsvFreeSpaceFinding -f (($FreeIssues | ForEach-Object { $_.Name }) -join ', ')) -Recommendation $LocalizedData.CsvFreeSpaceBP
                            }
                        }

                        if ($InfoLevel.Cluster -ge 2) {
                            # Cluster-wide CSV setting, shown below the volumes.
                            $SettingsObj = [PSCustomObject][ordered]@{
                                $LocalizedData.BlockCacheSize = $(if ([string]$CsvData.BlockCacheSize -in '', '0') {
                                        $LocalizedData.ValueDisabled
                                    } else {
                                        $LocalizedData.ValueMB -f $CsvData.BlockCacheSize
                                    })
                            }
                            $TableParams = @{
                                Name = "$($LocalizedData.TableSettings) - $HvObjectName"
                                List = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $SettingsObj | Table @TableParams

                            if ($NodeStateObj.Count -gt 0) {
                                Section -Style Heading3 $LocalizedData.HeadingNodeState {
                                    Paragraph $LocalizedData.ParagraphNodeState
                                    BlankLine
                                    $TableParams = @{
                                        Name = "$($LocalizedData.TableNodeState) - $HvObjectName"
                                        List = $false
                                        ColumnWidths = 26, 18, 18, 19, 19
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $NodeStateObj | Table @TableParams
                                }
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
