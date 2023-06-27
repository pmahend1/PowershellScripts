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

    # Environment temp files deletion
    $envTempFilesUnsorted = Get-ChildItem $env:TEMP -Recurse -Force
    $envTempFiles = $envTempFilesUnsorted | Select-Object FullName, @{Name = "FolderDepth"; Expression = { $_.FullName.Split('\').Count } } | Sort-Object -Property @{ Expression = 'FolderDepth'; Descending = $true }, @{ Expression = { $($_.FullName).Length } ; Descending = $true }
    foreach ($tempFile in $envTempFiles) {
        try {
            Write-Progress "Deleting " $tempFile.FullName
            Remove-Item -Path $tempFile.FullName -Recurse -Force
            if ($? -eq $true) {
                Write-Host "Deleted " $tempFile.FullName -ForegroundColor Green
            }
        }
        catch  [System.Exception] {
            Write-Error $_
        }
    }

    # Windows temp files deletion
    $windowsTempFilesUnsorted = Get-ChildItem $env:windir/Temp -Recurse -Force
    $windowsTempFiles = $windowsTempFilesUnsorted | Select-Object FullName, @{Name = "FolderDepth"; Expression = { $_.FullName.Split('\').Count } } | Sort-Object -Property @{ Expression = 'FolderDepth'; Descending = $true }, @{ Expression = { $($_.FullName).Length } ; Descending = $true }
    foreach ($tempFile in $windowsTempFiles) {
        try {
            Write-Progress "Deleting " $tempFile.FullName
            Remove-Item -Path $tempFile.FullName -Recurse -Force
            if ($? -eq $true) {
                Write-Host "Deleted " $tempFile.FullName -ForegroundColor Green
            }
        }
        catch  [System.Exception] {
            Write-Error $_
        }
    }
}