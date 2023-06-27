<#
 .Synopsis
  function Remove-TempFiles

 .Description
  Deletes Temp Files.

 .Parameter Exclude
  List of folders to exclude.

 .Example
  Remove-TempFiles
#>
function Remove-TempFiles {
    $envTempFiles = Get-ChildItem $env:TEMP -Recurse -Force
    foreach ($tempFile in $envTempFiles) {
        try {
            Write-Progress "Deleting " $item.FullName
            Remove-Item -Path $item.FullName -Recurse -Force
            if ($? -eq $true) {
                Write-Host "Deleted " $item.FullName
            }
        }
        catch  [System.Exception] {
            Write-Error $_
        }
    }

    $windowsTempFiles = Get-ChildItem $env:windir/Temp -Recurse -Force
    foreach ($tempFile in $windowsTempFiles) {
        try {
            Write-Progress "Deleting " $item.FullName
            Remove-Item -Path $item.FullName -Recurse -Force
            if ($? -eq $true) {
                Write-Host "Deleted " $item.FullName
            }
        }
        catch  [System.Exception] {
            Write-Error $_
        }
    }
}