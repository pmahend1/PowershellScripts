<#
 .Synopsis
  DeleteBinObjFolders function

 .Description
  Deletes bin , obj folders

 .Parameter Exclude
  List of folders to exclude.

 .Example
   # Default
  DeleteBinObjFolders

 .Example
   # With Exclude
   DeleteBinObjFolders -Exclude node_modules, temp
#>
function DeleteBinObjFolders {
    [CmdletBinding()]
    param (
        [System.Array] $exclude
    )
    if ($exclude.Length -eq 0) {
        $binObjFolders = Get-ChildItem -Include bin, obj -Recurse -Force
    }
    else {
        $exclusions = $exclude | Join-String -Separator ','  
        $binObjFolders = Get-ChildItem -Include bin, obj -Exclude $exclusions -Recurse -Force
    }
    
    if ($binObjFolders -eq 0) {
        Write-Warning 'No bin, obj folders found!'
    }
    else {
        Write-Warning " - y/n"

        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete all bin, obj folders."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any bin, obj folders."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    
        $title = "Delete bin, obj folders" 
        $message = "$($BranchesToDelete.Length) local orphan branches to delete. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)
    
        if ($result -eq 0) {
            foreach ($item in $binObjFolders) {
                try {
                    Remove-Item $item -Recurse -Force
                }
                catch  [System.Exception] {
                    Write-Error $_ 
                }
            }
        }
        else {
            Write-Warning "Selected No. Aborting..."
        }   
    }
}