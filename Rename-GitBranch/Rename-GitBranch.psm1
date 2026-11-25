<#
 .Synopsis
  Rename git branch.

 .Description
  Renames a git branch locally and remotely.

  Steps (stops at the first one that fails):
    1. Rename the local branch.
    2. Push the new branch and set it as upstream.
       If this fails, the local rename is undone, so nothing has changed.
    3. Delete the old branch on the remote (skipped if it was never pushed).

 .Parameter OldName
  Current branch name. Defaults to the checked out branch.

 .Parameter NewName
  New branch name.

 .Parameter Remote
  Remote. Defaults to origin.

 .Parameter DryRun
  Informs what changes will be made. Same as -WhatIf.

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch'
   Rename-GitBranch -OldName foo-branch -NewName bar-branch -Remote origin

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch'
   Rename-GitBranch -OldName foo-branch -NewName bar-branch

 .Example
   # Rename the current branch to 'bar-branch'
   Rename-GitBranch -NewName bar-branch

 .Example
   # Rename git branch 'foo-branch' to 'bar-branch' -DryRun
   Rename-GitBranch -OldName foo-branch -NewName bar-branch -DryRun
#>

# Runs git and throws with git's own message if it fails.
function Invoke-Git {
  # Native stderr would become an error record and stop the script if the caller uses -ErrorAction Stop.
  $ErrorActionPreference = 'Continue'
  $output = & git @args 2>&1
  $exitCode = $LASTEXITCODE
  $lines = @($output | ForEach-Object { "$_" })
  if ($exitCode -ne 0) {
    throw "git $($args -join ' ') failed (exit $exitCode): $($lines -join [Environment]::NewLine)"
  }
  return $lines
}

# Runs git quietly and returns its exit code.
function Get-GitExitCode {
  $ErrorActionPreference = 'Continue'
  $null = & git @args 2>&1
  return $LASTEXITCODE
}

# True if git exits with 0 (used for yes/no checks).
function Test-Git {
  return (Get-GitExitCode @args) -eq 0
}

function Rename-GitBranch {
  [CmdletBinding(SupportsShouldProcess = $true)]
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

  if (-not (Test-Git rev-parse --git-dir)) {
    Write-Error "Not in a git repository (or git is not installed)."
    return
  }

  if ([string]::IsNullOrEmpty($OldName)) {
    $OldName = (Invoke-Git branch --show-current) -join ''
    if ([string]::IsNullOrEmpty($OldName)) {
      Write-Error "Error getting current branch name (detached HEAD?). Pass -OldName."
      return
    }
    Write-Host "Current branch is $OldName"
  }

  # Checks before changing anything.
  if (-not (Test-Git show-ref --verify --quiet "refs/heads/$OldName")) {
    Write-Error "Branch $OldName does not exist locally."
    return
  }
  if (-not (Test-Git check-ref-format --branch $NewName)) {
    Write-Error "$NewName is not a valid branch name."
    return
  }
  if (Test-Git show-ref --verify --quiet "refs/heads/$NewName") {
    Write-Error "Branch $NewName already exists. Please choose a different NewName."
    return
  }
  if (@(Invoke-Git remote) -notcontains $Remote) {
    Write-Error "Remote $Remote does not exist. Pass -Remote."
    return
  }

  # Exit code 2 = branch not found on remote. Any other failure (no network, auth) stops here.
  $lsRemoteExit = Get-GitExitCode ls-remote --exit-code --heads $Remote "refs/heads/$OldName"
  if ($lsRemoteExit -ne 0 -and $lsRemoteExit -ne 2) {
    Write-Error "Could not reach remote $Remote (git ls-remote exit $lsRemoteExit)."
    return
  }
  $oldOnRemote = $lsRemoteExit -eq 0

  $commands = @(
    "git branch -m $OldName $NewName",
    "git push -u $Remote $NewName"
  )
  if ($oldOnRemote) {
    $commands += "git push $Remote --delete $OldName"
  }

  if ($DryRun -or $WhatIfPreference) {
    Write-Host "# Following commands will be run." -ForegroundColor DarkGray
    $commands | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    if (-not $oldOnRemote) {
      Write-Host "# $OldName is not on $Remote, so nothing to delete there." -ForegroundColor DarkGray
    }
    return
  }

  if (-not $PSCmdlet.ShouldProcess("$OldName -> $NewName on $Remote", 'Rename branch')) {
    return
  }

  # 1. Rename locally.
  try {
    $null = Invoke-Git branch -m $OldName $NewName
    Write-Host "Renamed $OldName to $NewName locally." -ForegroundColor Green
  }
  catch {
    Write-Error $_.Exception.Message
    return
  }

  # 2. Push new branch first, so the remote never ends up with neither branch.
  try {
    $null = Invoke-Git push -u $Remote $NewName
    Write-Host "Pushed $NewName to $Remote and set it as upstream." -ForegroundColor Green
  }
  catch {
    $pushError = $_.Exception.Message
    try {
      $null = Invoke-Git branch -m $NewName $OldName
      Write-Error "Push failed, so the local rename was undone. Nothing changed. $pushError"
    }
    catch {
      Write-Error "Push failed and undoing the local rename also failed; local branch is now $NewName. $pushError"
    }
    return
  }

  # 3. Delete old branch on remote.
  if ($oldOnRemote) {
    try {
      $null = Invoke-Git push $Remote --delete $OldName
      Write-Host "Deleted $OldName on $Remote" -ForegroundColor Green
    }
    catch {
      Write-Error "Renamed and pushed $NewName, but could not delete $OldName on $Remote. Delete it manually. $($_.Exception.Message)"
    }
  }
}
