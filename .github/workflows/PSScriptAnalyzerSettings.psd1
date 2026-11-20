@{
    ExcludeRules = @(
        'PSUseToExportFieldsInManifest',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidGlobalVars'
    )
    Rules = @{
        # The module runs on Windows PowerShell 5.1 and PowerShell 7: no syntax that only one of them understands.
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
