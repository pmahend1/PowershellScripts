<#
 .Synopsis
  Rename git branch.

 .Description
  Renames a git branch locally and remotely.

 .Parameter OldName
  Current branch name.

 .Parameter NewName
  New branch name.

 .Parameter Remote
  Remote

 .Parameter DryRun
  Informs what changes will be made

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch'
   Rename-GitBranch -OldName foo-branch -NewName bar-branch -Remote origin

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch'
   Rename-GitBranch -OldName foo-branch -NewName bar-branch

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch' -DryRun
   Rename-GitBranch -OldName foo-branch -NewName bar-branch -DryRun
#>

function Rename-GitBranch {
  param(
    [Parameter(Mandatory = $false)]
    [string] $OldName = "",

    [Parameter(Mandatory = $true)]
    [string] $NewName,

    [Parameter(Mandatory = $false)]
    [string] $Remote = 'origin',

    [Parameter(Mandatory = $false)]
    [switch] $DryRun
  )

  try {
    if ([string]::IsNullOrEmpty($OldName)) {
      $OldName = git branch --show-current
      Write-Host "Current branch is $OldName"
    }

    if ([string]::IsNullOrEmpty($OldName)) {
      Write-Error "Error getting current branch name. Make sure git is installed and you are in a repo path."
      return;
    }

    $branches = git branch
    $branches = $branches | ForEach-Object $_ { $_.Trim() }

    if ($branches.Contains($NewName)) {
      Write-Error "Branch $NewName already exists. Please choose a different NewName".
      return;
    }

    if ($DryRun -eq $false) {
      git branch -m $OldName $NewName
      Write-Host "Renamed $OldName to $NewName locally." -ForegroundColor Green

      git push $Remote --delete $OldName
      Write-Host "Deleted $OldName on $Remote" -ForegroundColor Green

      git branch --unset-upstream $NewName
      Write-Host "Upstream of $NewName was unset to prevent pushing to $Remote/$OldName" -ForegroundColor Green

      git push $Remote $NewName
      Write-Host "Pushed $NewName to $Remote" -ForegroundColor Green

      git push $Remote -u $NewName
      Write-Host "$NewName upstream branch was reset." -ForegroundColor Green
    }
    else {
      $text = "# Following commands will be run.
# Rename the local branch to the new name
git branch -m $OldName $NewName

# Delete the old branch on remote - where $Remote is, for example, origin
git push $Remote --delete $OldName

# Prevent git from using the old name when pushing in the next step.
# Otherwise, git will use the old upstream name instead of $NewName.
git branch --unset-upstream $NewName

# Push the new branch to remote
git push $Remote $NewName

# Reset the upstream branch for the new_name local branch
git push $Remote -u $NewName"

      Write-Host $text -ForegroundColor DarkGray
    }
  }
  catch {
    Write-Error $_
  }
}