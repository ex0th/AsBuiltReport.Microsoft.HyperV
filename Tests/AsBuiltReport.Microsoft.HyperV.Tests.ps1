BeforeAll {
    # Import the module under test
    # Requires AsBuiltReport.Core to be installed
    Import-Module AsBuiltReport.Core -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\AsBuiltReport.Microsoft.HyperV.psd1') -Force -ErrorAction Stop
}

Describe 'AsBuiltReport.Microsoft.HyperV' {

    Context 'Module Manifest' {

        BeforeAll {
            $script:manifest = Test-ModuleManifest -Path (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\AsBuiltReport.Microsoft.HyperV.psd1') -ErrorAction Stop
        }

        It 'has a valid manifest' {
            $script:manifest | Should -Not -BeNullOrEmpty
        }

        It 'has the correct module name' {
            $script:manifest.Name | Should -Be 'AsBuiltReport.Microsoft.HyperV'
        }

    }

    Context 'Public Functions' {

        It 'exports Invoke-AsBuiltReport.Microsoft.HyperV' {
            $commands = @(Get-Command -Module 'AsBuiltReport.Microsoft.HyperV')
            $commands.Name | Should -Contain 'Invoke-AsBuiltReport.Microsoft.HyperV'
        }

    }

    Context 'Report Configuration' {

        BeforeAll {
            $script:ModuleFolder = Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV'
            $script:Config = Get-Content -Path (Join-Path $script:ModuleFolder 'AsBuiltReport.Microsoft.HyperV.json') -Raw | ConvertFrom-Json
            $script:SourceText = (Get-ChildItem -Path (Join-Path $script:ModuleFolder 'Src') -Filter '*.ps1' -Recurse | Get-Content -Raw) -join [Environment]::NewLine
        }

        It 'has the report sections Core expects' {
            $script:Config.Report | Should -Not -BeNullOrEmpty
            $script:Config.Options | Should -Not -BeNullOrEmpty
            $script:Config.InfoLevel | Should -Not -BeNullOrEmpty
            $script:Config.HealthCheck | Should -Not -BeNullOrEmpty
        }

        It 'uses InfoLevel values between 0 and 5' {
            foreach ($Property in ($script:Config.InfoLevel.PSObject.Properties | Where-Object { $_.Name -ne '_comment_' })) {
                $Property.Value | Should -BeIn @(0, 1, 2, 3, 4, 5) -Because "InfoLevel.$($Property.Name)"
            }
        }

        It 'only defines InfoLevel keys that the code uses' {
            foreach ($Property in ($script:Config.InfoLevel.PSObject.Properties | Where-Object { $_.Name -ne '_comment_' })) {
                $script:SourceText | Should -Match ([regex]::Escape("`$InfoLevel.$($Property.Name)")) -Because "InfoLevel.$($Property.Name) should be evaluated somewhere"
            }
        }

        It 'only defines HealthCheck keys that the code uses' {
            foreach ($Group in $script:Config.HealthCheck.PSObject.Properties) {
                foreach ($Check in $Group.Value.PSObject.Properties) {
                    $script:SourceText | Should -Match ([regex]::Escape("`$Healthcheck.$($Group.Name).$($Check.Name)")) -Because "HealthCheck.$($Group.Name).$($Check.Name) should be evaluated somewhere"
                }
            }
        }

        It 'accepts only known storage topology values' {
            foreach ($Value in @($script:Config.Options.StorageTopology)) {
                $Value | Should -BeIn @('Auto', 'S2D', 'iSCSI', 'FibreChannel', 'SharedSAS', 'SMB', 'Local')
            }
        }

    }

    Context 'Report Conventions' {

        # Downstream tooling relies on numbered headings and on "Table N - <Section> - <Object>" captions.
        It '<Name> does not exclude headings from numbering' -TestCases @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private') -Filter 'Get-Abr*.ps1' | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }) {
            param ($Name, $Path)
            $Text = Get-Content -Path $Path -Raw
            $Text | Should -Not -Match 'ExcludeFromTOC'
            $Text | Should -Not -Match 'NOTOCHeading'
        }

        It '<Name> names every table as "Section - Object" and sets a caption' -TestCases @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private') -Filter 'Get-Abr*.ps1' | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }) {
            param ($Name, $Path)
            $Text = Get-Content -Path $Path -Raw
            $TableNames = [regex]::Matches($Text, 'Name = "(?<value>[^"]+)"\s*\r?\n\s*List =')
            $TableNames.Count | Should -BeGreaterThan 0
            foreach ($TableName in $TableNames) {
                $TableName.Groups['value'].Value | Should -Match '^\$\(\$LocalizedData\.\w+\) - .+$'
            }
            ([regex]::Matches($Text, '\$TableParams\[''Caption''\] = "- \$\(\$TableParams\.Name\)"')).Count | Should -Be $TableNames.Count
        }

    }

}
