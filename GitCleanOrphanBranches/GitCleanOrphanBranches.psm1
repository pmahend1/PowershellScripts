
<#PSScriptInfo

.VERSION 1.0.1

.GUID a9667520-61fa-4e5f-bf05-3666ea11665a

.AUTHOR Prateek Mahendrakar

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI https://github.com/pmahend1/PowershellScripts

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 Script to clean orphan branches which are deleted in remote but present in local 

#> 
Param()


Function GitCleanOrphanBranches {
    # get branches to delete
    git fetch --prune
    $BranchesToDelete = git branch -vv | Select-String -Pattern ': gone]' | Select-String -Pattern '\*' -NotMatch 
    # delete branch one by one
    if ($BranchesToDelete.Length -eq 0) {
        Write-Warning "No orphan branches to delete locally."
    }
    else {
        Write-Warning " - y/n"

        ## The following four lines only need to be declared once in your script.
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete local branches which dont exist in remote."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any local branches"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        ## Use the following each time your want to prompt the use
        $title = "Delete Local Orphan Branches" 
        $message = "$($BranchesToDelete.Length) local orphan branches to delete. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)

        if($result -eq 0)
        {
            foreach ($item in $BranchesToDelete) {
                try {
                    # Get branch name
                    $itemString = $item.ToString().Trim()
                    $branch = $itemString.Split(" ")[0]
        
                    # Delete
                    Write-Host "Deleting " $branch -ForegroundColor Green
                    git branch -D $branch
                }
                catch  [System.Exception] {
                    Write-Error $_ 
                }
            }
        }else
        {
            Write-Error "Selected No. Aborting..."
        }        
    }
}
New-Alias -Name gcob -Value GitCleanOrphanBranches -Force