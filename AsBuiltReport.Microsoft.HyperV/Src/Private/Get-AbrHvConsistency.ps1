function Get-AbrHvConsistency {
    <#
    .SYNOPSIS
        Used by As Built Report to compare the configuration of the nodes of a cluster.
    .DESCRIPTION
        Compares operating system, hotfixes, hardware, Hyper-V settings, networking, storage and installed
        features between the nodes. InfoLevel 1 shows the compared categories and the deviations; InfoLevel 2
        adds the full comparison per category. Health checks highlight deviations per category.
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
        $LocalizedData = $reportTranslate.GetAbrHvConsistency
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Consistency)
    }

    process {
        try {
            if ($InfoLevel.Consistency -ge 1 -and $HvNodeSessions.Count -ge 2) {
                Write-PScriboMessage ($LocalizedData.Collecting -f $HvObjectName)

                #region Collection
                $NodeData = @(Invoke-HvNodeCommand -FailureMessage $LocalizedData.HostFailed -ScriptBlock {
                        $NewItem = {
                            param ($Key, $Value)
                            [PSCustomObject]@{ Key = [string]$Key; Value = [string]$Value }
                        }
                        $Os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction SilentlyContinue
                        $CurrentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
                        $ComputerSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction SilentlyContinue
                        $Bios = Get-CimInstance -ClassName 'Win32_BIOS' -ErrorAction SilentlyContinue
                        $Processors = @(Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction SilentlyContinue)
                        $VMHost = Get-VMHost -ErrorAction SilentlyContinue
                        $DefaultVersion = Get-VMHostSupportedVersion -Default -ErrorAction SilentlyContinue

                        $OperatingSystem = @(
                            & $NewItem 'Edition' $Os.Caption
                            & $NewItem 'Build' ('{0}.{1}' -f $Os.Version, $CurrentVersion.UBR)
                            & $NewItem 'InstallationType' $CurrentVersion.InstallationType
                            & $NewItem 'DisplayVersion' $CurrentVersion.DisplayVersion
                        )
                        $Hardware = @(
                            & $NewItem 'Manufacturer' $ComputerSystem.Manufacturer
                            & $NewItem 'Model' $ComputerSystem.Model
                            & $NewItem 'BiosVersion' $Bios.SMBIOSBIOSVersion
                            & $NewItem 'Processor' (@($Processors | ForEach-Object { ([string]$_.Name).Trim() } | Select-Object -Unique) -join '; ')
                            & $NewItem 'LogicalProcessors' (($Processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
                            & $NewItem 'Memory' ('{0} GB' -f [math]::Round([double]$ComputerSystem.TotalPhysicalMemory / 1GB))
                        )
                        $HyperVSettings = @(
                            & $NewItem 'VirtualMachinePath' $VMHost.VirtualMachinePath
                            & $NewItem 'VirtualHardDiskPath' $VMHost.VirtualHardDiskPath
                            & $NewItem 'NumaSpanning' $VMHost.NumaSpanningEnabled
                            & $NewItem 'EnhancedSessionMode' $VMHost.EnableEnhancedSessionMode
                            & $NewItem 'DefaultVmVersion' $DefaultVersion.Version
                        )
                        $Hotfix = @(Get-HotFix -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.HotFixID } |
                                Sort-Object -Unique | ForEach-Object { & $NewItem $_ 'Installed' })
                        $Features = @(Get-WindowsFeature -ErrorAction SilentlyContinue | Where-Object { $_.Installed } |
                                ForEach-Object { [string]$_.Name } | Sort-Object | ForEach-Object { & $NewItem $_ 'Installed' })

                        # Networking: switches, host vNICs, driver versions, jumbo frames, RDMA and DCB.
                        $NetAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
                        $Network = New-Object -TypeName System.Collections.Generic.List[Object]
                        foreach ($VSwitch in @(Get-VMSwitch -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
                            $Network.Add((& $NewItem "Switch|$($VSwitch.Name)" ('{0}, SET {1}, {2}' -f $VSwitch.SwitchType,
                                        [bool]$VSwitch.EmbeddedTeamingEnabled, @($VSwitch.NetAdapterInterfaceDescriptions).Count)))
                        }
                        foreach ($Vnic in @(Get-VMNetworkAdapter -ManagementOS -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
                            $Vlan = Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $Vnic.Name -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                            $Network.Add((& $NewItem "Vnic|$($Vnic.Name)" ('{0}, VLAN {1}' -f $Vnic.SwitchName, $(if ($Vlan.OperationMode -eq 'Access') {
                                                $Vlan.AccessVlanId
                                            } else {
                                                $Vlan.OperationMode
                                            }))))
                        }
                        foreach ($DriverGroup in @($NetAdapters | Group-Object -Property { ([string]$_.InterfaceDescription) -replace ' #\d+$', '' } |
                                    Sort-Object -Property Name)) {
                            $Network.Add((& $NewItem "Driver|$($DriverGroup.Name)" ((@($DriverGroup.Group | ForEach-Object {
                                                    [string]$_.DriverVersion
                                                } | Sort-Object -Unique)) -join ', ')))
                        }
                        foreach ($Adapter in @($NetAdapters | Sort-Object -Property Name)) {
                            $Jumbo = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword '*JumboPacket' -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                            if ($Jumbo) {
                                $Network.Add((& $NewItem "Jumbo|$($Adapter.Name)" (@($Jumbo.RegistryValue) | Select-Object -First 1)))
                            }
                        }
                        foreach ($Rdma in @(Get-NetAdapterRdma -ErrorAction SilentlyContinue | Sort-Object -Property Name)) {
                            $Network.Add((& $NewItem "Rdma|$($Rdma.Name)" ([bool]$Rdma.Enabled)))
                        }
                        if (Get-Command -Name 'Get-NetQosFlowControl' -ErrorAction SilentlyContinue) {
                            $Network.Add((& $NewItem 'PfcPriorities' ((@(Get-NetQosFlowControl -ErrorAction SilentlyContinue | Where-Object { $_.Enabled } |
                                                ForEach-Object { [string]$_.Priority })) -join ',')))
                            $Network.Add((& $NewItem 'TrafficClasses' ((@(Get-NetQosTrafficClass -ErrorAction SilentlyContinue | Sort-Object -Property Name |
                                                ForEach-Object { '{0}:{1}:{2}' -f $_.Name, (@($_.Priority) -join ','), $_.BandwidthPercentage })) -join '; ')))
                        }

                        # Storage: MPIO, firmware of the local disks per model, connected iSCSI targets.
                        $Storage = New-Object -TypeName System.Collections.Generic.List[Object]
                        $MpioFeature = Get-WindowsFeature -Name 'Multipath-IO' -ErrorAction SilentlyContinue
                        $MpioInstalled = [bool]($MpioFeature -and $MpioFeature.Installed)
                        $Storage.Add((& $NewItem 'MpioInstalled' $MpioInstalled))
                        if ($MpioInstalled -and (Get-Command -Name 'Get-MSDSMGlobalDefaultLoadBalancePolicy' -ErrorAction SilentlyContinue)) {
                            $Storage.Add((& $NewItem 'LoadBalancePolicy' (Get-MSDSMGlobalDefaultLoadBalancePolicy -ErrorAction SilentlyContinue)))
                        }
                        $LocalDisks = @(Get-StorageSubSystem -FriendlyName 'Windows Storage*' -ErrorAction SilentlyContinue |
                                Get-PhysicalDisk -ErrorAction SilentlyContinue)
                        foreach ($ModelGroup in @($LocalDisks | Group-Object -Property { ([string]$_.Model).Trim() } | Sort-Object -Property Name)) {
                            $Storage.Add((& $NewItem "Firmware|$($ModelGroup.Name)" ((@($ModelGroup.Group | ForEach-Object {
                                                    ([string]$_.FirmwareVersion).Trim()
                                                } | Sort-Object -Unique)) -join ', ')))
                        }
                        if (Get-Command -Name 'Get-IscsiSession' -ErrorAction SilentlyContinue) {
                            foreach ($Session in @(Get-IscsiSession -ErrorAction SilentlyContinue | Sort-Object -Property TargetNodeAddress)) {
                                $Storage.Add((& $NewItem "IscsiTarget|$($Session.TargetNodeAddress)" $(if ($Session.IsConnected) { 'Connected' } else { 'Disconnected' })))
                            }
                        }

                        [PSCustomObject]@{
                            OperatingSystem = $OperatingSystem
                            Hotfix = $Hotfix
                            Hardware = $Hardware
                            HyperVSettings = $HyperVSettings
                            Network = @($Network.ToArray())
                            Storage = @($Storage.ToArray())
                            Features = $Features
                        }
                    } | Sort-Object -Property NodeName)
                $NodeNames = @($NodeData | ForEach-Object { [string]$_.NodeName })
                #endregion Collection

                #region Comparison
                # Category, health check and whether a missing key is a deviation of that host.
                $Categories = @(
                    @{ Name = 'OperatingSystem'; Check = $Healthcheck.Consistency.OperatingSystem; PreferPresent = $false }
                    @{ Name = 'Hotfix'; Check = $Healthcheck.Consistency.Hotfix; PreferPresent = $true }
                    @{ Name = 'Hardware'; Check = $Healthcheck.Consistency.Hardware; PreferPresent = $false }
                    @{ Name = 'HyperVSettings'; Check = $Healthcheck.Consistency.HyperVSettings; PreferPresent = $false }
                    @{ Name = 'Network'; Check = $Healthcheck.Consistency.Network; PreferPresent = $true }
                    @{ Name = 'Storage'; Check = $Healthcheck.Consistency.Storage; PreferPresent = $true }
                    @{ Name = 'Features'; Check = $Healthcheck.Consistency.Features; PreferPresent = $true }
                )
                $FormatKey = {
                    param ($Key)
                    $Parts = ([string]$Key).Split('|', 2)
                    if ($Parts.Count -eq 2) {
                        $Prefix = $LocalizedData["Prefix$($Parts[0])"]
                        '{0}: {1}' -f $(if ($Prefix) { $Prefix } else { $Parts[0] }), $Parts[1]
                    } else {
                        $Label = $LocalizedData["Setting$Key"]
                        if ($Label) { $Label } else { [string]$Key }
                    }
                }
                $FormatValue = {
                    param ($Value, $Missing)
                    if ($Missing) {
                        $LocalizedData.ValueMissing
                    } elseif ($Value -eq 'True') {
                        ConvertTo-HvDisplayValue $true
                    } elseif ($Value -eq 'False') {
                        ConvertTo-HvDisplayValue $false
                    } elseif ($Value -eq 'Installed') {
                        $LocalizedData.ValueInstalled
                    } else {
                        ConvertTo-HvDisplayValue $Value
                    }
                }

                $Results = @(foreach ($Category in $Categories) {
                        $InputObject = @($NodeData | ForEach-Object {
                                [PSCustomObject]@{ Name = $_.NodeName; Items = @($_.$($Category.Name)) }
                            })
                        $Keys = @($InputObject | ForEach-Object { @($_.Items) } | Where-Object { $_ } | ForEach-Object { [string]$_.Key } |
                                Select-Object -Unique)
                        [PSCustomObject]@{
                            Name = $Category.Name
                            Label = $LocalizedData["Category$($Category.Name)"]
                            Check = [bool]$Category.Check
                            Input = $InputObject
                            Keys = $Keys
                            Deviations = @(Resolve-HvKeyedDeviation -InputObject $InputObject -PreferPresent:$Category.PreferPresent)
                        }
                    })
                #endregion Comparison

                #region Objects
                $SummaryObj = @(foreach ($Result in $Results) {
                        [PSCustomObject][ordered]@{
                            $LocalizedData.Category = $Result.Label
                            $LocalizedData.ComparedItems = $Result.Keys.Count
                            $LocalizedData.DeviationCount = @($Result.Deviations | ForEach-Object { $_.Key } | Select-Object -Unique).Count
                        }
                    })
                $DeviationObj = @(foreach ($Result in $Results) {
                        foreach ($Deviation in $Result.Deviations) {
                            [PSCustomObject][ordered]@{
                                $LocalizedData.Category = $Result.Label
                                $LocalizedData.Setting = & $FormatKey $Deviation.Key
                                $LocalizedData.HostName = $Deviation.Name
                                $LocalizedData.Value = & $FormatValue -Value $Deviation.Value -Missing $Deviation.Missing
                                $LocalizedData.Reference = $(if (-not $Deviation.HasReference) {
                                        $LocalizedData.ValueNoMajority
                                    } else {
                                        & $FormatValue -Value $Deviation.Reference -Missing $Deviation.ReferenceIsMissing
                                    })
                            }
                        }
                    })
                #endregion Objects

                #region Health checks
                $CheckedResults = @($Results | Where-Object { $_.Check -and $_.Deviations.Count -gt 0 })
                $ShowCheck = ($CheckedResults.Count -gt 0)
                if ($ShowCheck) {
                    foreach ($Result in $CheckedResults) {
                        $SummaryObj | Where-Object { $_.$($LocalizedData.Category) -eq $Result.Label } |
                            Set-Style -Style Warning -Property $LocalizedData.DeviationCount
                        $DeviationObj | Where-Object { $_.$($LocalizedData.Category) -eq $Result.Label } |
                            Set-Style -Style Warning -Property $LocalizedData.Value
                    }
                }
                #endregion Health checks

                Section -Style Heading2 $LocalizedData.Heading {
                    Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName, ($NodeNames -join ', '))
                    BlankLine
                    $TableParams = @{
                        Name = "$($LocalizedData.TableSummary) - $HvObjectName"
                        List = $false
                        ColumnWidths = 50, 25, 25
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $SummaryObj | Table @TableParams

                    if ($ShowCheck) {
                        Paragraph $LocalizedData.HealthCheck -Bold -Underline
                        BlankLine
                        Paragraph ($LocalizedData.ConsistencyBP -f (($CheckedResults | ForEach-Object { $_.Label }) -join ', '))
                        BlankLine
                    }

                    Section -Style Heading3 $LocalizedData.HeadingDeviations {
                        if ($DeviationObj.Count -eq 0) {
                            Paragraph $LocalizedData.NoDeviations
                        } else {
                            Paragraph $LocalizedData.ParagraphDeviations
                            BlankLine
                            $TableParams = @{
                                Name = "$($LocalizedData.TableDeviations) - $HvObjectName"
                                List = $false
                                ColumnWidths = 16, 30, 16, 19, 19
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $DeviationObj | Table @TableParams
                        }
                    }

                    if ($InfoLevel.Consistency -ge 2) {
                        foreach ($Result in @($Results | Where-Object { $_.Keys.Count -gt 0 })) {
                            Section -Style Heading3 ($LocalizedData.HeadingMatrix -f $Result.Label) {
                                $Lookup = @{}
                                foreach ($HostInput in $Result.Input) {
                                    $Values = @{}
                                    foreach ($Item in @($HostInput.Items | Where-Object { $_ })) {
                                        $Values[[string]$Item.Key] = [string]$Item.Value
                                    }
                                    $Lookup[[string]$HostInput.Name] = $Values
                                }
                                $MatrixObj = @(foreach ($Key in $Result.Keys) {
                                        $Row = [ordered]@{ $LocalizedData.Setting = & $FormatKey $Key }
                                        foreach ($NodeName in $NodeNames) {
                                            $Values = $Lookup[$NodeName]
                                            $Missing = -not ($Values -and $Values.ContainsKey($Key))
                                            $Row[$NodeName] = & $FormatValue -Value $(if (-not $Missing) { $Values[$Key] } else { $null }) -Missing $Missing
                                        }
                                        $RowObj = [PSCustomObject]$Row
                                        if ($Result.Check) {
                                            $DeviatingHosts = @($Result.Deviations | Where-Object { $_.Key -eq $Key } | ForEach-Object { $_.Name })
                                            if ($DeviatingHosts.Count -gt 0) {
                                                $RowObj | Set-Style -Style Warning -Property $DeviatingHosts
                                            }
                                        }
                                        $RowObj
                                    })
                                $NodeWidth = [math]::Floor(65 / [math]::Max($NodeNames.Count, 1))
                                $TableParams = @{
                                    Name = "$($LocalizedData.TableMatrix) - $($Result.Label)"
                                    List = $false
                                    ColumnWidths = @(100 - ($NodeWidth * $NodeNames.Count)) + @($NodeNames | ForEach-Object { $NodeWidth })
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $MatrixObj | Table @TableParams
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
