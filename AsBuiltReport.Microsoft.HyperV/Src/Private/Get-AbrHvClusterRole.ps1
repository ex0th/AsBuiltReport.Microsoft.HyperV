function Get-AbrHvClusterRole {
    <#
    .SYNOPSIS
        Used by As Built Report to document the roles of a failover cluster.
    .DESCRIPTION
        Documents the clustered roles (virtual machines, file servers and other roles) with type, owner node,
        state, start priority and preferred owners. InfoLevel 2 adds the failover and failback settings.
        A health check highlights roles that failed or are only partially online.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterRole
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $GroupData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    Get-ClusterGroup -ErrorAction Stop | ForEach-Object {
                        $ClusterGroup = $_
                        $Owners = Get-ClusterOwnerNode -Group $ClusterGroup.Name -ErrorAction SilentlyContinue
                        [PSCustomObject]@{
                            Name = [string]$ClusterGroup.Name
                            GroupType = [string]$ClusterGroup.GroupType
                            IsCoreGroup = [string]$ClusterGroup.IsCoreGroup
                            OwnerNode = [string]$ClusterGroup.OwnerNode
                            State = [string]$ClusterGroup.State
                            Priority = [string]$ClusterGroup.Priority
                            PreferredOwners = [string[]]@($Owners.OwnerNodes | ForEach-Object { [string]$_.Name })
                            FailoverThreshold = [string]$ClusterGroup.FailoverThreshold
                            FailoverPeriod = [string]$ClusterGroup.FailoverPeriod
                            AutoFailbackType = [string]$ClusterGroup.AutoFailbackType
                            FailbackWindowStart = [string]$ClusterGroup.FailbackWindowStart
                            FailbackWindowEnd = [string]$ClusterGroup.FailbackWindowEnd
                            AntiAffinityClassNames = [string[]]@($ClusterGroup.AntiAffinityClassNames | ForEach-Object { [string]$_ })
                        }
                    }
                }
                $GroupData = @($GroupData | Where-Object { $_ })
                $Roles = @(Resolve-HvClusterGroup -Group $GroupData | Sort-Object -Property Name)
                #endregion Collection

                #region Objects
                $RoleObj = @(foreach ($Role in $Roles) {
                        $Group = $GroupData | Where-Object { $_.Name -eq $Role.Name } | Select-Object -First 1
                        $TypeLabel = if ($Role.GroupType) { $LocalizedData["Type$($Role.GroupType)"] }
                        $PriorityLabel = if ($Role.PriorityKey) { $LocalizedData["Priority$($Role.PriorityKey)"] }
                        [PSCustomObject][ordered]@{
                            $LocalizedData.RoleName = $Role.Name
                            $LocalizedData.RoleType = $(if ($TypeLabel) { $TypeLabel } else { ConvertTo-HvDisplayValue $Role.GroupType })
                            $LocalizedData.OwnerNode = ConvertTo-HvDisplayValue $Role.OwnerNode
                            $LocalizedData.State = ConvertTo-HvDisplayValue $Role.State
                            $LocalizedData.Priority = $(if ($PriorityLabel) { $PriorityLabel } else { ConvertTo-HvDisplayValue $Role.PriorityKey })
                            $LocalizedData.PreferredOwners = $(if (@($Group.PreferredOwners).Count -gt 0) {
                                    ConvertTo-HvDisplayValue $Group.PreferredOwners
                                } else {
                                    $LocalizedData.ValueAnyNode
                                })
                        }
                    })

                # Summary per node: every node of the discovery, also nodes without roles.
                $SummaryNodes = @(@($HvNodeFacts | ForEach-Object { [string]$_.ComputerName }) +
                    @($Roles | ForEach-Object { $_.OwnerNode }) | Where-Object { $_ } | Sort-Object -Unique)
                $SummaryItems = @(foreach ($NodeName in $SummaryNodes) {
                        $NodeRoles = @($Roles | Where-Object { $_.OwnerNode -eq $NodeName })
                        $NotOnline = @($NodeRoles | Where-Object { $_.StateSeverity -ne 'Ok' })
                        [PSCustomObject]@{
                            Severity = $(if ($NotOnline | Where-Object { $_.StateSeverity -eq 'Critical' }) { 'Critical' } elseif ($NotOnline.Count -gt 0) { 'Warning' } else { 'Ok' })
                            Row = [PSCustomObject][ordered]@{
                                $LocalizedData.Node = $NodeName
                                $LocalizedData.RoleCount = $NodeRoles.Count
                                $LocalizedData.VmCount = @($NodeRoles | Where-Object { $_.GroupType -eq 'VirtualMachine' }).Count
                                $LocalizedData.OtherRoleCount = @($NodeRoles | Where-Object { $_.GroupType -ne 'VirtualMachine' }).Count
                                $LocalizedData.OnlineCount = @($NodeRoles | Where-Object { $_.State -eq 'Online' }).Count
                                $LocalizedData.OfflineCount = @($NodeRoles | Where-Object { $_.State -eq 'Offline' }).Count
                                $LocalizedData.NotOnlineCount = $NotOnline.Count
                            }
                        }
                    })

                $FailoverObj = @()
                if ($InfoLevel.Cluster -ge 2) {
                    $FailoverObj = @(foreach ($Role in $Roles) {
                            $Group = $GroupData | Where-Object { $_.Name -eq $Role.Name } | Select-Object -First 1
                            # 4294967295 (UInt32 max) means the cluster calculates the value (number of nodes - 1).
                            $Threshold = if ($Group.FailoverThreshold -eq '4294967295') {
                                $LocalizedData.ValueAutomatic
                            } else {
                                ConvertTo-HvDisplayValue $Group.FailoverThreshold
                            }
                            $Failback = if ($Group.AutoFailbackType -eq '1') {
                                if ($Group.FailbackWindowStart -in '', '-1' -or $Group.FailbackWindowEnd -in '', '-1') {
                                    $LocalizedData.FailbackImmediately
                                } else {
                                    $LocalizedData.FailbackWindow -f $Group.FailbackWindowStart, $Group.FailbackWindowEnd
                                }
                            } else {
                                $LocalizedData.FailbackPrevent
                            }
                            [PSCustomObject][ordered]@{
                                $LocalizedData.RoleName = $Role.Name
                                $LocalizedData.FailoverThreshold = $Threshold
                                $LocalizedData.FailoverPeriod = ConvertTo-HvDisplayValue $Group.FailoverPeriod
                                $LocalizedData.Failback = $Failback
                                $LocalizedData.AntiAffinity = ConvertTo-HvDisplayValue $Group.AntiAffinityClassNames
                            }
                        })
                }
                #endregion Objects

                #region Health checks
                $UnhealthyRoles = @($Roles | Where-Object { $_.StateSeverity -ne 'Ok' })
                $ShowStateCheck = ($Healthcheck.Cluster.RoleState -and $UnhealthyRoles.Count -gt 0)
                if ($ShowStateCheck) {
                    foreach ($Role in $UnhealthyRoles) {
                        $RoleObj | Where-Object { $_.$($LocalizedData.RoleName) -eq $Role.Name } |
                            Set-Style -Style $Role.StateSeverity -Property $LocalizedData.State
                    }
                    foreach ($Item in @($SummaryItems | Where-Object { $_.Severity -ne 'Ok' })) {
                        $Item.Row | Set-Style -Style $Item.Severity -Property $LocalizedData.NotOnlineCount
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine
                    if ($RoleObj.Count -eq 0) {
                        Paragraph $LocalizedData.NoRoles
                    } else {
                        # InfoLevel 1: roles per node; the full list follows from InfoLevel 2.
                        $TableParams = @{
                            Name = "$($LocalizedData.TableSummary) - $HvObjectName"
                            List = $false
                            ColumnWidths = 22, 12, 14, 13, 12, 12, 15
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        @($SummaryItems | ForEach-Object { $_.Row }) | Table @TableParams

                        if ($ShowStateCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Severity (Get-HvMaxSeverity @($UnhealthyRoles | ForEach-Object { $_.StateSeverity })) -Finding ($LocalizedData.RoleStateFinding -f (($UnhealthyRoles | ForEach-Object { $_.Name }) -join ', ')) -Recommendation $LocalizedData.RoleStateBP
                        }

                        if ($InfoLevel.Cluster -ge 2) {
                            Section -Style Heading3 $LocalizedData.HeadingRoles {
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableRoles) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 24, 16, 15, 12, 12, 21
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $RoleObj | Table @TableParams
                            }
                        }

                        if ($FailoverObj.Count -gt 0) {
                            Section -Style Heading3 $LocalizedData.HeadingFailover {
                                Paragraph $LocalizedData.ParagraphFailover
                                BlankLine
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableFailover) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 28, 16, 16, 20, 20
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $FailoverObj | Table @TableParams
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
