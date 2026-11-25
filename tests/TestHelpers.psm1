# Shared helpers for the Pester tests. Works on Windows PowerShell 5.1 and PowerShell 7+.

function Test-OnWindows {
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

# Root can delete files in read-only folders, so permission tests are skipped for root.
function Test-IsRoot {
    if (Test-OnWindows) { return $false }
    return ((& id -u) -eq '0')
}

# Creates a file with optional content, creating parent folders as needed.
function New-TestFile {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Content = 'x'
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    [System.IO.File]::WriteAllText($Path, $Content)
    return $Path
}

# Junction on Windows (no admin rights needed), symbolic link elsewhere.
function New-DirectoryLink {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Target
    )
    $type = if (Test-OnWindows) { 'Junction' } else { 'SymbolicLink' }
    $null = New-Item -ItemType $type -Path $Path -Value $Target
}

# Opens a file so that nobody else can open or delete it (on Windows). Dispose the result to unlock.
function Lock-TestFile {
    param([Parameter(Mandatory)] [string] $Path)
    return [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
}

# Points git at a throwaway global config so the user's/runner's config, hooks and
# signing settings can't change test results. Returns the old values for Restore-GitTestEnvironment.
function Initialize-GitTestEnvironment {
    param([Parameter(Mandatory)] [string] $Root)

    $names = 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_TERMINAL_PROMPT', 'GIT_DIR', 'GIT_WORK_TREE'
    $saved = @{}
    foreach ($name in $names) {
        $saved[$name] = [System.Environment]::GetEnvironmentVariable($name)
    }

    $null = New-Item -ItemType Directory -Path $Root -Force
    $config = Join-Path $Root 'gitconfig'
    $lines = @(
        '[user]', "`tname = Pester", "`temail = pester@example.invalid",
        '[init]', "`tdefaultBranch = main",
        '[commit]', "`tgpgsign = false",
        '[core]', "`tautocrlf = false",
        '[advice]', "`tdetachedHead = false"
    )
    [System.IO.File]::WriteAllText($config, ($lines -join "`n") + "`n")

    $env:GIT_CONFIG_GLOBAL = $config
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_TERMINAL_PROMPT = '0'
    Remove-Item Env:\GIT_DIR, Env:\GIT_WORK_TREE -ErrorAction SilentlyContinue
    return $saved
}

function Restore-GitTestEnvironment {
    param([Parameter(Mandatory)] [hashtable] $Saved)
    foreach ($name in $Saved.Keys) {
        [System.Environment]::SetEnvironmentVariable($name, $Saved[$name])
    }
}

# Runs git in a folder and throws if it fails. Returns output lines.
# Usage: Invoke-TestGit <folder> <git args...>
# Plain $args (no param block) so git options like -m or -u are passed through, not bound by PowerShell.
function Invoke-TestGit {
    $Path = $args[0]
    $Arguments = @($args | Select-Object -Skip 1)
    $ErrorActionPreference = 'Continue'
    $output = & git -C $Path @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { "$_" })
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Path (exit $exitCode): $($lines -join "`n")"
    }
    return $lines
}

# Creates a bare repo (the "remote") and a clone of it with one commit on main pushed.
# Returns @{ Remote = <bare repo path>; Local = <clone path> }.
function New-GitFixture {
    param([Parameter(Mandatory)] [string] $Root)

    $remote = Join-Path $Root 'remote.git'
    $local = Join-Path $Root 'local'
    $null = New-Item -ItemType Directory -Path $Root -Force

    $null = Invoke-TestGit $Root init --bare --initial-branch=main $remote
    $null = Invoke-TestGit $Root clone $remote $local
    $null = New-TestFile -Path (Join-Path $local 'README.md') -Content 'fixture'
    $null = Invoke-TestGit $local add README.md
    $null = Invoke-TestGit $local commit -m 'initial commit'
    $null = Invoke-TestGit $local push -u origin main

    return @{ Remote = $remote; Local = $local }
}

# Creates a branch with one commit, optionally pushed with upstream set. Leaves main checked out.
function New-GitBranch {
    param(
        [Parameter(Mandatory)] [string] $Repo,
        [Parameter(Mandatory)] [string] $Name,
        [string] $Message = "commit on $Name",
        [switch] $Push
    )
    $null = Invoke-TestGit $Repo switch -c $Name main
    $file = 'file-' + ($Name -replace '[^A-Za-z0-9]', '_') + '.txt'
    $null = New-TestFile -Path (Join-Path $Repo $file) -Content $Name
    $null = Invoke-TestGit $Repo add $file
    $null = Invoke-TestGit $Repo commit -m $Message
    if ($Push) {
        $null = Invoke-TestGit $Repo push -u origin $Name
    }
    $null = Invoke-TestGit $Repo switch main
}

# Local branch names.
function Get-TestGitBranches {
    param([Parameter(Mandatory)] [string] $Repo)
    return @(Invoke-TestGit $Repo for-each-ref '--format=%(refname:short)' refs/heads)
}

# Writes a git hook (sh script, LF line endings, executable). Git for Windows runs hooks through its sh.
function New-GitHook {
    param(
        [Parameter(Mandatory)] [string] $GitDir,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Body
    )
    $hooks = Join-Path $GitDir 'hooks'
    $null = New-Item -ItemType Directory -Path $hooks -Force
    $path = Join-Path $hooks $Name
    $script = "#!/bin/sh`n" + ($Body -replace "`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($path, $script)
    if (-not (Test-OnWindows)) {
        & chmod +x $path
    }
    return $path
}

Export-ModuleMember -Function *
