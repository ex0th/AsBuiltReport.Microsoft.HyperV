function Get-AbrHvEnvironmentType {
    <#
    .SYNOPSIS
        Used by As Built Report to document the detected Hyper-V environment type and storage topology.
    .DESCRIPTION
        Renders the result of Resolve-HvEnvironmentType, which the main function computes once per target
        because it also decides which cluster, networking and storage sections are relevant.
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
        $LocalizedData = $reportTranslate.GetAbrHvEnvironmentType
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Environment)
    }

    process {
        try {
            if ($InfoLevel.Environment -ge 1 -and $HvEnvironment) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                $TopologyLabels = @($HvEnvironment.StorageTopology | ForEach-Object { $LocalizedData["Topology$_"] })
                $NodesWithoutHyperV = @($HvEnvironment.NodesWithoutHyperV | Where-Object { $_ })
                $HyperVNodeCount = $HvEnvironment.ReachableNodeCount - $NodesWithoutHyperV.Count

                $SummaryObj = [PSCustomObject][ordered]@{
                    $LocalizedData.EnvironmentType = $LocalizedData["Env$($HvEnvironment.EnvironmentType)"]
                    $LocalizedData.Platform = $LocalizedData["Platform$($HvEnvironment.Platform)"]
                    $LocalizedData.DeploymentModel = $(if ($HvEnvironment.IsCluster) { $LocalizedData.DeploymentCluster } else { $LocalizedData.DeploymentStandalone })
                    $LocalizedData.StorageTopology = ConvertTo-HvDisplayValue $TopologyLabels
                    $LocalizedData.Nodes = ('{0} / {1}' -f $HvEnvironment.ReachableNodeCount, $HvEnvironment.NodeCount)
                    $LocalizedData.HyperVRole = ('{0} / {1}' -f $HyperVNodeCount, $HvEnvironment.ReachableNodeCount)
                    $LocalizedData.Mpio = ConvertTo-HvDisplayValue $HvEnvironment.UsesMpio
                    $LocalizedData.Rdma = ConvertTo-HvDisplayValue $HvEnvironment.UsesRdma
                    $LocalizedData.Dcb = ConvertTo-HvDisplayValue $HvEnvironment.UsesDcb
                    $LocalizedData.SetSwitch = ConvertTo-HvDisplayValue $HvEnvironment.UsesSet
                    $LocalizedData.DetectionMode = $LocalizedData["Detection$($HvEnvironment.DetectionMode)"]
                }

                $NodesUnreachable = ($HvEnvironment.ReachableNodeCount -lt $HvEnvironment.NodeCount)
                if ($Healthcheck.Environment.NodeReachability -and $NodesUnreachable) {
                    $SummaryObj | Set-Style -Style Critical -Property $LocalizedData.Nodes
                }
                if ($Healthcheck.Environment.HyperVRole -and $NodesWithoutHyperV.Count -gt 0) {
                    $SummaryObj | Set-Style -Style Critical -Property $LocalizedData.HyperVRole
                }

                $EvidenceObj = @()
                if ($InfoLevel.Environment -ge 2) {
                    foreach ($Item in $HvEnvironment.Evidence) {
                        try {
                            $Indicates = if ($Item.Indicates) {
                                $Label = $LocalizedData["Indicates$($Item.Indicates)"]
                                if ($Label) { $Label } else { $LocalizedData["Topology$($Item.Indicates)"] }
                            } else {
                                $null
                            }
                            # Fixed wording (e.g. 'Installed') is translated via ValueKey; other values are shown as collected.
                            $Value = $Item.Value
                            if ($Item.ValueKey -and $LocalizedData["Value$($Item.ValueKey)"]) {
                                $Value = $LocalizedData["Value$($Item.ValueKey)"] -f @($Item.ValueArgs)
                            }
                            $EvidenceObj += [PSCustomObject][ordered]@{
                                $LocalizedData.Check = $(if ($LocalizedData["Check$($Item.Check)"]) { $LocalizedData["Check$($Item.Check)"] } else { $Item.Check })
                                $LocalizedData.Scope = ConvertTo-HvDisplayValue $Item.Scope
                                $LocalizedData.Value = ConvertTo-HvDisplayValue $Value
                                $LocalizedData.Indicates = ConvertTo-HvDisplayValue $Indicates
                            }
                        } catch {
                            Write-PScriboMessage -IsWarning $_.Exception.Message
                        }
                    }
                }

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    $TableParams = @{
                        Name = "$($LocalizedData.TableEnvironment) - $HvObjectName"
                        List = $true
                        ColumnWidths = 40, 60
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $SummaryObj | Table @TableParams

                    $ShowReachabilityCheck = ($Healthcheck.Environment.NodeReachability -and $NodesUnreachable)
                    $ShowHyperVRoleCheck = ($Healthcheck.Environment.HyperVRole -and $NodesWithoutHyperV.Count -gt 0)
                    if ($ShowReachabilityCheck -or $ShowHyperVRoleCheck) {
                        Paragraph $LocalizedData.HealthCheck -Bold -Underline
                        BlankLine
                        if ($ShowReachabilityCheck) {
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Severity Critical -Finding $LocalizedData.NodeReachabilityFinding -Recommendation $LocalizedData.NodeReachabilityBP
                        }
                        if ($ShowHyperVRoleCheck) {
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Severity Critical -Finding ($LocalizedData.HyperVRoleFinding -f ($NodesWithoutHyperV -join ', ')) -Recommendation $LocalizedData.HyperVRoleBP
                        }
                    }

                    if ($EvidenceObj) {
                        Section -Style Heading3 $LocalizedData.HeadingEvidence {
                            Paragraph ($LocalizedData.ParagraphEvidence -f $HvObjectName)
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableEvidence) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 18, 40, 20
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $EvidenceObj | Sort-Object -Property $LocalizedData.Scope, $LocalizedData.Check | Table @TableParams
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
