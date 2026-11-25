function Get-AbrHvHealthCheckSummary {
    <#
    .SYNOPSIS
        Used by As Built Report to list every health check finding of a cluster or host in one table.
    .DESCRIPTION
        Lists the findings that the sections reported with Write-HvHealthCheck: area (section), severity,
        finding and recommendation. Critical findings are listed first. Only rendered when health checks
        are enabled (New-AsBuiltReport -EnableHealthCheck).
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
        $LocalizedData = $reportTranslate.GetAbrHvHealthCheckSummary
    }

    process {
        try {
            if ($Healthcheck) {
                $Findings = @($HvHealthFindings | Where-Object { $_ })
                # Critical first, otherwise in the order of the report.
                $Ordered = @(@($Findings | Where-Object { $_.Severity -eq 'Critical' }) + @($Findings | Where-Object { $_.Severity -ne 'Critical' }))

                $SummaryObj = @(foreach ($Finding in $Ordered) {
                        $Row = [PSCustomObject][ordered]@{
                            $LocalizedData.Area = $Finding.Area
                            $LocalizedData.Severity = $LocalizedData["Severity$($Finding.Severity)"]
                            $LocalizedData.Finding = $Finding.Finding
                            $LocalizedData.Recommendation = ConvertTo-HvDisplayValue $Finding.Recommendation
                        }
                        $Row | Set-Style -Style $Finding.Severity -Property $LocalizedData.Severity
                        $Row
                    })

                Section -Style Heading2 $LocalizedData.Heading {
                    if ($SummaryObj.Count -eq 0) {
                        Paragraph ($LocalizedData.NoFindings -f $HvObjectName)
                    } else {
                        $Critical = @($Findings | Where-Object { $_.Severity -eq 'Critical' }).Count
                        Paragraph ($LocalizedData.ParagraphSummary -f $HvObjectName, $Findings.Count, $Critical, ($Findings.Count - $Critical))
                        BlankLine
                        $TableParams = @{
                            Name = "$($LocalizedData.TableSummary) - $HvObjectName"
                            List = $false
                            ColumnWidths = 16, 10, 37, 37
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SummaryObj | Table @TableParams
                    }
                }
            }
        } catch {
            Write-PScriboMessage -IsWarning $_.Exception.Message
        }
    }

    end {}
}
