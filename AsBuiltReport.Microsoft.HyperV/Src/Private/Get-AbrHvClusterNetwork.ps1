function Get-AbrHvClusterNetwork {
    <#
    .SYNOPSIS
        Used by As Built Report to document the networks and network interfaces of a failover cluster.
    .DESCRIPTION
        Documents every cluster network with its role, state, subnets and whether live migration may use it,
        and the network interfaces of every node. Health checks highlight networks and interfaces that are
        not up and clusters with only one network for cluster communication.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterNetwork
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $NetworkData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $VMResourceType = Get-ClusterResourceType -Name 'Virtual Machine' -ErrorAction SilentlyContinue
                    $MigrationParams = if ($VMResourceType) {
                        Get-ClusterParameter -InputObject $VMResourceType -Name 'MigrationExcludeNetworks', 'MigrationNetworkOrder' -ErrorAction SilentlyContinue
                    }
                    [PSCustomObject]@{
                        MigrationExcludeNetworks = [string]($MigrationParams | Where-Object { $_.Name -eq 'MigrationExcludeNetworks' }).Value
                        MigrationNetworkOrder = [string]($MigrationParams | Where-Object { $_.Name -eq 'MigrationNetworkOrder' }).Value
                        Networks = @(Get-ClusterNetwork -ErrorAction Stop | ForEach-Object {
                                $Network = $_
                                $Subnets = @()
                                $Ipv4 = @($Network.Ipv4Addresses)
                                $Ipv4Prefix = @($Network.Ipv4PrefixLengths)
                                for ($Index = 0; $Index -lt $Ipv4.Count; $Index++) {
                                    $Subnets += '{0}/{1}' -f $Ipv4[$Index], $Ipv4Prefix[$Index]
                                }
                                $Ipv6 = @($Network.Ipv6Addresses)
                                $Ipv6Prefix = @($Network.Ipv6PrefixLengths)
                                for ($Index = 0; $Index -lt $Ipv6.Count; $Index++) {
                                    $Subnets += '{0}/{1}' -f $Ipv6[$Index], $Ipv6Prefix[$Index]
                                }
                                [PSCustomObject]@{
                                    Name = [string]$Network.Name
                                    Id = [string]$Network.Id
                                    Role = [int]$Network.Role
                                    State = [string]$Network.State
                                    Subnets = [string[]]$Subnets
                                    Metric = $Network.Metric
                                    AutoMetric = [bool]$Network.AutoMetric
                                    Description = [string]$Network.Description
                                }
                            })
                        Interfaces = @(Get-ClusterNetworkInterface -ErrorAction Stop | ForEach-Object {
                                [PSCustomObject]@{
                                    Node = [string]$_.Node
                                    Network = [string]$_.Network
                                    Adapter = [string]$_.Adapter
                                    Address = [string]$_.Address
                                    State = [string]$_.State
                                    DhcpEnabled = [bool]$_.DhcpEnabled
                                }
                            })
                    }
                }
                $NetworkState = Resolve-HvClusterNetwork -Network $NetworkData.Networks `
                    -MigrationExcludeNetworks $NetworkData.MigrationExcludeNetworks `
                    -MigrationNetworkOrder $NetworkData.MigrationNetworkOrder
                #endregion Collection

                #region Network objects
                $NetworkSeverity = @{}
                $NetworkObj = foreach ($Network in @($NetworkData.Networks | Sort-Object -Property Name)) {
                    $Evaluated = $NetworkState.Networks | Where-Object { $_.Id -eq ([string]$Network.Id).ToLowerInvariant() } |
                        Select-Object -First 1
                    $RoleLabel = $LocalizedData["Role$($Evaluated.RoleKey)"]
                    $InObj = [ordered]@{
                        $LocalizedData.NetworkName = $Network.Name
                        $LocalizedData.Role = $(if ($RoleLabel) { $RoleLabel } else { ConvertTo-HvDisplayValue $Network.Role })
                        $LocalizedData.State = $Network.State
                        $LocalizedData.Subnets = ConvertTo-HvDisplayValue $Network.Subnets
                        $LocalizedData.LiveMigration = ConvertTo-HvDisplayValue $Evaluated.AllowedForMigration
                    }
                    if ($InfoLevel.Cluster -ge 2) {
                        $InObj[$LocalizedData.MigrationOrder] = ConvertTo-HvDisplayValue $Evaluated.MigrationOrder
                        $InObj[$LocalizedData.Metric] = ConvertTo-HvDisplayValue $Network.Metric
                        $InObj[$LocalizedData.AutoMetric] = ConvertTo-HvDisplayValue $Network.AutoMetric
                        $InObj[$LocalizedData.Description] = ConvertTo-HvDisplayValue $Network.Description
                    }
                    $NetworkSeverity[[string]$Network.Name] = $Evaluated.StateSeverity
                    [PSCustomObject]$InObj
                }
                $NetworkObj = @($NetworkObj)

                $InterfaceObj = @(foreach ($Interface in @($NetworkData.Interfaces | Sort-Object -Property Node, Network)) {
                        $InObj = [ordered]@{
                            $LocalizedData.Node = $Interface.Node
                            $LocalizedData.Network = $Interface.Network
                            $LocalizedData.Adapter = ConvertTo-HvDisplayValue $Interface.Adapter
                            $LocalizedData.Address = ConvertTo-HvDisplayValue $Interface.Address
                            $LocalizedData.State = $Interface.State
                        }
                        if ($InfoLevel.Cluster -ge 2) {
                            $InObj[$LocalizedData.Dhcp] = ConvertTo-HvDisplayValue $Interface.DhcpEnabled
                        }
                        [PSCustomObject]$InObj
                    })
                #endregion Network objects

                #region Health checks
                $NetworksNotUp = @($NetworkObj | Where-Object { $NetworkSeverity[$_.$($LocalizedData.NetworkName)] -ne 'Ok' })
                $InterfacesNotUp = @($InterfaceObj | Where-Object { $_.$($LocalizedData.State) -ne 'Up' })
                $ShowStateCheck = ($Healthcheck.Cluster.NetworkState -and ($NetworksNotUp.Count -gt 0 -or $InterfacesNotUp.Count -gt 0))
                $ShowRedundancyCheck = ($Healthcheck.Cluster.NetworkRedundancy -and $NetworkState.Findings -contains 'SingleClusterNetwork')
                if ($Healthcheck.Cluster.NetworkState) {
                    $NetworkObj | Where-Object { $NetworkSeverity[$_.$($LocalizedData.NetworkName)] -eq 'Critical' } |
                        Set-Style -Style Critical -Property $LocalizedData.State
                    $NetworkObj | Where-Object { $NetworkSeverity[$_.$($LocalizedData.NetworkName)] -eq 'Warning' } |
                        Set-Style -Style Warning -Property $LocalizedData.State
                    $InterfaceObj | Where-Object { $_.$($LocalizedData.State) -eq 'Failed' } | Set-Style -Style Critical -Property $LocalizedData.State
                    $InterfaceObj | Where-Object { @('Up', 'Failed') -notcontains $_.$($LocalizedData.State) } |
                        Set-Style -Style Warning -Property $LocalizedData.State
                }
                if ($ShowRedundancyCheck) {
                    $NetworkObj | Where-Object { $_.$($LocalizedData.Role) -ne $LocalizedData.RoleNone } |
                        Set-Style -Style Warning -Property $LocalizedData.Role
                }                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    Section -Style Heading3 $LocalizedData.HeadingNetworks {
                        if ($InfoLevel.Cluster -ge 2) {
                            # One single-row list table per network: PScribo drops captions from multi-row list tables.
                            foreach ($Network in $NetworkObj) {
                                Section -Style Heading4 $Network.$($LocalizedData.NetworkName) {
                                    $TableParams = @{
                                        Name = "$($LocalizedData.TableNetwork) - $($Network.$($LocalizedData.NetworkName))"
                                        List = $true
                                        ColumnWidths = 40, 60
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $Network | Table @TableParams
                                }
                            }
                        } else {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableNetworks) - $HvObjectName"
                                List = $false
                                ColumnWidths = 24, 20, 12, 28, 16
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $NetworkObj | Table @TableParams
                        }

                        if ($ShowStateCheck -or $ShowRedundancyCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowStateCheck) {
                                $Affected = @($NetworksNotUp | ForEach-Object { $_.$($LocalizedData.NetworkName) }) +
                                    @($InterfacesNotUp | ForEach-Object { '{0} ({1})' -f $_.$($LocalizedData.Network), $_.$($LocalizedData.Node) })
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Severity (Get-HvMaxSeverity (@($NetworksNotUp | ForEach-Object { $NetworkSeverity[$_.$($LocalizedData.NetworkName)] }) + @($InterfacesNotUp | ForEach-Object { if ($_.$($LocalizedData.State) -eq 'Failed') { 'Critical' } }))) -Finding ($LocalizedData.NetworkStateFinding -f ($Affected -join ', ')) -Recommendation $LocalizedData.NetworkStateBP
                            }
                            if ($ShowRedundancyCheck) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.NetworkRedundancyFinding -f $NetworkState.ClusterNetworkCount) -Recommendation $LocalizedData.NetworkRedundancyBP
                            }
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingInterfaces {
                        Paragraph ($LocalizedData.ParagraphInterfaces -f $HvObjectName)
                        BlankLine
                        $TableParams = @{
                            Name = "$($LocalizedData.TableInterfaces) - $HvObjectName"
                            List = $false
                            ColumnWidths = $(if ($InfoLevel.Cluster -ge 2) { 18, 18, 26, 16, 12, 10 } else { 20, 20, 30, 18, 12 })
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $InterfaceObj | Table @TableParams
                    }
                }
            }
        } catch {
            Write-PScriboMessage -IsWarning $_.Exception.Message
        }
    }

    end {}
}
