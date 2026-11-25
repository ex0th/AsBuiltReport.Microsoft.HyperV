function Get-AbrHvClusterAwareUpdating {
    <#
    .SYNOPSIS
        Used by As Built Report to document Cluster-Aware Updating (CAU) of a failover cluster.
    .DESCRIPTION
        Documents the CAU self-updating role (status, schedule, updating options) and the result of the most
        recent updating run. InfoLevel 2 adds further options and the result of the last run per node.
        Health checks highlight clusters without an active self-updating role and a last run that did not
        succeed.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterAwareUpdating
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                # Only reads the CAU configuration and reports; nothing is started or changed.
                $CauData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $Available = [bool](Get-Command -Name 'Get-CauClusterRole' -ErrorAction SilentlyContinue)
                    $RoleParameter = @()
                    $LastRun = $null
                    if ($Available) {
                        try {
                            $RoleParameter = @(Get-CauClusterRole -ErrorAction Stop -WarningAction SilentlyContinue | ForEach-Object {
                                    $Value = $_.Value
                                    if ($Value -is [enum]) {
                                        $Value = [string]$Value
                                    } elseif ($Value -is [array]) {
                                        $Value = [string[]]@($Value | ForEach-Object { [string]$_ })
                                    }
                                    [PSCustomObject]@{ Name = [string]$_.Name; Value = $Value }
                                })
                        } catch {
                            # No self-updating role on this cluster.
                            $RoleParameter = @()
                        }
                        try {
                            $Report = Get-CauReport -Last -Detailed -ErrorAction Stop -WarningAction SilentlyContinue
                            if ($Report) {
                                $ResultProperty = @('ClusterResult', 'Status', 'Result') |
                                    Where-Object { $Report.PSObject.Properties[$_] } | Select-Object -First 1
                                $LastRun = [PSCustomObject]@{
                                    StartTimestamp = $Report.StartTimestamp
                                    Result = $(if ($ResultProperty) { [string]$Report.$ResultProperty } else { '' })
                                    Nodes = @(foreach ($NodeResult in @($Report.NodeResults | Where-Object { $_ })) {
                                            [PSCustomObject]@{
                                                Node = [string]$NodeResult.Node
                                                Status = [string]$NodeResult.Status
                                                UpdateCount = @($NodeResult.UpdateResults | Where-Object { $_ }).Count
                                            }
                                        })
                                }
                            }
                        } catch {
                            # No updating run recorded.
                            $LastRun = $null
                        }
                    }
                    [PSCustomObject]@{
                        Available = $Available
                        RoleParameter = $RoleParameter
                        LastRun = $LastRun
                    }
                }
                $CauState = Resolve-HvCauState -RoleParameter @($CauData.RoleParameter) -LastRunResult $(if ($CauData.LastRun) {
                        [string]$CauData.LastRun.Result
                    } else {
                        ''
                    })
                $Settings = $CauState.Settings
                #endregion Collection

                #region Formatting
                $Culture = Get-HvReportCulture
                $FormatDate = {
                    param ($Value)
                    if ($Value -is [datetime]) {
                        $Value.ToString('g', $Culture)
                    } else {
                        ConvertTo-HvDisplayValue $Value
                    }
                }
                $FormatSetting = {
                    param ($Name)
                    if ($Settings.Contains($Name)) {
                        ConvertTo-HvDisplayValue $Settings[$Name]
                    } else {
                        '--'
                    }
                }
                # Day names in the report language, for example 'Tuesday' or 'Monday, Thursday'.
                $DayNames = @(([string]$Settings['DaysOfWeek']).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } |
                        ForEach-Object {
                            $Day = $_
                            try {
                                $Culture.DateTimeFormat.GetDayName([System.DayOfWeek]$Day)
                            } catch {
                                $Day
                            }
                        })
                $Schedule = if ($DayNames.Count -eq 0) {
                    '--'
                } elseif (@($Settings['WeeksOfMonth'] | Where-Object { $_ }).Count -gt 0) {
                    $LocalizedData.ScheduleMonthly -f ($DayNames -join ', '), ((@($Settings['WeeksOfMonth']) | ForEach-Object { [string]$_ }) -join ', ')
                } elseif ([string]$Settings['IntervalWeeks'] -notin '', '0') {
                    $LocalizedData.ScheduleInterval -f ($DayNames -join ', '), $Settings['IntervalWeeks']
                } else {
                    $LocalizedData.ScheduleWeekly -f ($DayNames -join ', ')
                }
                #endregion Formatting

                #region Objects
                $CauObj = $null
                if ($CauData.Available) {
                    $InObj = [ordered]@{
                        $LocalizedData.SelfUpdatingRole = ConvertTo-HvDisplayValue $CauState.HasSelfUpdatingRole
                    }
                    if ($CauState.HasSelfUpdatingRole) {
                        $InObj[$LocalizedData.RoleName] = & $FormatSetting 'ResourceGroupName'
                        $InObj[$LocalizedData.RoleStatus] = & $FormatSetting 'Status'
                        $InObj[$LocalizedData.Schedule] = $Schedule
                        $InObj[$LocalizedData.StartDate] = & $FormatDate $Settings['StartDate']
                        $InObj[$LocalizedData.MaxFailedNodes] = & $FormatSetting 'MaxFailedNodes'
                        $InObj[$LocalizedData.MaxRetriesPerNode] = & $FormatSetting 'MaxRetriesPerNode'
                        $InObj[$LocalizedData.RequireAllNodesOnline] = & $FormatSetting 'RequireAllNodesOnline'
                        $InObj[$LocalizedData.Plugin] = & $FormatSetting 'CauPluginName'
                        if ($InfoLevel.Cluster -ge 2) {
                            $InObj[$LocalizedData.FailbackMode] = & $FormatSetting 'FailbackMode'
                            $InObj[$LocalizedData.RebootTimeout] = & $FormatSetting 'RebootTimeoutMinutes'
                            $InObj[$LocalizedData.PreUpdateScript] = & $FormatSetting 'PreUpdateScript'
                            $InObj[$LocalizedData.PostUpdateScript] = & $FormatSetting 'PostUpdateScript'
                            $InObj[$LocalizedData.FirewallRules] = & $FormatSetting 'EnableFirewallRules'
                        }
                    }
                    $InObj[$LocalizedData.LastRun] = $(if ($CauData.LastRun) {
                            & $FormatDate $CauData.LastRun.StartTimestamp
                        } else {
                            $LocalizedData.ValueNoRun
                        })
                    $InObj[$LocalizedData.LastRunResult] = $(if ($CauData.LastRun) {
                            ConvertTo-HvDisplayValue $CauData.LastRun.Result
                        } else {
                            '--'
                        })
                    $CauObj = [PSCustomObject]$InObj
                }

                $NodeObj = @()
                if ($InfoLevel.Cluster -ge 2 -and $CauData.LastRun) {
                    $NodeObj = @(foreach ($NodeResult in @($CauData.LastRun.Nodes | Sort-Object -Property Node)) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.Node = $NodeResult.Node
                                $LocalizedData.NodeStatus = ConvertTo-HvDisplayValue $NodeResult.Status
                                $LocalizedData.UpdateCount = ConvertTo-HvDisplayValue $NodeResult.UpdateCount
                            }
                        })
                }
                #endregion Objects

                #region Health checks
                $ShowRoleCheck = ($Healthcheck.Cluster.CauSelfUpdating -and $CauObj -and
                    ($CauState.Findings -contains 'NoSelfUpdatingRole' -or $CauState.Findings -contains 'SelfUpdatingRoleOffline'))
                if ($ShowRoleCheck) {
                    $Column = if ($CauState.HasSelfUpdatingRole) { $LocalizedData.RoleStatus } else { $LocalizedData.SelfUpdatingRole }
                    $CauObj | Set-Style -Style Warning -Property $Column
                }
                $ShowRunCheck = ($Healthcheck.Cluster.CauLastRun -and $CauObj -and $CauState.Findings -contains 'LastRunNotSucceeded')
                if ($ShowRunCheck) {
                    $CauObj | Set-Style -Style Warning -Property $LocalizedData.LastRunResult
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine
                    if (-not $CauObj) {
                        Paragraph $LocalizedData.ModuleMissing
                    } else {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableCau) - $HvObjectName"
                            List = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $CauObj | Table @TableParams

                        if ($ShowRoleCheck -or $ShowRunCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowRoleCheck) {
                                if ($CauState.HasSelfUpdatingRole) {
                                    Write-HvHealthCheck -Area $LocalizedData.Heading -Finding $LocalizedData.SelfUpdatingOfflineFinding -Recommendation $LocalizedData.SelfUpdatingOfflineBP
                                } else {
                                    Write-HvHealthCheck -Area $LocalizedData.Heading -Finding $LocalizedData.NoSelfUpdatingRoleFinding -Recommendation $LocalizedData.NoSelfUpdatingRoleBP
                                }
                                BlankLine
                            }
                            if ($ShowRunCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding $LocalizedData.LastRunFinding -Recommendation $LocalizedData.LastRunBP
                            }
                        }

                        if ($NodeObj.Count -gt 0) {
                            Section -Style Heading3 $LocalizedData.HeadingLastRun {
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableLastRun) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 40, 30, 30
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $NodeObj | Table @TableParams
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
