# Pester shares variables between BeforeDiscovery/BeforeAll/BeforeEach and the It blocks, which the
# analyzer can't see. Test helpers that create files don't need -WhatIf.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester scoping')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helpers')]
param()

BeforeDiscovery {
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $isRoot = (-not $onWindows) -and ((& id -u) -eq '0')
    # Unix sockets can be created from .NET Core / PowerShell 7+ only.
    $canMakeSocket = (-not $onWindows) -and ($PSVersionTable.PSVersion.Major -ge 7)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../Remove-TempFiles/Remove-TempFiles.psd1') -Force
    $onWindows = Test-OnWindows
}

AfterAll {
    Remove-Module Remove-TempFiles, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Remove-TempFiles' {

    BeforeEach {
        # Fresh fake temp folder for every test. Never the real temp folder.
        $tempRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot
    }

    It 'deletes files and folders (with nested content) in the given folder' {
        New-TestFile (Join-Path $tempRoot 'a.tmp')
        New-TestFile (Join-Path $tempRoot 'folder/sub/deep/b.tmp')
        New-TestFile (Join-Path $tempRoot 'folder/c.tmp')

        $out = Remove-TempFiles -Path $tempRoot 6>&1

        @(Get-ChildItem -LiteralPath $tempRoot -Force) | Should -HaveCount 0
        Test-Path -LiteralPath $tempRoot | Should -BeTrue -Because 'only the contents are deleted, not the temp folder itself'
        "$out" | Should -Match 'Deleted 2 items\. 0 items could not be fully deleted\.'
    }

    It 'deletes hidden and read-only files' {
        $hidden = New-TestFile (Join-Path $tempRoot '.hidden')
        $readOnly = New-TestFile (Join-Path $tempRoot 'readonly.tmp')
        $inFolder = New-TestFile (Join-Path $tempRoot 'folder/readonly.tmp')
        foreach ($file in $readOnly, $inFolder) {
            (Get-Item -LiteralPath $file).Attributes = 'ReadOnly'
        }
        if ($onWindows) { (Get-Item -LiteralPath $hidden -Force).Attributes = 'Hidden' }

        Remove-TempFiles -Path $tempRoot 6>$null

        @(Get-ChildItem -LiteralPath $tempRoot -Force) | Should -HaveCount 0
    }

    It 'handles names with spaces and special characters' {
        $names = @('with space', '-starts-with-dash', "it's", '[brackets]', 'amp&ersand', '100%', '%OS%', 'caret^', 'bang!', 'ünïcödé')
        foreach ($name in $names) {
            New-TestFile (Join-Path $tempRoot "$name/file.txt")
            New-TestFile (Join-Path $tempRoot "$name.txt")
        }

        Remove-TempFiles -Path $tempRoot -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

        $errors | Should -HaveCount 0
        @(Get-ChildItem -LiteralPath $tempRoot -Force | ForEach-Object Name) | Should -BeNullOrEmpty
    }

    It 'cleans several folders in one call' {
        $second = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestFile (Join-Path $tempRoot 'a.tmp')
        New-TestFile (Join-Path $second 'b/c.tmp')

        $out = Remove-TempFiles -Path $tempRoot, $second 6>&1

        @(Get-ChildItem -LiteralPath $tempRoot -Force) | Should -HaveCount 0
        @(Get-ChildItem -LiteralPath $second -Force) | Should -HaveCount 0
        "$out" | Should -Match 'Deleted 2 items\.'
    }

    It 'skips names matching -Exclude (wildcards allowed)' {
        New-TestFile (Join-Path $tempRoot 'keep-me/file.txt')
        New-TestFile (Join-Path $tempRoot 'vscode-123/file.txt')
        New-TestFile (Join-Path $tempRoot 'MyApp.log')
        New-TestFile (Join-Path $tempRoot 'delete-me.txt')

        Remove-TempFiles -Path $tempRoot -Exclude 'keep-me', 'vscode-*', 'MyApp*' 6>$null

        @(Get-ChildItem -LiteralPath $tempRoot -Force | ForEach-Object Name | Sort-Object) |
            Should -Be @('keep-me', 'MyApp.log', 'vscode-123')
    }

    It 'only matches -Exclude against top-level names' {
        New-TestFile (Join-Path $tempRoot 'outer/keep-me/file.txt')

        Remove-TempFiles -Path $tempRoot -Exclude 'keep-me' 6>$null

        Test-Path -LiteralPath (Join-Path $tempRoot 'outer') | Should -BeFalse
    }

    It 'deletes nothing with -WhatIf' {
        New-TestFile (Join-Path $tempRoot 'a.tmp')
        New-TestFile (Join-Path $tempRoot 'folder/b.tmp')

        $out = Remove-TempFiles -Path $tempRoot -WhatIf 6>&1

        @(Get-ChildItem -LiteralPath $tempRoot -Force) | Should -HaveCount 2
        "$out" | Should -Not -Match 'Deleted \d+ item'
    }

    It 'warns and continues when a folder does not exist' {
        $missing = Join-Path $TestDrive 'does-not-exist'
        New-TestFile (Join-Path $tempRoot 'a.tmp')

        Remove-TempFiles -Path $missing, $tempRoot -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        "$warnings" | Should -Match ([regex]::Escape("Temp folder '$missing' not found"))
        @(Get-ChildItem -LiteralPath $tempRoot -Force) | Should -HaveCount 0
    }

    It 'handles an empty folder without errors' {
        $out = Remove-TempFiles -Path $tempRoot -ErrorVariable errors 6>&1
        $errors | Should -HaveCount 0
        "$out" | Should -Match 'Deleted 0 items\. 0 items'
    }

    It 'deletes a folder link but not the folder it points to' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $precious = New-TestFile (Join-Path $outside 'precious.txt')
        New-DirectoryLink -Path (Join-Path $tempRoot 'link') -Target $outside

        Remove-TempFiles -Path $tempRoot 6>$null

        Test-Path -LiteralPath (Join-Path $tempRoot 'link') | Should -BeFalse
        Test-Path -LiteralPath $precious | Should -BeTrue
    }

    Context 'default folders' {
        # Test-Path is mocked to say no folder exists, so nothing can be deleted; -WhatIf on top of that.
        BeforeEach {
            Mock -ModuleName Remove-TempFiles Test-Path { $false }
        }

        It 'uses the user and Windows temp folders on Windows' -Skip:(-not $onWindows) {
            Remove-TempFiles -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

            $warnings | Should -HaveCount 2
            "$($warnings[0])" | Should -BeLike "*'$env:TEMP'*"
            "$($warnings[1])" | Should -BeLike "*'$(Join-Path $env:windir 'Temp')'*"
        }

        It 'uses the user temp folder on Linux' -Skip:($onWindows -or $IsMacOS) {
            Remove-TempFiles -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

            $warnings | Should -HaveCount 1
            "$($warnings[0])" | Should -BeLike "*'$([System.IO.Path]::GetTempPath())'*"
        }

        It 'uses the user temp and cache folders on macOS' -Skip:(-not $IsMacOS) {
            Remove-TempFiles -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

            $warnings | Should -HaveCount 2
            "$($warnings[0])" | Should -BeLike "*'$([System.IO.Path]::GetTempPath())'*"
            "$($warnings[1])" | Should -BeLike "*'$(Join-Path $HOME 'Library/Caches')'*"
        }
    }

    Context 'Windows' -Skip:(-not $onWindows) {

        It 'reports a locked file as an error and keeps deleting the rest' {
            $locked = New-TestFile (Join-Path $tempRoot 'locked.tmp')
            $lockedInFolder = New-TestFile (Join-Path $tempRoot 'folder/locked.tmp')
            New-TestFile (Join-Path $tempRoot 'folder/free.tmp')
            New-TestFile (Join-Path $tempRoot 'free.tmp')
            $streams = @((Lock-TestFile $locked), (Lock-TestFile $lockedInFolder))
            try {
                $out = Remove-TempFiles -Path $tempRoot -ErrorVariable errors -ErrorAction SilentlyContinue 6>&1
            }
            finally {
                $streams | ForEach-Object { $_.Dispose() }
            }

            $errors | Should -HaveCount 2
            "$errors" | Should -Match 'locked\.tmp'
            "$errors" | Should -Match 'folder'
            Test-Path -LiteralPath (Join-Path $tempRoot 'free.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $tempRoot 'folder/free.tmp') | Should -BeFalse -Because 'rd keeps going past locked files'
            Test-Path -LiteralPath $lockedInFolder | Should -BeTrue
            "$out" | Should -Match 'Deleted 1 item\. 2 items could not be fully deleted\.'
        }

        It 'stops reporting errors with -ErrorAction SilentlyContinue' {
            $locked = New-TestFile (Join-Path $tempRoot 'locked.tmp')
            $stream = Lock-TestFile $locked
            try {
                { Remove-TempFiles -Path $tempRoot -ErrorAction SilentlyContinue 6>$null } | Should -Not -Throw
            }
            finally {
                $stream.Dispose()
            }
        }
    }

    Context 'macOS/Linux' -Skip:$onWindows {

        It 'always skips well-known entries used by running programs' {
            $kept = @('.X11-unix', '.ICE-unix', 'systemd-private-abc', 'tmux-1000', 'ssh-XXXXabc',
                'com.apple.launchd.abc', 'CoreFxPipe_abc', 'dotnet-diagnostic-1-2-socket', 'clr-debug-pipe-1-2-in')
            foreach ($name in $kept) { New-TestFile (Join-Path $tempRoot "$name/file") }
            New-TestFile (Join-Path $tempRoot 'regular/file')

            Remove-TempFiles -Path $tempRoot 6>$null

            @(Get-ChildItem -LiteralPath $tempRoot -Force | ForEach-Object Name | Sort-Object) |
                Should -Be @($kept | Sort-Object)
        }

        It 'skips Unix sockets' -Skip:(-not $canMakeSocket) {
            $socketPath = Join-Path $tempRoot 'app.sock'
            $socket = New-Object System.Net.Sockets.Socket ([System.Net.Sockets.AddressFamily]::Unix), ([System.Net.Sockets.SocketType]::Stream), ([System.Net.Sockets.ProtocolType]::Unspecified)
            try {
                $socket.Bind((New-Object System.Net.Sockets.UnixDomainSocketEndPoint $socketPath))
                New-TestFile (Join-Path $tempRoot 'regular.tmp')

                Remove-TempFiles -Path $tempRoot 6>$null

                Test-Path -LiteralPath $socketPath | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $tempRoot 'regular.tmp') | Should -BeFalse
            }
            finally {
                $socket.Dispose()
            }
        }

        It 'reports entries it has no permission to delete' -Skip:$isRoot {
            $protected = Join-Path $tempRoot 'protected'
            New-TestFile (Join-Path $protected 'file')
            New-TestFile (Join-Path $tempRoot 'free.tmp')
            & chmod 555 $protected
            try {
                Remove-TempFiles -Path $tempRoot -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null
            }
            finally {
                & chmod 755 $protected
            }

            $errors | Should -HaveCount 1
            "$errors" | Should -Match 'protected'
            Test-Path -LiteralPath (Join-Path $tempRoot 'free.tmp') | Should -BeFalse
        }
    }
}
