function Get-AbrHvVirtualMachine {
    <#
    .SYNOPSIS
        Used by As Built Report to document the virtual machines of a cluster or host.
    .DESCRIPTION
        Optional inventory of all virtual machines of the cluster or host (InfoLevel.VirtualMachines, disabled
        by default). InfoLevel 1 lists every virtual machine with host, state, version, processors, memory,
        disks, network and checkpoints. InfoLevel 2 adds the details, virtual hard disks and network adapters
        of every virtual machine.
        Health checks highlight virtual machines with checkpoints, virtual machines on cluster nodes that are
        not clustered, outdated configuration versions and network adapters without a virtual switch.
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
        $LocalizedData = $reportTranslate.GetAbrHvVirtualMachine
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.VirtualMachines)
    }

    process {
        try {
            if ($InfoLevel.VirtualMachines -ge 1 -and $HvNodeSessions.Count -gt 0) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)
                $IsCluster = [bool]$HvClusterSession

                #region Collection
                # Every node returns the virtual machines it owns, so each virtual machine is listed once.
                $HostData = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.HostFailed -ScriptBlock {
                        $DefaultVersion = [string](Get-VMHostSupportedVersion -Default -ErrorAction SilentlyContinue).Version
                        [PSCustomObject]@{
                            DefaultVersion = $DefaultVersion
                            VMs = @(Get-VM -ErrorAction Stop | ForEach-Object {
                                    $VM = $_
                                    $Firmware = $null
                                    if ($VM.Generation -eq 2) {
                                        $Firmware = Get-VMFirmware -VM $VM -ErrorAction SilentlyContinue
                                    }
                                    $Security = Get-VMSecurity -VM $VM -ErrorAction SilentlyContinue
                                    $Replication = Get-VMReplication -VM $VM -ErrorAction SilentlyContinue | Select-Object -First 1
                                    [PSCustomObject]@{
                                        Name = [string]$VM.Name
                                        State = [string]$VM.State
                                        Generation = [string]$VM.Generation
                                        Version = [string]$VM.Version
                                        ProcessorCount = [int]$VM.ProcessorCount
                                        MemoryStartup = [double]$VM.MemoryStartup
                                        DynamicMemoryEnabled = [string][bool]$VM.DynamicMemoryEnabled
                                        MemoryMinimum = [double]$VM.MemoryMinimum
                                        MemoryMaximum = [double]$VM.MemoryMaximum
                                        MemoryAssigned = [double]$VM.MemoryAssigned
                                        IsClustered = [string][bool]$VM.IsClustered
                                        CheckpointType = [string]$VM.CheckpointType
                                        CheckpointCount = @(Get-VMSnapshot -VM $VM -ErrorAction SilentlyContinue).Count
                                        AutomaticStartAction = [string]$VM.AutomaticStartAction
                                        AutomaticStopAction = [string]$VM.AutomaticStopAction
                                        Path = [string]$VM.Path
                                        SecureBoot = $(if ($Firmware) { [string]$Firmware.SecureBoot } else { '' })
                                        TpmEnabled = $(if ($Security) { [string][bool]$Security.TpmEnabled } else { '' })
                                        ReplicationMode = $(if ($Replication) { [string]$Replication.Mode } else { '' })
                                        Disks = @(Get-VMHardDiskDrive -VM $VM -ErrorAction SilentlyContinue | ForEach-Object {
                                                $Drive = $_
                                                $Vhd = $null
                                                if ($Drive.Path) {
                                                    $Vhd = Get-VHD -Path $Drive.Path -ErrorAction SilentlyContinue
                                                }
                                                [PSCustomObject]@{
                                                    Controller = '{0} {1}:{2}' -f $Drive.ControllerType, $Drive.ControllerNumber, $Drive.ControllerLocation
                                                    Path = [string]$Drive.Path
                                                    VhdFormat = [string]$Vhd.VhdFormat
                                                    VhdType = [string]$Vhd.VhdType
                                                    Size = $(if ($Vhd) { [double]$Vhd.Size } else { $null })
                                                    FileSize = $(if ($Vhd) { [double]$Vhd.FileSize } else { $null })
                                                }
                                            })
                                        Adapters = @(Get-VMNetworkAdapter -VM $VM -ErrorAction SilentlyContinue | ForEach-Object {
                                                $Adapter = $_
                                                $Vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $Adapter -ErrorAction SilentlyContinue | Select-Object -First 1
                                                [PSCustomObject]@{
                                                    Name = [string]$Adapter.Name
                                                    SwitchName = [string]$Adapter.SwitchName
                                                    VlanMode = [string]$Vlan.OperationMode
                                                    VlanId = [string]$Vlan.AccessVlanId
                                                    MacAddress = [string]$Adapter.MacAddress
                                                    DynamicMac = [string][bool]$Adapter.DynamicMacAddressEnabled
                                                }
                                            })
                                    }
                                })
                        }
                    } | Sort-Object -Property NodeName)

                $VMs = @(foreach ($HostItem in $HostData) {
                        foreach ($VM in @($HostItem.VMs | Where-Object { $_ })) {
                            $VM | Add-Member -MemberType NoteProperty -Name 'HostName' -Value $HostItem.NodeName -Force
                            $VM | Add-Member -MemberType NoteProperty -Name 'Findings' -Force -Value @(
                                Resolve-HvVmFinding -VM $VM -IsCluster:$IsCluster -HostDefaultVersion $HostItem.DefaultVersion
                            )
                            $VM
                        }
                    })
                $VMs = @($VMs | Sort-Object -Property Name, HostName)
                #endregion Collection

                #region Objects
                $FormatVlan = {
                    param ($Adapter)
                    switch ($Adapter.VlanMode) {
                        'Access' { $Adapter.VlanId }
                        'Untagged' { $LocalizedData.ValueUntagged }
                        default { ConvertTo-HvDisplayValue $Adapter.VlanMode }
                    }
                }
                $FormatNetwork = {
                    param ($VM)
                    $Items = @($VM.Adapters | Where-Object { $_ } | ForEach-Object {
                            if ($_.SwitchName) {
                                '{0} (VLAN {1})' -f $_.SwitchName, (& $FormatVlan $_)
                            } else {
                                $LocalizedData.ValueNotConnected
                            }
                        })
                    if ($Items.Count -gt 0) { $Items -join ', ' } else { $LocalizedData.ValueNone }
                }
                $FormatMemory = {
                    param ($VM)
                    if ($VM.DynamicMemoryEnabled -eq 'True') {
                        $LocalizedData.ValueDynamicMemory -f (ConvertTo-HvSize $VM.MemoryStartup)
                    } else {
                        ConvertTo-HvSize $VM.MemoryStartup
                    }
                }
                $FormatDisks = {
                    param ($VM)
                    $Disks = @($VM.Disks | Where-Object { $_ })
                    if ($Disks.Count -eq 0) {
                        $LocalizedData.ValueNone
                    } else {
                        $LocalizedData.ValueDisks -f $Disks.Count, (ConvertTo-HvSize (($Disks | Measure-Object -Property Size -Sum).Sum))
                    }
                }

                $VmObj = @(foreach ($VM in $VMs) {
                        $InObj = [ordered]@{
                            $LocalizedData.VmName = $VM.Name
                            $LocalizedData.HostName = $VM.HostName
                            $LocalizedData.State = ConvertTo-HvDisplayValue $VM.State
                            $LocalizedData.Version = '{0} / {1}' -f $VM.Generation, $VM.Version
                            $LocalizedData.Processors = $VM.ProcessorCount
                            $LocalizedData.Memory = & $FormatMemory $VM
                            $LocalizedData.Disks = & $FormatDisks $VM
                            $LocalizedData.Network = & $FormatNetwork $VM
                            $LocalizedData.Checkpoints = $VM.CheckpointCount
                        }
                        if ($IsCluster) {
                            $InObj[$LocalizedData.Clustered] = ConvertTo-HvDisplayValue ($VM.IsClustered -eq 'True')
                        }
                        [PSCustomObject]@{
                            VM = $VM
                            Row = [PSCustomObject]$InObj
                        }
                    })
                #endregion Objects

                #region Health checks
                $CheckMap = [ordered]@{
                    Checkpoints = @{ Enabled = $Healthcheck.VirtualMachines.Checkpoints; Column = $LocalizedData.Checkpoints; Text = $LocalizedData.CheckpointsBP }
                    NotClustered = @{ Enabled = $Healthcheck.VirtualMachines.NotClustered; Column = $LocalizedData.Clustered; Text = $LocalizedData.NotClusteredBP }
                    ConfigurationVersion = @{ Enabled = $Healthcheck.VirtualMachines.ConfigurationVersion; Column = $LocalizedData.Version; Text = $LocalizedData.ConfigurationVersionBP }
                    NetworkDisconnected = @{ Enabled = $Healthcheck.VirtualMachines.NetworkDisconnected; Column = $LocalizedData.Network; Text = $LocalizedData.NetworkDisconnectedBP }
                }
                $ShownChecks = New-Object -TypeName System.Collections.Generic.List[String]
                foreach ($CheckName in @($CheckMap.Keys)) {
                    $Check = $CheckMap[$CheckName]
                    $Affected = @($VmObj | Where-Object { $_.VM.Findings -contains $CheckName })
                    if (-not $Check.Enabled -or $Affected.Count -eq 0) {
                        continue
                    }
                    $ShownChecks.Add($CheckName)
                    foreach ($Item in $Affected) {
                        if ($Item.Row.PSObject.Properties[$Check.Column]) {
                            $Item.Row | Set-Style -Style Warning -Property $Check.Column
                        }
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    $Running = @($VMs | Where-Object { $_.State -eq 'Running' }).Count
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName, $VMs.Count, $Running)
                    BlankLine
                    if ($VmObj.Count -eq 0) {
                        Paragraph $LocalizedData.NoVMs
                    } else {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableVMs) - $HvObjectName"
                            List = $false
                        }
                        if ($IsCluster) {
                            $TableParams['ColumnWidths'] = 14, 11, 8, 8, 6, 10, 12, 15, 8, 8
                        } else {
                            $TableParams['ColumnWidths'] = 15, 12, 9, 9, 7, 11, 13, 16, 8
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        @($VmObj | ForEach-Object { $_.Row }) | Table @TableParams

                        if ($ShownChecks.Count -gt 0) {
                            Paragraph $LocalizedData.HealthCheck -Bold -Underline
                            BlankLine
                            foreach ($CheckName in $ShownChecks) {
                                $Names = @($VmObj | Where-Object { $_.VM.Findings -contains $CheckName } | ForEach-Object { $_.VM.Name })
                                Paragraph ($CheckMap[$CheckName].Text -f ($Names -join ', '))
                                BlankLine
                            }
                        }

                        if ($InfoLevel.VirtualMachines -ge 2) {
                            foreach ($VM in $VMs) {
                                Section -Style Heading3 $VM.Name {
                                    $DetailObj = [PSCustomObject][ordered]@{
                                        $LocalizedData.VmName = $VM.Name
                                        $LocalizedData.HostName = $VM.HostName
                                        $LocalizedData.State = ConvertTo-HvDisplayValue $VM.State
                                        $LocalizedData.Generation = ConvertTo-HvDisplayValue $VM.Generation
                                        $LocalizedData.ConfigurationVersion = ConvertTo-HvDisplayValue $VM.Version
                                        $LocalizedData.Path = ConvertTo-HvDisplayValue $VM.Path
                                        $LocalizedData.Processors = $VM.ProcessorCount
                                        $LocalizedData.StartupMemory = ConvertTo-HvSize $VM.MemoryStartup
                                        $LocalizedData.DynamicMemory = $(if ($VM.DynamicMemoryEnabled -eq 'True') {
                                                $LocalizedData.ValueMemoryRange -f (ConvertTo-HvSize $VM.MemoryMinimum), (ConvertTo-HvSize $VM.MemoryMaximum)
                                            } else {
                                                ConvertTo-HvDisplayValue $false
                                            })
                                        $LocalizedData.AssignedMemory = ConvertTo-HvSize $VM.MemoryAssigned
                                        $LocalizedData.CheckpointType = ConvertTo-HvDisplayValue $VM.CheckpointType
                                        $LocalizedData.Checkpoints = $VM.CheckpointCount
                                        $LocalizedData.StartAction = ConvertTo-HvDisplayValue $VM.AutomaticStartAction
                                        $LocalizedData.StopAction = ConvertTo-HvDisplayValue $VM.AutomaticStopAction
                                        $LocalizedData.SecureBoot = $(if ($VM.SecureBoot) { ConvertTo-HvDisplayValue $VM.SecureBoot } else { '--' })
                                        $LocalizedData.Tpm = $(if ($VM.TpmEnabled) { ConvertTo-HvDisplayValue ($VM.TpmEnabled -eq 'True') } else { '--' })
                                        $LocalizedData.Replication = $(if ($VM.ReplicationMode) { ConvertTo-HvDisplayValue $VM.ReplicationMode } else { $LocalizedData.ValueNone })
                                        $LocalizedData.Clustered = ConvertTo-HvDisplayValue ($VM.IsClustered -eq 'True')
                                    }
                                    $TableParams = @{
                                        Name = "$($LocalizedData.TableVM) - $($VM.Name)"
                                        List = $true
                                        ColumnWidths = 40, 60
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $DetailObj | Table @TableParams

                                    $DiskObj = @(foreach ($Disk in @($VM.Disks | Where-Object { $_ })) {
                                            [PSCustomObject][ordered]@{
                                                $LocalizedData.Controller = $Disk.Controller
                                                $LocalizedData.Path = ConvertTo-HvDisplayValue $Disk.Path
                                                $LocalizedData.VhdType = ConvertTo-HvDisplayValue (@($Disk.VhdFormat, $Disk.VhdType) | Where-Object { $_ })
                                                $LocalizedData.Size = ConvertTo-HvSize $Disk.Size
                                                $LocalizedData.FileSize = ConvertTo-HvSize $Disk.FileSize
                                            }
                                        })
                                    if ($DiskObj.Count -gt 0) {
                                        BlankLine
                                        $TableParams = @{
                                            Name = "$($LocalizedData.TableVmDisks) - $($VM.Name)"
                                            List = $false
                                            ColumnWidths = 16, 44, 16, 12, 12
                                        }
                                        if ($Report.ShowTableCaptions) {
                                            $TableParams['Caption'] = "- $($TableParams.Name)"
                                        }
                                        $DiskObj | Table @TableParams
                                    }

                                    $AdapterObj = @(foreach ($Adapter in @($VM.Adapters | Where-Object { $_ })) {
                                            [PSCustomObject][ordered]@{
                                                $LocalizedData.AdapterName = $Adapter.Name
                                                $LocalizedData.SwitchName = $(if ($Adapter.SwitchName) { $Adapter.SwitchName } else { $LocalizedData.ValueNotConnected })
                                                $LocalizedData.Vlan = & $FormatVlan $Adapter
                                                $LocalizedData.MacAddress = $(if ($Adapter.DynamicMac -eq 'True') { $LocalizedData.ValueDynamicMac } else { ConvertTo-HvDisplayValue $Adapter.MacAddress })
                                            }
                                        })
                                    if ($AdapterObj.Count -gt 0) {
                                        BlankLine
                                        $TableParams = @{
                                            Name = "$($LocalizedData.TableVmAdapters) - $($VM.Name)"
                                            List = $false
                                            ColumnWidths = 25, 30, 20, 25
                                        }
                                        if ($Report.ShowTableCaptions) {
                                            $TableParams['Caption'] = "- $($TableParams.Name)"
                                        }
                                        $AdapterObj | Table @TableParams
                                    }
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
