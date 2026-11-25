BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../Rename-GitBranch/Rename-GitBranch.psd1') -Force
    $savedGitEnv = Initialize-GitTestEnvironment -Root (Join-Path $TestDrive 'gitenv')

    # Branch names on the bare remote.
    function Get-RemoteBranches([string] $Remote) {
        @(Invoke-TestGit $Remote for-each-ref '--format=%(refname:short)' refs/heads | Sort-Object)
    }

    function Get-Upstream([string] $Repo, [string] $Branch) {
        (Invoke-TestGit $Repo for-each-ref '--format=%(upstream:short)' "refs/heads/$Branch") -join ''
    }
}

AfterAll {
    Restore-GitTestEnvironment $savedGitEnv
    Remove-Module Rename-GitBranch, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Rename-GitBranch' {

    BeforeEach {
        $fixture = New-GitFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $repo = $fixture.Local
        $remote = $fixture.Remote
        Push-Location -LiteralPath $repo
    }

    AfterEach {
        Pop-Location
    }

    Context 'success' {

        It 'renames a branch locally and on the remote, and sets the new upstream' {
            New-GitBranch $repo 'old-name' -Push

            Rename-GitBranch -OldName 'old-name' -NewName 'new-name' -ErrorVariable errors 6>$null

            $errors | Should -HaveCount 0
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'new-name')
            Get-RemoteBranches $remote | Should -Be @('main', 'new-name')
            Get-Upstream $repo 'new-name' | Should -Be 'origin/new-name'
        }

        It 'renames the current branch when -OldName is not given' {
            New-GitBranch $repo 'current' -Push
            Invoke-TestGit $repo switch 'current'

            $out = Rename-GitBranch -NewName 'renamed' 6>&1

            "$out" | Should -Match 'Current branch is current'
            (Invoke-TestGit $repo branch --show-current) -join '' | Should -Be 'renamed'
            Get-RemoteBranches $remote | Should -Be @('main', 'renamed')
        }

        It 'pushes a branch that was never on the remote, with nothing to delete there' {
            New-GitBranch $repo 'local-only'

            Rename-GitBranch -OldName 'local-only' -NewName 'published' -ErrorVariable errors 6>$null

            $errors | Should -HaveCount 0
            Get-RemoteBranches $remote | Should -Be @('main', 'published')
            Get-Upstream $repo 'published' | Should -Be 'origin/published'
        }

        It 'renames to a name with slashes' {
            New-GitBranch $repo 'flat' -Push

            Rename-GitBranch -OldName 'flat' -NewName 'feature/nested/name' 6>$null

            Get-RemoteBranches $remote | Should -Be @('feature/nested/name', 'main')
        }

        It 'uses -Remote' {
            $second = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.git')
            Invoke-TestGit $repo init --bare --initial-branch=main $second
            Invoke-TestGit $repo remote add upstream $second
            New-GitBranch $repo 'topic'
            Invoke-TestGit $repo push -u upstream 'topic'

            Rename-GitBranch -OldName 'topic' -NewName 'topic-2' -Remote upstream 6>$null

            Get-RemoteBranches $second | Should -Be @('topic-2')
            Get-RemoteBranches $remote | Should -Be @('main')
            Get-Upstream $repo 'topic-2' | Should -Be 'upstream/topic-2'
        }
    }

    Context '-DryRun and -WhatIf' {

        It 'lists the commands and changes nothing with -<Switch>' -ForEach @(
            @{ Switch = 'DryRun' }
            @{ Switch = 'WhatIf' }
        ) {
            New-GitBranch $repo 'old-name' -Push
            $params = @{ OldName = 'old-name'; NewName = 'new-name'; $Switch = $true }

            $out = Rename-GitBranch @params 6>&1

            "$out" | Should -Match 'git branch -m old-name new-name'
            "$out" | Should -Match 'git push -u origin new-name'
            "$out" | Should -Match 'git push origin --delete old-name'
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'old-name')
            Get-RemoteBranches $remote | Should -Be @('main', 'old-name')
        }

        It 'says there is nothing to delete on the remote for a local-only branch' {
            New-GitBranch $repo 'local-only'

            $out = Rename-GitBranch -OldName 'local-only' -NewName 'x' -DryRun 6>&1

            "$out" | Should -Not -Match '--delete'
            "$out" | Should -Match 'local-only is not on origin'
        }
    }

    Context 'checks before changing anything' {

        It 'fails when <Case>' -ForEach @(
            @{ Case = 'the old branch does not exist'; OldName = 'missing'; NewName = 'x'; RemoteName = 'origin'; Message = 'Branch missing does not exist locally' }
            @{ Case = 'the new branch already exists'; OldName = 'old-name'; NewName = 'main'; RemoteName = 'origin'; Message = 'Branch main already exists' }
            @{ Case = 'the new name is invalid'; OldName = 'old-name'; NewName = 'bad..name'; RemoteName = 'origin'; Message = 'bad..name is not a valid branch name' }
            @{ Case = 'the remote does not exist'; OldName = 'old-name'; NewName = 'x'; RemoteName = 'nope'; Message = 'Remote nope does not exist' }
        ) {
            New-GitBranch $repo 'old-name' -Push

            Rename-GitBranch -OldName $OldName -NewName $NewName -Remote $RemoteName -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

            "$errors" | Should -Match ([regex]::Escape($Message))
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'old-name')
            Get-RemoteBranches $remote | Should -Be @('main', 'old-name')
        }

        It 'fails when the remote cannot be reached' {
            New-GitBranch $repo 'old-name' -Push
            Invoke-TestGit $repo remote set-url origin (Join-Path $TestDrive 'no-such-remote.git')

            Rename-GitBranch -OldName 'old-name' -NewName 'x' -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

            "$errors" | Should -Match 'Could not reach remote origin'
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'old-name')
        }

        It 'fails on a detached HEAD without -OldName' {
            Invoke-TestGit $repo switch --detach main

            Rename-GitBranch -NewName 'x' -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

            "$errors" | Should -Match 'detached HEAD'
            Get-TestGitBranches $repo | Should -Be @('main')
        }

        It 'fails outside a git repository' {
            $notRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $notRepo
            $env:GIT_CEILING_DIRECTORIES = $TestDrive
            Push-Location -LiteralPath $notRepo
            try {
                Rename-GitBranch -OldName 'a' -NewName 'b' -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null
            }
            finally {
                Pop-Location
                Remove-Item Env:\GIT_CEILING_DIRECTORIES
            }

            "$errors" | Should -Match 'Not in a git repository'
        }
    }

    Context 'remote rejects a step' {

        It 'undoes the local rename when the push of the new branch fails' {
            New-GitBranch $repo 'old-name' -Push
            # Reject every push that creates or updates a branch.
            New-GitHook -GitDir $remote -Name 'pre-receive' -Body @'
while read old new ref; do
  case "$new" in
    0000000000000000000000000000000000000000) ;;
    *) echo "rejected by test hook: $ref" >&2; exit 1 ;;
  esac
