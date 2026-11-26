# Pester shares variables between BeforeDiscovery/BeforeAll/BeforeEach and the It blocks, which the
# analyzer can't see. Test helpers that create files don't need -WhatIf.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester scoping')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helpers')]
param()

BeforeDiscovery {
    $onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $isRoot = (-not $onWindows) -and ((& id -u) -eq '0')
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../DeleteBinObjFolders/DeleteBinObjFolders.psd1') -Force
    $onWindows = Test-OnWindows

    # Relative folder paths (directories only) under $Root, '/'-separated, sorted.
    function Get-Folders([string] $Root) {
        $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
        @(Get-ChildItem -LiteralPath $rootFull -Recurse -Directory -Force |
                ForEach-Object { $_.FullName.Substring($rootFull.Length + 1) -replace '\\', '/' } |
                Sort-Object)
    }

    # Puts a project file in each folder (relative to $Root), so its bin/obj folders get deleted.
    function New-ProjectFile([string] $Root, [string[]] $Folder, [string] $Name = 'App.csproj') {
        foreach ($f in $Folder) { $null = New-TestFile (Join-Path (Join-Path $Root $f) $Name) }
    }
}

AfterAll {
    Remove-Module DeleteBinObjFolders, TestHelpers -ErrorAction SilentlyContinue
}

