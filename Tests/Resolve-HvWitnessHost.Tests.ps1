# Unit tests for the file share witness location check. All data is synthetic (example.com, TEST-NET).
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvWitnessHost.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    $script:VMs = @(
        [PSCustomObject]@{ Name = 'APP01'; HostNames = @('app01.example.com'); IPAddresses = @('192.0.2.21', 'fe80::1') }
        [PSCustomObject]@{ Name = 'File Server'; HostNames = @('fs01.example.com'); IPAddresses = @('192.0.2.30') }
        [PSCustomObject]@{ Name = 'NoTools'; HostNames = @(); IPAddresses = @() }
    )
}

Describe 'Resolve-HvWitnessHost' {

    It 'finds the VM by its name' {
        Resolve-HvWitnessHost -SharePath '\\app01\witness$' -VM $script:VMs | Should -Be 'APP01'
    }

    It 'finds the VM by the guest host name' {
        Resolve-HvWitnessHost -SharePath '\\fs01.example.com\witness' -VM $script:VMs | Should -Be 'File Server'
    }

    It 'finds the VM by its IP address' {
        Resolve-HvWitnessHost -SharePath '\\192.0.2.30\witness' -VM $script:VMs | Should -Be 'File Server'
    }

    It 'returns nothing for a server outside the cluster' {
        Resolve-HvWitnessHost -SharePath '\\fs02.example.com\witness' -VM $script:VMs | Should -BeNullOrEmpty
        Resolve-HvWitnessHost -SharePath '\\192.0.2.99\witness' -VM $script:VMs | Should -BeNullOrEmpty
    }

    It 'does not match a DFS namespace by the domain name' {
        Resolve-HvWitnessHost -SharePath '\\example.com\dfs\witness' -VM $script:VMs | Should -BeNullOrEmpty
    }

    It 'returns nothing without share path or VMs' {
        Resolve-HvWitnessHost -SharePath '' -VM $script:VMs | Should -BeNullOrEmpty
        Resolve-HvWitnessHost -SharePath '\\app01\witness' -VM @() | Should -BeNullOrEmpty
    }
}
