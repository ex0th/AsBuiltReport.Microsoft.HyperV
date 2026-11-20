# Unit tests for the quorum evaluation. All data is synthetic; no data from real environments.
#
# Run from the repository root: Invoke-Pester -Path .\Tests\Resolve-HvQuorumState.Tests.ps1

BeforeAll {
    . (Join-Path $PSScriptRoot '..\AsBuiltReport.Microsoft.HyperV\Src\Private\Helpers.ps1')

    function New-TestQuorumData {
        param (
            [String] $QuorumType = 'Majority',
            [String] $WitnessName,
            [String] $WitnessResourceType,
            [String] $WitnessState = 'Online',
            [Int] $DynamicQuorum = 1,
            [Int] $WitnessDynamicWeight = 1,
            [Int] $LowerQuorumPriorityNodeId = 0,
            [Int[]] $NodeWeight = @(1, 1),
            [Int[]] $DynamicWeight = @(1, 1)
        )
        $Nodes = for ($Index = 0; $Index -lt $NodeWeight.Count; $Index++) {
            [PSCustomObject]@{
                Name = 'node{0:d2}' -f ($Index + 1)
                Id = [string]($Index + 1)
                State = 'Up'
                NodeWeight = [uint32]$NodeWeight[$Index]
                DynamicWeight = [uint32]$DynamicWeight[$Index]
            }
        }
        [PSCustomObject]@{
            QuorumType = $QuorumType
            WitnessName = $WitnessName
            WitnessResourceType = $WitnessResourceType
            WitnessState = $(if ($WitnessName) { $WitnessState } else { $null })
            DynamicQuorum = [uint32]$DynamicQuorum
            WitnessDynamicWeight = [uint32]$WitnessDynamicWeight
            LowerQuorumPriorityNodeId = [uint32]$LowerQuorumPriorityNodeId
            Nodes = @($Nodes)
        }
    }
}

Describe 'Resolve-HvQuorumState' {

    Context 'Witness types' {

        It 'recognises a <Expected> witness from the resource type <ResourceType>' -TestCases @(
            @{ ResourceType = 'Physical Disk'; Expected = 'Disk' }
            @{ ResourceType = 'File Share Witness'; Expected = 'FileShare' }
            @{ ResourceType = 'Cloud Witness'; Expected = 'Cloud' }
            @{ ResourceType = 'Custom Witness'; Expected = 'Other' }
        ) {
            param ($ResourceType, $Expected)
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType $ResourceType)
            $Result.WitnessType | Should -Be $Expected
            $Result.HasWitness | Should -BeTrue
            $Result.QuorumModel | Should -Be 'NodeAndWitnessMajority'
            $Result.Findings | Should -BeNullOrEmpty
        }

        It 'reports no witness when no quorum resource exists' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -NodeWeight 1, 1, 1 -DynamicWeight 1, 1, 1)
            $Result.WitnessType | Should -Be 'None'
            $Result.HasWitness | Should -BeFalse
            $Result.WitnessHasVote | Should -BeFalse
            $Result.QuorumModel | Should -Be 'NodeMajority'
        }

        It 'keeps the legacy disk only model' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -QuorumType 'DiskOnly' -WitnessName 'Cluster Disk 1' -WitnessResourceType 'Physical Disk')
            $Result.QuorumModel | Should -Be 'DiskOnly'
        }

    }

    Context 'Findings' {

        It 'flags a two-node cluster without witness' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -DynamicWeight 0, 1)
            $Result.Findings | Should -Contain 'NoWitnessTwoNodes'
            $Result.Findings | Should -Not -Contain 'NoWitness'
        }

        It 'flags a larger cluster without witness as NoWitness' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -NodeWeight 1, 1, 1, 1 -DynamicWeight 1, 1, 1, 0)
            $Result.Findings | Should -Contain 'NoWitness'
            $Result.Findings | Should -Not -Contain 'NoWitnessTwoNodes'
        }

        It 'counts only nodes with an assigned vote' {
            # Three nodes, one without a vote: two voting nodes and no witness.
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -NodeWeight 1, 1, 0 -DynamicWeight 1, 0, 0)
            $Result.VotingNodeCount | Should -Be 2
            $Result.Findings | Should -Contain 'NoWitnessTwoNodes'
        }

        It 'does not flag a missing witness for the disk only model' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -QuorumType 'DiskOnly' -WitnessName 'Cluster Disk 1' -WitnessResourceType 'Physical Disk')
            $Result.Findings | Should -BeNullOrEmpty
        }

        It 'flags a witness in the state <State>' -TestCases @(
            @{ State = 'Offline' }
            @{ State = 'Failed' }
            @{ State = 'Pending' }
        ) {
            param ($State)
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Cloud Witness' -WitnessResourceType 'Cloud Witness' -WitnessState $State)
            $Result.Findings | Should -Contain 'WitnessNotOnline'
            $Result.WitnessState | Should -Be $State
        }

        It 'flags disabled dynamic quorum' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType 'File Share Witness' -DynamicQuorum 0)
            $Result.Findings | Should -Be @('DynamicQuorumDisabled')
            $Result.DynamicQuorum | Should -BeFalse
        }

    }

    Context 'Votes' {

        It 'reports whether the witness currently has a vote' {
            $WithVote = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType 'Cloud Witness' -WitnessDynamicWeight 1)
            $WithoutVote = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType 'Cloud Witness' -WitnessDynamicWeight 0)
            $WithVote.WitnessHasVote | Should -BeTrue
            $WithoutVote.WitnessHasVote | Should -BeFalse
        }

        It 'resolves the lower quorum priority node to its name' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType 'Cloud Witness' -LowerQuorumPriorityNodeId 2)
            $Result.LowerPriorityNodeName | Should -Be 'node02'
        }

        It 'reports no lower quorum priority node for the ID 0' {
            $Result = Resolve-HvQuorumState -QuorumData (New-TestQuorumData -WitnessName 'Witness' -WitnessResourceType 'Cloud Witness')
            $Result.LowerPriorityNodeName | Should -BeNullOrEmpty
        }

    }

}
