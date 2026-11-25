<#
 .Synopsis
  function Get-LockingProcesses

 .Description
  Gets locking processes blocking given file or folder. Windows only.

  Uses Sysinternals handle.exe (handle64.exe on 64-bit Windows), which ships in the module folder.
  The Sysinternals EULA is accepted automatically (-accepteula), so the first run doesn't wait for it.
  Without administrator rights only handles of processes you can access are found.

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

# Runs handle.exe from the module folder and returns its output lines.
# Separate function so tests can mock it.
function Invoke-Handle {
    param([string] $Path)

    $exe = if ([Environment]::Is64BitOperatingSystem) { 'handle64.exe' } else { 'handle.exe' }
    $handle = Join-Path $PSScriptRoot $exe
    & $handle -accepteula -nobanner -u $Path 2>&1 | ForEach-Object { "$_" }
}

function Get-LockingProcesses {

    [cmdletbinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $True,
            HelpMessage = "What is the path or filename? You can enter a partial name without wildcards")]
        [Alias("name")]
        [ValidateNotNullorEmpty()]
        [string]$Path
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        Write-Error "Get-LockingProcesses only works on Windows."
        return
    }

    # Name is matched lazily up to ' pid:' so image names with dots, dashes or spaces work too.
    [regex]$matchPattern = "(?m)^(?<Name>\S.*?)\s+pid:\s+(?<PID>\d+)\s+type:\s+(?<Type>\w+)\s+(?<User>.+?)\s+\w+:\s+(?<Path>.*?)\s*$"
    $data = @(Invoke-Handle -Path $Path) -join "`n"
    $MyMatches = $matchPattern.Matches( $data )

    if ($MyMatches.count) {
        $MyMatches | ForEach-Object {
            $fullName = $_.groups["Name"].value
            [pscustomobject]@{
                FullName = $fullName
                Name     = [System.IO.Path]::GetFileNameWithoutExtension($fullName)
                ID       = $_.groups["PID"].value
                Type     = $_.groups["Type"].value
                User     = $_.groups["User"].value.trim()
                Path     = $_.groups["Path"].value
                toString = "pid: $($_.groups["PID"].value), user: $($_.groups["User"].value.trim()), image: $fullName"
            }
        }
    }
    else {
        Write-Warning "No matching handles found"
    }
}

New-Alias -Name glp -Value Get-LockingProcesses -Force
