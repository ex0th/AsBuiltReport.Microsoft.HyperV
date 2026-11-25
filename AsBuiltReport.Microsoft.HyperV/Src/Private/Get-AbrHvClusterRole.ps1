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
                        $TypeLabel = $LocalizedData["Type$($Role.GroupType)"]
                        $PriorityLabel = $LocalizedData["Priority$($Role.PriorityKey)"]
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
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine
                    if ($RoleObj.Count -eq 0) {
                        Paragraph $LocalizedData.NoRoles
                    } else {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableRoles) - $HvObjectName"
                            List = $false
                            ColumnWidths = 24, 16, 15, 12, 12, 21
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $RoleObj | Table @TableParams

                        if ($ShowStateCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            Paragraph ($LocalizedData.RoleStateBP -f (($UnhealthyRoles | ForEach-Object { $_.Name }) -join ', '))
                            BlankLine
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
