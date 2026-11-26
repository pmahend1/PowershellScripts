@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Published command names (Remove-BinObjFolders, Get-LockingProcesses, ...) are plural;
        # renaming them would break existing users.
        'PSUseSingularNouns',
        # Write-Host is used on purpose for interactive prompts and coloured status lines.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        # The git helpers pass their arguments straight to git, so calls read like git itself:
        # Invoke-Git branch -m $OldName $NewName
        PSAvoidUsingPositionalParameters = @{
            Enable           = $true
            CommandAllowList = @('Invoke-Git', 'Test-Git', 'Get-GitExitCode')
        }
    }
}
