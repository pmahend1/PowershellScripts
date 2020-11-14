<#
 .Synopsis
  function Remove-BinObjFolders 

 .Description
  Deletes bin, obj folders recursively

 .Parameter Exclude
  List of folders to exclude.

 .Example
  Remove-BinObjFolders

 .Example
  Remove-BinObjFolders -Exclude node_modules, temp
  
  If you want to exclude folders node_modules and temp from being deleted:

#>
function Remove-BinObjFolders 
{
    [CmdletBinding()]
    param 
    (
        [System.Array] $Exclude
    )
    if ($Exclude.Length -eq 0) 
    {
        $binObjFolders = Get-ChildItem -Include bin, obj -Recurse -Force
    }
    else 
    {
        $exclusions = $Exclude | Join-String -Separator ',' 
        $binObjFolders = Get-ChildItem -Include bin, obj -Exclude $exclusions -Recurse -Force
    }
    
    if ($binObjFolders.Count -eq 0) 
    {
        Write-Warning 'No bin, obj folders found!'
    }
    else 
    {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete all bin, obj folders."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any bin, obj folders."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    
        $title = "Delete bin, obj folders" 
        $message = "$($binObjFolders.Length) folders will be deleted. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)
    
        if ($result -eq 0) 
        {
            foreach ($item in $binObjFolders)
            {
                try 
                {
                    Write-Host "Deleting " $item
                    Remove-Item $item -Recurse -Force
                }
                catch  [System.Exception] 
                {
                    Write-Error $_
                }
            }
        }
        else 
        {
            Write-Warning "Selected No. Aborting..."
        }   
    }
}
New-Alias -Name rbof -Value Remove-BinObjFolders -Force