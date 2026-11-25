# Unit tests for the shared block storage evaluation. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvStoragePath.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    # A host with MPIO, two disks with two paths each and a persistent, connected iSCSI session.
    function New-TestStorageData {
        [PSCustomObject]@{
            MpioInstalled = 'True'
            Disks = @(
                [PSCustomObject]@{ Number = '1'; FriendlyName = 'LUN01'; BusType = 'iSCSI'; Paths = 2 }
                [PSCustomObject]@{ Number = '2'; FriendlyName = 'LUN02'; BusType = 'iSCSI'; Paths = 4 }
            )
            IscsiSessions = @(
                [PSCustomObject]@{ TargetNodeAddress = 'iqn.2000-01.com.example:target01'; IsConnected = 'True'; IsPersistent = 'True' }
            )
        }
    }
}

Describe 'Resolve-HvStoragePath' {

    It 'returns nothing for redundant paths and persistent sessions' {
        Resolve-HvStoragePath -StorageData (New-TestStorageData) | Should -BeNullOrEmpty
    }

    It 'returns nothing for a host without shared disks and sessions' {
        $Data = [PSCustomObject]@{ MpioInstalled = 'False'; Disks = @(); IscsiSessions = @() }
        Resolve-HvStoragePath -StorageData $Data | Should -BeNullOrEmpty
    }

    It 'flags a disk with a single path' {
        $Data = New-TestStorageData
        $Data.Disks[0].Paths = 1
        $Result = @(Resolve-HvStoragePath -StorageData $Data)
        $Result.Check | Should -Be @('SinglePath')
        $Result[0].Object | Should -Be '1 (LUN01)'
    }

    It 'treats a disk that MPIO does not claim as a single path' {
        $Data = New-TestStorageData
        $Data.Disks[1].Paths = $null
        @(Resolve-HvStoragePath -StorageData $Data).Object | Should -Be @('2 (LUN02)')
    }

    It 'flags shared disks without MPIO' {
        $Data = New-TestStorageData
        $Data.MpioInstalled = 'False'
        foreach ($Disk in $Data.Disks) {
            $Disk.Paths = $null
        }
        $Result = @(Resolve-HvStoragePath -StorageData $Data)
        $Result.Check | Should -Be @('MpioMissing', 'SinglePath', 'SinglePath')
    }

    It 'rates a disconnected session as critical' {
        $Data = New-TestStorageData
        $Data.IscsiSessions[0].IsConnected = 'False'
        $Result = @(Resolve-HvStoragePath -StorageData $Data)
        $Result.Check | Should -Be @('IscsiNotConnected')
        $Result[0].Severity | Should -Be 'Critical'
        $Result[0].Object | Should -Be 'iqn.2000-01.com.example:target01'
    }

    It 'warns about a session that is not persistent' {
        $Data = New-TestStorageData
        $Data.IscsiSessions[0].IsPersistent = 'False'
        $Result = @(Resolve-HvStoragePath -StorageData $Data)
        $Result.Check | Should -Be @('IscsiNotPersistent')
        $Result[0].Severity | Should -Be 'Warning'
    }
}

Describe 'ConvertTo-HvResourceSeverity' {

    It 'maps <State> to <Expected>' -TestCases @(
        @{ State = 'Online'; Expected = 'Ok' }
        @{ State = 'Offline'; Expected = 'Warning' }
        @{ State = 'OnlinePending'; Expected = 'Warning' }
        @{ State = 'Failed'; Expected = 'Critical' }
    ) {
        param ($State, $Expected)
        ConvertTo-HvResourceSeverity $State | Should -Be $Expected
    }
}
