<#
 .Synopsis
  function Get-LockingProcesses

 .Description
  Gets locking processes blocking given file or folder.
 
 .Parameter Path
  The path or filename.You can enter a partial name without wildcards.
  Alias name

 .Example
  Get-LockingProcesses explorer

 .Example
  Get-LockingProcesses -Path C:\Folder1\Folder2

 .Example
  Get-LockingProcesses -name C:\Folder1\Folder2
#>
function Get-LockingProcesses {

    [cmdletbinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $True,
            HelpMessage = "What is the path or filename? You can enter a partial name without wildcards")]
        [Alias("name")]
        [ValidateNotNullorEmpty()]
        [string]$Path
    )

    [regex]$matchPattern = "(?m)^(?<Name>\w+\.\w+)\s+pid:\s+(?<PID>\d+)\s+type:\s+(?<Type>\w+)\s+(?<User>.+)\s+\w+:\s+(?<Path>.*)$"
    $handle = '.\handle64.exe'
    $data = &$handle -u $Path -nobanner
    #$data = Start-Process $handle -ArgumentList u,$Path,nobanner
    $data = $data -join "`n"
    $MyMatches = $matchPattern.Matches( $data )

    if ($MyMatches.count) {
        $MyMatches | ForEach-Object {
            [pscustomobject]@{
                FullName = $_.groups["Name"].value
                Name     = $_.groups["Name"].value.split(".")[0]
                ID       = $_.groups["PID"].value
                Type     = $_.groups["Type"].value
                User     = $_.groups["User"].value.trim()
                Path     = $_.groups["Path"].value
                toString = "pid: $($_.groups["PID"].value), user: $($_.groups["User"].value), image: $($_.groups["Name"].value)"
            } 
        }
    }
    else {
        Write-Warning "No matching handles found"
    }
} 

New-Alias -Name glp -Value Get-LockingProcesses -Force
