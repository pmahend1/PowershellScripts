<#
 .Synopsis
  Deletes orphan branches deleted from remote but present in local.

 .Description
  Runs 'git fetch --prune', then deletes every local branch whose upstream branch is gone.
  Skips the current branch and branches checked out in other worktrees.
  All branches are deleted in a single 'git branch -D' call.

 .Parameter Force
  Delete without asking for confirmation. Aliases: -Y, -Yes.

 .Example
  Remove-GitOrphanBranches

 .Example
  # No prompt
  rgob -Y

 .Example
  # Show what would be deleted
  Remove-GitOrphanBranches -WhatIf
#>

# Runs git and throws with git's own message if it fails.
function Invoke-Git {
    # Native stderr would become an error record and stop the script if the caller uses -ErrorAction Stop.
    $ErrorActionPreference = 'Continue'
    # Turn stderr lines into strings in the same pipeline: in Windows PowerShell 5.1, collecting them
    # first would also add git's normal stderr output (e.g. fetch progress) to the caller's -ErrorVariable.
    $lines = @(& git @args 2>&1 | ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($args -join ' ') failed (exit $exitCode): $($lines -join [Environment]::NewLine)"
    }
    return $lines
}

function Remove-GitOrphanBranches {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('Y', 'Yes')]
        [switch] $Force
    )

    try {
        $null = Invoke-Git rev-parse --git-dir
    }
    catch {
        Write-Error "Not in a git repository (or git is not installed)."
        return
    }

    try {
        $null = Invoke-Git fetch --prune
    }
    catch {
        Write-Warning "Could not fetch from remote; using what is known locally. $($_.Exception.Message)"
    }

    # Exact data instead of parsing 'git branch -vv' (which includes commit messages).
    # Fields: current-branch marker, worktree path, branch name, upstream status.
    $tab = "`t"
    $refs = Invoke-Git for-each-ref "--format=%(HEAD)$tab%(worktreepath)$tab%(refname:short)$tab%(upstream:track)" refs/heads

    $toDelete = New-Object System.Collections.Generic.List[string]
    foreach ($line in $refs) {
        $fields = $line.Split("`t")
        if ($fields.Count -lt 4 -or $fields[3] -ne '[gone]') { continue }

        $branch = $fields[2]
        if ($fields[0] -eq '*') {
            Write-Warning "Skipping current branch '$branch' (its remote branch is gone). Switch to another branch to delete it."
        }
        elseif ($fields[1]) {
            Write-Warning "Skipping '$branch': it is checked out in worktree '$($fields[1])'."
        }
        else {
            $toDelete.Add($branch)
        }
    }

    if ($toDelete.Count -eq 0) {
        Write-Warning "No orphan branches to delete locally."
        return
    }

    $toDelete = @($toDelete | Where-Object { $PSCmdlet.ShouldProcess($_, 'Delete local branch') })
    if ($toDelete.Count -eq 0) {
        return
    }

    if (-not $Force) {
        Write-Host "Local branches whose remote branch is gone:"
        $toDelete | ForEach-Object { Write-Host "  $_" }

        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete local branches which dont exist in remote."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any local branches"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $title = "Delete Local Orphan Branches"
        $message = "$($toDelete.Count) local orphan branches to delete. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)

        if ($result -ne 0) {
            Write-Warning "Selected No. Aborting..."
            return
        }
    }

    # One git call per 100 branches (keeps the command line well under the Windows limit).
    for ($i = 0; $i -lt $toDelete.Count; $i += 100) {
        $batch = @($toDelete[$i..([Math]::Min($i + 99, $toDelete.Count - 1))])
        try {
            Invoke-Git branch -D @batch | ForEach-Object { Write-Host $_ -ForegroundColor Green }
        }
        catch {
            Write-Error $_.Exception.Message
        }
    }
}

New-Alias -Name rgob -Value Remove-GitOrphanBranches -Force
