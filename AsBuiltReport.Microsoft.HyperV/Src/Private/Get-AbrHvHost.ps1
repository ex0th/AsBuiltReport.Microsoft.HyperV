function Get-AbrHvHost {
    <#
    .SYNOPSIS
        Used by As Built Report to document the Hyper-V specific settings of every host.
    .DESCRIPTION
        Documents the settings that are specific to Hyper-V and not covered by AsBuiltReport.Microsoft.Windows:
        hypervisor scheduler, virtualization-based security, Secure Boot, TPM and the default VM configuration
        version. InfoLevel 2 adds the running security services, the supported VM configuration versions,
        enhanced session mode, GPU partitioning, Discrete Device Assignment and virtual Fibre Channel SANs.
        Health checks highlight hosts that use the classic scheduler with SMT and hosts without Secure Boot.
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
        $LocalizedData = $reportTranslate.GetAbrHvHost
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Host)
    }

    process {
        try {
            if ($InfoLevel.Host -ge 1 -and $HvNodeSessions.Count -gt 0) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $HostData = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.HostFailed -ScriptBlock {
                        $VMHost = Get-VMHost -ErrorAction Stop
                        # Event 2 of the hypervisor records the scheduler type at boot.
                        $SchedulerEvent = Get-WinEvent -FilterHashtable @{
                            LogName = 'System'
                            ProviderName = 'Microsoft-Windows-Hyper-V-Hypervisor'
                            Id = 2
                        } -MaxEvents 1 -ErrorAction SilentlyContinue
                        $DeviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName 'Win32_DeviceGuard' -ErrorAction SilentlyContinue
                        $SecureBootState = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
                        $Tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName 'Win32_Tpm' -ErrorAction SilentlyContinue
                        $Versions = @(Get-VMHostSupportedVersion -ErrorAction SilentlyContinue)
                        $GpuCount = $null
                        if (Get-Command -Name 'Get-VMHostPartitionableGpu' -ErrorAction SilentlyContinue) {
                            $GpuCount = @(Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue).Count
                        }
                        $AssignableCount = $null
                        if (Get-Command -Name 'Get-VMHostAssignableDevice' -ErrorAction SilentlyContinue) {
                            $AssignableCount = @(Get-VMHostAssignableDevice -ErrorAction SilentlyContinue).Count
                        }
                        $ComputerSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction SilentlyContinue
                        $Bios = Get-CimInstance -ClassName 'Win32_BIOS' -ErrorAction SilentlyContinue
                        $Processors = @(Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction SilentlyContinue)
                        $MemoryModules = @(Get-CimInstance -ClassName 'Win32_PhysicalMemory' -ErrorAction SilentlyContinue)
                        [PSCustomObject]@{
                            Hardware = [PSCustomObject]@{
                                Manufacturer = ([string]$ComputerSystem.Manufacturer).Trim()
                                Model = ([string]$ComputerSystem.Model).Trim()
                                SerialNumber = ([string]$Bios.SerialNumber).Trim()
                                BiosVersion = ([string]$Bios.SMBIOSBIOSVersion).Trim()
                                Processor = (@($Processors | ForEach-Object { ([string]$_.Name).Trim() } | Select-Object -Unique) -join '; ')
                                Sockets = $Processors.Count
                                Cores = [int](($Processors | Measure-Object -Property NumberOfCores -Sum).Sum)
                                LogicalProcessors = [int](($Processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
                                # Installed memory from the modules; falls back to the memory visible to Windows.
                                Memory = $(if ($MemoryModules.Count -gt 0) {
                                        [double](($MemoryModules | Measure-Object -Property Capacity -Sum).Sum)
                                    } else {
                                        [double]$ComputerSystem.TotalPhysicalMemory
                                    })
                            }
                            NetAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Sort-Object -Property Name | ForEach-Object {
                                    [PSCustomObject]@{
                                        Name = [string]$_.Name
                                        InterfaceDescription = [string]$_.InterfaceDescription
                                        DriverVersion = [string]$_.DriverVersion
                                        DriverDate = [string]$_.DriverDate
                                        DriverProvider = [string]$_.DriverProvider
                                    }
                                })
                            SchedulerType =$(if ($SchedulerEvent) { [string]$SchedulerEvent.Properties[0].Value } else { $null })
                            VbsStatus = $(if ($DeviceGuard) { [string]$DeviceGuard.VirtualizationBasedSecurityStatus } else { $null })
                            SecurityServicesRunning = [string[]]@($DeviceGuard.SecurityServicesRunning | ForEach-Object { [string]$_ })
                            SecureBoot = $(if ($SecureBootState) { [string]$SecureBootState.UEFISecureBootEnabled } else { $null })
                            TpmPresent = [bool]$Tpm
                            TpmVersion = $(if ($Tpm -and $Tpm.SpecVersion) { ([string]$Tpm.SpecVersion).Split(',')[0].Trim() } else { $null })
                            DefaultVmVersion = [string]($Versions | Where-Object { $_.IsDefault } | Select-Object -First 1).Version
                            SupportedVmVersions = [string[]]@($Versions | ForEach-Object { [string]$_.Version })
                            EnhancedSessionMode = [bool]$VMHost.EnableEnhancedSessionMode
                            PartitionableGpuCount = $GpuCount
                            AssignableDeviceCount = $AssignableCount
                            VirtualSans = [string[]]@(Get-VMSan -ErrorAction SilentlyContinue -WarningAction SilentlyContinue |
                                    ForEach-Object { [string]$_.Name })
                        }
                    } | Sort-Object -Property NodeName)
                #endregion Collection

                #region Objects
                $HostObj = @(foreach ($HostItem in $HostData) {
                        $Security = Resolve-HvHostSecurity -HostSetting $HostItem
                        $InObj = [ordered]@{
                            $LocalizedData.HostName = $HostItem.NodeName
                            $LocalizedData.Scheduler = $LocalizedData["Scheduler$($Security.SchedulerKey)"]
                            $LocalizedData.Vbs = $LocalizedData["Vbs$($Security.VbsKey)"]
                            $LocalizedData.SecureBoot = $LocalizedData["SecureBoot$($Security.SecureBootKey)"]
                            $LocalizedData.Tpm = $(if ($HostItem.TpmPresent) {
                                    if ($HostItem.TpmVersion) { $HostItem.TpmVersion } else { ConvertTo-HvDisplayValue $true }
                                } else {
                                    $LocalizedData.ValueNotPresent
                                })
                            $LocalizedData.DefaultVmVersion = ConvertTo-HvDisplayValue $HostItem.DefaultVmVersion
                        }
                        if ($InfoLevel.Host -ge 2) {
                            $InObj[$LocalizedData.SecurityServices] = $(if ($Security.ServiceKeys.Count -gt 0) {
                                    ($Security.ServiceKeys | ForEach-Object {
                                        $Label = $LocalizedData["Service$_"]
                                        if ($Label) { $Label } else { $_ }
                                    }) -join ', '
                                } else {
                                    $LocalizedData.ValueNone
                                })
                            $InObj[$LocalizedData.SupportedVmVersions] = ConvertTo-HvDisplayValue $HostItem.SupportedVmVersions
                            $InObj[$LocalizedData.EnhancedSessionMode] = ConvertTo-HvDisplayValue $HostItem.EnhancedSessionMode
                            $InObj[$LocalizedData.PartitionableGpus] = ConvertTo-HvDisplayValue $HostItem.PartitionableGpuCount
                            $InObj[$LocalizedData.AssignableDevices] = ConvertTo-HvDisplayValue $HostItem.AssignableDeviceCount
                            $InObj[$LocalizedData.VirtualSans] = $(if (@($HostItem.VirtualSans).Count -gt 0) {
                                    ConvertTo-HvDisplayValue $HostItem.VirtualSans
                                } else {
                                    $LocalizedData.ValueNone
                                })
                        }
                        [PSCustomObject]@{
                            Name = $HostItem.NodeName
                            Findings = $Security.Findings
                            Row = [PSCustomObject]$InObj
                        }
                    })
                $HardwareObj = @()
                $ProcessorObj = @()
                $DriverObj = @()
                if ($InfoLevel.Host -ge 2) {
                    $HardwareObj = @(foreach ($HostItem in $HostData) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.Manufacturer = ConvertTo-HvDisplayValue $HostItem.Hardware.Manufacturer
                                $LocalizedData.Model = ConvertTo-HvDisplayValue $HostItem.Hardware.Model
                                $LocalizedData.SerialNumber = ConvertTo-HvDisplayValue $HostItem.Hardware.SerialNumber
                                $LocalizedData.BiosVersion = ConvertTo-HvDisplayValue $HostItem.Hardware.BiosVersion
                            }
                        })
                    $ProcessorObj = @(foreach ($HostItem in $HostData) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.HostName = $HostItem.NodeName
                                $LocalizedData.Processor = ConvertTo-HvDisplayValue $HostItem.Hardware.Processor
                                $LocalizedData.Sockets = $HostItem.Hardware.Sockets
                                $LocalizedData.Cores = $HostItem.Hardware.Cores
                                $LocalizedData.LogicalProcessors = $HostItem.Hardware.LogicalProcessors
                                $LocalizedData.Memory = ConvertTo-HvSize $HostItem.Hardware.Memory
                            }
                        })
                    $DriverObj = @(foreach ($HostItem in $HostData) {
                            foreach ($Adapter in @($HostItem.NetAdapters | Where-Object { $_ })) {
                                [PSCustomObject][ordered]@{
                                    $LocalizedData.HostName = $HostItem.NodeName
                                    $LocalizedData.AdapterName = $Adapter.Name
                                    $LocalizedData.Description = ConvertTo-HvDisplayValue $Adapter.InterfaceDescription
                                    $LocalizedData.DriverVersion = ConvertTo-HvDisplayValue $Adapter.DriverVersion
                                    $LocalizedData.DriverDate = ConvertTo-HvDisplayValue $Adapter.DriverDate
                                    $LocalizedData.DriverProvider = ConvertTo-HvDisplayValue $Adapter.DriverProvider
                                }
                            }
                        })
                }
                #endregion Objects

                #region Health checks
                $SchedulerHosts = @($HostObj | Where-Object { $_.Findings -contains 'ClassicScheduler' } | ForEach-Object { $_.Name })
                $ShowSchedulerCheck = ($Healthcheck.Host.SchedulerType -and $SchedulerHosts.Count -gt 0)
                if ($ShowSchedulerCheck) {
                    $HostObj | Where-Object { $SchedulerHosts -contains $_.Name } | ForEach-Object {
                        $_.Row | Set-Style -Style Warning -Property $LocalizedData.Scheduler
                    }
                }
                $SecureBootHosts = @($HostObj | Where-Object { $_.Findings -contains 'SecureBootOff' } | ForEach-Object { $_.Name })
                $ShowSecureBootCheck = ($Healthcheck.Host.SecureBoot -and $SecureBootHosts.Count -gt 0)
                if ($ShowSecureBootCheck) {
                    $HostObj | Where-Object { $SecureBootHosts -contains $_.Name } | ForEach-Object {
                        $_.Row | Set-Style -Style Warning -Property $LocalizedData.SecureBoot
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName)
                    BlankLine
                    if ($InfoLevel.Host -ge 2) {
                        # One single-row list table per host: PScribo drops captions from multi-row list tables.
                        foreach ($HostItem in $HostObj) {
                            Section -Style Heading3 $HostItem.Name {
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableHost) - $($HostItem.Name)"
                                    List = $true
                                    ColumnWidths = 40, 60
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $HostItem.Row | Table @TableParams
                            }
                        }
                    } else {
                        $TableParams = @{
                            Name = "$($LocalizedData.TableHosts) - $HvObjectName"
                            List = $false
                            ColumnWidths = 20, 20, 18, 14, 12, 16
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        @($HostObj | ForEach-Object { $_.Row }) | Table @TableParams
                    }

                    if ($ShowSchedulerCheck -or $ShowSecureBootCheck) {
                        Paragraph $LocalizedData.HealthCheck -Bold -Underline
                        BlankLine
                        if ($ShowSchedulerCheck) {
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.SchedulerTypeFinding -f ($SchedulerHosts -join ', ')) -Recommendation $LocalizedData.SchedulerTypeBP
                        }
                        if ($ShowSecureBootCheck) {
                            Write-HvHealthCheck -Area $LocalizedData.Heading -Finding ($LocalizedData.SecureBootFinding -f ($SecureBootHosts -join ', ')) -Recommendation $LocalizedData.SecureBootBP
                        }
                    }

                    if ($HardwareObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingHardware {
                            Paragraph $LocalizedData.ParagraphHardware
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableHardware) - $HvObjectName"
                                List = $false
                                ColumnWidths = 20, 20, 20, 20, 20
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $HardwareObj | Table @TableParams
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableProcessors) - $HvObjectName"
                                List = $false
                                ColumnWidths = 18, 34, 10, 10, 14, 14
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ProcessorObj | Table @TableParams
                        }
                    }

                    if ($DriverObj.Count -gt 0) {
                        Section -Style Heading3 $LocalizedData.HeadingDrivers {
                            Paragraph $LocalizedData.ParagraphDrivers
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableDrivers) - $HvObjectName"
                                List = $false
                                ColumnWidths = 16, 16, 28, 14, 12, 14
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $DriverObj | Table @TableParams
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
