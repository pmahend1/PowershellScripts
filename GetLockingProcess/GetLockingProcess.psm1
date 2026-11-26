<#
 .Synopsis
  function Get-LockingProcesses

 .Description
  Gets locking processes blocking given file or folder. Windows only.

  Uses Sysinternals Handle v5, which ships in the module folder: handle64.exe on x64 Windows,
  handle64a.exe on ARM64 Windows, handle.exe on 32-bit Windows.
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

# Picks the handle build for this machine: handle64a.exe (ARM64), handle64.exe (x64) or handle.exe (x86).
function Get-HandleExeName {
    # OSArchitecture needs .NET Framework 4.7.1+ in Windows PowerShell 5.1; fall back to the environment.
    # PROCESSOR_ARCHITEW6432 is set when a 32-bit process runs on 64-bit Windows.
    $arch = try { "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" } catch { '' }
    if (-not $arch) { $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE } }

    if ($arch -eq 'Arm64') { return 'handle64a.exe' }
    if ($arch -eq 'X64' -or $arch -eq 'AMD64' -or [Environment]::Is64BitOperatingSystem) { return 'handle64.exe' }
    return 'handle.exe'
}

# Runs handle.exe from the module folder and returns its output lines.
# Separate function so tests can mock it.
function Invoke-Handle {
    param([string] $Path)

    $handle = Join-Path $PSScriptRoot (Get-HandleExeName)
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
    # The handle column is hex: Handle 4.x prints '810:', Handle 5 prints '81008X' (no colon).
    # Keeping it to hex digits + letters stops a user name with a space (NT AUTHORITY\SYSTEM) being split.
    [regex]$matchPattern = "(?m)^(?<Name>\S.*?)\s+pid:\s+(?<PID>\d+)\s+type:\s+(?<Type>\w+)\s+(?<User>.+?)\s+[0-9A-Fa-f]+[A-Za-z]*:?\s+(?<Path>.*?)\s*$"
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
