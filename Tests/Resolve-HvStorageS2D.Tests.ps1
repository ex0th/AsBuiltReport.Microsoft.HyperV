# Unit tests for the Storage Spaces Direct evaluation. All data is synthetic.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvStorageS2D.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')
}

Describe 'ConvertTo-HvHealthSeverity' {

    It 'maps <Status> to <Expected>' -TestCases @(
        @{ Status = 'Healthy'; Expected = 'Ok' }
        @{ Status = 0; Expected = 'Ok' }
        @{ Status = 'Warning'; Expected = 'Warning' }
        @{ Status = 'Unknown'; Expected = 'Warning' }
        @{ Status = 'Unhealthy'; Expected = 'Critical' }
        @{ Status = 2; Expected = 'Critical' }
    ) {
        param ($Status, $Expected)
        ConvertTo-HvHealthSeverity $Status | Should -Be $Expected
    }
}

Describe 'ConvertTo-HvFaultSeverity' {

    It 'maps <Severity> to <Expected>' -TestCases @(
        @{ Severity = 'Information'; Expected = 'Ok' }
        @{ Severity = 'Degraded/Warning'; Expected = 'Warning' }
        @{ Severity = 'Minor failure'; Expected = 'Warning' }
        @{ Severity = 'Major failure'; Expected = 'Critical' }
        @{ Severity = 'Critical failure'; Expected = 'Critical' }
        @{ Severity = 'Non-recoverable error'; Expected = 'Critical' }
        @{ Severity = 4; Expected = 'Warning' }
        @{ Severity = 6; Expected = 'Critical' }
    ) {
        param ($Severity, $Expected)
        ConvertTo-HvFaultSeverity $Severity | Should -Be $Expected
    }
}

Describe 'Resolve-HvResiliency' {

    It 'maps <Name> with <Copies> copies and redundancy <Redundancy> to <Expected>' -TestCases @(
        @{ Name = 'Mirror'; Copies = 2; Redundancy = 1; Expected = 'TwoWayMirror' }
        @{ Name = 'Mirror'; Copies = 3; Redundancy = 2; Expected = 'ThreeWayMirror' }
        @{ Name = 'Mirror'; Copies = 4; Redundancy = 3; Expected = 'NestedTwoWayMirror' }
        @{ Name = 'Parity'; Copies = 1; Redundancy = 1; Expected = 'SingleParity' }
        @{ Name = 'Parity'; Copies = 1; Redundancy = 2; Expected = 'DualParity' }
        @{ Name = 'Parity'; Copies = 2; Redundancy = 3; Expected = 'NestedParity' }
        @{ Name = 'Simple'; Copies = 1; Redundancy = 0; Expected = 'Simple' }
        @{ Name = 'Custom'; Copies = 1; Redundancy = 0; Expected = 'Custom' }
        @{ Name = ''; Copies = $null; Redundancy = $null; Expected = '' }
    ) {
        param ($Name, $Copies, $Redundancy, $Expected)
        Resolve-HvResiliency -ResiliencySettingName $Name -NumberOfDataCopies $Copies -PhysicalDiskRedundancy $Redundancy |
            Should -Be $Expected
    }
}

Describe 'Resolve-HvS2DReserve' {

    BeforeAll {
        function New-TestDisk {
            param ([Double] $Size, [String] $Usage = 'Auto-Select')
            [PSCustomObject]@{ Size = $Size; Usage = $Usage }
        }
    }

    It 'recommends one capacity drive per node' {
        $Disks = @(1..8 | ForEach-Object { New-TestDisk -Size 1TB })
        $Result = Resolve-HvS2DReserve -PoolSize 8TB -AllocatedSize 5TB -PhysicalDisk $Disks -NodeCount 2
        $Result.ReserveBytes | Should -Be (2 * 1TB)
        $Result.FreeBytes | Should -Be 3TB
        $Result.ReserveMet | Should -BeTrue
        [math]::Round($Result.AllocatedPercent, 1) | Should -Be 62.5
    }

    It 'limits the reserve to four drives' {
        $Disks = @(1..16 | ForEach-Object { New-TestDisk -Size 1TB })
        (Resolve-HvS2DReserve -PoolSize 16TB -AllocatedSize 0 -PhysicalDisk $Disks -NodeCount 8).ReserveBytes | Should -Be 4TB
    }

    It 'uses the largest capacity drive and ignores cache drives' {
        $Disks = @(
            New-TestDisk -Size 4TB
            New-TestDisk -Size 8TB
            New-TestDisk -Size 16TB -Usage 'Journal'
        )
        (Resolve-HvS2DReserve -PoolSize 12TB -AllocatedSize 0 -PhysicalDisk $Disks -NodeCount 2).ReserveBytes | Should -Be 16TB
    }

    It 'flags a pool with less unallocated capacity than the reserve' {
        $Disks = @(1..4 | ForEach-Object { New-TestDisk -Size 2TB })
        $Result = Resolve-HvS2DReserve -PoolSize 8TB -AllocatedSize 5TB -PhysicalDisk $Disks -NodeCount 2
        $Result.ReserveMet | Should -BeFalse
    }

    It 'handles a pool without disk information' {
        $Result = Resolve-HvS2DReserve -PoolSize 0 -AllocatedSize 0 -NodeCount 2
        $Result.ReserveBytes | Should -Be 0
        $Result.AllocatedPercent | Should -BeNullOrEmpty
    }
}
