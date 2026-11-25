<#
 .Synopsis
  function Remove-TempFiles

 .Description
  Deletes temp files. Works on Windows, macOS and Linux.

  Default folders:
    Windows     : user temp ($env:TEMP) and $env:windir\Temp
    macOS/Linux : the user temp folder ($TMPDIR, falls back to /tmp)

  Each top-level entry is deleted in a single native call instead of enumerating and deleting
  every file through Remove-Item:
    Windows     : rd /s /q   (rd is a cmd.exe built-in, so it runs through cmd.exe)
    macOS/Linux : /bin/rm -rf
  Entries that can't be deleted (in use, permission denied) are reported as non-terminating
  errors, so -ErrorAction SilentlyContinue hides them.

  On macOS/Linux, rm deletes files even if a running program has them open. To avoid breaking
  running programs, some well-known entries (sockets, tmux/ssh-agent folders, X11 folders,
  PowerShell/.NET IPC pipes) are always skipped there.

 .Parameter Path
  Temp folders to clean. Defaults depend on the OS (see Description).

 .Parameter Exclude
  List of top-level file/folder names (wildcards allowed) to exclude.

 .Example
  Remove-TempFiles

 .Example
  # Do not show errors for files that are in use
  Remove-TempFiles -ErrorAction SilentlyContinue

 .Example
  # Show what would be deleted
  Remove-TempFiles -WhatIf

 .Example
  Remove-TempFiles -Exclude 'vscode-*', 'MyApp'
#>
function Remove-TempFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string[]] $Path,

        [Parameter(Mandatory = $false)]
        [string[]] $Exclude = @()
    )

    # $IsWindows only exists in PowerShell 6+, so check the platform directly.
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    if (-not $Path) {
        if ($onWindows) {
            $Path = @($env:TEMP, (Join-Path $env:windir 'Temp'))
        }
        else {
            $Path = @([System.IO.Path]::GetTempPath())
        }
    }

    $alwaysExclude = @()
    if (-not $onWindows) {
        $alwaysExclude = @(
            '.X11-unix', '.ICE-unix', '.XIM-unix', '.font-unix', '.Test-unix',
            'systemd-private-*', 'snap-private-tmp',
            'tmux-*', 'ssh-*', 'com.apple.*', 'powerlog',
            'CoreFxPipe_*', 'dotnet-diagnostic-*', 'clr-debug-pipe-*'
        )
    }
    $allExclude = $alwaysExclude + $Exclude

    $deleted = 0
    $failed = 0

    foreach ($root in $Path) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Warning "Temp folder '$root' not found. Skipping."
            continue
        }

        # Only top-level entries; each one is removed recursively in one shot.
        $items = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)
        $index = 0

        foreach ($item in $items) {
            $index++

            $isExcluded = $false
            foreach ($pattern in $allExclude) {
                if ($item.Name -like $pattern) { $isExcluded = $true; break }
            }
            # Skip Unix sockets (UnixMode exists in PowerShell 7.1+), e.g. a running program's IPC endpoint.
            if (-not $onWindows -and $item.PSObject.Properties['UnixMode'] -and "$($item.UnixMode)".StartsWith('s')) {
                $isExcluded = $true
            }
            if ($isExcluded) {
                Write-Verbose "Excluded $($item.FullName)"
                continue
            }

            Write-Progress -Activity "Deleting temp files in $root" -Status $item.FullName -PercentComplete (($index / $items.Count) * 100)

            if (-not $PSCmdlet.ShouldProcess($item.FullName, 'Delete')) {
                continue
            }

            if ($onWindows) {
                $isDirectory = ($item.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0
                if ($isDirectory) {
                    # rd is a cmd.exe built-in (in PowerShell, 'rd' is an alias for Remove-Item), so call it through cmd.exe.
                    # It keeps going past locked files and does not follow junctions.
                    # The path goes in through an environment variable: cmd expands %VAR% only once, so a name
                    # like '%OS%' stays literal. Put on the command line, cmd would expand it to another path.
                    $env:REMOVE_TEMPFILES_TARGET = $item.FullName
                    $null = cmd.exe /d /v:off /c 'rd /s /q "%REMOVE_TEMPFILES_TARGET%" >nul 2>&1'
                }
                else {
                    # -Force deletes read-only and hidden files. -ErrorAction Ignore: a locked file is
                    # reported once, below, instead of also leaking the exception into -ErrorVariable.
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Ignore
                }
            }
            else {
                # Full path so the PowerShell 'rm' alias (Remove-Item) is never picked up.
                # '--' stops names that start with '-' being read as options.
                $null = & /bin/rm -rf -- $item.FullName 2>&1
            }

            if (Test-Path -LiteralPath $item.FullName) {
                $failed++
                Write-Error "Could not fully delete '$($item.FullName)' (in use or permission denied)."
            }
            else {
                $deleted++
                Write-Verbose "Deleted $($item.FullName)"
            }
        }

        Write-Progress -Activity "Deleting temp files in $root" -Completed
    }
    Remove-Item Env:\REMOVE_TEMPFILES_TARGET -ErrorAction Ignore

    if (-not $WhatIfPreference) {
        Write-Host "Deleted $deleted item(s). $failed item(s) could not be fully deleted." -ForegroundColor Green
    }
}
