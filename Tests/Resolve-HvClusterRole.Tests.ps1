# Unit tests for the cluster role, CSV and CAU evaluation. All data is synthetic; no data from real environments.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvClusterRole.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestGroup {
        param (
            [String] $Name,
            [String] $GroupType = 'VirtualMachine',
            [String] $State = 'Online',
            [Object] $Priority = 2000,
            [Object] $IsCoreGroup = $false
        )
        [PSCustomObject]@{
            Name = $Name
            GroupType = $GroupType
            IsCoreGroup = $IsCoreGroup
            OwnerNode = 'hv01'
            State = $State
            Priority = $Priority
        }
    }
}

Describe 'Resolve-HvClusterGroup' {

    It 'leaves out the core and infrastructure groups' {
        $Result = @(Resolve-HvClusterGroup -Group @(
                New-TestGroup -Name 'Cluster Group' -GroupType 'Cluster' -IsCoreGroup $true
                New-TestGroup -Name 'Available Storage' -GroupType 'AvailableStorage' -IsCoreGroup $true -State 'Offline'
                New-TestGroup -Name 'pool' -GroupType 'ClusterStoragePool'
                New-TestGroup -Name 'SDDC Group' -GroupType 'CoreSddc' -IsCoreGroup 'True'
                New-TestGroup -Name 'vm01'
                New-TestGroup -Name 'fs01' -GroupType 'FileServer'
            ))
        $Result.Name | Should -Be @('vm01', 'fs01')
    }

    It 'maps the priority <Priority> to <Expected>' -TestCases @(
        @{ Priority = 3000; Expected = 'High' }
        @{ Priority = 2000; Expected = 'Medium' }
        @{ Priority = 1000; Expected = 'Low' }
        @{ Priority = 0; Expected = 'NoAutoStart' }
        @{ Priority = 1500; Expected = '1500' }
    ) {
        param ($Priority, $Expected)
        (Resolve-HvClusterGroup -Group @(New-TestGroup -Name 'vm01' -Priority $Priority)).PriorityKey | Should -Be $Expected
    }

    It 'rates the state <State> as <Expected>' -TestCases @(
        @{ State = 'Online'; Expected = 'Ok' }
        @{ State = 'Offline'; Expected = 'Ok' }
        @{ State = 'Failed'; Expected = 'Critical' }
        @{ State = 'PartialOnline'; Expected = 'Warning' }
        @{ State = 'Pending'; Expected = 'Warning' }
    ) {
        param ($State, $Expected)
        (Resolve-HvClusterGroup -Group @(New-TestGroup -Name 'vm01' -State $State)).StateSeverity | Should -Be $Expected
    }

    It 'returns nothing for a cluster without roles' {
        Resolve-HvClusterGroup -Group @() | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-HvCsvState' {

    BeforeAll {
        function New-TestCsv {
            param (
                [String] $Name = 'Volume1',
                [String] $State = 'Online',
                [Object] $FreePercent = 50,
                [Object] $MaintenanceMode = $false
            )
            [PSCustomObject]@{ Name = $Name; State = $State; FreePercent = $FreePercent; MaintenanceMode = $MaintenanceMode }
        }
        function New-TestCsvState {
            param (
                [String] $Name = 'Volume1',
                [String] $Node,
                [String] $StateInfo = 'Direct',
                [String] $FileSystemReason = 'NotFileSystemRedirected',
                [String] $BlockReason = 'NotBlockRedirected'
            )
            [PSCustomObject]@{
                Name = $Name
                Node = $Node
                StateInfo = $StateInfo
                FileSystemRedirectedIOReason = $FileSystemReason
                BlockRedirectedIOReason = $BlockReason
            }
        }
    }

    It 'rates the state <State> as <Expected>' -TestCases @(
        @{ State = 'Online'; Expected = 'Ok' }
        @{ State = 'Failed'; Expected = 'Critical' }
        @{ State = 'Offline'; Expected = 'Critical' }
        @{ State = 'PartialOnline'; Expected = 'Warning' }
    ) {
        param ($State, $Expected)
        (Resolve-HvCsvState -Volume @(New-TestCsv -State $State)).StateSeverity | Should -Be $Expected
    }

    It 'warns about a volume in maintenance mode' {
        (Resolve-HvCsvState -Volume @(New-TestCsv -MaintenanceMode 'True')).StateSeverity | Should -Be 'Warning'
    }

    It 'reports direct I/O' {
        $Result = Resolve-HvCsvState -Volume @(New-TestCsv) -NodeState @(
            New-TestCsvState -Node 'hv01'
            New-TestCsvState -Node 'hv02'
        )
        $Result.IoModeKey | Should -Be 'Direct'
        $Result.IoSeverity | Should -Be 'Ok'
    }

    It 'accepts file system redirected I/O on ReFS' {
        $Result = Resolve-HvCsvState -Volume @(New-TestCsv) -NodeState @(
            New-TestCsvState -Node 'hv01' -StateInfo 'FileSystemRedirected' -FileSystemReason 'FileSystemReFs'
            New-TestCsvState -Node 'hv02' -StateInfo 'FileSystemRedirected' -FileSystemReason 'FileSystemReFs'
        )
        $Result.IoModeKey | Should -Be 'ReFsRedirected'
        $Result.IoSeverity | Should -Be 'Ok'
    }

    It 'warns about block redirected I/O and names the node' {
        $Result = Resolve-HvCsvState -Volume @(New-TestCsv) -NodeState @(
            New-TestCsvState -Node 'hv01'
            New-TestCsvState -Node 'hv02' -StateInfo 'BlockRedirected' -BlockReason 'NoDiskConnectivity'
        )
        $Result.IoModeKey | Should -Be 'Redirected'
        $Result.IoSeverity | Should -Be 'Warning'
        $Result.RedirectedNodes | Should -Be @('hv02')
    }

    It 'only uses the node states of the same volume' {
        $Result = @(Resolve-HvCsvState -Volume @(New-TestCsv -Name 'Volume1'; New-TestCsv -Name 'Volume2') -NodeState @(
                New-TestCsvState -Name 'Volume1' -Node 'hv01'
                New-TestCsvState -Name 'Volume2' -Node 'hv01' -StateInfo 'FileSystemRedirected' -FileSystemReason 'UserRequest'
            ))
        ($Result | Where-Object { $_.Name -eq 'Volume1' }).IoModeKey | Should -Be 'Direct'
        ($Result | Where-Object { $_.Name -eq 'Volume2' }).IoModeKey | Should -Be 'Redirected'
    }

    It 'reports an unknown I/O mode without node states' {
        (Resolve-HvCsvState -Volume @(New-TestCsv)).IoModeKey | Should -Be 'Unknown'
    }

    It 'rates <FreePercent> % free space as <Expected>' -TestCases @(
        @{ FreePercent = 50; Expected = 'Ok' }
        @{ FreePercent = 20; Expected = 'Ok' }
        @{ FreePercent = 19.9; Expected = 'Warning' }
        @{ FreePercent = 9.5; Expected = 'Critical' }
    ) {
        param ($FreePercent, $Expected)
        (Resolve-HvCsvState -Volume @(New-TestCsv -FreePercent $FreePercent)).FreeSeverity | Should -Be $Expected
    }

    It 'does not rate a volume without free space information' {
        (Resolve-HvCsvState -Volume @(New-TestCsv -FreePercent $null)).FreeSeverity | Should -Be 'Ok'
    }
}

Describe 'Resolve-HvCauState' {

    It 'flags a cluster without self-updating role' {
        $Result = Resolve-HvCauState -RoleParameter @()
        $Result.HasSelfUpdatingRole | Should -BeFalse
        $Result.Findings | Should -Be @('NoSelfUpdatingRole')
    }

    It 'reads the name/value pairs returned by Get-CauClusterRole' {
        $Result = Resolve-HvCauState -RoleParameter @(
            [PSCustomObject]@{ Name = 'ResourceGroupName'; Value = 'CAUexample' }
            [PSCustomObject]@{ Name = 'Status'; Value = 'Online' }
            [PSCustomObject]@{ Name = 'MaxFailedNodes'; Value = 1 }
        )
        $Result.HasSelfUpdatingRole | Should -BeTrue
        $Result.SelfUpdatingRoleOnline | Should -BeTrue
        $Result.Settings['MaxFailedNodes'] | Should -Be 1
        $Result.Findings | Should -BeNullOrEmpty
    }

    It 'flags a self-updating role that is offline' {
        $Result = Resolve-HvCauState -RoleParameter @{ ResourceGroupName = 'CAUexample'; Status = 'Offline' }
        $Result.Findings | Should -Be @('SelfUpdatingRoleOffline')
    }

    It 'flags a last run with the result <Result>' -TestCases @(
        @{ Result = 'Failed' }
        @{ Result = 'Canceled' }
    ) {
        param ($Result)
        (Resolve-HvCauState -RoleParameter @{ ResourceGroupName = 'CAUexample'; Status = 'Online' } -LastRunResult $Result).Findings |
            Should -Be @('LastRunNotSucceeded')
    }

    It 'accepts a successful last run and no recorded run' {
        $Role = @{ ResourceGroupName = 'CAUexample'; Status = 'Online' }
        (Resolve-HvCauState -RoleParameter $Role -LastRunResult 'Succeeded').Findings | Should -BeNullOrEmpty
        (Resolve-HvCauState -RoleParameter $Role -LastRunResult '').Findings | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-HvSize' {

    It 'formats <Bytes> bytes as <Expected>' -TestCases @(
        @{ Bytes = 536870912000; Expected = ('{0} GB' -f 500) }
        @{ Bytes = 1610612736; Expected = ('{0} GB' -f 1.5) }
        @{ Bytes = 1099511627776; Expected = ('{0} TB' -f 1) }
        @{ Bytes = 1649267441664; Expected = ('{0} TB' -f 1.5) }
    ) {
        param ($Bytes, $Expected)
        ConvertTo-HvSize $Bytes | Should -Be $Expected
    }

    It 'shows -- for an empty value' {
        ConvertTo-HvSize $null | Should -Be '--'
    }

    It 'uses the decimal separator of the given culture' {
        ConvertTo-HvSize 1610612736 -Culture ([System.Globalization.CultureInfo]::GetCultureInfo('en-US')) | Should -Be '1.5 GB'
        ConvertTo-HvSize 1610612736 -Culture ([System.Globalization.CultureInfo]::GetCultureInfo('de-DE')) | Should -Be '1,5 GB'
    }
}

Describe 'ConvertTo-HvPercent' {

    It 'rounds to the given decimals in the given culture' {
        $EnUs = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
        ConvertTo-HvPercent 97.44922 -Culture $EnUs | Should -Be '97.4 %'
        ConvertTo-HvPercent 25 -Decimals 2 -Culture $EnUs | Should -Be '25 %'
        ConvertTo-HvPercent 97.44922 -Culture ([System.Globalization.CultureInfo]::GetCultureInfo('de-DE')) | Should -Be '97,4 %'
    }

    It 'shows -- for an empty value' {
        ConvertTo-HvPercent $null | Should -Be '--'
    }
}
