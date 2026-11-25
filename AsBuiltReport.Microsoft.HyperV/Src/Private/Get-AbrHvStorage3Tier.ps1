function Get-AbrHvStorage3Tier {
    <#
    .SYNOPSIS
        Used by As Built Report to document shared block storage (3-tier) of a cluster or host.
    .DESCRIPTION
        Documents the iSCSI sessions, Fibre Channel initiator ports, the Multipath I/O configuration, the
        shared disks with their number of paths and the physical disk resources of the cluster.
        InfoLevel 2 adds the iSCSI target portals and initiator names, further MPIO settings and the
        supported hardware list.
        Health checks highlight shared disks with a single path or without MPIO, iSCSI sessions that are not
        connected or not persistent, and cluster disks that are not online.
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
        $LocalizedData = $reportTranslate.GetAbrHvStorage3Tier
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Storage3Tier)
    }

    process {
        try {
            $SharedTopology = @(@($HvEnvironment.StorageTopology) | Where-Object { $_ -in 'iSCSI', 'FibreChannel', 'SharedSAS' })
            if ($InfoLevel.Storage3Tier -ge 1 -and $HvNodeSessions.Count -gt 0 -and $SharedTopology.Count -gt 0) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)
                $IsCluster = [bool]$HvClusterSession

                #region Collection
                $StorageData = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.HostFailed -ArgumentList $IsCluster -ScriptBlock {
                        param ($IsCluster)
                        $InitiatorPorts = @(Get-InitiatorPort -ErrorAction SilentlyContinue)
                        $HasIscsi = [bool](Get-Command -Name 'Get-IscsiSession' -ErrorAction SilentlyContinue)
                        $MpioFeature = Get-WindowsFeature -Name 'Multipath-IO' -ErrorAction SilentlyContinue
                        $MpioInstalled = [bool]($MpioFeature -and $MpioFeature.Installed)

                        # MPIO path count per disk serial number (read-only WMI class of the MPIO driver).
                        $PathCount = @{}
                        if ($MpioInstalled) {
                            foreach ($DiskInfo in @(Get-CimInstance -Namespace 'root\wmi' -ClassName 'MPIO_DISK_INFO' -ErrorAction SilentlyContinue)) {
                                foreach ($Drive in @($DiskInfo.DriveInfo | Where-Object { $_ })) {
                                    $PathCount[([string]$Drive.SerialNumber).Trim()] = [int]$Drive.NumberPaths
                                }
                            }
                        }

                        $Mpio = $null
                        if ($MpioInstalled -and (Get-Command -Name 'Get-MSDSMGlobalDefaultLoadBalancePolicy' -ErrorAction SilentlyContinue)) {
                            $Setting = Get-MPIOSetting -ErrorAction SilentlyContinue
                            $AutoClaim = Get-MSDSMAutomaticClaimSettings -ErrorAction SilentlyContinue
                            $Mpio = [PSCustomObject]@{
                                LoadBalancePolicy = [string](Get-MSDSMGlobalDefaultLoadBalancePolicy -ErrorAction SilentlyContinue)
                                AutoClaimBusTypes = [string[]]@($(if ($AutoClaim) {
                                            $AutoClaim.Keys | Where-Object { $AutoClaim[$_] } | ForEach-Object { [string]$_ }
                                        }))
                                PathVerification = [string]$Setting.PathVerificationState
                                PathVerificationPeriod = [string]$Setting.PathVerificationPeriod
                                PdoRemovePeriod = [string]$Setting.PDORemovePeriod
                                RetryCount = [string]$Setting.RetryCount
                                DiskTimeout = [string]$Setting.DiskTimeoutValue
                                SupportedHardware = [string[]]@(Get-MSDSMSupportedHW -ErrorAction SilentlyContinue | ForEach-Object {
                                        '{0} {1}' -f ([string]$_.VendorId).Trim(), ([string]$_.ProductId).Trim()
                                    })
                            }
                        }

                        # Shared disks: iSCSI and Fibre Channel always, SAS only when the disk is clustered.
                        $Disks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object {
                                $Bus = [string]$_.BusType
                                $Bus -in 'iSCSI', 'FibreChannel', 'Fibre Channel' -or ($Bus -eq 'SAS' -and $IsCluster -and $_.IsClustered)
                            } | ForEach-Object {
                                $Serial = ([string]$_.SerialNumber).Trim()
                                [PSCustomObject]@{
                                    Number = [string]$_.Number
                                    FriendlyName = [string]$_.FriendlyName
                                    SerialNumber = $Serial
                                    BusType = [string]$_.BusType
                                    Size = [double]$_.Size
                                    IsClustered = [string][bool]$_.IsClustered
                                    Paths = $(if ($PathCount.ContainsKey($Serial)) { $PathCount[$Serial] } else { $null })
                                }
                            })

                        $IscsiSessions = @()
                        $IscsiPortals = @()
                        if ($HasIscsi) {
                            $IscsiSessions = @(Get-IscsiSession -ErrorAction SilentlyContinue | ForEach-Object {
                                    $Session = $_
                                    $Connections = @(Get-IscsiConnection -IscsiSession $Session -ErrorAction SilentlyContinue)
                                    [PSCustomObject]@{
                                        TargetNodeAddress = [string]$Session.TargetNodeAddress
                                        IsConnected = [string][bool]$Session.IsConnected
                                        IsPersistent = [string][bool]$Session.IsPersistent
                                        Connections = $Connections.Count
                                        InitiatorAddresses = [string[]]@($Connections | ForEach-Object { [string]$_.InitiatorAddress } | Select-Object -Unique)
                                        TargetAddresses = [string[]]@($Connections | ForEach-Object {
                                                '{0}:{1}' -f $_.TargetAddress, $_.TargetPortNumber
                                            } | Select-Object -Unique)
                                    }
                                })
                            $IscsiPortals = @(Get-IscsiTargetPortal -ErrorAction SilentlyContinue | ForEach-Object {
                                    [PSCustomObject]@{
                                        Address = [string]$_.TargetPortalAddress
                                        Port = [string]$_.TargetPortalPortNumber
                                        InitiatorAddress = [string]$_.InitiatorPortalAddress
                                    }
                                })
                        }

                        [PSCustomObject]@{
                            MpioInstalled = [string]$MpioInstalled
                            Mpio = $Mpio
                            Disks = $Disks
                            IscsiSessions = $IscsiSessions
                            IscsiPortals = $IscsiPortals
                            IscsiInitiator = [string[]]@($InitiatorPorts | Where-Object { [string]$_.ConnectionType -eq 'iSCSI' } |
                                    ForEach-Object { [string]$_.NodeAddress })
                            FcPorts = @($InitiatorPorts | Where-Object { [string]$_.ConnectionType -match '^Fibre ?Channel$' } | ForEach-Object {
                                    [PSCustomObject]@{
                                        NodeAddress = [string]$_.NodeAddress
                                        PortAddress = [string]$_.PortAddress
                                        OperationalStatus = [string](@($_.OperationalStatus) -join ', ')
                                    }
                                })
                        }
                    } | Sort-Object -Property NodeName)

                $ClusterDisks = @()
                if ($IsCluster) {
                    $ClusterDisks = @(Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                            Get-ClusterResource -ErrorAction Stop | Where-Object { [string]$_.ResourceType -eq 'Physical Disk' } | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    OwnerGroup = [string]$_.OwnerGroup
                                    OwnerNode = [string]$_.OwnerNode
                                    State = [string]$_.State
                                    IsCsv = 'False'
                                }
                            }
                            # Disks added to Cluster Shared Volumes are no longer listed as cluster resources.
                            Get-ClusterSharedVolume -ErrorAction SilentlyContinue | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    OwnerGroup = ''
                                    OwnerNode = [string]$_.OwnerNode
                                    State = [string]$_.State
                                    IsCsv = 'True'
                                }
                            }
                        } | Sort-Object -Property Name)
                }

                $Findings = @(foreach ($HostItem in $StorageData) {
                        Resolve-HvStoragePath -StorageData $HostItem | ForEach-Object {
                            $_ | Add-Member -MemberType NoteProperty -Name 'NodeName' -Value $HostItem.NodeName -PassThru
                        }
                    })
                #endregion Collection

                #region Objects
                $SessionObj = @(foreach ($HostItem in $StorageData) {
                        foreach ($Session in @($HostItem.IscsiSessions | Sort-Object -Property TargetNodeAddress)) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.Target = $Session.TargetNodeAddress
                                $LocalizedData.InitiatorAddress = ConvertTo-HvDisplayValue $Session.InitiatorAddresses
                                $LocalizedData.TargetAddress = ConvertTo-HvDisplayValue $Session.TargetAddresses
                                $LocalizedData.Connections = $Session.Connections
                                $LocalizedData.Persistent = ConvertTo-HvDisplayValue ($Session.IsPersistent -eq 'True')
                                $LocalizedData.Connected = ConvertTo-HvDisplayValue ($Session.IsConnected -eq 'True')
                            }
                        }
                    })
                $PortalObj = @()
                if ($InfoLevel.Storage3Tier -ge 2) {
                    $PortalObj = @(foreach ($HostItem in $StorageData) {
                            foreach ($Portal in @($HostItem.IscsiPortals)) {
                                [PSCustomObject][ordered]@{
                                    $LocalizedData.HostName = $HostItem.NodeName
                                    $LocalizedData.InitiatorName = ConvertTo-HvDisplayValue $HostItem.IscsiInitiator
                                    $LocalizedData.Portal = '{0}:{1}' -f $Portal.Address, $Portal.Port
                                    $LocalizedData.InitiatorAddress = ConvertTo-HvDisplayValue $Portal.InitiatorAddress
                                }
                            }
                        })
                }

                $FcObj = @(foreach ($HostItem in $StorageData) {
                        foreach ($Port in @($HostItem.FcPorts)) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.Wwnn = ConvertTo-HvDisplayValue $Port.NodeAddress
                                $LocalizedData.Wwpn = ConvertTo-HvDisplayValue $Port.PortAddress
                                $LocalizedData.Status = ConvertTo-HvDisplayValue $Port.OperationalStatus
                            }
                        }
                    })

                $MpioObj = @(foreach ($HostItem in $StorageData) {
                        $Mpio = $HostItem.Mpio
                        $PolicyLabel = if ($Mpio -and $Mpio.LoadBalancePolicy) { $LocalizedData["Policy$($Mpio.LoadBalancePolicy)"] }
                        $InObj = [ordered]@{
                            $LocalizedData.HostName = $HostItem.NodeName
                            $LocalizedData.MpioInstalled = ConvertTo-HvDisplayValue ($HostItem.MpioInstalled -eq 'True')
                            $LocalizedData.LoadBalancePolicy = $(if ($PolicyLabel) { $PolicyLabel } elseif ($Mpio) { ConvertTo-HvDisplayValue $Mpio.LoadBalancePolicy } else { '--' })
                            $LocalizedData.AutoClaim = $(if ($Mpio) { ConvertTo-HvDisplayValue $Mpio.AutoClaimBusTypes } else { '--' })
                            $LocalizedData.PathVerification = $(if ($Mpio) { ConvertTo-HvDisplayValue $Mpio.PathVerification } else { '--' })
                        }
                        if ($InfoLevel.Storage3Tier -ge 2) {
                            $InObj[$LocalizedData.PdoRemovePeriod] = $(if ($Mpio) { ConvertTo-HvDisplayValue $Mpio.PdoRemovePeriod } else { '--' })
                            $InObj[$LocalizedData.DiskTimeout] = $(if ($Mpio) { ConvertTo-HvDisplayValue $Mpio.DiskTimeout } else { '--' })
                            $InObj[$LocalizedData.SupportedHardware] = $(if ($Mpio) { ConvertTo-HvDisplayValue $Mpio.SupportedHardware } else { '--' })
                        }
                        [PSCustomObject]$InObj
                    })

                $DiskObj = @(foreach ($HostItem in $StorageData) {
                        foreach ($Disk in @($HostItem.Disks | Sort-Object -Property { [int]$_.Number })) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.DiskNumber = $Disk.Number
                                $LocalizedData.DiskName = ConvertTo-HvDisplayValue $Disk.FriendlyName
                                $LocalizedData.BusType = ConvertTo-HvDisplayValue $Disk.BusType
                                $LocalizedData.Size = ConvertTo-HvSize $Disk.Size
                                $LocalizedData.Paths = $(if ($null -ne $Disk.Paths -and [string]$Disk.Paths -ne '') { [string]$Disk.Paths } else { $LocalizedData.ValueNotClaimed })
                                $LocalizedData.Clustered = ConvertTo-HvDisplayValue ($Disk.IsClustered -eq 'True')
                            }
                        }
                    })

                $ClusterDiskObj = @(foreach ($Disk in $ClusterDisks) {
                        [PSCustomObject][ordered]@{
                            $LocalizedData.ResourceName = $Disk.Name
                            $LocalizedData.OwnerGroup = ConvertTo-HvDisplayValue $Disk.OwnerGroup
                            $LocalizedData.OwnerNode = ConvertTo-HvDisplayValue $Disk.OwnerNode
                            $LocalizedData.State = ConvertTo-HvDisplayValue $Disk.State
                            $LocalizedData.Csv = ConvertTo-HvDisplayValue ($Disk.IsCsv -eq 'True')
                        }
                    })
                #endregion Objects

                #region Health checks
                $PathFindings = @($Findings | Where-Object { $_.Check -in 'MpioMissing', 'SinglePath' })
                $ShowPathCheck = ($Healthcheck.Storage3Tier.PathRedundancy -and $PathFindings.Count -gt 0)
                if ($ShowPathCheck) {
                    foreach ($Finding in @($PathFindings | Where-Object { $_.Check -eq 'MpioMissing' })) {
                        $MpioObj | Where-Object { $_.$($LocalizedData.HostName) -eq $Finding.NodeName } |
                            Set-Style -Style Warning -Property $LocalizedData.MpioInstalled
                    }
                    foreach ($Finding in @($PathFindings | Where-Object { $_.Check -eq 'SinglePath' })) {
                        $Number = ([string]$Finding.Object).Split(' ')[0]
                        $DiskObj | Where-Object { $_.$($LocalizedData.HostName) -eq $Finding.NodeName -and $_.$($LocalizedData.DiskNumber) -eq $Number } |
                            Set-Style -Style Warning -Property $LocalizedData.Paths
                    }
                }
                $SessionFindings = @($Findings | Where-Object { $_.Check -in 'IscsiNotConnected', 'IscsiNotPersistent' })
                $ShowSessionCheck = ($Healthcheck.Storage3Tier.IscsiSession -and $SessionFindings.Count -gt 0)
                if ($ShowSessionCheck) {
                    foreach ($Finding in $SessionFindings) {
                        $Column = if ($Finding.Check -eq 'IscsiNotConnected') { $LocalizedData.Connected } else { $LocalizedData.Persistent }
                        $SessionObj | Where-Object { $_.$($LocalizedData.HostName) -eq $Finding.NodeName -and $_.$($LocalizedData.Target) -eq $Finding.Object } |
                            Set-Style -Style $Finding.Severity -Property $Column
                    }
                }
                $DiskIssues = @($ClusterDisks | Where-Object { (ConvertTo-HvResourceSeverity $_.State) -ne 'Ok' })
                $ShowClusterDiskCheck = ($Healthcheck.Storage3Tier.ClusterDiskState -and $DiskIssues.Count -gt 0)
                if ($ShowClusterDiskCheck) {
                    foreach ($Disk in $DiskIssues) {
                        $ClusterDiskObj | Where-Object { $_.$($LocalizedData.ResourceName) -eq $Disk.Name } |
                            Set-Style -Style (ConvertTo-HvResourceSeverity $Disk.State) -Property $LocalizedData.State
                    }
                }
                $FindingList = {
                    param ([String[]] $CheckNames)
                    (@($Findings | Where-Object { $_.Check -in $CheckNames } | ForEach-Object {
                                if ($_.Object) { '{0} ({1})' -f $_.Object, $_.NodeName } else { $_.NodeName }
                            }) -join ', ')
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    if ($SessionObj.Count -gt 0 -or $PortalObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingIscsi {
                            if ($SessionObj.Count -gt 0) {
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableIscsiSessions) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 14, 28, 14, 16, 9, 10, 9
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $SessionObj | Table @TableParams
                            } else {
                                Paragraph $LocalizedData.NoIscsiSessions
                            }
                            if ($ShowSessionCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                if (@($SessionFindings | Where-Object { $_.Check -eq 'IscsiNotConnected' }).Count -gt 0) {
                                    Write-HvHealthCheck -Area $LocalizedData.Heading -Severity Critical -Finding ($LocalizedData.IscsiNotConnectedFinding -f (& $FindingList 'IscsiNotConnected')) -Recommendation $LocalizedData.IscsiNotConnectedBP
                                }
                                if (@($SessionFindings | Where-Object { $_.Check -eq 'IscsiNotPersistent' }).Count -gt 0) {
                                    Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.IscsiNotPersistentFinding -f (& $FindingList 'IscsiNotPersistent')) -Recommendation $LocalizedData.IscsiNotPersistentBP
                                }
                            }
                            if ($PortalObj.Count -gt 0) {
                                BlankLine
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableIscsiPortals) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 18, 42, 20, 20
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $PortalObj | Table @TableParams
                            }
                        }
                    }

                    if ($FcObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingFc {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableFc) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 28, 28, 22
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $FcObj | Table @TableParams
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingMpio {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableMpio) - $HvObjectName"
                            List = $false
                        }
                        if ($InfoLevel.Storage3Tier -ge 2) {
                            $TableParams['ColumnWidths'] = 12, 9, 13, 12, 11, 10, 10, 23
                        } else {
                            $TableParams['ColumnWidths'] = 20, 14, 24, 22, 20
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $MpioObj | Table @TableParams
                    }

                    Section -Style Heading3 $LocalizedData.HeadingDisks {
                        if ($DiskObj.Count -eq 0) {
                            Paragraph $LocalizedData.NoDisks
                        } else {
                            Paragraph $LocalizedData.ParagraphDisks
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableDisks) - $HvObjectName"
                                List = $false
                                ColumnWidths = 16, 9, 25, 13, 13, 12, 12
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $DiskObj | Table @TableParams
                        }
                        if ($ShowPathCheck) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            if (@($PathFindings | Where-Object { $_.Check -eq 'MpioMissing' }).Count -gt 0) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.MpioMissingFinding -f (& $FindingList 'MpioMissing')) -Recommendation $LocalizedData.MpioMissingBP
                            }
                            if (@($PathFindings | Where-Object { $_.Check -eq 'SinglePath' }).Count -gt 0) {
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.SinglePathFinding -f (& $FindingList 'SinglePath')) -Recommendation $LocalizedData.SinglePathBP
                            }
                        }
                    }

                    if ($ClusterDiskObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingClusterDisks {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableClusterDisks) - $HvObjectName"
                                List = $false
                                ColumnWidths = 28, 24, 18, 15, 15
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ClusterDiskObj | Table @TableParams
                            if ($ShowClusterDiskCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Write-HvHealthCheck -Area $LocalizedData.Heading -Severity (Get-HvMaxSeverity @($DiskIssues | ForEach-Object { ConvertTo-HvResourceSeverity $_.State })) -Finding ($LocalizedData.ClusterDiskStateFinding -f (($DiskIssues | ForEach-Object { $_.Name }) -join ', ')) -Recommendation $LocalizedData.ClusterDiskStateBP
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
