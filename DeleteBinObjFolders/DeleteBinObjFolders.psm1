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
function Remove-BinObjFolders {
    [CmdletBinding()]
    param 
    (
        [System.Array] $Exclude
    )
 
    $exclusionString = ''
    if ($Exclude.Length -ne 0) {
        $exclusionString = $Exclude | Join-String -Separator ',' 
    }

    $folderFindJob = Start-Job -ScriptBlock { Get-ChildItem -Include bin, obj -Exclude $exclusionString -Recurse -Force }

    while ($folderFindJob.State -eq [System.Management.Automation.JobState]::Running) {
        Write-Progress -Activity 'Remove-BinObjFolder' -Status "Searching for folder..."
    }

    $unsortedList = $folderFindJob | Wait-Job | Receive-Job

    if ($unsortedList.Count -eq 0) {
        Write-Warning 'No bin, obj folders found!'
    }
    else {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete all bin, obj folders."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any bin, obj folders."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        
        $title = "Delete bin, obj folders" 
        $message = "$($unsortedList.Length) folders will be deleted. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)
        
        if ($result -eq 0) {

            $sortedJob = Start-Job -ScriptBlock { $unsortedList | Select-Object FullName, @{Name = "FolderDepth"; Expression = { $_.DirectoryName.Split('\').Count } } | Sort-Object -Descending FolderDepth, FullName }

            while ($sortedJob.State -eq [System.Management.Automation.JobState]::Running) {
                Write-Progress -Activity "Remove-BinObjFolder" -status "Sorting folders..." 
            }
            
            $sortedFolders = $sortedJob |  Wait-Job | Receive-Job
            
            foreach ($item in $sortedFolders) {
                try {
                    Write-Host "Deleting " $item
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
New-Alias -Name rbof -Value Remove-BinObjFolders -Force