done
exit 0
'@

            Rename-GitBranch -OldName 'old-name' -NewName 'new-name' -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

            "$errors" | Should -Match 'Push failed, so the local rename was undone'
            "$errors" | Should -Match 'rejected by test hook'
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'old-name')
            Get-Upstream $repo 'old-name' | Should -Be 'origin/old-name'
            Get-RemoteBranches $remote | Should -Be @('main', 'old-name')
        }

        It 'keeps the new branch and says so when deleting the old remote branch fails' {
            New-GitBranch $repo 'old-name' -Push
            # Reject every push that deletes a branch.
            New-GitHook -GitDir $remote -Name 'pre-receive' -Body @'
while read old new ref; do
  case "$new" in
    0000000000000000000000000000000000000000) echo "delete rejected by test hook: $ref" >&2; exit 1 ;;
  esac
done
exit 0
'@

            Rename-GitBranch -OldName 'old-name' -NewName 'new-name' -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

            "$errors" | Should -Match 'could not delete old-name on origin'
            Get-TestGitBranches $repo | Sort-Object | Should -Be @('main', 'new-name')
            Get-Upstream $repo 'new-name' | Should -Be 'origin/new-name'
            Get-RemoteBranches $remote | Should -Be @('main', 'new-name', 'old-name')
        }
    }
}
