<#
 .Synopsis
  function Remove-BinObjFolders

 .Description
  Deletes bin, obj folders recursively under the current folder (or -Path). Works on Windows, macOS and Linux.

  Only bin/obj folders next to a .NET project or solution file are deleted, so unrelated folders
  named bin (scripts, tools) are left alone. Recognized files:
    .csproj .fsproj .vbproj .sqlproj .esproj .wapproj .proj .sln .slnx .slnf
  A bin/obj folder without one is searched like any other folder.

  The search does not go into bin/obj folders it found, excluded folders, .git, node_modules,
  or symlinks/junctions. Each folder found is then deleted in a single native call instead of
  through Remove-Item:
    Windows     : rd /s /q   (rd is a cmd.exe built-in, so it runs through cmd.exe)
    macOS/Linux : /bin/rm -rf
  Folders that can't be deleted (in use, permission denied) are reported as non-terminating
  errors, so -ErrorAction SilentlyContinue hides them.

 .Parameter Path
  Folder to search. Defaults to the current folder.

 .Parameter Exclude
  List of folder names (wildcards allowed) to exclude. Excluded folders are not searched.

 .Parameter Force
  Delete without asking for confirmation. Aliases: -Y, -Yes.

 .Example
  Remove-BinObjFolders

 .Example
  Remove-BinObjFolders -Exclude node_modules, temp

  If you want to exclude folders node_modules and temp from being deleted:

 .Example
  # Show what would be deleted
  Remove-BinObjFolders -WhatIf

 .Example
  # No prompt, no errors for folders that are in use
  Remove-BinObjFolders -Force -ErrorAction SilentlyContinue

 .Example
  # Same as -Force
  rbof -Y
#>

# File extensions that mark a folder as a .NET project or solution folder.
$script:ProjectExtensions = @('.csproj', '.fsproj', '.vbproj', '.sqlproj', '.esproj', '.wapproj', '.proj', '.sln', '.slnx', '.slnf')

# True if the folder directly contains a project or solution file.
function Test-ProjectFolder([System.IO.DirectoryInfo] $Directory) {
    try {
        foreach ($file in $Directory.EnumerateFiles()) {
            # -contains is case-insensitive, so App.CSPROJ counts too.
            if ($script:ProjectExtensions -contains $file.Extension) { return $true }
        }
    }
    catch {
        Write-Verbose "Could not list files in $($Directory.FullName): $($_.Exception.Message)"
    }
    return $false
}

function Remove-BinObjFolders {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $false)]
        [string] $Path = '.',

        [Parameter(Mandatory = $false)]
        [string[]] $Exclude = @(),

        [Parameter(Mandatory = $false)]
        [Alias('Y', 'Yes')]
        [switch] $Force
    )

    # $IsWindows only exists in PowerShell 6+, so check the platform directly.
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    # Folder names are case-insensitive on Windows; on macOS/Linux only match 'bin'/'obj' exactly.
    $targetNames = @('bin', 'obj')
    $alwaysExclude = @('.git', 'node_modules')
    $allExclude = $alwaysExclude + $Exclude

    $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath

    # Search: walk the tree, stop at bin/obj (whole folder gets deleted anyway) and excluded folders.
    $found = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $pending.Push((New-Object System.IO.DirectoryInfo $root))
    $searched = 0

    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        $searched++
        if ($searched % 500 -eq 0) {
            Write-Progress -Activity 'Remove-BinObjFolders' -Status "Searching for folders... ($searched searched, $($found.Count) found)"
        }

        try {
            $children = $dir.GetDirectories()
        }
        catch {
            Write-Verbose "Skipped $($dir.FullName): $($_.Exception.Message)"
            continue
        }

        # Checked only when $dir has a bin/obj child, and then only once.
        $isProjectFolder = $null

        foreach ($child in $children) {
            # Don't follow symlinks/junctions out of the tree.
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

            $isExcluded = $false
            foreach ($pattern in $allExclude) {
                if ($child.Name -like $pattern) { $isExcluded = $true; break }
            }
            if ($isExcluded) {
                Write-Verbose "Excluded $($child.FullName)"
                continue
            }

            $isTarget = if ($onWindows) { $targetNames -contains $child.Name } else { $targetNames -ccontains $child.Name }
            if ($isTarget) {
                if ($null -eq $isProjectFolder) { $isProjectFolder = Test-ProjectFolder $dir }
                if ($isProjectFolder) {
                    $found.Add($child.FullName)
                    continue
                }
                Write-Verbose "Kept $($child.FullName): no project or solution file next to it."
            }
            $pending.Push($child)
        }
    }
    Write-Progress -Activity 'Remove-BinObjFolders' -Completed

    if ($found.Count -eq 0) {
        Write-Warning 'No bin, obj folders found next to a project or solution file!'
        return
    }

    if (-not $Force -and -not $WhatIfPreference) {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will delete all bin, obj folders."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does NOT delete any bin, obj folders."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $title = "Delete bin, obj folders"
        $message = "$($found.Count) folders will be deleted. Do you want to continue?"
        $result = $host.ui.PromptForChoice($title, $message, $options, 1)

        if ($result -ne 0) {
            Write-Warning "Selected No. Aborting..."
            return
        }
    }

    $deleted = 0
    $failed = 0
    $index = 0

    foreach ($folder in $found) {
        $index++
        Write-Progress -Activity 'Remove-BinObjFolders' -Status "Deleting $folder" -PercentComplete (($index / $found.Count) * 100)

        if (-not $PSCmdlet.ShouldProcess($folder, 'Delete')) {
            continue
        }

        if ($onWindows) {
            # rd is a cmd.exe built-in (in PowerShell, 'rd' is an alias for Remove-Item), so call it through cmd.exe.
            # It keeps going past locked files and does not follow junctions.
            # The path goes in through an environment variable: cmd expands %VAR% only once, so a folder
            # like '%OS%' stays literal. Put on the command line, cmd would expand it to another path.
            $env:REMOVE_BINOBJ_TARGET = $folder
            $null = cmd.exe /d /v:off /c 'rd /s /q "%REMOVE_BINOBJ_TARGET%" >nul 2>&1'
        }
        else {
            # Full path so the PowerShell 'rm' alias (Remove-Item) is never picked up.
            $null = & /bin/rm -rf -- $folder 2>&1
        }

        if (Test-Path -LiteralPath $folder) {
            $failed++
            Write-Error "Could not fully delete '$folder' (in use or permission denied)."
        }
        else {
            $deleted++
            Write-Host "Deleted $folder"
        }
    }
    Write-Progress -Activity 'Remove-BinObjFolders' -Completed
    Remove-Item Env:\REMOVE_BINOBJ_TARGET -ErrorAction Ignore

    if (-not $WhatIfPreference) {
        Write-Host "Deleted $deleted folder(s). $failed folder(s) could not be fully deleted." -ForegroundColor Green
    }
}

New-Alias -Name rbof -Value Remove-BinObjFolders -Force
