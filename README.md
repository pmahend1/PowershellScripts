# PowershellScripts

Collection of useful powershell scripts and modules published to [PowerShell Gallery](https://www.powershellgallery.com/packages?q=owner%3APrateekRM)

## [1. GitCleanOrphanBranches](https://www.powershellgallery.com/packages/GitCleanOrphanBranches)

Deletes orphan branches deleted from remote but present in local.

### 1.1 Installation

`Install-Module -Name GitCleanOrphanBranches`

### 1.2 Aliases

`rgob`

### 1.3 Usage

- Go to a git directory and run `Remove-GitOrphanBranches`
- Pass `Y` when prompted, or skip the prompt with `-Y` (same as `-Force`): `rgob -Y`
- Preview what would be deleted: `Remove-GitOrphanBranches -WhatIf`
- The current branch and branches checked out in other worktrees are never deleted.

## [2. DeleteBinObjFolders](https://www.powershellgallery.com/packages/DeleteBinObjFolders)

Deletes bin, obj folders recursively.

### 2.1 Installation

`Install-Module -Name DeleteBinObjFolders`

### 2.2 Aliases

`rbof`

### 2.3 Usage

- Run `Remove-BinObjFolders`
- To exclude few folders pass `Exclude` parameter with comma separated strings.  
  `Remove-BinObjFolders -Exclude folder1,folder2,folderN`
- Pass `Y` when prompted, or skip the prompt with `-Y` (same as `-Force`): `rbof -Y`
- Preview what would be deleted: `Remove-BinObjFolders -WhatIf`
- Hide errors for folders in use: `Remove-BinObjFolders -ErrorAction SilentlyContinue`
- `.git` and `node_modules` are never searched. Works on Windows, macOS and Linux.

## [3. GetLockingProcess](https://github.com/pmahend1/PowershellScripts/tree/main/GetLockingProcess)

### 3.1 Installation

`Install-Module -Name GetLockingProcess`

### 3.2 Aliases

`glp`

### 3.3 Usage

- Run `Get-LockingProcesses -Path {path}`

> [!WARNING]
> Windows only

## [4. RemoveTempFiles](https://github.com/pmahend1/PowershellScripts/tree/main/RemoveTempFiles)

### 4.1 Installation

`Install-Module -Name RemoveTempFiles`

### 4.2 Aliases

None.

### 4.3 Usage

- Run `Remove-TempFiles`.  
- Hide errors for files in use: `Remove-TempFiles -ErrorAction SilentlyContinue`  
- Preview what would be deleted: `Remove-TempFiles -WhatIf`  
- Skip some entries: `Remove-TempFiles -Exclude 'vscode-*', 'MyApp'`  
  
> [!NOTE]
> Works on Windows, macOS and Linux. On macOS/Linux it cleans `$TMPDIR` (or `/tmp`) and always skips sockets, tmux/ssh-agent and X11 folders, and PowerShell/.NET IPC pipes.

## [5. Rename-GitBranch](https://github.com/pmahend1/PowershellScripts/tree/main/Rename-GitBranch)

### 5.1 Installation

`Install-Module -Name Rename-GitBranch`

### 5.2 Aliases

None.

### 5.3 Usage

- Run `Rename-GitBranch -OldName {old-branch-name} -NewName {new-branch-name} -Remote {default:origin}`.  
- Run `Rename-GitBranch -OldName {old-branch-name} -NewName {new-branch-name} -Remote {default:origin} -DryRun` with dryrun flag to know what commands will run.  
- Leave out `-OldName` to rename the current branch.  
- The new branch is pushed before the old one is deleted on the remote. If the push fails, the local rename is undone.