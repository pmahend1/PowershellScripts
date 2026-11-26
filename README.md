# PowershellScripts

[![CI](https://github.com/pmahend1/PowershellScripts/actions/workflows/ci.yml/badge.svg)](https://github.com/pmahend1/PowershellScripts/actions/workflows/ci.yml)

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
- Only bin/obj folders next to a project or solution file (`.csproj`, `.fsproj`, `.vbproj`, `.sqlproj`, `.esproj`, `.wapproj`, `.proj`, `.sln`, `.slnx`, `.slnf`) are deleted, so unrelated `bin` folders (scripts, tools) are kept.
- `.git` and `node_modules` are never searched. Works on Windows, macOS and Linux.

## [3. GetLockingProcess](https://github.com/pmahend1/PowershellScripts/tree/main/GetLockingProcess)

### 3.1 Installation

`Install-Module -Name GetLockingProcess`

### 3.2 Aliases

`glp`

### 3.3 Usage

- Run `Get-LockingProcesses -Path {path}`

> [!WARNING]
> Windows only. Uses [Sysinternals Handle](https://learn.microsoft.com/sysinternals/downloads/handle), which is not shipped with the module. It uses `handle64.exe` (x64), `handle64a.exe` (ARM64) or `handle.exe` (32-bit) from PATH; if it's not there, it downloads Handle once from Microsoft into `%LOCALAPPDATA%\GetLockingProcess\Handle` and only uses it if it's signed by Microsoft. By using it you accept the [Sysinternals license terms](https://learn.microsoft.com/sysinternals/license-terms).

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
> Works on Windows, macOS and Linux. On macOS it cleans `$TMPDIR` and `~/Library/Caches`; on Linux `$TMPDIR` (or `/tmp`). On both it always skips `com.apple.*` entries, sockets, tmux/ssh-agent and X11 folders, and PowerShell/.NET IPC pipes.

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
## Running the tests

Tests use [Pester](https://pester.dev) 5 or later and run on Windows (Windows PowerShell 5.1 and PowerShell 7+), macOS and Linux.

```powershell
Install-Module Pester -Scope CurrentUser -SkipPublisherCheck
./Invoke-Tests.ps1
# Skip the slow test that runs the real handle.exe
./Invoke-Tests.ps1 -ExcludeTag Integration
```

- Tests only work in temporary folders (Pester's `$TestDrive`); they never touch your real temp folder or repositories.
- Git tests use a local bare repository as the remote and a throwaway git config, so your own git settings don't affect them.
- CI runs the tests on every push and pull request on Windows (Windows PowerShell 5.1 and PowerShell 7), Ubuntu and macOS, and lints the modules with PSScriptAnalyzer using [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1):

  ```powershell
  Invoke-ScriptAnalyzer -Path ./RemoveTempFiles -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
  ```
