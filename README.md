# PowershellScripts

Collection of useful powershell scripts and modules published to [PowerShell Gallery](https://www.powershellgallery.com/packages?q=owner%3APrateekRM)

## 1. [GitCleanOrphanBranches](https://www.powershellgallery.com/packages/GitCleanOrphanBranches)

Deletes orphan branches deleted from remote but present in local.

### Installation

`Install-Module -Name GitCleanOrphanBranches`

### Aliases

`rgob`

### Usage

- Go to a git directory and run `Remove-GitOrphanBranches`
- Pass `Y` when prompted.

## 2. [DeleteBinObjFolders](https://www.powershellgallery.com/packages/DeleteBinObjFolders)

Deletes bin, obj folders recursively.

### Installation

`Install-Module -Name DeleteBinObjFolders`

### Aliases

`rbof`

### Usage

- Run `Remove-BinObjFolders`
- To exclude few folders pass `Exclude` parameter with comma separated strings.  
  `Remove-BinObjFolders -Exclude folder1,folder2,folderN`
- Pass `Y` when prompted
