function Get-AbrHvStorageS2D {
    <#
    .SYNOPSIS
        Used by As Built Report to document Storage Spaces Direct of a failover cluster.
    .DESCRIPTION
        Documents the Storage Spaces Direct configuration and cache, the storage pool with capacity and
        reserve, the physical disks per node, the virtual disks with resiliency, running storage jobs and
        current health faults. InfoLevel 2 adds every physical disk, the storage tiers and the fault domains.
        Health checks highlight unhealthy pools, virtual disks and physical disks, a reserve below the
        recommendation, running repair jobs and health faults.
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
        $LocalizedData = $reportTranslate.GetAbrHvStorageS2D
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.StorageS2D)
    }

    process {
        try {
            if ($InfoLevel.StorageS2D -ge 1 -and $HvClusterSession -and @($HvEnvironment.StorageTopology) -contains 'S2D') {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $S2DData = Invoke-Command -Session $HvClusterSession -ErrorAction Stop -ScriptBlock {
                    $S2D = Get-ClusterStorageSpacesDirect -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    $Pools = @(Get-StoragePool -IsPrimordial $false -ErrorAction Stop | Where-Object { $_.IsClustered -ne $false })

                    # Physical disk to node mapping. A node can appear in several storage subsystems.
                    $DiskNode = @{}
                    foreach ($StorageNode in @(Get-StorageNode -ErrorAction SilentlyContinue)) {
                        foreach ($Disk in @($StorageNode | Get-PhysicalDisk -PhysicallyConnected -ErrorAction SilentlyContinue)) {
                            $DiskNode[[string]$Disk.UniqueId] = [string]$StorageNode.Name
                        }
                    }

                    $FaultDomainCount = [ordered]@{}
                    foreach ($Type in 'StorageSite', 'StorageRack', 'StorageChassis', 'StorageScaleUnit') {
                        $FaultDomainCount[$Type] = @(Get-StorageFaultDomain -Type $Type -ErrorAction SilentlyContinue).Count
                    }

                    $Faults = @()
                    if (Get-Command -Name 'Get-HealthFault' -ErrorAction SilentlyContinue) {
                        $Faults = @(Get-HealthFault -ErrorAction SilentlyContinue | ForEach-Object {
                                [PSCustomObject]@{
                                    Severity = [string]$_.PerceivedSeverity
                                    FaultType = [string]$_.FaultType
                                    Object = [string]$_.FaultingObjectDescription
                                    Reason = [string]$_.Reason
                                }
                            })
                    }

                    [PSCustomObject]@{
                        S2D = $(if ($S2D) {
                                [PSCustomObject]@{
                                    State = [string]$S2D.State
                                    CacheState = [string]$S2D.CacheState
                                    CacheModeSSD = [string]$S2D.CacheModeSSD
                                    CacheModeHDD = [string]$S2D.CacheModeHDD
                                    CachePageSizeKBytes = [string]$S2D.CachePageSizeKBytes
                                    CacheMetadataReserveBytes = $S2D.CacheMetadataReserveBytes
                                }
                            })
                        Pools = @(foreach ($Pool in $Pools) {
                                [PSCustomObject]@{
                                    Name = [string]$Pool.FriendlyName
                                    HealthStatus = [string]$Pool.HealthStatus
                                    OperationalStatus = [string]$Pool.OperationalStatus
                                    Size = [double]$Pool.Size
                                    AllocatedSize = [double]$Pool.AllocatedSize
                                    FaultDomainAwareness = [string]$Pool.FaultDomainAwarenessDefault
                                    ResiliencyDefault = [string]$Pool.ResiliencySettingNameDefault
                                    Version = [string]$Pool.Version
                                    PhysicalDisks = @($Pool | Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
                                            [PSCustomObject]@{
                                                Node = [string]$DiskNode[[string]$_.UniqueId]
                                                SerialNumber = [string]$_.SerialNumber
                                                Model = [string]$_.Model
                                                MediaType = [string]$_.MediaType
                                                BusType = [string]$_.BusType
                                                Size = [double]$_.Size
                                                Usage = [string]$_.Usage
                                                FirmwareVersion = [string]$_.FirmwareVersion
                                                HealthStatus = [string]$_.HealthStatus
                                                OperationalStatus = [string](@($_.OperationalStatus) -join ', ')
                                            }
                                        })
                                    VirtualDisks = @($Pool | Get-VirtualDisk -ErrorAction SilentlyContinue | ForEach-Object {
                                            $VirtualDisk = $_
                                            [PSCustomObject]@{
                                                Name = [string]$VirtualDisk.FriendlyName
                                                ResiliencySettingName = [string]$VirtualDisk.ResiliencySettingName
                                                NumberOfDataCopies = [string]$VirtualDisk.NumberOfDataCopies
                                                PhysicalDiskRedundancy = [string]$VirtualDisk.PhysicalDiskRedundancy
                                                Size = [double]$VirtualDisk.Size
                                                FootprintOnPool = [double]$VirtualDisk.FootprintOnPool
                                                HealthStatus = [string]$VirtualDisk.HealthStatus
                                                OperationalStatus = [string](@($VirtualDisk.OperationalStatus) -join ', ')
                                                ProvisioningType = [string]$VirtualDisk.ProvisioningType
                                                Tiers = @(Get-StorageTier -VirtualDisk $VirtualDisk -ErrorAction SilentlyContinue | ForEach-Object {
                                                        [PSCustomObject]@{
                                                            Name = [string]$_.FriendlyName
                                                            ResiliencySettingName = [string]$_.ResiliencySettingName
                                                            NumberOfDataCopies = [string]$_.NumberOfDataCopies
                                                            PhysicalDiskRedundancy = [string]$_.PhysicalDiskRedundancy
                                                            MediaType = [string]$_.MediaType
                                                            ProvisioningType = [string]$_.ProvisioningType
                                                            Size = [double]$_.Size
                                                        }
                                                    })
                                            }
                                        })
                                }
                            })
                        FaultDomainCount = [PSCustomObject]$FaultDomainCount
                        Jobs = @(Get-StorageJob -ErrorAction SilentlyContinue | ForEach-Object {
                                [PSCustomObject]@{
                                    Name = [string]$_.Name
                                    JobState = [string]$_.JobState
                                    PercentComplete = $_.PercentComplete
                                    BytesProcessed = $_.BytesProcessed
                                    BytesTotal = $_.BytesTotal
                                }
                            })
                        Faults = $Faults
                    }
                }
                $Pools = @($S2DData.Pools | Where-Object { $_ })
                $NodeCount = @($HvNodeFacts).Count
                foreach ($Pool in $Pools) {
                    foreach ($Disk in @($Pool.PhysicalDisks)) {
                        if ($Disk.Node) {
                            $Disk.Node = Get-HvNodeName -Fqdn $Disk.Node
                        }
                    }
                }
                #endregion Collection

                #region Objects
                $FormatResiliency = {
                    param ($Item)
                    $Key = Resolve-HvResiliency -ResiliencySettingName $Item.ResiliencySettingName `
                        -NumberOfDataCopies $Item.NumberOfDataCopies -PhysicalDiskRedundancy $Item.PhysicalDiskRedundancy
                    $Label = if ($Key) { $LocalizedData["Resiliency$Key"] }
                    if ($Label) { $Label } else { ConvertTo-HvDisplayValue $Key }
                }

                $ConfigObj = $null
                if ($S2DData.S2D) {
                    $ConfigHash = [ordered]@{
                        $LocalizedData.S2DState = ConvertTo-HvDisplayValue $S2DData.S2D.State
                        $LocalizedData.CacheState = ConvertTo-HvDisplayValue $S2DData.S2D.CacheState
                        $LocalizedData.CacheModeSSD = ConvertTo-HvDisplayValue $S2DData.S2D.CacheModeSSD
                        $LocalizedData.CacheModeHDD = ConvertTo-HvDisplayValue $S2DData.S2D.CacheModeHDD
                    }
                    if ($InfoLevel.StorageS2D -ge 2) {
                        $ConfigHash[$LocalizedData.CachePageSize] = $(if ($S2DData.S2D.CachePageSizeKBytes) {
                                $LocalizedData.ValueKB -f $S2DData.S2D.CachePageSizeKBytes
                            } else {
                                '--'
                            })
                        $ConfigHash[$LocalizedData.CacheMetadataReserve] = ConvertTo-HvSize $S2DData.S2D.CacheMetadataReserveBytes
                    }
                    $ConfigObj = [PSCustomObject]$ConfigHash
                }

                $PoolItems = @(foreach ($Pool in $Pools) {
                        $Reserve = Resolve-HvS2DReserve -PoolSize $Pool.Size -AllocatedSize $Pool.AllocatedSize `
                            -PhysicalDisk @($Pool.PhysicalDisks) -NodeCount $NodeCount
                        $PoolHash = [ordered]@{
                            $LocalizedData.PoolName = $Pool.Name
                            $LocalizedData.HealthStatus = ConvertTo-HvDisplayValue $Pool.HealthStatus
                            $LocalizedData.OperationalStatus = ConvertTo-HvDisplayValue $Pool.OperationalStatus
                            $LocalizedData.Size = ConvertTo-HvSize $Pool.Size
                            $LocalizedData.Allocated = '{0} ({1})' -f (ConvertTo-HvSize $Pool.AllocatedSize), (ConvertTo-HvPercent $Reserve.AllocatedPercent)
                            $LocalizedData.Free = ConvertTo-HvSize $Reserve.FreeBytes
                            $LocalizedData.RecommendedReserve = ConvertTo-HvSize $Reserve.ReserveBytes
                            $LocalizedData.ResiliencyDefault = ConvertTo-HvDisplayValue $Pool.ResiliencyDefault
                            $LocalizedData.FaultDomainAwareness = ConvertTo-HvDisplayValue $Pool.FaultDomainAwareness
                        }
                        if ($InfoLevel.StorageS2D -ge 2) {
                            $PoolHash[$LocalizedData.Version] = ConvertTo-HvDisplayValue $Pool.Version
                        }
                        [PSCustomObject]@{
                            Pool = $Pool
                            Reserve = $Reserve
                            Severity = ConvertTo-HvHealthSeverity $Pool.HealthStatus
                            Row = [PSCustomObject]$PoolHash
                        }
                    })

                $AllDisks = @($Pools | ForEach-Object { @($_.PhysicalDisks) } | Where-Object { $_ })
                $DiskSummaryObj = @(foreach ($NodeGroup in @($AllDisks | Group-Object -Property Node | Sort-Object -Property Name)) {
                        $NodeDisks = @($NodeGroup.Group)
                        $Media = @($NodeDisks | Group-Object -Property MediaType | Sort-Object -Property Name | ForEach-Object {
                                '{0}: {1}' -f $_.Name, $_.Count
                            })
                        [PSCustomObject][ordered]@{
                            $LocalizedData.Node = $(if ($NodeGroup.Name) { $NodeGroup.Name } else { $LocalizedData.ValueUnknownNode })
                            $LocalizedData.DiskCount = $NodeDisks.Count
                            $LocalizedData.MediaTypes = ConvertTo-HvDisplayValue $Media
                            $LocalizedData.CacheDisks = @($NodeDisks | Where-Object { $_.Usage -eq 'Journal' }).Count
                            $LocalizedData.RawCapacity = ConvertTo-HvSize (($NodeDisks | Measure-Object -Property Size -Sum).Sum)
                            $LocalizedData.UnhealthyDisks = @($NodeDisks | Where-Object { (ConvertTo-HvHealthSeverity $_.HealthStatus) -ne 'Ok' -or $_.Usage -eq 'Retired' }).Count
                        }
                    })

                $DiskObj = @()
                if ($InfoLevel.StorageS2D -ge 2) {
                    $DiskObj = @(foreach ($Disk in @($AllDisks | Sort-Object -Property Node, SerialNumber)) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.Node = ConvertTo-HvDisplayValue $Disk.Node
                                $LocalizedData.SerialNumber = ConvertTo-HvDisplayValue $Disk.SerialNumber
                                $LocalizedData.Model = ConvertTo-HvDisplayValue $Disk.Model
                                $LocalizedData.MediaType = ConvertTo-HvDisplayValue $Disk.MediaType
                                $LocalizedData.Size = ConvertTo-HvSize $Disk.Size
                                $LocalizedData.Usage = ConvertTo-HvDisplayValue $Disk.Usage
                                $LocalizedData.Firmware = ConvertTo-HvDisplayValue $Disk.FirmwareVersion
                                $LocalizedData.HealthStatus = ConvertTo-HvDisplayValue $Disk.HealthStatus
                            }
                        })
                }

                $AllVirtualDisks = @($Pools | ForEach-Object { @($_.VirtualDisks) } | Where-Object { $_ } | Sort-Object -Property Name)
                $VirtualDiskObj = @(foreach ($VirtualDisk in $AllVirtualDisks) {
                        $Resiliency = if ($VirtualDisk.ResiliencySettingName) {
                            & $FormatResiliency $VirtualDisk
                        } elseif (@($VirtualDisk.Tiers).Count -gt 0) {
                            (@($VirtualDisk.Tiers) | ForEach-Object { & $FormatResiliency $_ } | Select-Object -Unique) -join ', '
                        } else {
                            '--'
                        }
                        [PSCustomObject][ordered]@{
                            $LocalizedData.VirtualDiskName = $VirtualDisk.Name
                            $LocalizedData.Resiliency = $Resiliency
                            $LocalizedData.Size = ConvertTo-HvSize $VirtualDisk.Size
                            $LocalizedData.Footprint = ConvertTo-HvSize $VirtualDisk.FootprintOnPool
                            # Volumes created with storage tiers store the provisioning type on the tiers.
                            $LocalizedData.Provisioning = $(if ($VirtualDisk.ProvisioningType) {
                                    ConvertTo-HvDisplayValue $VirtualDisk.ProvisioningType
                                } else {
                                    ConvertTo-HvDisplayValue @($VirtualDisk.Tiers | Where-Object { $_ -and $_.ProvisioningType } |
                                            ForEach-Object { $_.ProvisioningType } | Select-Object -Unique)
                                })
                            $LocalizedData.HealthStatus = ConvertTo-HvDisplayValue $VirtualDisk.HealthStatus
                            $LocalizedData.OperationalStatus = ConvertTo-HvDisplayValue $VirtualDisk.OperationalStatus
                        }
                    })

                $TierObj = @()
                if ($InfoLevel.StorageS2D -ge 2) {
                    $TierObj = @(foreach ($VirtualDisk in $AllVirtualDisks) {
                            foreach ($Tier in @($VirtualDisk.Tiers | Where-Object { $_ })) {
                                [PSCustomObject][ordered]@{
                                    $LocalizedData.VirtualDiskName = $VirtualDisk.Name
                                    $LocalizedData.TierName = $Tier.Name
                                    $LocalizedData.Resiliency = & $FormatResiliency $Tier
                                    $LocalizedData.MediaType = ConvertTo-HvDisplayValue $Tier.MediaType
                                    $LocalizedData.Size = ConvertTo-HvSize $Tier.Size
                                }
                            }
                        })
                }

                $FaultDomainObj = $null
                if ($InfoLevel.StorageS2D -ge 2 -and $S2DData.FaultDomainCount) {
                    $FaultDomainObj = [PSCustomObject][ordered]@{
                        $LocalizedData.Sites = $S2DData.FaultDomainCount.StorageSite
                        $LocalizedData.Racks = $S2DData.FaultDomainCount.StorageRack
                        $LocalizedData.Chassis = $S2DData.FaultDomainCount.StorageChassis
                        $LocalizedData.ScaleUnits = $S2DData.FaultDomainCount.StorageScaleUnit
                    }
                }

                $Jobs = @($S2DData.Jobs | Where-Object { $_ })
                $JobObj = @(foreach ($Job in $Jobs) {
                        [PSCustomObject][ordered]@{
                            $LocalizedData.JobName = $Job.Name
                            $LocalizedData.JobState = ConvertTo-HvDisplayValue $Job.JobState
                            $LocalizedData.PercentComplete = ConvertTo-HvPercent $Job.PercentComplete -Decimals 0
                            $LocalizedData.Processed = '{0} / {1}' -f (ConvertTo-HvSize $Job.BytesProcessed), (ConvertTo-HvSize $Job.BytesTotal)
                        }
                    })

                $Faults = @($S2DData.Faults | Where-Object { $_ })
                $FaultObj = @(foreach ($Fault in $Faults) {
                        [PSCustomObject][ordered]@{
                            $LocalizedData.FaultSeverity = ConvertTo-HvDisplayValue $Fault.Severity
                            $LocalizedData.FaultType = ConvertTo-HvDisplayValue ($Fault.FaultType -replace '^Microsoft\.Health\.FaultType\.', '')
                            $LocalizedData.FaultObject = ConvertTo-HvDisplayValue $Fault.Object
                            $LocalizedData.FaultReason = ConvertTo-HvDisplayValue $Fault.Reason
                        }
                    })
                #endregion Objects

                #region Health checks
                $UnhealthyPools = @($PoolItems | Where-Object { $_.Severity -ne 'Ok' })
                $ShowPoolCheck = ($Healthcheck.StorageS2D.PoolHealth -and $UnhealthyPools.Count -gt 0)
                if ($ShowPoolCheck) {
                    foreach ($PoolItem in $UnhealthyPools) {
                        $PoolItem.Row | Set-Style -Style $PoolItem.Severity -Property $LocalizedData.HealthStatus
                    }
                }
                $ReserveIssues = @($PoolItems | Where-Object { -not $_.Reserve.ReserveMet })
                $ShowReserveCheck = ($Healthcheck.StorageS2D.ReserveCapacity -and $ReserveIssues.Count -gt 0)
                if ($ShowReserveCheck) {
                    foreach ($PoolItem in $ReserveIssues) {
                        $PoolItem.Row | Set-Style -Style Warning -Property $LocalizedData.Free
                    }
                }

                $UnhealthyVirtualDisks = @($AllVirtualDisks | Where-Object { (ConvertTo-HvHealthSeverity $_.HealthStatus) -ne 'Ok' })
                $ShowVirtualDiskCheck = ($Healthcheck.StorageS2D.VirtualDiskHealth -and $UnhealthyVirtualDisks.Count -gt 0)
                if ($ShowVirtualDiskCheck) {
                    foreach ($VirtualDisk in $UnhealthyVirtualDisks) {
                        $VirtualDiskObj | Where-Object { $_.$($LocalizedData.VirtualDiskName) -eq $VirtualDisk.Name } |
                            Set-Style -Style (ConvertTo-HvHealthSeverity $VirtualDisk.HealthStatus) -Property $LocalizedData.HealthStatus
                    }
                }

                $UnhealthyDisks = @($AllDisks | Where-Object { (ConvertTo-HvHealthSeverity $_.HealthStatus) -ne 'Ok' -or $_.Usage -eq 'Retired' })
                $ShowDiskCheck = ($Healthcheck.StorageS2D.PhysicalDiskHealth -and $UnhealthyDisks.Count -gt 0)
                if ($ShowDiskCheck) {
                    $DiskSummaryObj | Where-Object { $_.$($LocalizedData.UnhealthyDisks) -gt 0 } |
                        Set-Style -Style Warning -Property $LocalizedData.UnhealthyDisks
                    foreach ($Disk in $UnhealthyDisks) {
                        $DiskObj | Where-Object { $_.$($LocalizedData.SerialNumber) -eq $Disk.SerialNumber } |
                            Set-Style -Style Warning -Property $LocalizedData.HealthStatus, $LocalizedData.Usage
                    }
                }

                $ShowJobCheck = ($Healthcheck.StorageS2D.StorageJobs -and @($Jobs | Where-Object { $_.JobState -eq 'Running' }).Count -gt 0)
                if ($ShowJobCheck) {
                    $JobObj | Where-Object { $_.$($LocalizedData.JobState) -eq 'Running' } |
                        Set-Style -Style Warning -Property $LocalizedData.JobState
                }

                $ShowFaultCheck = ($Healthcheck.StorageS2D.HealthFaults -and $Faults.Count -gt 0)
                if ($ShowFaultCheck) {
                    for ($Index = 0; $Index -lt $Faults.Count; $Index++) {
                        $Severity = ConvertTo-HvFaultSeverity $Faults[$Index].Severity
                        if ($Severity -ne 'Ok') {
                            $FaultObj[$Index] | Set-Style -Style $Severity -Property $LocalizedData.FaultSeverity
                        }
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine

                    if ($ConfigObj) {
                        Section -Style Heading3 $LocalizedData.HeadingConfiguration {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableConfiguration) - $HvObjectName"
                                List = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ConfigObj | Table @TableParams
                        }
                    }

                    foreach ($PoolItem in $PoolItems) {
                        Section -Style Heading3 ($LocalizedData.HeadingPool -f $PoolItem.Pool.Name) {
                            $TableParams = @{
                                Name = "$($LocalizedData.TablePool) - $($PoolItem.Pool.Name)"
                                List = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $PoolItem.Row | Table @TableParams

                            $PoolUnhealthy = ($ShowPoolCheck -and $PoolItem.Severity -ne 'Ok')
                            $PoolReserve = ($ShowReserveCheck -and -not $PoolItem.Reserve.ReserveMet)
                            if ($PoolUnhealthy -or $PoolReserve) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                if ($PoolUnhealthy) {
                                    Paragraph ($LocalizedData.PoolHealthBP -f $PoolItem.Pool.Name)
                                    BlankLine
                                }
                                if ($PoolReserve) {
                                    Paragraph ($LocalizedData.ReserveCapacityBP -f (ConvertTo-HvSize $PoolItem.Reserve.ReserveBytes), (ConvertTo-HvSize $PoolItem.Reserve.FreeBytes))
                                    BlankLine
                                }
                            }
                        }
                    }

                    if ($DiskSummaryObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingDisks {
                            Paragraph $LocalizedData.ParagraphDisks
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableDiskSummary) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 12, 22, 12, 16, 16
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $DiskSummaryObj | Table @TableParams

                            if ($DiskObj.Count -gt 0) {
                                BlankLine
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableDisks) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 13, 18, 14, 9, 10, 12, 10, 14
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $DiskObj | Table @TableParams
                            }

                            if ($ShowDiskCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Paragraph ($LocalizedData.PhysicalDiskHealthBP -f (($UnhealthyDisks | ForEach-Object {
                                                '{0} ({1})' -f $_.SerialNumber, $_.Node
                                            }) -join ', '))
                                BlankLine
                            }
                        }
                    }

                    Section -Style Heading3 $LocalizedData.HeadingVirtualDisks {
                        if ($VirtualDiskObj.Count -eq 0) {
                            Paragraph $LocalizedData.NoVirtualDisks
                        } else {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableVirtualDisks) - $HvObjectName"
                                List = $false
                                ColumnWidths = 22, 18, 11, 11, 11, 12, 15
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $VirtualDiskObj | Table @TableParams

                            if ($TierObj.Count -gt 0) {
                                BlankLine
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableTiers) - $HvObjectName"
                                    List = $false
                                    ColumnWidths = 24, 28, 20, 14, 14
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $TierObj | Table @TableParams
                            }

                            if ($ShowVirtualDiskCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Paragraph ($LocalizedData.VirtualDiskHealthBP -f (($UnhealthyVirtualDisks | ForEach-Object { $_.Name }) -join ', '))
                                BlankLine
                            }
                        }
                    }

                    if ($FaultDomainObj) {
                        Section -Style Heading3 $LocalizedData.HeadingFaultDomains {
                            Paragraph $LocalizedData.ParagraphFaultDomains
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableFaultDomains) - $HvObjectName"
                                List = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $FaultDomainObj | Table @TableParams
                        }
                    }

                    if ($JobObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingJobs {
                            $TableParams = @{
                                Name = "$($LocalizedData.TableJobs) - $HvObjectName"
                                List = $false
                                ColumnWidths = 40, 15, 15, 30
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $JobObj | Table @TableParams
                            if ($ShowJobCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Paragraph $LocalizedData.StorageJobsBP
                                BlankLine
                            }
                        }
                    }

                    if ($FaultObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingFaults {
                            Paragraph $LocalizedData.ParagraphFaults
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableFaults) - $HvObjectName"
                                List = $false
                                ColumnWidths = 14, 24, 24, 38
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $FaultObj | Table @TableParams
                            if ($ShowFaultCheck) {
                                Paragraph $LocalizedData.HealthCheck -Bold -Underline
                                BlankLine
                                Paragraph $LocalizedData.HealthFaultsBP
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
