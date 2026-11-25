# Checks the language files:
# - every string a function reads via $LocalizedData.<Key> exists in the en-US template
# - every other language has exactly the same keys as en-US
#
# A missing string renders as an empty label or heading, which is easy to miss when testing in one language.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\LocalizationData.Tests.ps1

BeforeDiscovery {
    $script:ModuleFolder = Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV'
    $script:FunctionFiles = @(Get-ChildItem -Path (Join-Path $script:ModuleFolder 'Src') -Filter '*.ps1' -Recurse |
            Where-Object { (Get-Content -Path $_.FullName -Raw) -match '\$LocalizedData = \$reportTranslate\.\w+' } |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $script:LanguageFolders = @(Get-ChildItem -Path (Join-Path $script:ModuleFolder 'Language') -Directory |
            Where-Object { $_.Name -ne 'en-US' } |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $script:ModuleFolder = Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV'
    $script:Template = Import-LocalizedData -BaseDirectory (Join-Path $script:ModuleFolder 'Language') -UICulture 'en-US' -FileName 'MicrosoftHyperV.psd1'
}

Describe 'Localization data' {

    It 'loads the en-US template' {
        $script:Template | Should -Not -BeNullOrEmpty
    }

    It '<Name> only uses strings that exist in en-US' -TestCases $script:FunctionFiles {
        param ($Name, $Path)
        $Text = Get-Content -Path $Path -Raw
        $SectionMatch = [regex]::Match($Text, '\$LocalizedData = \$reportTranslate\.(?<section>\w+)')
        $SectionMatch.Success | Should -BeTrue -Because 'functions bind their strings with $LocalizedData = $reportTranslate.<Section>'
        $Section = $script:Template[$SectionMatch.Groups['section'].Value]
        $Section | Should -Not -BeNullOrEmpty -Because "section '$($SectionMatch.Groups['section'].Value)' must exist in en-US"

        # Static keys only; keys built at runtime (e.g. "Env$Type") are covered by the classification tests.
        $Keys = @([regex]::Matches($Text, '\$LocalizedData\.(?<key>\w+)') | ForEach-Object { $_.Groups['key'].Value }) +
            @([regex]::Matches($Text, '\$LocalizedData\[''(?<key>\w+)''\]') | ForEach-Object { $_.Groups['key'].Value }) |
            Sort-Object -Unique
        foreach ($Key in $Keys) {
            $Section.ContainsKey($Key) | Should -BeTrue -Because "'$Key' is used in $Name"
        }
    }

    It 'provides display strings for every environment type and storage topology' {
        $Section = $script:Template['GetAbrHvEnvironmentType']
        foreach ($Type in 'Standalone', 'S2D', 'AzureLocal', 'ThreeTier', 'SMB', 'Mixed', 'NoSharedStorage') {
            $Section.ContainsKey("Env$Type") | Should -BeTrue -Because "Env$Type is rendered for that environment type"
        }
        foreach ($Topology in 'S2D', 'iSCSI', 'FibreChannel', 'SharedSAS', 'SMB', 'Local') {
            $Section.ContainsKey("Topology$Topology") | Should -BeTrue -Because "Topology$Topology is rendered for that storage topology"
        }
        foreach ($Platform in 'WindowsServer', 'AzureLocal') {
            $Section.ContainsKey("Platform$Platform") | Should -BeTrue
        }
        foreach ($Mode in 'Automatic', 'Override') {
            $Section.ContainsKey("Detection$Mode") | Should -BeTrue
        }
    }

    It 'provides a label for every detection check' {
        $Section = $script:Template['GetAbrHvEnvironmentType']
        $HelperText = Get-Content -Path (Join-Path $script:ModuleFolder 'Src\Private\Helpers.ps1') -Raw
        $Checks = @([regex]::Matches($HelperText, "Check = '(?<check>\w+)'") | ForEach-Object { $_.Groups['check'].Value }) +
            @([regex]::Matches($HelperText, "'(?<check>ClusteredDisk|DataDisk)'") | ForEach-Object { $_.Groups['check'].Value }) |
            Sort-Object -Unique
        $Checks.Count | Should -BeGreaterThan 0
        foreach ($Check in $Checks) {
            $Section.ContainsKey("Check$Check") | Should -BeTrue -Because "evidence check '$Check' needs a label"
        }
    }

    It 'provides a translation for every evidence value key' {
        $Section = $script:Template['GetAbrHvEnvironmentType']
        $HelperText = Get-Content -Path (Join-Path $script:ModuleFolder 'Src\Private\Helpers.ps1') -Raw
        # Literal keys plus the keys assigned through variables ($Membership, $RoleState).
        $ValueKeys = @([regex]::Matches($HelperText, "ValueKey = '(?<key>\w+)'") | ForEach-Object { $_.Groups['key'].Value }) +
            @('Cluster', 'None', 'Installed', 'NotInstalled') | Sort-Object -Unique
        foreach ($Key in $ValueKeys) {
            $Section.ContainsKey("Value$Key") | Should -BeTrue -Because "evidence value key '$Key' needs a translation"
        }
    }

    It 'provides display strings for the mapped cluster property values' {
        $Section = $script:Template['GetAbrHvClusterOverview']
        foreach ($Key in 'AutoBalancerMode0', 'AutoBalancerMode1', 'AutoBalancerMode2', 'AutoBalancerLevel1', 'AutoBalancerLevel2', 'AutoBalancerLevel3') {
            $Section.ContainsKey($Key) | Should -BeTrue -Because "$Key is rendered for that cluster setting"
        }
        foreach ($Level in 8..12) {
            $Section.ContainsKey("FunctionalLevel$Level") | Should -BeTrue -Because "FunctionalLevel$Level is rendered for that level"
        }
    }

    It 'provides display strings for every quorum model and witness type' {
        $Section = $script:Template['GetAbrHvClusterQuorum']
        foreach ($Model in 'NodeMajority', 'NodeAndWitnessMajority', 'DiskOnly') {
            $Section.ContainsKey("Model$Model") | Should -BeTrue -Because "Model$Model is rendered for that quorum model"
        }
        # 'Other' shows the raw resource type and needs no translation.
        foreach ($Type in 'None', 'Disk', 'FileShare', 'Cloud') {
            $Section.ContainsKey("Witness$Type") | Should -BeTrue -Because "Witness$Type is rendered for that witness type"
        }
    }

    It 'provides display strings for every cluster network role' {
        $Section = $script:Template['GetAbrHvClusterNetwork']
        foreach ($Role in 'None', 'ClusterOnly', 'ClientOnly', 'ClusterAndClient') {
            $Section.ContainsKey("Role$Role") | Should -BeTrue -Because "Role$Role is rendered for that network role"
        }
    }

    It 'provides display strings for every live migration performance option' {
        $Section = $script:Template['GetAbrHvLiveMigration']
        foreach ($Option in 'TCPIP', 'Compression', 'SMB') {
            $Section.ContainsKey("Performance$Option") | Should -BeTrue -Because "Performance$Option is rendered for that option"
        }
    }

    It 'provides display strings for every cluster role priority and CSV I/O mode' {
        $Section = $script:Template['GetAbrHvClusterRole']
        foreach ($Key in 'High', 'Medium', 'Low', 'NoAutoStart') {
            $Section.ContainsKey("Priority$Key") | Should -BeTrue -Because "Priority$Key is rendered for that priority"
        }
        # Other role types show the raw group type.
        foreach ($Type in 'VirtualMachine', 'FileServer', 'ScaleoutFileServer') {
            $Section.ContainsKey("Type$Type") | Should -BeTrue -Because "Type$Type is rendered for that role type"
        }
        $Section = $script:Template['GetAbrHvClusterSharedVolume']
        foreach ($Mode in 'Direct', 'ReFsRedirected', 'Redirected', 'Unknown') {
            $Section.ContainsKey("IoMode$Mode") | Should -BeTrue -Because "IoMode$Mode is rendered for that I/O mode"
        }
    }

    It 'provides display strings for every host scheduler, VBS, security service and Secure Boot value' {
        $Section = $script:Template['GetAbrHvHost']
        foreach ($Key in 'ClassicNoSmt', 'Classic', 'Core', 'Root', 'Unknown') {
            $Section.ContainsKey("Scheduler$Key") | Should -BeTrue -Because "Scheduler$Key is rendered for that scheduler type"
        }
        foreach ($Key in 'Off', 'Configured', 'Running', 'Unknown') {
            $Section.ContainsKey("Vbs$Key") | Should -BeTrue -Because "Vbs$Key is rendered for that VBS status"
        }
        # Unknown service numbers show the raw key.
        foreach ($Key in 'CredentialGuard', 'Hvci', 'SystemGuard', 'SmmProtection', 'KernelShadowStack', 'Hvpt') {
            $Section.ContainsKey("Service$Key") | Should -BeTrue -Because "Service$Key is rendered for that security service"
        }
        foreach ($Key in 'On', 'Off', 'Unknown') {
            $Section.ContainsKey("SecureBoot$Key") | Should -BeTrue -Because "SecureBoot$Key is rendered for that state"
        }
    }

    # Only defined when translations exist: Pester 6 fails on empty -TestCases, and Pester 5 has no
    # -AllowNullOrEmptyForEach switch.
    if ($script:LanguageFolders.Count -gt 0) {
        It 'language <Name> is saved as UTF-8 with BOM' -TestCases $script:LanguageFolders {
            param ($Name, $Path)
            # Windows PowerShell 5.1 reads language files without BOM as ANSI, which breaks umlauts and accents.
            $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $Path 'MicrosoftHyperV.psd1'))
            ($Bytes.Count -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) | Should -BeTrue
        }

        It 'language <Name> has the same keys as en-US' -TestCases $script:LanguageFolders {
            param ($Name, $Path)
            $Localized = Import-LocalizedData -BaseDirectory (Split-Path -Path $Path -Parent) -UICulture $Name -FileName 'MicrosoftHyperV.psd1'
            foreach ($SectionName in $script:Template.Keys) {
                $Localized.ContainsKey($SectionName) | Should -BeTrue -Because "section '$SectionName' is missing in $Name"
                $Missing = @($script:Template[$SectionName].Keys | Where-Object { -not $Localized[$SectionName].ContainsKey($_) })
                $Missing | Should -BeNullOrEmpty -Because "keys missing in $Name/$SectionName"
            }
        }
    }
}