Describe 'Remove-BinObjFolders' {

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root
    }

    It 'deletes bin and obj folders at any depth and keeps everything else' {
        New-TestFile (Join-Path $root 'App/App.csproj')
        New-TestFile (Join-Path $root 'App/bin/Debug/App.dll')
        New-TestFile (Join-Path $root 'App/obj/project.assets.json')
        New-TestFile (Join-Path $root 'src/Lib/Lib.csproj')
        New-TestFile (Join-Path $root 'src/Lib/bin/Release/net8.0/Lib.dll')
        New-TestFile (Join-Path $root 'src/Lib/obj/Lib.csproj.nuget.g.props')
        New-TestFile (Join-Path $root 'Tests.slnx')
        New-TestFile (Join-Path $root 'bin/top-level.dll')

        $out = Remove-BinObjFolders -Path $root -Force 6>&1

        Get-Folders $root | Should -Be @('App', 'src', 'src/Lib')
        Test-Path -LiteralPath (Join-Path $root 'App/App.csproj') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'src/Lib/Lib.csproj') | Should -BeTrue
        "$out" | Should -Match 'Deleted 5 folder\(s\)\. 0 folder\(s\) could not be fully deleted\.'
    }

    It 'only deletes bin/obj folders next to a project or solution file' {
        New-TestFile (Join-Path $root 'scripts/bin/run.sh')
        New-TestFile (Join-Path $root 'docs/obj/x')
        New-TestFile (Join-Path $root 'src/App.csproj.bak')
        New-TestFile (Join-Path $root 'src/bin/x')

        Remove-BinObjFolders -Path $root -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        Get-Folders $root | Should -Be @('docs', 'docs/obj', 'scripts', 'scripts/bin', 'src', 'src/bin')
        "$warnings" | Should -Match 'No bin, obj folders found next to a project or solution file'
    }

    It 'recognizes every project and solution file type' -ForEach @(
        @{ File = 'App.csproj' }, @{ File = 'App.fsproj' }, @{ File = 'App.vbproj' }, @{ File = 'Db.sqlproj' },
        @{ File = 'Web.esproj' }, @{ File = 'Pkg.wapproj' }, @{ File = 'Build.proj' },
        @{ File = 'All.sln' }, @{ File = 'All.slnx' }, @{ File = 'Some.slnf' }, @{ File = 'UPPER.CSPROJ' }
    ) {
        New-ProjectFile $root 'App' -Name $File
        New-TestFile (Join-Path $root 'App/bin/x')
        New-TestFile (Join-Path $root 'App/obj/x')

        Remove-BinObjFolders -Path $root -Force 6>$null

        Get-Folders $root | Should -Be @('App')
    }

    It 'searches inside a bin/obj folder it keeps' {
        New-ProjectFile $root 'tools/bin/Nested'
        New-TestFile (Join-Path $root 'tools/bin/Nested/obj/x')

        Remove-BinObjFolders -Path $root -Force 6>$null

        Get-Folders $root | Should -Be @('tools', 'tools/bin', 'tools/bin/Nested')
    }

    It 'counts a bin/obj inside another bin/obj once (it is deleted with its parent)' {
        New-ProjectFile $root 'App'
        New-TestFile (Join-Path $root 'App/bin/obj/x')
        New-TestFile (Join-Path $root 'App/obj/bin/y')

        $out = Remove-BinObjFolders -Path $root -Force 6>&1

        Get-Folders $root | Should -Be @('App')
        "$out" | Should -Match 'Deleted 2 folder\(s\)'
    }

    It 'never searches .git or node_modules' {
        New-ProjectFile $root '.git/objects', 'web/node_modules/pkg', 'web'
        New-TestFile (Join-Path $root '.git/objects/obj/x')
        New-TestFile (Join-Path $root 'web/node_modules/pkg/bin/cli.js')
        New-TestFile (Join-Path $root 'web/bin/x')

        Remove-BinObjFolders -Path $root -Force 6>$null

        Test-Path -LiteralPath (Join-Path $root '.git/objects/obj') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'web/node_modules/pkg/bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'web/bin') | Should -BeFalse
    }

    It 'does not search folders matching -Exclude (wildcards allowed)' {
        New-ProjectFile $root 'keep/App', 'vendor-a', 'vendor-b/sub', 'App'
        New-TestFile (Join-Path $root 'keep/App/bin/x')
        New-TestFile (Join-Path $root 'vendor-a/obj/x')
        New-TestFile (Join-Path $root 'vendor-b/sub/bin/x')
        New-TestFile (Join-Path $root 'App/bin/x')

        Remove-BinObjFolders -Path $root -Exclude 'keep', 'vendor-*' -Force 6>$null

        Test-Path -LiteralPath (Join-Path $root 'keep/App/bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'vendor-a/obj') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'vendor-b/sub/bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'App/bin') | Should -BeFalse
    }

    It 'can exclude a bin/obj folder by name' {
        New-ProjectFile $root 'App'
        New-TestFile (Join-Path $root 'App/bin/x')
        New-TestFile (Join-Path $root 'App/obj/x')

        Remove-BinObjFolders -Path $root -Exclude 'obj' -Force 6>$null

        Get-Folders $root | Should -Be @('App', 'App/obj')
    }

    It 'only matches folders named exactly bin or obj' {
        New-ProjectFile $root 'App', 'Files'
        New-TestFile (Join-Path $root 'App/binaries/x')
        New-TestFile (Join-Path $root 'App/objects/x')
        New-TestFile (Join-Path $root 'App/my-bin/x')
        New-TestFile (Join-Path $root 'Files/bin')   # a file, not a folder
        New-TestFile (Join-Path $root 'Files/obj')

        Remove-BinObjFolders -Path $root -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        Get-Folders $root | Should -Be @('App', 'App/binaries', 'App/my-bin', 'App/objects', 'Files')
        Test-Path -LiteralPath (Join-Path $root 'Files/bin') -PathType Leaf | Should -BeTrue
        "$warnings" | Should -Match 'No bin, obj folders found'
    }

    It 'does not follow folder links out of the tree' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-ProjectFile $outside '.', 'Other'
        New-ProjectFile $root '.', 'App'
        New-TestFile (Join-Path $outside 'Other/bin/precious.dll')
        New-TestFile (Join-Path $outside 'bin/precious.dll')
        New-DirectoryLink -Path (Join-Path $root 'linked') -Target $outside
        New-DirectoryLink -Path (Join-Path $root 'bin') -Target (Join-Path $outside 'bin')
        New-TestFile (Join-Path $root 'App/bin/x')

        Remove-BinObjFolders -Path $root -Force 6>$null

        Test-Path -LiteralPath (Join-Path $outside 'Other/bin/precious.dll') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $outside 'bin/precious.dll') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'App/bin') | Should -BeFalse
    }

    It 'handles folder names with spaces and special characters' {
        $names = @('with space', '-starts-with-dash', "it's", '[brackets]', 'amp&ersand', '100%', '%OS%', 'caret^', 'bang!', 'ünïcödé')
        foreach ($name in $names) {
            New-ProjectFile $root $name
            New-TestFile (Join-Path $root "$name/bin/x.dll")
        }

        Remove-BinObjFolders -Path $root -Force -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null

        $errors | Should -HaveCount 0
        Get-Folders $root | Should -Be @($names | Sort-Object)
    }

    It 'searches the current folder when -Path is not given' {
        New-ProjectFile $root 'App'
        New-TestFile (Join-Path $root 'App/bin/x')
        Push-Location -LiteralPath $root
        try {
            Remove-BinObjFolders -Force 6>$null
        }
        finally {
            Pop-Location
        }

        Get-Folders $root | Should -Be @('App')
    }

    It 'accepts -Y and -Yes as -Force' {
        New-ProjectFile $root 'A', 'B'
        New-TestFile (Join-Path $root 'A/bin/x')
        New-TestFile (Join-Path $root 'B/obj/x')

        Remove-BinObjFolders -Path (Join-Path $root 'A') -Y 6>$null
        rbof -Path (Join-Path $root 'B') -Yes 6>$null

        Get-Folders $root | Should -Be @('A', 'B')
    }

    It 'deletes nothing with -WhatIf' {
        New-ProjectFile $root 'App'
        New-TestFile (Join-Path $root 'App/bin/x')
        New-TestFile (Join-Path $root 'App/obj/x')

        $out = Remove-BinObjFolders -Path $root -WhatIf 6>&1

        Get-Folders $root | Should -Be @('App', 'App/bin', 'App/obj')
        "$out" | Should -Not -Match 'Deleted'
    }

    It 'warns when no folders are found' {
        New-TestFile (Join-Path $root 'src/code.cs')

        Remove-BinObjFolders -Path $root -Force -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        "$warnings" | Should -Match 'No bin, obj folders found'
    }

    It 'throws for a path that does not exist' {
        { Remove-BinObjFolders -Path (Join-Path $root 'missing') -Force } | Should -Throw
    }

    Context 'Windows' -Skip:(-not $onWindows) {

        It 'matches bin/obj case-insensitively' {
            New-ProjectFile $root 'A', 'B'
            New-TestFile (Join-Path $root 'A/Bin/x')
            New-TestFile (Join-Path $root 'B/OBJ/x')

            Remove-BinObjFolders -Path $root -Force 6>$null

            Get-Folders $root | Should -Be @('A', 'B')
        }

        It 'reports a folder with a locked file and keeps deleting the rest' {
            New-ProjectFile $root 'A', 'B'
            $locked = New-TestFile (Join-Path $root 'A/bin/locked.dll')
            New-TestFile (Join-Path $root 'A/bin/free.dll')
            New-TestFile (Join-Path $root 'B/obj/x')
            $stream = Lock-TestFile $locked
            try {
                $out = Remove-BinObjFolders -Path $root -Force -ErrorVariable errors -ErrorAction SilentlyContinue 6>&1
            }
            finally {
                $stream.Dispose()
            }

            $errors | Should -HaveCount 1
            "$errors" | Should -Match ([regex]::Escape((Join-Path $root 'A\bin')))
            Test-Path -LiteralPath (Join-Path $root 'A/bin/free.dll') | Should -BeFalse -Because 'rd keeps going past locked files'
            Test-Path -LiteralPath (Join-Path $root 'B/obj') | Should -BeFalse
            "$out" | Should -Match 'Deleted 1 folder\(s\)\. 1 folder\(s\) could not be fully deleted\.'
        }

        It 'deletes read-only and hidden files' {
            New-ProjectFile $root 'A'
            $readOnly = New-TestFile (Join-Path $root 'A/bin/readonly.dll')
            $hidden = New-TestFile (Join-Path $root 'A/obj/hidden.txt')
            (Get-Item -LiteralPath $readOnly).Attributes = 'ReadOnly'
            (Get-Item -LiteralPath $hidden).Attributes = 'Hidden'

            Remove-BinObjFolders -Path $root -Force 6>$null

            Get-Folders $root | Should -Be @('A')
        }
    }

    Context 'macOS/Linux' -Skip:$onWindows {

        It 'only matches lowercase bin/obj' {
            # Separate parents: the macOS file system is case-insensitive, so bin and Bin can't be siblings.
            New-ProjectFile $root 'A', 'B', 'C'
            New-TestFile (Join-Path $root 'A/Bin/x')
            New-TestFile (Join-Path $root 'B/OBJ/x')
            New-TestFile (Join-Path $root 'C/bin/x')

            Remove-BinObjFolders -Path $root -Force 6>$null

            Get-Folders $root | Should -Be @('A', 'A/Bin', 'B', 'B/OBJ', 'C')
        }

        It 'reports a folder it has no permission to delete' -Skip:$isRoot {
            New-ProjectFile $root 'A', 'B'
            New-TestFile (Join-Path $root 'A/bin/sub/x')
            New-TestFile (Join-Path $root 'B/obj/x')
            $protected = Join-Path $root 'A/bin/sub'
            & chmod 555 $protected
            try {
                Remove-BinObjFolders -Path $root -Force -ErrorVariable errors -ErrorAction SilentlyContinue 6>$null
            }
            finally {
                & chmod 755 $protected
            }

            $errors | Should -HaveCount 1
            "$errors" | Should -Match 'A/bin'
            Test-Path -LiteralPath (Join-Path $root 'B/obj') | Should -BeFalse
        }
    }
}
