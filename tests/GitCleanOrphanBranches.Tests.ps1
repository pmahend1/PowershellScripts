# Pester shares variables between BeforeDiscovery/BeforeAll/BeforeEach and the It blocks, which the
# analyzer can't see. Test helpers that create files don't need -WhatIf.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester scoping')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helpers')]
param()

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../GitCleanOrphanBranches/GitCleanOrphanBranches.psd1') -Force
    $savedGitEnv = Initialize-GitTestEnvironment -Root (Join-Path $TestDrive 'gitenv')
}

AfterAll {
    Restore-GitTestEnvironment $savedGitEnv
    Remove-Module GitCleanOrphanBranches, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Remove-GitOrphanBranches' {

    BeforeEach {
        $fixture = New-GitFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $repo = $fixture.Local
        $remote = $fixture.Remote
        Push-Location -LiteralPath $repo
    }

    AfterEach {
        Pop-Location
    }

    It 'deletes local branches whose remote branch is gone and keeps the rest' {
        New-GitBranch $repo 'gone-1' -Push
        New-GitBranch $repo 'feature/gone-2' -Push
        New-GitBranch $repo 'still-on-remote' -Push
        New-GitBranch $repo 'local-only'
        Invoke-TestGit $remote branch -D 'gone-1' 'feature/gone-2'

        Remove-GitOrphanBranches -Force -ErrorVariable errors 6>$null

        Get-TestGitBranches $repo | Sort-Object | Should -Be @('local-only', 'main', 'still-on-remote')
        $errors | Should -HaveCount 0 -Because "git's normal stderr output (fetch progress) is not an error"
    }

    It 'runs git fetch --prune first (no manual fetch needed)' {
        New-GitBranch $repo 'gone' -Push
        Invoke-TestGit $remote branch -D 'gone'
        # The clone still has origin/gone until it fetches.
        Invoke-TestGit $repo for-each-ref --format='%(refname)' refs/remotes/origin/gone | Should -Not -BeNullOrEmpty

        Remove-GitOrphanBranches -Force 6>$null

        Get-TestGitBranches $repo | Should -Be @('main')
    }

    It 'is not fooled by commit messages that look like git branch -vv output' {
        # Old versions parsed 'git branch -vv', where the commit message is part of the line.
        New-GitBranch $repo 'tricky-1' -Message '* main 1234567 [origin/main: gone] fake' -Push
        New-GitBranch $repo 'tricky-2' -Message 'fix: gone] and [origin/x: gone]' -Push
        New-GitBranch $repo 'really-gone' -Message 'normal message' -Push
        Invoke-TestGit $remote branch -D 'really-gone'

        Remove-GitOrphanBranches -Force 6>$null

        Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'tricky-1', 'tricky-2')
    }

    It 'skips the current branch and warns' {
        New-GitBranch $repo 'current' -Push
        New-GitBranch $repo 'other' -Push
        Invoke-TestGit $repo switch 'current'
        Invoke-TestGit $remote branch -D 'current' 'other'

        Remove-GitOrphanBranches -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        Get-TestGitBranches $repo | Sort-Object | Should -Be @('current', 'main')
        "$warnings" | Should -Match "Skipping current branch 'current'"
    }

    It 'skips branches checked out in another worktree and warns' {
        New-GitBranch $repo 'in-worktree' -Push
        New-GitBranch $repo 'other' -Push
        $worktree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Invoke-TestGit $repo worktree add $worktree 'in-worktree'
        Invoke-TestGit $remote branch -D 'in-worktree' 'other'

        Remove-GitOrphanBranches -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        Get-TestGitBranches $repo | Sort-Object | Should -Be @('in-worktree', 'main')
        "$warnings" | Should -Match "Skipping 'in-worktree': it is checked out in worktree"
    }

    It 'deletes branches with unmerged commits (uses branch -D)' {
        New-GitBranch $repo 'unmerged' -Push
        Invoke-TestGit $remote branch -D 'unmerged'

        Remove-GitOrphanBranches -Force 6>$null

        Get-TestGitBranches $repo | Should -Be @('main')
    }

    It 'deletes more than 100 branches (several git calls)' {
        # Branches that track a remote branch that never existed show as [gone], so no pushing needed.
        $names = 1..150 | ForEach-Object { 'bulk-{0:000}' -f $_ }
        # One git call creates all branches (fetching main from the repo itself into each name).
        $refspecs = @($names | ForEach-Object { "main:refs/heads/$_" })
        Invoke-TestGit $repo fetch --quiet . @refspecs
        $config = New-Object System.Text.StringBuilder
        foreach ($name in $names) {
            $null = $config.Append("[branch `"$name`"]`n`tremote = origin`n`tmerge = refs/heads/$name`n")
        }
        [System.IO.File]::AppendAllText((Join-Path $repo '.git/config'), $config.ToString())

        Remove-GitOrphanBranches -Force 6>$null

        Get-TestGitBranches $repo | Should -Be @('main')
    }

    It 'deletes nothing with -WhatIf' {
        New-GitBranch $repo 'gone' -Push
        Invoke-TestGit $remote branch -D 'gone'

        Remove-GitOrphanBranches -WhatIf 6>$null

        Get-TestGitBranches $repo | Sort-Object | Should -Be @('gone', 'main')
    }

    It 'accepts -Y and the rgob alias' {
        New-GitBranch $repo 'gone-1' -Push
        Invoke-TestGit $remote branch -D 'gone-1'
        Remove-GitOrphanBranches -Y 6>$null
        Get-TestGitBranches $repo | Should -Be @('main')

        New-GitBranch $repo 'gone-2' -Push
        Invoke-TestGit $remote branch -D 'gone-2'
        rgob -Yes 6>$null
        Get-TestGitBranches $repo | Should -Be @('main')
    }

    It 'warns when there is nothing to delete' {
        New-GitBranch $repo 'still-on-remote' -Push

        Remove-GitOrphanBranches -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        "$warnings" | Should -Match 'No orphan branches to delete locally'
        Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'still-on-remote')
    }

    It 'warns and uses what it knows locally when fetch fails' {
        New-GitBranch $repo 'gone' -Push
        Invoke-TestGit $repo fetch
        Invoke-TestGit $repo update-ref -d 'refs/remotes/origin/gone'
        Invoke-TestGit $repo remote set-url origin (Join-Path $TestDrive 'no-such-remote.git')

        Remove-GitOrphanBranches -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        "$warnings" | Should -Match 'Could not fetch from remote'
        Get-TestGitBranches $repo | Should -Be @('main')
    }

    It 'writes an error outside a git repository' {
        $notRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $notRepo
        # Stop git from finding a repository above TestDrive (e.g. if the temp folder is inside one).
        $env:GIT_CEILING_DIRECTORIES = $TestDrive
        Push-Location -LiteralPath $notRepo
        try {
            Remove-GitOrphanBranches -Force -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null
        }
        finally {
            Pop-Location
            Remove-Item Env:\GIT_CEILING_DIRECTORIES
        }

        "$errors" | Should -Match 'Not in a git repository'
    }
}
