function Get-AbrHvClusterQuorum {
    <#
    .SYNOPSIS
        Used by As Built Report to document the quorum and witness configuration of a failover cluster.
    .DESCRIPTION
        Documents the quorum model, the witness and the vote of every node. Health checks highlight
        clusters without a witness, a witness that is not online and disabled dynamic quorum.
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
        $LocalizedData = $reportTranslate.GetAbrHvClusterQuorum
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Cluster)
    }

    process {
        try {
            if ($InfoLevel.Cluster -ge 1 -and $HvClusterSession) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $QuorumData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $Cluster = Get-Cluster -ErrorAction Stop
                    $Quorum = Get-ClusterQuorum -ErrorAction Stop
                    $Witness = $Quorum.QuorumResource
                    $WitnessType = if ($Witness) { [string]$Witness.ResourceType.Name } else { $null }

                    # Only the target of the witness is read. The cloud witness access key is never requested.
                    $WitnessTarget = $null
                    $WitnessEndpoint = $null
                    if ($WitnessType -eq 'File Share Witness') {
                        $WitnessTarget = (Get-ClusterParameter -InputObject $Witness -Name 'SharePath' -ErrorAction SilentlyContinue).Value
                    } elseif ($WitnessType -eq 'Cloud Witness') {
                        $WitnessTarget = (Get-ClusterParameter -InputObject $Witness -Name 'AccountName' -ErrorAction SilentlyContinue).Value
                        $WitnessEndpoint = (Get-ClusterParameter -InputObject $Witness -Name 'EndpointInfo' -ErrorAction SilentlyContinue).Value
                    }

                    [PSCustomObject]@{
                        QuorumType = [string]$Quorum.QuorumType
                        WitnessName = $(if ($Witness) { [string]$Witness.Name } else { $null })
                        WitnessResourceType = $WitnessType
                        WitnessState = $(if ($Witness) { [string]$Witness.State } else { $null })
                        WitnessOwnerNode = $(if ($Witness) { [string]$Witness.OwnerNode } else { $null })
                        WitnessTarget = [string]$WitnessTarget
                        WitnessEndpoint = [string]$WitnessEndpoint
                        DynamicQuorum = $Cluster.DynamicQuorum
                        WitnessDynamicWeight = $Cluster.WitnessDynamicWeight
                        LowerQuorumPriorityNodeId = $Cluster.LowerQuorumPriorityNodeId
                        QuorumArbitrationTimeMax = $Cluster.QuorumArbitrationTimeMax
                        WitnessDatabaseWriteTimeout = $Cluster.WitnessDatabaseWriteTimeout
                        Nodes = @(Get-ClusterNode -ErrorAction Stop | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    Id = [string]$_.Id
                                    State = [string]$_.State
                                    NodeWeight = $_.NodeWeight
                                    DynamicWeight = $_.DynamicWeight
                                }
                            })
                    }
                }
                $QuorumState = Resolve-HvQuorumState -QuorumData $QuorumData

                # A file share witness on a virtual machine of the same cluster fails together with the cluster.
                $WitnessVm = $null
                if ($Healthcheck.Cluster.QuorumWitnessLocation -and $QuorumState.WitnessType -eq 'FileShare' -and $QuorumData.WitnessTarget) {
                    $VmIdentity = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.WitnessVmFailed -ScriptBlock {
                            foreach ($VM in @(Get-VM -ErrorAction SilentlyContinue)) {
                                # Guest host name from the Hyper-V data exchange (read-only CIM class).
                                $Kvp = Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName 'Msvm_KvpExchangeComponent' `
                                    -Filter "SystemName='$($VM.Id)'" -ErrorAction SilentlyContinue
                                $HostNames = foreach ($ItemXml in @($Kvp.GuestIntrinsicExchangeItems | Where-Object { $_ })) {
                                    $Xml = $ItemXml -as [xml]
                                    if ($Xml) {
                                        $Properties = @($Xml.INSTANCE.PROPERTY)
                                        if (($Properties | Where-Object { $_.NAME -eq 'Name' }).VALUE -eq 'FullyQualifiedDomainName') {
                                            [string]($Properties | Where-Object { $_.NAME -eq 'Data' }).VALUE
                                        }
                                    }
                                }
                                [PSCustomObject]@{
                                    Name = [string]$VM.Name
                                    HostNames = [string[]]@($HostNames | Where-Object { $_ })
                                    IPAddresses = [string[]]@(Get-VMNetworkAdapter -VM $VM -ErrorAction SilentlyContinue |
                                            ForEach-Object { @($_.IPAddresses) } | Where-Object { $_ } | ForEach-Object { [string]$_ })
                                }
                            }
                        })
                    $WitnessVm = Resolve-HvWitnessHost -SharePath $QuorumData.WitnessTarget -VM $VmIdentity
                }
                #endregion Collection

                #region Quorum configuration object
                $WitnessTypeLabel = if ($QuorumState.WitnessType -eq 'Other') {
                    $QuorumData.WitnessResourceType
                } else {
                    $LocalizedData["Witness$($QuorumState.WitnessType)"]
                }
                $QuorumObj = [ordered]@{
                    $LocalizedData.QuorumModel = $LocalizedData["Model$($QuorumState.QuorumModel)"]
                    $LocalizedData.WitnessType = $WitnessTypeLabel
                }
                if ($QuorumState.HasWitness) {
                    $QuorumObj[$LocalizedData.WitnessResource] = ConvertTo-HvDisplayValue $QuorumData.WitnessName
                    $QuorumObj[$LocalizedData.WitnessState] = ConvertTo-HvDisplayValue $QuorumData.WitnessState
                    if ($QuorumState.WitnessType -eq 'FileShare') {
                        $QuorumObj[$LocalizedData.WitnessSharePath] = ConvertTo-HvDisplayValue $QuorumData.WitnessTarget
                    } elseif ($QuorumState.WitnessType -eq 'Cloud') {
                        $QuorumObj[$LocalizedData.WitnessAccount] = ConvertTo-HvDisplayValue $QuorumData.WitnessTarget
                        $QuorumObj[$LocalizedData.WitnessEndpoint] = ConvertTo-HvDisplayValue $QuorumData.WitnessEndpoint
                    }
                    $QuorumObj[$LocalizedData.WitnessOwnerNode] = ConvertTo-HvDisplayValue $QuorumData.WitnessOwnerNode
                    $QuorumObj[$LocalizedData.WitnessVote] = ConvertTo-HvDisplayValue $QuorumState.WitnessHasVote
                }
                $QuorumObj[$LocalizedData.VotingNodes] = '{0} / {1}' -f $QuorumState.VotingNodeCount, @($QuorumData.Nodes).Count
                $QuorumObj[$LocalizedData.DynamicQuorum] = ConvertTo-HvDisplayValue $QuorumState.DynamicQuorum
                if ($InfoLevel.Cluster -ge 2) {
                    $QuorumObj[$LocalizedData.LowerPriorityNode] = $(if ($QuorumState.LowerPriorityNodeName) {
                            $QuorumState.LowerPriorityNodeName
                        } else {
                            $LocalizedData.ValueNone
                        })
                    $QuorumObj[$LocalizedData.ArbitrationTime] = ConvertTo-HvDisplayValue $QuorumData.QuorumArbitrationTimeMax
                    $QuorumObj[$LocalizedData.WitnessWriteTimeout] = ConvertTo-HvDisplayValue $QuorumData.WitnessDatabaseWriteTimeout
                }
                $QuorumObj = [PSCustomObject]$QuorumObj
                #endregion Quorum configuration object

                #region Node vote objects
                $VoteObj = foreach ($Node in @($QuorumData.Nodes | Sort-Object -Property Name)) {
                    [PSCustomObject][ordered]@{
                        $LocalizedData.NodeName = $Node.Name
                        $LocalizedData.State = $Node.State
                        $LocalizedData.AssignedVote = ConvertTo-HvDisplayValue ([int]$Node.NodeWeight -eq 1)
                        $LocalizedData.CurrentVote = ConvertTo-HvDisplayValue ([int]$Node.DynamicWeight -eq 1)
                    }
                }
                #endregion Node vote objects

                #region Health checks
                $Findings = @($QuorumState.Findings)
                $ShowWitnessCheck = ($Healthcheck.Cluster.QuorumWitness -and
                    ($Findings -contains 'NoWitnessTwoNodes' -or $Findings -contains 'NoWitness'))
                $ShowWitnessStateCheck = ($Healthcheck.Cluster.QuorumWitnessState -and $Findings -contains 'WitnessNotOnline')
                $ShowDynamicQuorumCheck = ($Healthcheck.Cluster.DynamicQuorum -and $Findings -contains 'DynamicQuorumDisabled')
                if ($ShowWitnessCheck) {
                    $WitnessStyle = if ($Findings -contains 'NoWitnessTwoNodes') { 'Critical' } else { 'Warning' }
                    $QuorumObj | Set-Style -Style $WitnessStyle -Property $LocalizedData.WitnessType
                }
                if ($ShowWitnessStateCheck) {
                    $QuorumObj | Set-Style -Style Critical -Property $LocalizedData.WitnessState
                }
                if ($ShowDynamicQuorumCheck) {
                    $QuorumObj | Set-Style -Style Warning -Property $LocalizedData.DynamicQuorum
                }
                $ShowWitnessLocationCheck = [bool]$WitnessVm
                if ($ShowWitnessLocationCheck) {
                    $QuorumObj | Set-Style -Style Critical -Property $LocalizedData.WitnessSharePath
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
                        $QuorumObj | Table @TableParams

                        if ($ShowWitnessCheck -or $ShowWitnessStateCheck -or $ShowDynamicQuorumCheck -or $ShowWitnessLocationCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if ($ShowWitnessCheck) {
                                if ($Findings -contains 'NoWitnessTwoNodes') {
                                    Paragraph $LocalizedData.NoWitnessTwoNodesBP
                                } else {
                                    Paragraph $LocalizedData.NoWitnessBP
                                }
                                BlankLine
                            }
                            if ($ShowWitnessStateCheck) {
                                Paragraph ($LocalizedData.WitnessStateBP -f $QuorumData.WitnessName, $QuorumData.WitnessState)
                                BlankLine
                            }
                            if ($ShowWitnessLocationCheck) {
                                Paragraph ($LocalizedData.WitnessLocationBP -f $QuorumData.WitnessTarget, $WitnessVm)
                                BlankLine
                            }
                            if ($ShowDynamicQuorumCheck) {
                                Paragraph $LocalizedData.DynamicQuorumBP
                                BlankLine
                            }
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingVotes {
                        Paragraph ($LocalizedData.ParagraphVotes -f $HvObjectName)
                        BlankLine
                        $TableParams = @{
                            Name = "$($LocalizedData.TableVotes) - $HvObjectName"
                            List = $false
                            ColumnWidths = 34, 22, 22, 22
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $VoteObj | Table @TableParams
                    }
                }
            }
        } catch {
            Write-PScriboMessage -IsWarning $_.Exception.Message
        }
    }

    end {}
}
