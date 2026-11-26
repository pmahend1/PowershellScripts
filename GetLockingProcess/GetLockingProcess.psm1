<#
 .Synopsis
  function Get-LockingProcesses

 .Description
  Gets locking processes blocking given file or folder. Windows only.

  Uses Sysinternals Handle: handle64.exe on x64 Windows, handle64a.exe on ARM64 Windows,
  handle.exe on 32-bit Windows. Handle is not shipped with this module (its license does not
  allow that). It is found in this order:
    1. On PATH (e.g. installed with the Sysinternals Suite).
    2. In $env:LOCALAPPDATA\GetLockingProcess\Handle, from an earlier download.
    3. Downloaded once from https://download.sysinternals.com/files/Handle.zip into that folder.
       The download is only used if it is signed by Microsoft.

  By using Handle you accept the Sysinternals license terms:
  https://learn.microsoft.com/sysinternals/license-terms
  Handle runs with -accepteula, so it doesn't stop to show the license dialog.
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

$script:HandleUrl = 'https://download.sysinternals.com/files/Handle.zip'
$script:LicenseUrl = 'https://learn.microsoft.com/sysinternals/license-terms'
# Script variable so tests can point it at a temporary folder.
$script:HandleCacheDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'GetLockingProcess\Handle' } else { '' }

# True if the file has a valid Authenticode signature from Microsoft.
function Test-MicrosoftSignature([string] $FilePath) {
    $signature = Get-AuthenticodeSignature -LiteralPath $FilePath
    return $signature.Status -eq 'Valid' -and "$($signature.SignerCertificate.Subject)" -like 'CN=Microsoft Corporation,*'
}

# Downloads Handle.zip into $script:HandleCacheDir. Throws if the download fails or isn't signed by Microsoft.
function Install-Handle {
    Write-Warning "Sysinternals Handle not found. Downloading it once from $script:HandleUrl to $script:HandleCacheDir. By using it you accept the Sysinternals license terms: $script:LicenseUrl"

    $work = Join-Path ([System.IO.Path]::GetTempPath()) "GetLockingProcess-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        $zip = Join-Path $work 'Handle.zip'
        $extracted = Join-Path $work 'Handle'
        # Windows PowerShell 5.1 may not offer TLS 1.2 by default, and its progress bar slows downloads a lot.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $script:HandleUrl -OutFile $zip -UseBasicParsing -ErrorAction Stop
        # .NET directly rather than Expand-Archive: the Archive module may be missing or (in 5.1 started
        # from pwsh) be pwsh's copy, which doesn't work in 5.1.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extracted)

        $exes = @(Get-ChildItem -LiteralPath $extracted -Filter 'handle*.exe')
        if ($exes.Count -eq 0) { throw "$script:HandleUrl did not contain handle.exe." }
        foreach ($exe in $exes) {
            if (-not (Test-MicrosoftSignature $exe.FullName)) {
                throw "$($exe.Name) from $script:HandleUrl is not signed by Microsoft, so it was not used."
            }
        }

        # Copy only after every file passed the signature check.
        $null = New-Item -ItemType Directory -Path $script:HandleCacheDir -Force
        Get-ChildItem -LiteralPath $extracted -File | Copy-Item -Destination $script:HandleCacheDir -Force -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Full path of the handle exe to run: from PATH, else the download folder, else downloads it first.
function Get-HandlePath {
    $exeName = Get-HandleExeName

    # handle.exe last: the 32-bit build also works on 64-bit Windows.
    foreach ($name in @($exeName, 'handle.exe') | Select-Object -Unique) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }

    if (-not $script:HandleCacheDir) { throw 'LOCALAPPDATA is not set, so Handle cannot be downloaded. Put handle.exe on PATH.' }
    $cached = Join-Path $script:HandleCacheDir $exeName
    if (-not (Test-Path -LiteralPath $cached)) {
        Install-Handle
    }
    if (-not (Test-Path -LiteralPath $cached)) { throw "$exeName was not found in the download from $script:HandleUrl." }
    return $cached
}

# Runs handle and returns its output lines. Separate function so tests can mock it.
function Invoke-Handle {
    param([string] $Path)

    $handle = Get-HandlePath
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
    try {
        $data = @(Invoke-Handle -Path $Path) -join "`n"
    }
    catch {
        Write-Error "Could not run Sysinternals Handle: $($_.Exception.Message)"
        return
    }
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
