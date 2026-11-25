function Get-AbrHvLiveMigration {
    <#
    .SYNOPSIS
        Used by As Built Report to document the live migration configuration of a cluster or standalone host.
    .DESCRIPTION
        Documents the cluster-wide live migration settings (networks, parallel migrations, SMB bandwidth
        limit) and the Hyper-V live migration settings of every host. Health checks highlight clusters without
        a network for live migration, hosts with live migration disabled and settings that differ between hosts.
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
        $LocalizedData = $reportTranslate.GetAbrHvLiveMigration
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.LiveMigration)
    }

    process {
        try {
            if ($InfoLevel.LiveMigration -ge 1 -and $HvNodeSessions.Count -gt 0) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $ClusterData = $null
                $NetworkState = $null
                if ($HvClusterSession) {
                    $ClusterData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                        $Cluster = Get-Cluster -ErrorAction Stop
                        $VMResourceType = Get-ClusterResourceType -Name 'Virtual Machine' -ErrorAction SilentlyContinue
                        $MigrationParams = if ($VMResourceType) {
                            Get-ClusterParameter -InputObject $VMResourceType -Name 'MigrationExcludeNetworks', 'MigrationNetworkOrder' -ErrorAction SilentlyContinue
                        }
                        [PSCustomObject]@{
                            # Cluster properties that older versions do not know stay empty.
                            MaximumParallelMigrations = $Cluster.MaximumParallelMigrations
                            SetSMBBandwidthLimit = $Cluster.SetSMBBandwidthLimit
                            SMBBandwidthLimitFactor = $Cluster.SMBBandwidthLimitFactor
                            MigrationExcludeNetworks = [string]($MigrationParams | Where-Object { $_.Name -eq 'MigrationExcludeNetworks' }).Value
                            MigrationNetworkOrder = [string]($MigrationParams | Where-Object { $_.Name -eq 'MigrationNetworkOrder' }).Value
                            Networks = @(Get-ClusterNetwork -ErrorAction Stop | ForEach-Object {
                                    [PSCustomObject]@{
                                        Name = [string]$_.Name
                                        Id = [string]$_.Id
                                        Role = [int]$_.Role
                                        State = [string]$_.State
                                    }
                                })
                        }
                    }
                    $NetworkState = Resolve-HvClusterNetwork -Network $ClusterData.Networks `
                        -MigrationExcludeNetworks $ClusterData.MigrationExcludeNetworks `
                        -MigrationNetworkOrder $ClusterData.MigrationNetworkOrder
                }

                $HostData = foreach ($Fqdn in @($HvNodeSessions.Keys)) {
                    try {
                        $HostSettings = Invoke-Command -Session $HvNodeSessions[$Fqdn] -ErrorAction Stop -ScriptBlock {
                            $VMHost = Get-VMHost -ErrorAction Stop
                            $SmbLimit = $null
                            if (Get-Command -Name 'Get-SmbBandwidthLimit' -ErrorAction SilentlyContinue) {
                                $SmbLimit = (Get-SmbBandwidthLimit -Category LiveMigration -ErrorAction SilentlyContinue).BytesPerSecond
                            }
                            [PSCustomObject]@{
                                Enabled = [bool]$VMHost.VirtualMachineMigrationEnabled
                                MaxMigrations = $VMHost.MaximumVirtualMachineMigrations
                                MaxStorageMigrations = $VMHost.MaximumStorageMigrations
                                Authentication = [string]$VMHost.VirtualMachineMigrationAuthenticationType
                                PerformanceOption = [string]$VMHost.VirtualMachineMigrationPerformanceOption
                                UseAnyNetwork = [bool]$VMHost.UseAnyNetworkForMigration
                                MigrationNetworks = [string[]]@(Get-VMMigrationNetwork -ErrorAction SilentlyContinue |
                                        Sort-Object -Property Priority | ForEach-Object { [string]$_.Subnet })
                                SmbBandwidthLimit = $SmbLimit
                            }
                        }
                        # Host names are taken from the discovery, so every section spells them the same way.
                        $ShortName = $Fqdn.Split('.')[0]
                        $NodeFact = $HvNodeFacts | Where-Object { $_.ComputerName -eq $ShortName } | Select-Object -First 1
                        $HostSettings | Add-Member -MemberType NoteProperty -Name 'Name' -Value $(if ($NodeFact) {
                                [string]$NodeFact.ComputerName
                            } else {
                                $ShortName
                            })
                        $HostSettings
                    } catch {
                        Write-PScriboMessage -IsWarning ($LocalizedData.HostFailed -f $Fqdn, $_.Exception.Message)
                    }
                }
                $HostData = @($HostData | Where-Object { $_ } | Sort-Object -Property Name)
                #endregion Collection

                #region Cluster object
                $ClusterObj = $null
                if ($ClusterData) {
                    $ExcludedNames = @($NetworkState.Networks | Where-Object { -not $_.AllowedForMigration } |
                            ForEach-Object { $_.Name })
                    $ClusterObjHash = [ordered]@{
                        $LocalizedData.MigrationNetworks = $(if ($NetworkState.MigrationNetworks.Count -gt 0) {
                                $NetworkState.MigrationNetworks -join ', '
                            } else {
                                $LocalizedData.ValueNone
                            })
                        $LocalizedData.ExcludedNetworks = $(if ($ExcludedNames.Count -gt 0) {
                                $ExcludedNames -join ', '
                            } else {
                                $LocalizedData.ValueNone
                            })
                        $LocalizedData.ParallelMigrations = ConvertTo-HvDisplayValue $ClusterData.MaximumParallelMigrations
                    }
                    if ($InfoLevel.LiveMigration -ge 2) {
                        $ClusterObjHash[$LocalizedData.ClusterSmbLimit] = $(if ($null -eq $ClusterData.SetSMBBandwidthLimit) {
                                '--'
                            } else {
                                ConvertTo-HvDisplayValue ([int]$ClusterData.SetSMBBandwidthLimit -eq 1)
                            })
                        # The factor is stored in hundredths of a percent (2500 = 25 %).
                        $ClusterObjHash[$LocalizedData.ClusterSmbLimitFactor] = $(if ($null -eq $ClusterData.SMBBandwidthLimitFactor) {
                                '--'
                            } else {
                                ConvertTo-HvPercent ([double]$ClusterData.SMBBandwidthLimitFactor / 100) -Decimals 2
                            })
                    }
                    $ClusterObj = [PSCustomObject]$ClusterObjHash
                }
                #endregion Cluster object

                #region Host objects
                # Display values of every setting, independent of the InfoLevel: the health check texts name
                # deviating settings with their values also when the InfoLevel hides the column.
                $DisplayData = @(foreach ($HostItem in $HostData) {
                        $PerformanceLabel = if ($HostItem.PerformanceOption) { $LocalizedData["Performance$($HostItem.PerformanceOption)"] }
                        [PSCustomObject]@{
                            Name = $HostItem.Name
                            Enabled = ConvertTo-HvDisplayValue $HostItem.Enabled
                            MaxMigrations = ConvertTo-HvDisplayValue $HostItem.MaxMigrations
                            MaxStorageMigrations = ConvertTo-HvDisplayValue $HostItem.MaxStorageMigrations
                            Authentication = ConvertTo-HvDisplayValue $HostItem.Authentication
                            PerformanceOption = $(if ($PerformanceLabel) {
                                    $PerformanceLabel
                                } else {
                                    ConvertTo-HvDisplayValue $HostItem.PerformanceOption
                                })
                            UseAnyNetwork = ConvertTo-HvDisplayValue $HostItem.UseAnyNetwork
                            MigrationNetworks = ConvertTo-HvDisplayValue $HostItem.MigrationNetworks
                            SmbBandwidthLimit = $(if ($HostItem.SmbBandwidthLimit) {
                                    $LocalizedData.ValueMbps -f [math]::Round([double]$HostItem.SmbBandwidthLimit * 8 / 1000000)
                                } else {
                                    $LocalizedData.ValueNoLimit
                                })
                        }
                    })
                $HostObj = @(foreach ($Display in $DisplayData) {
                        $InObj = [ordered]@{
                            $LocalizedData.HostName = $Display.Name
                            $LocalizedData.Enabled = $Display.Enabled
                            $LocalizedData.MaxMigrations = $Display.MaxMigrations
                            $LocalizedData.MaxStorageMigrations = $Display.MaxStorageMigrations
                            $LocalizedData.Authentication = $Display.Authentication
                            $LocalizedData.PerformanceOption = $Display.PerformanceOption
                        }
                        if ($InfoLevel.LiveMigration -ge 2) {
                            $InObj[$LocalizedData.UseAnyNetwork] = $Display.UseAnyNetwork
                            $InObj[$LocalizedData.HostMigrationNetworks] = $Display.MigrationNetworks
                            $InObj[$LocalizedData.SmbLimit] = $Display.SmbBandwidthLimit
                        }
                        [PSCustomObject]$InObj
                    })
                #endregion Host objects

                #region Health checks
                $ShowNetworkCheck = ($Healthcheck.LiveMigration.MigrationNetwork -and $NetworkState -and
                    $NetworkState.Findings -contains 'NoMigrationNetwork')
                if ($ShowNetworkCheck) {
                    $ClusterObj | Set-Style -Style Critical -Property $LocalizedData.MigrationNetworks
                }

                $HostsDisabled = @($HostData | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
                $ShowEnabledCheck = ($Healthcheck.LiveMigration.HostMigrationEnabled -and $HostsDisabled.Count -gt 0)
                if ($ShowEnabledCheck) {
                    $HostObj | Where-Object { $HostsDisabled -contains $_.$($LocalizedData.HostName) } |
                        Set-Style -Style Warning -Property $LocalizedData.Enabled
                }

                # Compared settings and the column that shows them.
                $CompareMap = [ordered]@{
                    Enabled = $LocalizedData.Enabled
                    MaxMigrations = $LocalizedData.MaxMigrations
                    MaxStorageMigrations = $LocalizedData.MaxStorageMigrations
                    Authentication = $LocalizedData.Authentication
                    PerformanceOption = $LocalizedData.PerformanceOption
                    UseAnyNetwork = $LocalizedData.UseAnyNetwork
                    MigrationNetworks = $LocalizedData.HostMigrationNetworks
                    SmbBandwidthLimit = $LocalizedData.SmbLimit
                }
                $Deviations = @(Resolve-HvSettingDeviation -InputObject $HostData -Property @($CompareMap.Keys))
                $ShowConsistencyCheck = ($Healthcheck.LiveMigration.SettingsConsistency -and $Deviations.Count -gt 0)
                if ($ShowConsistencyCheck) {
                    foreach ($Deviation in $Deviations) {
                        $Column = $CompareMap[$Deviation.Property]
                        # Columns that the InfoLevel hides are still named in the health check text.
                        $HostObj | Where-Object { $_.$($LocalizedData.HostName) -eq $Deviation.Name -and $_.PSObject.Properties[$Column] } |
                            Set-Style -Style Warning -Property $Column
                    }
                }

                $HostsCredSSP = @($HostData | Where-Object { [string]$_.Authentication -eq 'CredSSP' } | ForEach-Object { $_.Name })
                $ShowCredSSPCheck = ($Healthcheck.LiveMigration.CredSSP -and $HostsCredSSP.Count -gt 0)
                if ($ShowCredSSPCheck) {
                    $HostObj | Where-Object { $HostsCredSSP -contains $_.$($LocalizedData.HostName) } |
                        Set-Style -Style Warning -Property $LocalizedData.Authentication
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    if ($ClusterObj) {
                        Section -Style Heading3 $LocalizedData.HeadingCluster {
                            Paragraph ($LocalizedData.ParagraphCluster -f $HvObjectName)
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableCluster) - $HvObjectName"
                                List = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ClusterObj | Table @TableParams

                            if ($ShowNetworkCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Severity Critical -Finding $LocalizedData.MigrationNetworkFinding -Recommendation $LocalizedData.MigrationNetworkBP
                            }
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingHosts {
                        Paragraph ($LocalizedData.ParagraphHosts -f $HvObjectName)
                        BlankLine
                        if ($InfoLevel.LiveMigration -ge 2) {
                            # One single-row list table per host: PScribo drops captions from multi-row list tables.
                            foreach ($HostItem in $HostObj) {
                                Section -Style Heading4 $HostItem.$($LocalizedData.HostName) {
                                    $TableParams = @{
                                        Name = "$($LocalizedData.TableHost) - $($HostItem.$($LocalizedData.HostName))"
                                        List = $true
                                        ColumnWidths = 40, 60
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $HostItem | Table @TableParams
                                }
                            }
                        } else {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableHosts) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 12, 14, 14, 18, 20
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $HostObj | Table @TableParams
                        }

                        if ($ShowEnabledCheck -or $ShowConsistencyCheck -or $ShowCredSSPCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowEnabledCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.HostMigrationEnabledFinding -f ($HostsDisabled -join ', ')) -Recommendation $LocalizedData.HostMigrationEnabledBP
                            }
                            if ($ShowConsistencyCheck) {
                                # Every deviating setting with the value of every host, e.g. "Authentication: CredSSP (node01), Kerberos (node02)".
                                $Settings = @(foreach ($Property in @($Deviations | ForEach-Object { $_.Property } | Select-Object -Unique)) {
                                        '{0}: {1}' -f $CompareMap[$Property], (Format-HvSettingDeviation -InputObject $DisplayData -Property $Property)
                                    })
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.SettingsConsistencyFinding -f ($Settings -join '; ')) -Recommendation $LocalizedData.SettingsConsistencyBP
                            }
                            if ($ShowCredSSPCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.CredSSPFinding -f ($HostsCredSSP -join ', ')) -Recommendation $LocalizedData.CredSSPBP
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
